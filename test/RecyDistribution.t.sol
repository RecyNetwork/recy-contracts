// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../src/RecyDistribution.sol";
import {RecyErrors} from "../src/lib/RecyErrors.sol";
import "./helpers/TestHelpers.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/Test.sol";

contract MockRecyToken {
    mapping(address => uint256) public balanceOf;
    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _owner) {
        if (_owner == address(0)) revert RecyErrors.AddressInvalid();

        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    // Each balance mutation emits the standard ERC20 Transfer event below.
    // forge-lint: disable-next-item(missing-events-access-control)
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can mint");
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    // Each balance mutation emits the standard ERC20 Transfer event below.
    // forge-lint: disable-next-item(missing-events-access-control)
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Only owner");
        if (newOwner == address(0)) revert RecyErrors.AddressInvalid();

        address previousOwner = owner;
        owner = newOwner;

        emit OwnershipTransferred(previousOwner, newOwner);
    }
}

contract MockRecyReport {
    uint256 public rewardTotal;
    uint256 public rewardClaimed;

    function setRewardTotal(uint256 _total) external {
        rewardTotal = _total;
    }

    function setRewardClaimed(uint256 _claimed) external {
        rewardClaimed = _claimed;
    }
}

/// @dev Report contract whose `rewardTotal()` reverts - the misconfigured/bricked report case
contract RevertingTotalReport {
    function rewardTotal() external pure returns (uint256) {
        revert("no accounting");
    }

    function rewardClaimed() external pure returns (uint256) {
        return 0;
    }
}

/// @dev Report contract whose second accounting read reverts
contract RevertingClaimedReport {
    uint256 public rewardTotal = 1000 * 10 ** 18;

    function rewardClaimed() external pure returns (uint256) {
        revert("no accounting");
    }
}

/// @dev Report contract that answers every call successfully with no return data.
///      Solidity's try/catch would *not* catch the resulting decode failure, so this is the
///      case that proves the bounded staticcall in `_staticReadUint` is load bearing.
contract MalformedAccountingReport {
    fallback() external {}
}

/// @dev Report whose first getter successfully returns 192 KiB. Producing it costs less than the
///      accounting stipend, while an unbounded caller-side copy costs roughly another stipend.
contract OversizedAccountingReport {
    function rewardTotal() external pure returns (uint256) {
        assembly {
            return(0, 0x30000)
        }
    }

    function rewardClaimed() external pure returns (uint256) {
        return 0;
    }
}

/// @dev Report contract that burns far more than the accounting read's gas stipend
contract GasBombReport {
    function rewardTotal() external view returns (uint256 sum) {
        for (uint256 i = 0; i < 100_000; i++) {
            // XOR makes every hash observable without arithmetic overflow; the loop itself,
            // rather than a panic on its first addition, must exhaust the read stipend.
            sum ^= uint256(keccak256(abi.encode(i, address(this))));
        }
    }

    function rewardClaimed() external pure returns (uint256) {
        return 0;
    }
}

/// @dev ERC20 whose transfer returns false without reverting - pins that rescueTokens' SafeERC20
///      turns a silently-failed recovery into a revert
contract FalseReturnRescueToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

// Every event emitted by the test contract is a vm.expectEmit template, not a production state
// transition. External setup calls cannot make these template logs reentrant.
// forge-lint: disable-start(reentrancy-events)
contract RecyDistributionTest is Test, TestHelpers {
    RecyDistribution public distribution;
    MockRecyToken public token;
    MockRecyReport public mockReport1;
    MockRecyReport public mockReport2;
    MockRecyReport public mockReport3;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public nonOwner = address(0x3);

    // Test amounts in wei (18 decimals)
    uint256 constant TOTAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M tokens
    uint256 constant REWARD_AMOUNT = 1000 * 10 ** 18; // 1K tokens
    uint256 constant CLAIMED_AMOUNT = 500 * 10 ** 18; // 500 tokens

    // Deliberately generous defaults so the legacy behaviour tests are not cap-limited;
    // the containment tests tighten these explicitly.
    uint256 constant MAX_MINT_PER_CALL = 100_000 * 10 ** 18;
    uint256 constant MAX_CUMULATIVE_MINT = 1_000_000 * 10 ** 18;
    uint256 constant ACCOUNTING_READ_STIPEND = 100_000;
    uint256 constant ADVERSARIAL_BATCH_GAS = 230_000;

    event TokensMinted(address indexed reportContract, uint256 amount);
    event ReportContractAdded(address indexed reportContract);
    event ReportContractRemoved(address indexed reportContract);
    event ReportContractBlacklisted(address indexed reportContract);
    event ReportContractWhitelisted(address indexed reportContract);
    event ReportMintSkipped(address indexed reportContract, RecyDistribution.MintBlocker reason);
    event BatchMintCompleted(uint256 totalMinted, uint256 mintedCount, uint256 skippedCount);
    event MaxMintPerCallUpdated(uint256 previousValue, uint256 newValue);
    event MaxCumulativeMintPerReportUpdated(uint256 previousValue, uint256 newValue);
    event TokensRescued(address indexed rescuedToken, address indexed to, uint256 amount);

    error GasBombUnexpectedlyCompleted(uint256 sum);

    function setUp() public {
        // Deploy mock token with owner
        token = new MockRecyToken(owner);

        // Deploy distribution contract
        vm.prank(owner);
        distribution = new RecyDistribution(address(token), MAX_MINT_PER_CALL, MAX_CUMULATIVE_MINT);

        // Deploy mock report contracts
        mockReport1 = new MockRecyReport();
        mockReport2 = new MockRecyReport();
        mockReport3 = new MockRecyReport();

        // Transfer token ownership to distribution contract so it can mint
        vm.prank(owner);
        token.transferOwnership(address(distribution));

        // Give owner some initial tokens for transfer tests
        vm.prank(address(distribution));
        token.mint(owner, 10_000 * 10 ** 18);
    }

    // ========== HELPERS ==========

    function _mintBlocked(address _reportContract, RecyDistribution.MintBlocker _reason)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(RecyDistribution.MintBlocked.selector, _reportContract, _reason);
    }

    function _whitelist(address _reportContract) internal {
        vm.prank(owner);
        distribution.whitelistReportContract(_reportContract);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function test_constructor() public view {
        assertEq(address(distribution.token()), address(token));
        assertEq(distribution.owner(), owner);
        assertEq(distribution.getReportContractCount(), 0);
        assertEq(distribution.maxMintPerCall(), MAX_MINT_PER_CALL);
        assertEq(distribution.maxCumulativeMintPerReport(), MAX_CUMULATIVE_MINT);
    }

    function test_constructorWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        new RecyDistribution(address(0), MAX_MINT_PER_CALL, MAX_CUMULATIVE_MINT);
    }

    function test_constructorWithNonContractToken() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RecyDistribution.NotAContract.selector, user));
        new RecyDistribution(user, MAX_MINT_PER_CALL, MAX_CUMULATIVE_MINT);
    }

    function test_constructorRejectsZeroPerCallCap() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.ZeroCap.selector);
        new RecyDistribution(address(token), 0, MAX_CUMULATIVE_MINT);
    }

    function test_constructorRejectsZeroCumulativeCap() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.ZeroCap.selector);
        new RecyDistribution(address(token), MAX_MINT_PER_CALL, 0);
    }

    function test_constructorEmitsCapEvents() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MaxMintPerCallUpdated(0, MAX_MINT_PER_CALL);
        vm.expectEmit(false, false, false, true);
        emit MaxCumulativeMintPerReportUpdated(0, MAX_CUMULATIVE_MINT);
        new RecyDistribution(address(token), MAX_MINT_PER_CALL, MAX_CUMULATIVE_MINT);
    }

    // ========== WHITELIST REPORT CONTRACT TESTS ==========

    function test_whitelistReportContract() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ReportContractAdded(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));

        assertEq(distribution.getReportContractCount(), 1);
        assertEq(distribution.reportContracts(0), address(mockReport1));
        assertTrue(distribution.isReportContract(address(mockReport1)));
        assertFalse(distribution.blacklistedReports(address(mockReport1)));
    }

    function test_whitelistReportContractMultiple() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        vm.stopPrank();

        assertEq(distribution.getReportContractCount(), 2);
        assertEq(distribution.reportContracts(0), address(mockReport1));
        assertEq(distribution.reportContracts(1), address(mockReport2));
    }

    function test_whitelistReportContractAlreadyExists() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1)); // Should not revert, just unblacklist
        vm.stopPrank();

        assertEq(distribution.getReportContractCount(), 1); // Still only 1
    }

    function test_whitelistReportContractAfterBlacklist() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectEmit(true, false, false, false);
        emit ReportContractWhitelisted(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        assertFalse(distribution.blacklistedReports(address(mockReport1)));
    }

    function test_whitelistReportContractOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.whitelistReportContract(address(mockReport1));
    }

    function test_whitelistReportContractZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        distribution.whitelistReportContract(address(0));
    }

    function test_whitelistReportContractRejectsNonContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RecyDistribution.NotAContract.selector, user));
        distribution.whitelistReportContract(user);

        assertEq(distribution.getReportContractCount(), 0);
        assertFalse(distribution.isReportContract(user));
    }

    // ========== BLACKLIST REPORT CONTRACT TESTS ==========

    function test_blacklistReportContract() public {
        // First whitelist
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.expectEmit(true, false, false, false);
        emit ReportContractBlacklisted(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        assertTrue(distribution.blacklistedReports(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 1); // Still in array
        assertTrue(distribution.isReportContract(address(mockReport1))); // Still a member
    }

    function test_blacklistReportContractNotFound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RecyDistribution.NotReportContract.selector, address(mockReport1)));
        distribution.blacklistReportContract(address(mockReport1));
    }

    function test_blacklistReportContractAlreadyBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectRevert(abi.encodeWithSelector(RecyDistribution.AlreadyBlacklisted.selector, address(mockReport1)));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();
    }

    function test_blacklistReportContractOnlyOwner() public {
        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.blacklistReportContract(address(mockReport1));
    }

    function test_blacklistReportContractZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        distribution.blacklistReportContract(address(0));
    }

    // ========== REMOVE REPORT CONTRACT TESTS ==========

    function test_removeReportContract() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.whitelistReportContract(address(mockReport3));

        vm.expectEmit(true, false, false, false);
        emit ReportContractRemoved(address(mockReport1));
        distribution.removeReportContract(address(mockReport1));
        vm.stopPrank();

        // Membership mapping and array agree after the swap-pop
        assertFalse(distribution.isReportContract(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 2);
        assertEq(distribution.reportContracts(0), address(mockReport3)); // last element moved into slot 0
        assertEq(distribution.reportContracts(1), address(mockReport2));
        assertTrue(distribution.isReportContract(address(mockReport2)));
        assertTrue(distribution.isReportContract(address(mockReport3)));
    }

    function test_removeReportContractLastElement() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.removeReportContract(address(mockReport2));
        vm.stopPrank();

        assertEq(distribution.getReportContractCount(), 1);
        assertEq(distribution.reportContracts(0), address(mockReport1));
        assertFalse(distribution.isReportContract(address(mockReport2)));
    }

    function test_removeReportContractNotFound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RecyDistribution.NotReportContract.selector, address(mockReport1)));
        distribution.removeReportContract(address(mockReport1));
    }

    function test_removeReportContractOnlyOwner() public {
        _whitelist(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.removeReportContract(address(mockReport1));
    }

    function test_removeThenReAddRestoresMembershipAndClearsBlacklist() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.blacklistReportContract(address(mockReport1));
        distribution.removeReportContract(address(mockReport1));

        // Blacklist flag survives removal in storage...
        assertTrue(distribution.blacklistedReports(address(mockReport1)));
        assertFalse(distribution.isReportContract(address(mockReport1)));

        // ...and re-registering clears it explicitly, emitting both facts
        vm.expectEmit(true, false, false, false);
        emit ReportContractAdded(address(mockReport1));
        vm.expectEmit(true, false, false, false);
        emit ReportContractWhitelisted(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        assertTrue(distribution.isReportContract(address(mockReport1)));
        assertFalse(distribution.blacklistedReports(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 2);
        assertEq(distribution.reportContracts(1), address(mockReport1)); // re-appended at the tail
    }

    /// @dev Removal must not be a way around the cumulative cap
    function test_removeThenReAddDoesNotResetCumulativeCap() public {
        vm.startPrank(owner);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);
        distribution.setMaxCumulativeMintPerReport(REWARD_AMOUNT);
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        mockReport1.setRewardTotal(REWARD_AMOUNT);

        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        assertEq(distribution.totalMintedToReport(address(mockReport1)), REWARD_AMOUNT);

        // Pretend the whole balance was claimed out, so a fresh shortfall exists
        mockReport1.setRewardTotal(REWARD_AMOUNT * 2);

        vm.startPrank(owner);
        distribution.removeReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));

        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsCumulativeCap));
        distribution.mintTokensToReport(address(mockReport1));
        vm.stopPrank();

        assertEq(distribution.totalMintedToReport(address(mockReport1)), REWARD_AMOUNT);
    }

    // ========== CALCULATE TOKENS TO MINT TESTS ==========

    function test_calculateTokensToMint() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        _whitelist(address(mockReport1));

        uint256 expected = REWARD_AMOUNT - CLAIMED_AMOUNT; // Should have = 500 tokens
        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, expected);
    }

    function test_calculateTokensToMintWithBalance() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        _whitelist(address(mockReport1));

        // Give some tokens to the report contract
        uint256 existingBalance = 200 * 10 ** 18;
        vm.prank(owner);
        assertTrue(token.transfer(address(mockReport1), existingBalance));

        uint256 shouldHave = REWARD_AMOUNT - CLAIMED_AMOUNT; // 500 tokens
        uint256 expected = shouldHave - existingBalance; // 500 - 200 = 300 tokens
        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, expected);
    }

    function test_calculateTokensToMintNoNeed() public {
        // Setup mock report where contract has enough tokens
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        _whitelist(address(mockReport1));

        // Give more tokens than needed
        uint256 excessBalance = 600 * 10 ** 18;
        vm.prank(owner);
        assertTrue(token.transfer(address(mockReport1), excessBalance));

        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, 0);
    }

    function test_calculateTokensToMintNotFound() public {
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.NotRegistered));
        // This call is expected to revert, so it has no return value to bind.
        // forge-lint: disable-next-line(unused-return)
        distribution.calculateTokensToMint(address(mockReport1));
    }

    function test_calculateTokensToMintBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.Blacklisted));
        // This call is expected to revert, so it has no return value to bind.
        // forge-lint: disable-next-line(unused-return)
        distribution.calculateTokensToMint(address(mockReport1));
    }

    // ========== PREVIEW MINT TESTS ==========

    function test_previewMintReportsBlockersWithoutReverting() public {
        (uint256 amount, RecyDistribution.MintBlocker reason) = distribution.previewMint(address(mockReport1));
        assertEq(amount, 0);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.NotRegistered));

        mockReport1.setRewardTotal(REWARD_AMOUNT);
        _whitelist(address(mockReport1));

        (amount, reason) = distribution.previewMint(address(mockReport1));
        assertEq(amount, REWARD_AMOUNT);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.None));

        vm.prank(owner);
        distribution.blacklistReportContract(address(mockReport1));

        (amount, reason) = distribution.previewMint(address(mockReport1));
        assertEq(amount, 0);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.Blacklisted));
    }

    // ========== MINT TOKENS TO REPORT TESTS ==========

    function test_mintTokensToReport() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        _whitelist(address(mockReport1));

        uint256 expectedMint = REWARD_AMOUNT - CLAIMED_AMOUNT;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport1), expectedMint);
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(token.balanceOf(address(mockReport1)), expectedMint);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), expectedMint);
    }

    function test_mintTokensToReportNoNeed() public {
        // Setup mock report where no tokens are needed
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(REWARD_AMOUNT); // All claimed

        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        distribution.mintTokensToReport(address(mockReport1));
    }

    function test_mintTokensToReportBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.Blacklisted));
        distribution.mintTokensToReport(address(mockReport1));
        vm.stopPrank();
    }

    function test_mintTokensToReportNotRegistered() public {
        mockReport1.setRewardTotal(REWARD_AMOUNT);

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.NotRegistered));
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(token.balanceOf(address(mockReport1)), 0);
    }

    function test_mintTokensToReportOnlyOwner() public {
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        _whitelist(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.mintTokensToReport(address(mockReport1));
    }

    /// @dev A registered address that has no code is never funded, even though the registry
    ///      already vetted it. Code is stripped here to exercise the mint-time re-check.
    function test_mintTokensToReportRejectsNonContract() public {
        address ghost = makeAddr("ghost");
        vm.etch(ghost, address(mockReport1).code);
        _whitelist(ghost);
        vm.etch(ghost, hex"");

        assertEq(ghost.code.length, 0);

        (uint256 amount, RecyDistribution.MintBlocker reason) = distribution.previewMint(ghost);
        assertEq(amount, 0);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.NotAContract));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(ghost, RecyDistribution.MintBlocker.NotAContract));
        distribution.mintTokensToReport(ghost);

        assertEq(token.balanceOf(ghost), 0);
    }

    // ========== INVERTED ACCOUNTING TESTS (§3.5) ==========

    /// @dev `rewardClaimed > rewardTotal` breaks the protocol invariant
    ///      `rewardTotal - rewardClaimed == outstanding obligations`. It must surface as a named
    ///      error rather than an arithmetic panic.
    function test_invertedAccountingIsANamedError() public {
        mockReport1.setRewardTotal(CLAIMED_AMOUNT);
        mockReport1.setRewardClaimed(REWARD_AMOUNT); // claimed > total

        _whitelist(address(mockReport1));

        (uint256 amount, RecyDistribution.MintBlocker reason) = distribution.previewMint(address(mockReport1));
        assertEq(amount, 0);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.AccountingInverted));

        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.AccountingInverted));
        // This call is expected to revert, so it has no return value to bind.
        // forge-lint: disable-next-line(unused-return)
        distribution.calculateTokensToMint(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.AccountingInverted));
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(token.balanceOf(address(mockReport1)), 0);
    }

    /// @dev One report with inverted accounting must not brick the batch path
    function test_invertedAccountingDoesNotBrickBatch() public {
        mockReport1.setRewardTotal(CLAIMED_AMOUNT);
        mockReport1.setRewardClaimed(REWARD_AMOUNT); // inverted

        mockReport2.setRewardTotal(REWARD_AMOUNT); // healthy

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(mockReport1), RecyDistribution.MintBlocker.AccountingInverted);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), REWARD_AMOUNT);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(REWARD_AMOUNT, 1, 1);
        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(mockReport1)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    // ========== MINT CAP CONTAINMENT TESTS (§3.1 second order) ==========

    /// @dev The core containment property: a report contract reporting an absurd `rewardTotal`
    ///      (the §3.1 self-dealing drain poisons exactly this value) mints *nothing*, however
    ///      many times the owner runs the top-up.
    // The bounded repetition is the tested contract: every poisoned attempt must remain blocked.
    // forge-lint: disable-next-item(calls-loop)
    function test_poisonedRewardTotalCannotMintPastPerCallCap() public {
        vm.startPrank(owner);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        mockReport1.setRewardTotal(9_000_000 * 10 ** 18); // poisoned

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(owner);
            vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall));
            distribution.mintTokensToReport(address(mockReport1));
        }

        assertEq(token.balanceOf(address(mockReport1)), 0);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 0);
    }

    /// @dev And a poison drip-fed one cap-sized step at a time is stopped by the cumulative cap
    // The bounded sequence proves cumulative accounting across successive external top-ups.
    // forge-lint: disable-next-item(calls-loop)
    function test_poisonedRewardTotalCannotMintPastCumulativeCap() public {
        vm.startPrank(owner);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);
        distribution.setMaxCumulativeMintPerReport(REWARD_AMOUNT * 2 + CLAIMED_AMOUNT); // 2.5 calls' worth
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        // Two full cap-sized top-ups are legitimate...
        for (uint256 i = 1; i <= 2; i++) {
            mockReport1.setRewardTotal(REWARD_AMOUNT * i);

            vm.prank(owner);
            distribution.mintTokensToReport(address(mockReport1));
        }

        assertEq(distribution.totalMintedToReport(address(mockReport1)), REWARD_AMOUNT * 2);

        // ...the third trips the cumulative ceiling, and no amount of escalation gets past it
        mockReport1.setRewardTotal(REWARD_AMOUNT * 3);

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsCumulativeCap));
        distribution.mintTokensToReport(address(mockReport1));

        mockReport1.setRewardTotal(type(uint128).max);

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall));
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(distribution.totalMintedToReport(address(mockReport1)), REWARD_AMOUNT * 2);
        assertLe(distribution.totalMintedToReport(address(mockReport1)), distribution.maxCumulativeMintPerReport());
    }

    /// @dev The batch sweep contains a poisoned report the same way, and keeps funding the rest
    function test_poisonedRewardTotalIsSkippedByBatch() public {
        vm.startPrank(owner);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        vm.stopPrank();

        mockReport1.setRewardTotal(9_000_000 * 10 ** 18); // poisoned
        mockReport2.setRewardTotal(CLAIMED_AMOUNT); // healthy

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), CLAIMED_AMOUNT);
        distribution.mintTokensToAllReports();

        assertEq(token.balanceOf(address(mockReport1)), 0);
        assertEq(token.balanceOf(address(mockReport2)), CLAIMED_AMOUNT);
    }

    /// @dev Lowering the cumulative cap below what a report already received must not underflow
    function test_loweringCumulativeCapBelowMintedBlocksFurtherMints() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        mockReport1.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        distribution.setMaxCumulativeMintPerReport(1);
        vm.stopPrank();

        mockReport1.setRewardTotal(REWARD_AMOUNT * 2);

        (uint256 amount, RecyDistribution.MintBlocker reason) = distribution.previewMint(address(mockReport1));
        assertEq(amount, 0);
        assertEq(uint8(reason), uint8(RecyDistribution.MintBlocker.ExceedsCumulativeCap));
    }

    // ========== CAP CONFIGURATION TESTS ==========

    function test_setMaxMintPerCall() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MaxMintPerCallUpdated(MAX_MINT_PER_CALL, REWARD_AMOUNT);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);

        assertEq(distribution.maxMintPerCall(), REWARD_AMOUNT);
    }

    function test_setMaxMintPerCallOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.setMaxMintPerCall(REWARD_AMOUNT);

        assertEq(distribution.maxMintPerCall(), MAX_MINT_PER_CALL);
    }

    function test_setMaxMintPerCallRejectsZero() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.ZeroCap.selector);
        distribution.setMaxMintPerCall(0);
    }

    function test_setMaxCumulativeMintPerReport() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MaxCumulativeMintPerReportUpdated(MAX_CUMULATIVE_MINT, REWARD_AMOUNT);
        distribution.setMaxCumulativeMintPerReport(REWARD_AMOUNT);

        assertEq(distribution.maxCumulativeMintPerReport(), REWARD_AMOUNT);
    }

    function test_setMaxCumulativeMintPerReportOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.setMaxCumulativeMintPerReport(REWARD_AMOUNT);

        assertEq(distribution.maxCumulativeMintPerReport(), MAX_CUMULATIVE_MINT);
    }

    function test_setMaxCumulativeMintPerReportRejectsZero() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.ZeroCap.selector);
        distribution.setMaxCumulativeMintPerReport(0);
    }

    function test_perCallCapAppliesToHonestOverflowToo() public {
        vm.startPrank(owner);
        distribution.setMaxMintPerCall(CLAIMED_AMOUNT);
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        mockReport1.setRewardTotal(REWARD_AMOUNT); // 1000 > 500 cap

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall));
        distribution.mintTokensToReport(address(mockReport1));

        // Raising the ceiling is the explicit, logged way through
        vm.prank(owner);
        distribution.setMaxMintPerCall(REWARD_AMOUNT);

        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(token.balanceOf(address(mockReport1)), REWARD_AMOUNT);
    }

    // ========== MINT TOKENS TO ALL REPORTS TESTS ==========

    function test_mintTokensToAllReports() public {
        // Setup multiple mock reports
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        mockReport2.setRewardTotal(2000 * 10 ** 18);
        mockReport2.setRewardClaimed(1000 * 10 ** 18);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport1), 500 * 10 ** 18);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), 1000 * 10 ** 18);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(1500 * 10 ** 18, 2, 0);

        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(mockReport1)), 500 * 10 ** 18);
        assertEq(token.balanceOf(address(mockReport2)), 1000 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 500 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport2)), 1000 * 10 ** 18);
    }

    function test_mintTokensToAllReportsSkipsBlacklisted() public {
        // Setup multiple mock reports
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        mockReport2.setRewardTotal(2000 * 10 ** 18);
        mockReport2.setRewardClaimed(1000 * 10 ** 18);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.blacklistReportContract(address(mockReport2)); // Blacklist second one

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(mockReport2), RecyDistribution.MintBlocker.Blacklisted);
        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(mockReport1)), 500 * 10 ** 18); // Got tokens
        assertEq(token.balanceOf(address(mockReport2)), 0); // Skipped
    }

    function test_mintTokensToAllReportsNoNeed() public {
        // Setup reports that don't need tokens
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(1000 * 10 ** 18); // All claimed

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        distribution.mintTokensToAllReports();
        vm.stopPrank();
    }

    function test_mintTokensToAllReportsEmptyRegistry() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        distribution.mintTokensToAllReports();
    }

    function test_mintTokensToAllReportsOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.mintTokensToAllReports();
    }

    /// @dev A sweep in which every report is skipped must still succeed: reverting would roll
    ///      back the skip logs that tell the operator what is wrong.
    function test_mintTokensToAllReportsAllSkippedStillSucceeds() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(mockReport1), RecyDistribution.MintBlocker.Blacklisted);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(0, 0, 1);
        distribution.mintTokensToAllReports();
        vm.stopPrank();
    }

    // ========== BATCH ROBUSTNESS AGAINST BROKEN REPORTS ==========

    function test_batchSkipsReportWhoseTotalReverts() public {
        RevertingTotalReport broken = new RevertingTotalReport();
        mockReport2.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(broken));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(broken), RecyDistribution.MintBlocker.AccountingUnreadable);
        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(broken)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    function test_batchSkipsReportWhoseClaimedReverts() public {
        RevertingClaimedReport broken = new RevertingClaimedReport();
        mockReport2.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(broken));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(broken), RecyDistribution.MintBlocker.AccountingUnreadable);
        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(broken)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    /// @dev A report answering with no return data would defeat try/catch; the bounded
    ///      staticcall treats a malformed answer as unreadable instead of decoding it.
    function test_batchSkipsReportWithMalformedAccounting() public {
        MalformedAccountingReport broken = new MalformedAccountingReport();
        mockReport2.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(broken));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(broken), RecyDistribution.MintBlocker.AccountingUnreadable);
        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(broken)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    /// @dev The hostile getter demonstrably completes with 192 KiB of return data under the
    ///      production stipend. The batch gets only enough gas for bounded copying plus the
    ///      healthy leg, so restoring an unbounded returndata copy makes this test run out of gas.
    function test_batchBoundsOversizedAccountingReturnData() public {
        OversizedAccountingReport oversized = new OversizedAccountingReport();
        assertEq(
            oversized.rewardTotal{gas: ACCOUNTING_READ_STIPEND}(),
            0,
            "oversized getter must complete within the accounting stipend"
        );
        (bool generated, bytes memory returnData) =
            address(oversized).staticcall(abi.encodeWithSelector(IRecyReportAccounting.rewardTotal.selector));
        assertTrue(generated, "oversized getter must return successfully");
        assertEq(returnData.length, 0x30000, "fixture must return 192 KiB");

        mockReport2.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(oversized));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(oversized), RecyDistribution.MintBlocker.AccountingUnreadable);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), REWARD_AMOUNT);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(REWARD_AMOUNT, 1, 1);
        distribution.mintTokensToAllReports{gas: ADVERSARIAL_BATCH_GAS}();
        vm.stopPrank();

        assertEq(token.balanceOf(address(oversized)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    /// @dev The getter first proves that 100k gas ends in empty-data OOG, not a checked-arithmetic
    ///      panic. The batch call has enough gas for that stipend plus a healthy mint, but not
    ///      enough to recover from EIP-150 after an uncapped getter consumes all forwarded gas.
    function test_batchSkipsGasBombReport() public {
        GasBombReport bomb = new GasBombReport();

        try bomb.rewardTotal{gas: ACCOUNTING_READ_STIPEND}() returns (uint256 sum) {
            revert GasBombUnexpectedlyCompleted(sum);
        } catch (bytes memory reason) {
            assertEq(reason.length, 0, "gas bomb must exhaust its stipend without panicking");
        }

        mockReport2.setRewardTotal(REWARD_AMOUNT);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(bomb));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(bomb), RecyDistribution.MintBlocker.AccountingUnreadable);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), REWARD_AMOUNT);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(REWARD_AMOUNT, 1, 1);
        distribution.mintTokensToAllReports{gas: ADVERSARIAL_BATCH_GAS}();
        vm.stopPrank();

        assertEq(token.balanceOf(address(bomb)), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    function test_batchSkipsCodelessReport() public {
        address ghost = makeAddr("ghost");
        vm.etch(ghost, address(mockReport1).code);
        _whitelist(ghost);
        vm.etch(ghost, hex"");

        mockReport2.setRewardTotal(REWARD_AMOUNT);
        _whitelist(address(mockReport2));

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(ghost, RecyDistribution.MintBlocker.NotAContract);
        distribution.mintTokensToAllReports();

        assertEq(token.balanceOf(ghost), 0);
        assertEq(token.balanceOf(address(mockReport2)), REWARD_AMOUNT);
    }

    // ========== RESCUE TESTS ==========

    function test_rescueTokens() public {
        uint256 stray = 42 * 10 ** 18;

        // Simulate tokens accidentally sent to the distribution contract
        vm.prank(owner);
        assertTrue(token.transfer(address(distribution), stray));
        assertEq(token.balanceOf(address(distribution)), stray);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(token), user, stray);
        distribution.rescueTokens(IERC20(address(token)), user, stray);

        assertEq(token.balanceOf(address(distribution)), 0);
        assertEq(token.balanceOf(user), stray);
    }

    function test_rescueTokensOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.rescueTokens(IERC20(address(token)), nonOwner, 1);
    }

    function test_rescueTokensZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        distribution.rescueTokens(IERC20(address(token)), address(0), 1);

        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        distribution.rescueTokens(IERC20(address(0)), user, 1);
        vm.stopPrank();
    }

    // ========== OWNERSHIP TESTS ==========

    function test_renounceOwnershipIsDisabled() public {
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.OwnershipRenounceDisabled.selector);
        distribution.renounceOwnership();

        assertEq(distribution.owner(), owner);
    }

    function test_ownershipTransferIsTwoStep() public {
        vm.prank(owner);
        distribution.transferOwnership(user);

        // Handover is not effective until the new owner accepts
        assertEq(distribution.owner(), owner);
        assertEq(distribution.pendingOwner(), user);

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.acceptOwnership();

        vm.prank(user);
        distribution.acceptOwnership();

        assertEq(distribution.owner(), user);
        assertEq(distribution.pendingOwner(), address(0));

        // Old owner has really lost control
        vm.prank(owner);
        vm.expectRevert();
        distribution.setMaxMintPerCall(REWARD_AMOUNT);
    }

    // ========== GETTER FUNCTION TESTS ==========

    function test_getAllReportContracts() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.blacklistReportContract(address(mockReport2));
        vm.stopPrank();

        address[] memory allContracts = distribution.getAllReportContracts();
        assertEq(allContracts.length, 2);
        assertEq(allContracts[0], address(mockReport1));
        assertEq(allContracts[1], address(mockReport2));
    }

    function test_getActiveReportContracts() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.whitelistReportContract(address(mockReport3));
        distribution.blacklistReportContract(address(mockReport2)); // Blacklist middle one
        vm.stopPrank();

        address[] memory activeContracts = distribution.getActiveReportContracts();
        assertEq(activeContracts.length, 2);
        assertEq(activeContracts[0], address(mockReport1));
        assertEq(activeContracts[1], address(mockReport3));
    }

    function test_getActiveReportContractsEmpty() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        address[] memory activeContracts = distribution.getActiveReportContracts();
        assertEq(activeContracts.length, 0);
    }

    function test_getReportContractCount() public {
        assertEq(distribution.getReportContractCount(), 0);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        assertEq(distribution.getReportContractCount(), 1);

        distribution.whitelistReportContract(address(mockReport2));
        assertEq(distribution.getReportContractCount(), 2);

        distribution.blacklistReportContract(address(mockReport1));
        assertEq(distribution.getReportContractCount(), 2); // Still 2, blacklisting doesn't remove
        vm.stopPrank();
    }

    function test_getActiveReportContractCount() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        assertEq(distribution.getActiveReportContractCount(), 2);

        distribution.blacklistReportContract(address(mockReport1));
        assertEq(distribution.getActiveReportContractCount(), 1);

        distribution.whitelistReportContract(address(mockReport1)); // Unblacklist
        assertEq(distribution.getActiveReportContractCount(), 2);
        vm.stopPrank();
    }

    function test_isReportContract() public {
        assertFalse(distribution.isReportContract(address(mockReport1)));

        _whitelist(address(mockReport1));
        assertTrue(distribution.isReportContract(address(mockReport1)));

        vm.prank(owner);
        distribution.blacklistReportContract(address(mockReport1));
        assertTrue(distribution.isReportContract(address(mockReport1))); // blacklisted, still a member

        vm.prank(owner);
        distribution.removeReportContract(address(mockReport1));
        assertFalse(distribution.isReportContract(address(mockReport1)));
    }

    // ========== EDGE CASE TESTS ==========

    function test_multipleMintingRounds() public {
        // Setup mock report
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        _whitelist(address(mockReport1));

        // First mint
        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 500 * 10 ** 18);

        // Increase rewards and mint again
        mockReport1.setRewardTotal(1500 * 10 ** 18);

        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 1000 * 10 ** 18); // 500 + 500
    }

    function test_whitelistAfterRemoval() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        // Whitelisting should unblacklist
        distribution.whitelistReportContract(address(mockReport1));
        assertFalse(distribution.blacklistedReports(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 1); // Still only 1 in array
        vm.stopPrank();
    }

    // ========== fundReport (PUSH-FUNDING) TESTS ==========
    //
    // Against a report running the Phase 2 implementation, `outstanding <= balance` is inductive
    // (validate refuses any promise the pool cannot cover), so the shortfall paths above never
    // fire in production. fundReport is the one mint path that will actually execute against the
    // fixed protocol; these tests plus the integration section below are its contract.

    function test_fundReportMintsAndRecordsCumulative() public {
        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport1), 500 * 10 ** 18);
        distribution.fundReport(address(mockReport1), 500 * 10 ** 18);

        assertEq(token.balanceOf(address(mockReport1)), 500 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 500 * 10 ** 18);
    }

    function test_fundReportRevertsForNonOwner() public {
        _whitelist(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        distribution.fundReport(address(mockReport1), 1);
    }

    function test_fundReportRevertsOnZeroAmount() public {
        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        distribution.fundReport(address(mockReport1), 0);
    }

    function test_fundReportRevertsWhenNotRegistered() public {
        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.NotRegistered));
        distribution.fundReport(address(mockReport1), 1);
    }

    function test_fundReportRevertsWhenBlacklisted() public {
        _whitelist(address(mockReport1));
        vm.prank(owner);
        distribution.blacklistReportContract(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.Blacklisted));
        distribution.fundReport(address(mockReport1), 1);
    }

    function test_fundReportRevertsWhenAccountingUnreadable() public {
        RevertingTotalReport broken = new RevertingTotalReport();
        _whitelist(address(broken));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(broken), RecyDistribution.MintBlocker.AccountingUnreadable));
        distribution.fundReport(address(broken), 1);
    }

    function test_fundReportRevertsWhenAccountingInverted() public {
        mockReport1.setRewardTotal(100);
        mockReport1.setRewardClaimed(200);
        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.AccountingInverted));
        distribution.fundReport(address(mockReport1), 1);
    }

    function test_fundReportRevertsAboveMaxMintPerCall() public {
        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall));
        distribution.fundReport(address(mockReport1), MAX_MINT_PER_CALL + 1);
    }

    function test_fundReportCumulativeCapExactBoundary() public {
        // Tight, dedicated pair so the boundary numbers are unambiguous.
        MockRecyToken tightToken = new MockRecyToken(owner);
        vm.prank(owner);
        RecyDistribution tightDist = new RecyDistribution(address(tightToken), 1000 * 10 ** 18, 1000 * 10 ** 18);
        vm.prank(owner);
        tightToken.transferOwnership(address(tightDist));
        vm.prank(owner);
        tightDist.whitelistReportContract(address(mockReport1));

        vm.startPrank(owner);
        tightDist.fundReport(address(mockReport1), 600 * 10 ** 18);
        // Exactly the remaining allowance must pass...
        tightDist.fundReport(address(mockReport1), 400 * 10 ** 18);
        assertEq(tightDist.totalMintedToReport(address(mockReport1)), 1000 * 10 ** 18);

        // ...and one wei past it must be blocked.
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsCumulativeCap));
        tightDist.fundReport(address(mockReport1), 1);
        vm.stopPrank();
    }

    function test_fundReportSharesOneLedgerWithShortfallPath() public {
        // A shortfall mint and a push mint must count against the same lifetime record.
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        _whitelist(address(mockReport1));

        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1)); // closes the 1000e18 gap
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 1000 * 10 ** 18);

        vm.prank(owner);
        distribution.fundReport(address(mockReport1), 500 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 1500 * 10 ** 18);
    }

    function test_fundReportIsStrict_overGapReportCannotBeDripFunded() public {
        // DELIBERATE SEMANTICS. A report whose gap exceeds maxMintPerCall reports
        // ExceedsMaxMintPerCall from previewMint regardless of the pushed amount: an oversized
        // gap means the report's accounting disagrees with the operator's expectations, and that
        // signal must not be fundable around in cap-sized steps. The escalation path is raising
        // maxMintPerCall to the full gap - deliberate and evented - not drip-funding.
        mockReport1.setRewardTotal(2 * MAX_MINT_PER_CALL);
        _whitelist(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert(_mintBlocked(address(mockReport1), RecyDistribution.MintBlocker.ExceedsMaxMintPerCall));
        distribution.fundReport(address(mockReport1), 1 * 10 ** 18);
    }

    // ========== SHORTFALL-PATH BOUNDARY TESTS ==========

    function test_shortfallExactCumulativeCapBoundary() public {
        // shortfall == remaining allowance mints exactly to the cap; the next wei is blocked.
        MockRecyToken tightToken = new MockRecyToken(owner);
        vm.prank(owner);
        RecyDistribution tightDist = new RecyDistribution(address(tightToken), 1000 * 10 ** 18, 800 * 10 ** 18);
        vm.prank(owner);
        tightToken.transferOwnership(address(tightDist));
        vm.prank(owner);
        tightDist.whitelistReportContract(address(mockReport1));

        mockReport1.setRewardTotal(800 * 10 ** 18);

        vm.prank(owner);
        tightDist.mintTokensToReport(address(mockReport1));
        assertEq(tightDist.totalMintedToReport(address(mockReport1)), 800 * 10 ** 18, "minted exactly to the cap");

        mockReport1.setRewardTotal(900 * 10 ** 18);
        (uint256 quote, RecyDistribution.MintBlocker blocker) = tightDist.previewMint(address(mockReport1));
        assertEq(quote, 0);
        assertEq(uint8(blocker), uint8(RecyDistribution.MintBlocker.ExceedsCumulativeCap));
    }

    function test_outstandingEqualsBalanceIsFunded() public {
        // Guards <= vs < at the funded check: exact equality means fully funded, not shortfall.
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        _whitelist(address(mockReport1));
        vm.prank(address(distribution));
        token.mint(address(mockReport1), 1000 * 10 ** 18);

        (uint256 quote, RecyDistribution.MintBlocker blocker) = distribution.previewMint(address(mockReport1));
        assertEq(quote, 0);
        assertEq(uint8(blocker), uint8(RecyDistribution.MintBlocker.None));

        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        distribution.mintTokensToReport(address(mockReport1));
    }

    function test_batchCountsWithMixedFundedMintedSkipped() public {
        // funded (quote 0), needs-mint, blacklisted: BatchMintCompleted counts minted and skipped
        // only - a funded target is neither, by design (it emits nothing).
        mockReport1.setRewardTotal(1000 * 10 ** 18); // funded below
        mockReport2.setRewardTotal(500 * 10 ** 18); // needs 500e18
        _whitelist(address(mockReport1));
        _whitelist(address(mockReport2));
        _whitelist(address(mockReport3));
        vm.prank(address(distribution));
        token.mint(address(mockReport1), 1000 * 10 ** 18);
        vm.prank(owner);
        distribution.blacklistReportContract(address(mockReport3));

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ReportMintSkipped(address(mockReport3), RecyDistribution.MintBlocker.Blacklisted);
        vm.expectEmit(false, false, false, true);
        emit BatchMintCompleted(500 * 10 ** 18, 1, 1);
        distribution.mintTokensToAllReports();

        assertEq(token.balanceOf(address(mockReport2)), 500 * 10 ** 18, "only the gap target was minted to");
        assertEq(token.balanceOf(address(mockReport1)), 1000 * 10 ** 18, "funded target untouched");
        assertEq(token.balanceOf(address(mockReport3)), 0, "blacklisted target untouched");
    }

    function testFuzz_quoteMintNeverPanicsOrExceedsCaps(uint256 total, uint256 claimed, uint256 balance) public {
        // Hardens the quote arithmetic against future edits: for ANY accounting state the quote
        // must not panic (incl. claimed > total), must never exceed either ceiling, and must be
        // exactly the shortfall when it is non-zero.
        total = bound(total, 0, type(uint128).max);
        claimed = bound(claimed, 0, type(uint128).max);
        balance = bound(balance, 0, type(uint128).max);

        mockReport1.setRewardTotal(total);
        mockReport1.setRewardClaimed(claimed);
        _whitelist(address(mockReport1));
        if (balance > 0) {
            vm.prank(address(distribution));
            token.mint(address(mockReport1), balance);
        }

        (uint256 amount, RecyDistribution.MintBlocker blocker) = distribution.previewMint(address(mockReport1));

        if (claimed > total) {
            assertEq(amount, 0);
            assertEq(uint8(blocker), uint8(RecyDistribution.MintBlocker.AccountingInverted));
            return;
        }

        assertLe(amount, distribution.maxMintPerCall());
        assertLe(amount, distribution.maxCumulativeMintPerReport());
        if (blocker != RecyDistribution.MintBlocker.None) {
            assertEq(amount, 0, "a blocked quote must be zero");
        }
        if (amount > 0) {
            assertEq(amount, (total - claimed) - balance, "a non-zero quote is exactly the shortfall");
        }
    }

    // ========== rescueTokens NON-STANDARD TOKEN ==========

    function test_rescueTokensRevertsWhenTokenReturnsFalse() public {
        // SafeERC20 is what turns a silently-failed recovery into a revert; cRECY reverts on
        // failure itself, so only a false-returning mock can prove this.
        FalseReturnRescueToken falseToken = new FalseReturnRescueToken();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        distribution.rescueTokens(IERC20(address(falseToken)), user, 1);
    }

    // ========== INTEGRATION WITH THE REAL PROTOCOL ==========
    //
    // Everything above drives mocks whose accounting is settable - states the FIXED protocol can
    // never enter. These tests wire the real RecyToken (onlyOwner mint) and a real RecyReport
    // behind a real ERC1967 proxy, proving: the reactive shortfall path is dead against a fixed
    // report at every lifecycle stage; fundReport is the production funding path; the 100k
    // accounting-read stipend suffices for genuine proxied reads; and the real token's ownership
    // wiring behaves.

    /// @dev Hand-derived, not read back from the contract: 1500 mg at the FIRST_EPOCH divisor
    ///      (supply 1M <= 2_138_428 tokens) is 1500 * 1e18 / 1e6.
    uint256 internal constant REAL_REWARD_1500MG = 1_500_000_000_000_000;
    /// @dev One 25% leg of that reward under the 25/25/25/25 test split.
    uint256 internal constant REAL_SHARE_25 = 375_000_000_000_000;

    function _deployUnfundedRealPair(bool giveTokenOwnership)
        internal
        returns (RecyReport realReport, RecyToken realToken, RecyDistribution realDist)
    {
        // createMinimalRecyReportSetup pre-funds the pool; the whole point here is starting empty.
        realToken =
            new RecyToken("Test Token", "TEST", 1_000_000, address(deployTestEndpoint(TEST_EID)), OWNER, block.chainid);

        RecyReportAttributes attrs = new RecyReportAttributes();
        RecyReportSvg svg = new RecyReportSvg();
        RecyReportData data = new RecyReportData(address(attrs), address(svg));
        RecyReport implementation = new RecyReport();

        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "RecyReport",
            "RECY",
            address(realToken),
            address(data),
            PROTOCOL,
            uint64(3600),
            uint8(25),
            uint8(25),
            uint8(25),
            uint8(25)
        );
        realReport = RecyReport(address(new ERC1967Proxy(address(implementation), initData)));
        setupRoles(realReport);

        vm.prank(owner);
        realDist = new RecyDistribution(address(realToken), MAX_MINT_PER_CALL, MAX_CUMULATIVE_MINT);
        vm.prank(owner);
        realDist.whitelistReportContract(address(realReport));

        if (giveTokenOwnership) {
            vm.prank(OWNER);
            realToken.transferOwnership(address(realDist));
        }
    }

    function _assertNoShortfall(RecyDistribution realDist, address realReport, string memory stage) internal view {
        (uint256 quote, RecyDistribution.MintBlocker blocker) = realDist.previewMint(realReport);
        assertEq(quote, 0, string.concat("quote must be zero: ", stage));
        assertEq(uint8(blocker), uint8(RecyDistribution.MintBlocker.None), string.concat("no blocker: ", stage));
    }

    function test_integration_fixedReportNeverHasShortfall_fundReportIsTheFundingPath() public {
        (RecyReport realReport, RecyToken realToken, RecyDistribution realDist) = _deployUnfundedRealPair(true);

        // Fresh, empty, fixed report: nothing outstanding, nothing to mint.
        _assertNoShortfall(realDist, address(realReport), "fresh");
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        realDist.mintTokensToReport(address(realReport));

        uint256 tokenA = mintAndCompleteReport(realReport);

        // Validation cannot open a gap - it refuses the promise outright...
        vm.prank(VALIDATOR);
        vm.expectRevert(RecyErrors.InsufficientRewardBalance.selector);
        realReport.validateRecyReport(tokenA);

        // ...so the reactive path STILL sees nothing to do. This is the deadlock shape the
        // shortfall paths cannot resolve: validate-then-top-up no longer exists.
        _assertNoShortfall(realDist, address(realReport), "after refused validation");

        // fundReport is the way out: proactive, owner-sized, cumulative-recorded. Fund for TWO
        // reports at once to also pin that surplus is headroom, not loss.
        vm.prank(owner);
        realDist.fundReport(address(realReport), 2 * REAL_REWARD_1500MG);
        assertEq(realToken.balanceOf(address(realReport)), 2 * REAL_REWARD_1500MG);
        assertEq(realDist.totalMintedToReport(address(realReport)), 2 * REAL_REWARD_1500MG);

        vm.prank(VALIDATOR);
        realReport.validateRecyReport(tokenA);
        _assertNoShortfall(realDist, address(realReport), "validated within funding");

        vm.warp(vm.getBlockTimestamp() + 3601);
        vm.prank(USER);
        realReport.claimRecyReportReward(tokenA);

        // Four legs with independent constants; residual = pushed - paid.
        assertEq(realToken.balanceOf(USER), REAL_SHARE_25, "generator leg");
        assertEq(realToken.balanceOf(RECYCLER), REAL_SHARE_25, "recycler leg");
        assertEq(realToken.balanceOf(VALIDATOR), REAL_SHARE_25, "validator leg");
        assertEq(realToken.balanceOf(PROTOCOL), REAL_SHARE_25, "protocol leg");
        assertEq(realToken.balanceOf(address(realReport)), REAL_REWARD_1500MG, "surplus stays as headroom");

        // A second report consumes the surplus WITHOUT further funding: solvency passes at exact
        // equality (rewardTotal == balance + rewardClaimed), pinning surplus-as-headroom.
        uint256 tokenB = realReport.nftNextId();
        vm.prank(USER);
        realReport.mintRecyReport();
        (uint32[] memory m, uint128[] memory a, uint32[] memory t, uint32[] memory s) = createTestMaterials();
        uint64 recycleDate = SafeCast.toUint64(vm.getBlockTimestamp());
        vm.prank(RECYCLER);
        realReport.setRecyReportResult(tokenB, recycleDate, 1500, m, a, t, s, 1);
        vm.prank(VALIDATOR);
        realReport.validateRecyReport(tokenB);
        _assertNoShortfall(realDist, address(realReport), "second validation from surplus");

        // vm.getBlockTimestamp, not block.timestamp: under via-ir the TIMESTAMP opcode is
        // CSE-cached within one function frame, so a second `block.timestamp` read after an
        // earlier vm.warp in the same test returns the stale pre-warp value.
        vm.warp(vm.getBlockTimestamp() + 3601);
        vm.prank(USER);
        realReport.claimRecyReportReward(tokenB);

        assertEq(realToken.balanceOf(address(realReport)), 0, "pool exactly consumed");
        assertEq(realToken.balanceOf(USER), 2 * REAL_SHARE_25);

        // Whole lifecycle done; the reactive path never had anything to do.
        _assertNoShortfall(realDist, address(realReport), "lifecycle complete");
        vm.prank(owner);
        vm.expectRevert(RecyDistribution.NoMintNeeded.selector);
        realDist.mintTokensToReport(address(realReport));
    }

    function test_integration_legacyGapClosedThroughRealToken() public {
        (RecyReport realReport, RecyToken realToken, RecyDistribution realDist) = _deployUnfundedRealPair(true);

        // Build a real validated obligation, then drain the pool - the state an unguarded
        // pre-upgrade validate used to leave behind (obligation with no backing balance).
        vm.prank(OWNER);
        assertTrue(realToken.transfer(address(realReport), REAL_REWARD_1500MG));
        uint256 tokenId = mintAndCompleteReport(realReport);
        vm.prank(VALIDATOR);
        realReport.validateRecyReport(tokenId);

        vm.prank(address(realReport));
        assertTrue(realToken.transfer(address(0xD00D), REAL_REWARD_1500MG));
        assertEq(realToken.balanceOf(address(realReport)), 0);

        // A genuine shortfall, read through the real proxy within the gas stipend.
        (uint256 quote, RecyDistribution.MintBlocker blocker) = realDist.previewMint(address(realReport));
        assertEq(quote, REAL_REWARD_1500MG, "shortfall is the exact gap");
        assertEq(uint8(blocker), uint8(RecyDistribution.MintBlocker.None));

        uint256 supplyBefore = realToken.totalSupply();
        vm.prank(owner);
        realDist.mintTokensToReport(address(realReport));

        assertEq(realToken.balanceOf(address(realReport)), REAL_REWARD_1500MG, "gap closed exactly");
        assertEq(realToken.totalSupply(), supplyBefore + REAL_REWARD_1500MG, "closed by NEW supply");
        assertEq(realDist.totalMintedToReport(address(realReport)), REAL_REWARD_1500MG);

        // The revived obligation is actually payable.
        vm.warp(block.timestamp + 3601);
        vm.prank(USER);
        realReport.claimRecyReportReward(tokenId);
        assertEq(realToken.balanceOf(USER), REAL_SHARE_25);
        assertEq(realToken.balanceOf(address(realReport)), 0);
    }

    function test_integration_mintRevertsWhenDistributionNotTokenOwner() public {
        (RecyReport realReport, RecyToken realToken, RecyDistribution realDist) = _deployUnfundedRealPair(false);

        // Same legacy-gap construction, but the distribution never received token ownership.
        vm.prank(OWNER);
        assertTrue(realToken.transfer(address(realReport), REAL_REWARD_1500MG));
        uint256 tokenId = mintAndCompleteReport(realReport);
        vm.prank(VALIDATOR);
        realReport.validateRecyReport(tokenId);
        vm.prank(address(realReport));
        assertTrue(realToken.transfer(address(0xD00D), REAL_REWARD_1500MG));

        bytes memory notOwner = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(realDist));

        // token.mint is trusted infrastructure: its failure aborts, it is never a per-report skip.
        vm.prank(owner);
        vm.expectRevert(notOwner);
        realDist.mintTokensToReport(address(realReport));

        vm.prank(owner);
        vm.expectRevert(notOwner);
        realDist.mintTokensToAllReports();

        vm.prank(owner);
        vm.expectRevert(notOwner);
        realDist.fundReport(address(realReport), 1);
    }
}
// forge-lint: disable-end(reentrancy-events)
