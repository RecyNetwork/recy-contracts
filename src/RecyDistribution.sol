// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyToken} from "./RecyToken.sol";
import {RecyErrors} from "./lib/RecyErrors.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IRecyReportAccounting
 * @notice The only surface of a RecyReport instance that RecyDistribution depends on
 * @dev Declared locally, and consumed only for its selectors, rather than importing RecyReport:
 *      every read of a report contract goes through a bounded low-level staticcall. A registered
 *      report contract is never trusted to answer - one that cannot account for its own
 *      obligations is skipped, never funded
 */
interface IRecyReportAccounting {
    function rewardTotal() external view returns (uint256);
    function rewardClaimed() external view returns (uint256);
}

/**
 * @title RecyDistribution
 * @notice Mints cRECY into RecyReport contracts to cover their reward obligations
 * @dev The shortfall-driven paths ({mintTokensToReport}, {mintTokensToAllReports}) derive the
 *      mint amount from a *foreign* accounting value (`rewardTotal - rewardClaimed`) that the
 *      distribution contract cannot verify. A poisoned or double-counted `rewardTotal` on a
 *      report contract would otherwise turn the operator's routine top-up into unbounded supply
 *      issuance. This contract therefore treats every report contract as untrusted:
 *      - every mint is bounded by {maxMintPerCall} and, cumulatively, by {maxCumulativeMintPerReport};
 *      - an inverted accounting invariant (`rewardClaimed > rewardTotal`) is a hard, named error;
 *      - a report contract that is not a contract, or whose accounting reverts, is never funded;
 *      - one broken report can never abort the batch sweep - it is skipped and logged
 *
 *      REACH OF THE SHORTFALL PATHS. Against a report running the Phase 2 implementation, a
 *      shortfall can never open: `validateRecyReport` refuses any promise the pool cannot already
 *      cover, claims reduce obligation and balance in step, and invalidation touches neither -
 *      `outstanding <= balance` is inductive there. The shortfall paths therefore only ever fire
 *      against legacy (pre-upgrade) report state. Ongoing issuance for fixed reports is
 *      necessarily proactive - mint BEFORE the validation that needs the balance - which is what
 *      {fundReport} is for
 */
contract RecyDistribution is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Reason a mint to a given report contract is not permitted
    /// @dev `None` means "no blocker"; it does not mean a mint is due (the amount may be 0)
    enum MintBlocker {
        None,
        NotRegistered,
        Blacklisted,
        NotAContract,
        AccountingUnreadable,
        AccountingInverted,
        ExceedsMaxMintPerCall,
        ExceedsCumulativeCap
    }

    /// @notice Gas stipend forwarded to each accounting read on a report contract
    /// @dev Two storage reads behind a proxy cost far less than this. The cap exists so a
    ///      misconfigured or hostile report contract cannot burn the batch's gas and, via the
    ///      63/64 rule, drag {mintTokensToAllReports} down with it
    uint256 private constant ACCOUNTING_READ_GAS = 100_000;

    /// @notice The cRECY token minted by this contract
    /// @dev Immutable: there is no rotation path, and swapping it would silently re-target
    ///      every cap and every `totalMintedToReport` figure already recorded
    RecyToken public immutable token;

    /// @notice Enumerable list of all registered report contracts (including blacklisted ones)
    address[] public reportContracts;

    /// @notice Total tokens minted to each report contract over its lifetime
    /// @dev Deliberately *not* cleared by {blacklistReportContract} or {removeReportContract},
    ///      so remove-and-re-add is not a way around {maxCumulativeMintPerReport}
    mapping(address => uint256) public totalMintedToReport;

    /// @notice Mapping to track blacklisted report contracts
    mapping(address => bool) public blacklistedReports;

    /// @notice Hard ceiling on the amount minted by a single {mintTokensToReport} or by a single
    ///         report contract's leg of {mintTokensToAllReports}
    uint256 public maxMintPerCall;

    /// @notice Hard ceiling on the lifetime total minted to any one report contract
    uint256 public maxCumulativeMintPerReport;

    /// @dev 1-based index into {reportContracts}; 0 means "not registered". Single source of
    ///      truth for O(1) membership and O(1) removal, replacing the previous O(N) array scans
    mapping(address => uint256) private _reportIndex;

    /// @notice Events
    event TokensMinted(address indexed reportContract, uint256 amount);
    event ReportContractAdded(address indexed reportContract);
    event ReportContractRemoved(address indexed reportContract);
    event ReportContractBlacklisted(address indexed reportContract);
    event ReportContractWhitelisted(address indexed reportContract);
    event ReportMintSkipped(address indexed reportContract, MintBlocker reason);
    event BatchMintCompleted(uint256 totalMinted, uint256 mintedCount, uint256 skippedCount);
    event MaxMintPerCallUpdated(uint256 previousValue, uint256 newValue);
    event MaxCumulativeMintPerReportUpdated(uint256 previousValue, uint256 newValue);
    event TokensRescued(address indexed rescuedToken, address indexed to, uint256 amount);

    /// @notice Errors
    error MintBlocked(address reportContract, MintBlocker reason);
    error NotReportContract(address account);
    error NotAContract(address account);
    error NoMintNeeded();
    error ZeroCap();
    error AlreadyBlacklisted(address reportContract);
    error OwnershipRenounceDisabled();

    /**
     * @notice Deploy the distribution contract with its mint containment already in place
     * @param _token The cRECY token this contract mints
     * @param _maxMintPerCall Initial per-call mint ceiling; must be non-zero
     * @param _maxCumulativeMintPerReport Initial lifetime-per-report mint ceiling; must be non-zero
     * @dev Both ceilings are constructor arguments rather than post-deployment configuration so
     *      the contract is never live with an unbounded mint path
     */
    constructor(address _token, uint256 _maxMintPerCall, uint256 _maxCumulativeMintPerReport) Ownable(msg.sender) {
        if (_token == address(0)) revert RecyErrors.AddressInvalid();
        if (_token.code.length == 0) revert NotAContract(_token);
        if (_maxMintPerCall == 0 || _maxCumulativeMintPerReport == 0) revert ZeroCap();

        token = RecyToken(_token);
        maxMintPerCall = _maxMintPerCall;
        maxCumulativeMintPerReport = _maxCumulativeMintPerReport;

        emit MaxMintPerCallUpdated(0, _maxMintPerCall);
        emit MaxCumulativeMintPerReportUpdated(0, _maxCumulativeMintPerReport);
    }

    /**
     * @notice Set the maximum amount that may be minted to one report contract in one call
     * @param _maxMintPerCall The new per-call ceiling; must be non-zero
     * @dev Only owner can call this function. Zero is rejected rather than treated as
     *      "unlimited" so the value can never be ambiguous
     */
    function setMaxMintPerCall(uint256 _maxMintPerCall) external onlyOwner {
        if (_maxMintPerCall == 0) revert ZeroCap();

        uint256 previousValue = maxMintPerCall;
        maxMintPerCall = _maxMintPerCall;

        emit MaxMintPerCallUpdated(previousValue, _maxMintPerCall);
    }

    /**
     * @notice Set the maximum amount that may ever be minted to any one report contract
     * @param _maxCumulativeMintPerReport The new lifetime ceiling; must be non-zero
     * @dev Only owner can call this function. Lowering it below an already-minted total simply
     *      leaves that report contract with no remaining allowance
     */
    function setMaxCumulativeMintPerReport(uint256 _maxCumulativeMintPerReport) external onlyOwner {
        if (_maxCumulativeMintPerReport == 0) revert ZeroCap();

        uint256 previousValue = maxCumulativeMintPerReport;
        maxCumulativeMintPerReport = _maxCumulativeMintPerReport;

        emit MaxCumulativeMintPerReportUpdated(previousValue, _maxCumulativeMintPerReport);
    }

    /**
     * @notice Register a RecyReport contract, and clear its blacklist flag if it has one
     * @param _reportContract The address of the RecyReport contract to whitelist
     * @dev Only owner can call this function. Idempotent: after a successful call the address is
     *      registered and not blacklisted. A first registration that also clears a stale
     *      blacklist flag (left behind by {removeReportContract}) emits both events
     */
    function whitelistReportContract(address _reportContract) external onlyOwner {
        if (_reportContract == address(0)) revert RecyErrors.AddressInvalid();
        if (_reportContract.code.length == 0) revert NotAContract(_reportContract);

        if (_reportIndex[_reportContract] == 0) {
            reportContracts.push(_reportContract);
            _reportIndex[_reportContract] = reportContracts.length;

            emit ReportContractAdded(_reportContract);
        }

        if (blacklistedReports[_reportContract]) {
            blacklistedReports[_reportContract] = false;

            emit ReportContractWhitelisted(_reportContract);
        }
    }

    /**
     * @notice Blacklist a RecyReport contract temporarily
     * @param _reportContract The address of the RecyReport contract to blacklist
     * @dev Only owner can call this function. Blacklisted contracts cannot receive minted tokens
     */
    function blacklistReportContract(address _reportContract) external onlyOwner {
        if (_reportContract == address(0)) revert RecyErrors.AddressInvalid();
        if (_reportIndex[_reportContract] == 0) revert NotReportContract(_reportContract);
        if (blacklistedReports[_reportContract]) revert AlreadyBlacklisted(_reportContract);

        blacklistedReports[_reportContract] = true;

        emit ReportContractBlacklisted(_reportContract);
    }

    /**
     * @notice Permanently deregister a RecyReport contract
     * @param _reportContract The address of the RecyReport contract to remove
     * @dev Only owner can call this function. Without this, {reportContracts} was push-only and
     *      {mintTokensToAllReports} would eventually exceed the block gas limit with no way back.
     *      Removal swap-pops the array in O(1) and leaves `totalMintedToReport` intact, so
     *      remove-then-re-add is not a way around {maxCumulativeMintPerReport}. The blacklist
     *      flag also survives, so it takes an explicit, logged {whitelistReportContract} to make
     *      a previously blacklisted address fundable again
     */
    function removeReportContract(address _reportContract) external onlyOwner {
        uint256 index = _reportIndex[_reportContract];
        if (index == 0) revert NotReportContract(_reportContract);

        uint256 lastIndex = reportContracts.length;
        if (index != lastIndex) {
            address moved = reportContracts[lastIndex - 1];
            reportContracts[index - 1] = moved;
            _reportIndex[moved] = index;
        }

        reportContracts.pop();
        delete _reportIndex[_reportContract];

        emit ReportContractRemoved(_reportContract);
    }

    /**
     * @notice Calculate the amount of tokens needed to be minted to a specific RecyReport contract
     * @param _reportContract The address of the RecyReport contract
     * @return tokensToMint The amount of tokens that need to be minted
     * @dev Strict quote: reverts with {MintBlocked} for exactly the conditions that would block
     *      {mintTokensToReport}, so the two can never disagree. Use {previewMint} for a
     *      non-reverting answer
     */
    function calculateTokensToMint(address _reportContract) public view returns (uint256 tokensToMint) {
        MintBlocker blocker;
        (tokensToMint, blocker) = previewMint(_reportContract);

        if (blocker != MintBlocker.None) revert MintBlocked(_reportContract, blocker);
    }

    /**
     * @notice Non-reverting quote for a report contract
     * @param _reportContract The address of the RecyReport contract
     * @return tokensToMint The amount that would be minted (0 whenever `reason` is not `None`)
     * @return reason Why the mint is blocked, or `None`
     * @dev Lets an operator see precisely why a report contract was skipped by the batch sweep
     */
    function previewMint(address _reportContract) public view returns (uint256 tokensToMint, MintBlocker reason) {
        if (_reportIndex[_reportContract] == 0) return (0, MintBlocker.NotRegistered);

        return _quoteMint(_reportContract);
    }

    /**
     * @notice Mint tokens to a specific RecyReport contract to cover reward shortfall
     * @param _reportContract The address of the RecyReport contract
     * @dev Only owner can call this function. Reverts rather than clamping when a ceiling is
     *      exceeded: a shortfall larger than {maxMintPerCall} means the report contract's
     *      accounting disagrees with the operator's expectations, which is exactly the signal
     *      that must not be swallowed
     */
    function mintTokensToReport(address _reportContract) external onlyOwner {
        (uint256 tokensToMint, MintBlocker blocker) = previewMint(_reportContract);

        if (blocker != MintBlocker.None) revert MintBlocked(_reportContract, blocker);
        if (tokensToMint == 0) revert NoMintNeeded();

        _mintTokens(_reportContract, tokensToMint);
    }

    /**
     * @notice Mint tokens to all registered RecyReport contracts that need them
     * @dev Only owner can call this function. Every per-report failure mode is a skip with a
     *      {ReportMintSkipped} log, never a revert, so one blacklisted, bricked or
     *      lying report contract cannot deny funding to all the others
     */
    function mintTokensToAllReports() external onlyOwner {
        uint256 length = reportContracts.length;
        uint256 totalMinted = 0;
        uint256 mintedCount = 0;
        uint256 skippedCount = 0;

        for (uint256 i = 0; i < length; i++) {
            address reportContract = reportContracts[i];

            (uint256 tokensToMint, MintBlocker blocker) = _quoteMint(reportContract);

            if (blocker != MintBlocker.None) {
                skippedCount++;

                // `_quoteMint` reaches only static reads, so nothing can reenter and fabricate
                // this diagnostic before it is emitted.
                // forge-lint: disable-next-line(reentrancy-events)
                emit ReportMintSkipped(reportContract, blocker);

                continue;
            }

            if (tokensToMint == 0) {
                continue;
            }

            _mintTokens(reportContract, tokensToMint);

            totalMinted += tokensToMint;
            mintedCount++;
        }

        // Only a completely inert sweep reverts. Reverting after a skip would roll back the
        // ReportMintSkipped logs that are the operator's only record of what went wrong.
        if (totalMinted == 0 && skippedCount == 0) revert NoMintNeeded();

        // Untrusted reports are read-only and RecyToken.mint has no callback; final batch counts
        // are only known after the loop.
        // forge-lint: disable-next-line(reentrancy-events)
        emit BatchMintCompleted(totalMinted, mintedCount, skippedCount);
    }

    /**
     * @notice Mint an owner-chosen amount of cRECY into a registered report contract
     * @param _reportContract The report contract to fund
     * @param _amount The amount to mint; non-zero, within both ceilings
     * @dev Only owner can call this function. Against a Phase 2 report the shortfall paths are
     *      dead by construction (see the contract docs): validation refuses promises the pool
     *      cannot cover, so the pool must be funded BEFORE the validation that needs it. This is
     *      that path. It obeys every containment the shortfall paths obey - the same blockers via
     *      {previewMint}, the same per-call ceiling and the same lifetime cumulative record - the
     *      only difference is that the owner names the amount instead of deriving it from a
     *      shortfall that a fixed report can never show.
     *
     *      STRICT BY DESIGN: a report whose shortfall state is itself blocked cannot be
     *      push-funded around the block either. In particular, a legacy report whose gap exceeds
     *      {maxMintPerCall} reports `ExceedsMaxMintPerCall` from {previewMint} regardless of
     *      `_amount`, so it cannot be drip-funded in cap-sized steps - an oversized gap means the
     *      report's accounting disagrees with the operator's expectations, and that signal must
     *      not be fundable around. The escalation path is deliberate and evented: raise
     *      {maxMintPerCall} to cover the full gap first, then fund.
     *
     *      ONE-WAY: RecyReport has no sweep or rescue path - cRECY pushed into a report can only
     *      leave through the four claim legs. A surplus is headroom for future validations on a
     *      going concern, but is permanently stranded on a mistaken target or a decommissioned
     *      plant. The two ceilings are the only guard on an owner amount typo
     */
    function fundReport(address _reportContract, uint256 _amount) external onlyOwner {
        if (_amount == 0) revert NoMintNeeded();

        (, MintBlocker blocker) = previewMint(_reportContract);
        if (blocker != MintBlocker.None) revert MintBlocked(_reportContract, blocker);

        if (_amount > maxMintPerCall) revert MintBlocked(_reportContract, MintBlocker.ExceedsMaxMintPerCall);

        uint256 alreadyMinted = totalMintedToReport[_reportContract];
        uint256 remainingAllowance =
            maxCumulativeMintPerReport > alreadyMinted ? maxCumulativeMintPerReport - alreadyMinted : 0;
        if (_amount > remainingAllowance) revert MintBlocked(_reportContract, MintBlocker.ExceedsCumulativeCap);

        _mintTokens(_reportContract, _amount);
    }

    /**
     * @notice Recover tokens accidentally sent to this contract
     * @param _token The token to recover
     * @param _to The recipient
     * @param _amount The amount to recover
     * @dev Only owner can call this function. This contract mints straight to report contracts and
     *      never needs a balance of its own, so anything sitting here is stray and would otherwise
     *      be stranded forever. Uses SafeERC20 so a non-standard token that reports failure by
     *      return value cannot make a failed recovery look successful. The contract is
     *      non-payable and has no `receive`, so there is no native-currency equivalent
     */
    function rescueTokens(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        if (address(_token) == address(0) || _to == address(0)) revert RecyErrors.AddressInvalid();

        emit TokensRescued(address(_token), _to, _amount);

        _token.safeTransfer(_to, _amount);
    }

    /**
     * @notice Whether an address is a registered report contract
     * @param _reportContract The address to check
     * @return True if registered (blacklisted or not)
     */
    function isReportContract(address _reportContract) public view returns (bool) {
        return _reportIndex[_reportContract] != 0;
    }

    /**
     * @notice Get all report contracts (including blacklisted ones)
     * @return Array of all report contract addresses
     */
    function getAllReportContracts() external view returns (address[] memory) {
        return reportContracts;
    }

    /**
     * @notice Get all active (non-blacklisted) report contracts
     * @return Array of active report contract addresses
     */
    function getActiveReportContracts() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active contracts
        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeCount++;
            }
        }

        // Create array of active contracts
        address[] memory activeContracts = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeContracts[index] = reportContracts[i];
                index++;
            }
        }

        return activeContracts;
    }

    /**
     * @notice Get the number of report contracts
     * @return The count of all report contracts (including blacklisted)
     */
    function getReportContractCount() external view returns (uint256) {
        return reportContracts.length;
    }

    /**
     * @notice Get the number of active (non-blacklisted) report contracts
     * @return The count of active report contracts
     */
    function getActiveReportContractCount() external view returns (uint256) {
        uint256 activeCount = 0;

        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeCount++;
            }
        }

        return activeCount;
    }

    /**
     * @notice Renouncing ownership is disabled
     * @dev This contract is expected to hold cRECY's minter (owner) role. An ownerless
     *      RecyDistribution would freeze the caps, the blacklist and {rescueTokens} forever while
     *      still holding the token's mint authority, permanently bricking distribution. Note that
     *      under that deployment all ongoing issuance flows through {fundReport}: fixed reports
     *      never show the shortfall the reactive paths mint against
     */
    function renounceOwnership() public pure override {
        revert OwnershipRenounceDisabled();
    }

    /**
     * @dev Quote a mint for an address that is already known to be registered.
     *      Invariant: `reason != None` implies `tokensToMint == 0`
     */
    function _quoteMint(address _reportContract) private view returns (uint256 tokensToMint, MintBlocker reason) {
        if (blacklistedReports[_reportContract]) return (0, MintBlocker.Blacklisted);

        // A report contract with no code cannot hold rewards, cannot account for them and cannot
        // pay them out. Never mint into it.
        if (_reportContract.code.length == 0) return (0, MintBlocker.NotAContract);

        (bool readable, uint256 totalRewards, uint256 claimedRewards) = _readAccounting(_reportContract);
        if (!readable) return (0, MintBlocker.AccountingUnreadable);

        // `rewardClaimed > rewardTotal` violates the protocol invariant
        // `rewardTotal - rewardClaimed == outstanding claimable obligations`. Report it as such
        // instead of letting the subtraction panic, which would take the batch down with it.
        if (claimedRewards > totalRewards) return (0, MintBlocker.AccountingInverted);

        uint256 outstanding = totalRewards - claimedRewards;
        // A fixed-size static balance read per report is intrinsic to shortfall accounting.
        // forge-lint: disable-next-line(calls-loop)
        uint256 contractBalance = token.balanceOf(_reportContract);

        // Already funded for everything it owes.
        if (outstanding <= contractBalance) return (0, MintBlocker.None);

        uint256 shortfall = outstanding - contractBalance;

        if (shortfall > maxMintPerCall) return (0, MintBlocker.ExceedsMaxMintPerCall);

        uint256 alreadyMinted = totalMintedToReport[_reportContract];
        uint256 remainingAllowance =
            maxCumulativeMintPerReport > alreadyMinted ? maxCumulativeMintPerReport - alreadyMinted : 0;

        if (shortfall > remainingAllowance) return (0, MintBlocker.ExceedsCumulativeCap);

        return (shortfall, MintBlocker.None);
    }

    /**
     * @dev Read both accounting values from an untrusted report contract under a bounded gas
     *      stipend. `readable` is false if either read fails or answers with anything other
     *      than a single well-formed word
     */
    function _readAccounting(address _reportContract)
        private
        view
        returns (bool readable, uint256 totalRewards, uint256 claimedRewards)
    {
        (bool totalOk, uint256 total) = _staticReadUint(_reportContract, IRecyReportAccounting.rewardTotal.selector);
        if (!totalOk) return (totalOk, 0, 0);

        (bool claimedOk, uint256 claimed) =
            _staticReadUint(_reportContract, IRecyReportAccounting.rewardClaimed.selector);
        if (!claimedOk) return (claimedOk, 0, 0);

        return (claimedOk, total, claimed);
    }

    /**
     * @dev Read a single `uint256` getter from an untrusted address
     * @return ok False if the call failed or the answer was not exactly one word
     * @return value The decoded word, or 0
     * @dev A low-level staticcall rather than try/catch: Solidity's try/catch does not catch a
     *      failure to decode the callee's return data, so a report contract answering with
     *      malformed data would abort the whole batch sweep. The call copies at most one word
     *      and separately requires the exact return-data size, so an oversized answer cannot
     *      turn the gas stipend into an unbounded caller-side copy
     */
    // This call is deliberately reachable from the batch. Its gas and output copy are bounded,
    // and every call failure becomes an unreadable-report skip.
    // forge-lint: disable-next-item(calls-loop)
    function _staticReadUint(address _target, bytes4 _selector) private view returns (bool ok, uint256 value) {
        bytes memory callData = abi.encodeWithSelector(_selector);

        assembly ("memory-safe") {
            let success := staticcall(ACCOUNTING_READ_GAS, _target, add(callData, 0x20), mload(callData), 0, 0x20)
            ok := and(success, eq(returndatasize(), 0x20))
            if ok { value := mload(0) }
        }
    }

    /// @dev Mint `_amount` to `_reportContract`, recording it against the cumulative cap first
    function _mintTokens(address _reportContract, uint256 _amount) private {
        totalMintedToReport[_reportContract] += _amount;

        // A batch necessarily calls mint once per eligible report. RecyToken is the immutable,
        // concrete dependency and its mint path performs no external callback.
        // forge-lint: disable-next-line(calls-loop)
        token.mint(_reportContract, _amount);

        // The same no-callback property makes this post-success receipt non-reentrant.
        // forge-lint: disable-next-line(reentrancy-events)
        emit TokensMinted(_reportContract, _amount);
    }
}
