// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {RecyReportData} from "./RecyReportData.sol";
import {RecyToken} from "./RecyToken.sol";
import {RecyConstants} from "./lib/RecyConstants.sol";
import {RecyTypes} from "./lib/RecyTypes.sol";
import {RecyErrors} from "./lib/RecyErrors.sol";
import {RecyReward} from "./lib/RecyReward.sol";

contract RecyReport is
    Initializable,
    ERC721Upgradeable,
    IERC4906,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ERC2771ContextUpgradeable
{
    RecyReportData private data;
    RecyToken public token;

    bytes32 public constant AUDITOR_ROLE = RecyConstants.AUDITOR_ROLE;
    bytes32 public constant RECYCLER_ROLE = RecyConstants.RECYCLER_ROLE;
    bytes32 public constant EMERGENCY_ROLE = RecyConstants.EMERGENCY_ROLE;

    /// @custom:storage-location erc7201:recy.storage.RecyReport.Forwarder
    struct ForwarderStorage {
        address trustedForwarder;
    }

    // keccak256(abi.encode(uint256(keccak256("recy.storage.RecyReport.Forwarder")) - 1))
    // & ~bytes32(uint256(0xff))
    bytes32 private constant FORWARDER_STORAGE_LOCATION =
        0x30bcef56db6f42da6964a7ba83863f99a06e22258c7b092a9ffe992173aa0200;

    event TrustedForwarderChanged(address indexed oldForwarder, address indexed newForwarder);
    event ReportResult(uint256 indexed tokenId, address indexed recycler, uint64 recycleDate, uint128 wasteAmount);
    event ReportValidated(uint256 indexed tokenId, address indexed validator, uint64 auditDate, uint128 rewardAmount);
    event ReportInvalidated(uint256 indexed tokenId, address indexed validator, uint64 inauditDate);
    event RewardClaimed(uint256 tokenId, address indexed claimant, uint128 rewardAmount);
    event UnlockDelayChanged(uint64 oldUnlockDelay, uint64 newUnlockDelay);
    event ProtocolAddressChanged(address indexed oldProtocolAddress, address indexed newProtocolAddress);

    // Forwarder configuration lives in an ERC-7201 namespace so adding it cannot shift protocol
    // state, counters, or mapping roots in any future upgrade.
    address public protocolAddress;

    uint128 public nftNextId;
    uint64 public unlockDelay; // Delay in seconds before the reward can be claimed
    uint8 public shareRecycler; // Percentage of the reward that goes to the recycler
    uint8 public shareValidator; // Percentage of the reward that goes to the validator
    uint8 public shareGenerator; // Percentage of the reward that goes to the generator
    uint8 public shareProtocol; // Percentage of the reward that goes to the protocol

    /// @notice Cumulative reward promised by every validation, in token wei
    /// @dev Invariant: `rewardTotal - rewardClaimed == outstanding claimable obligations`, i.e. the
    ///      total still owed to holders of reports sitting in RECYCLE_VALIDATED. `rewardTotal` only
    ///      ever grows, in validateRecyReport; `rewardClaimed` only ever grows, in
    ///      claimRecyReportReward, so the difference falls back to zero as reports are paid out.
    ///      Invalidation never touches either: it can only act on a report that was never validated,
    ///      so nothing was ever added for it and there is nothing to release.
    ///      RecyDistribution mints real cRECY against this difference, so it is a supply invariant.
    uint256 public rewardTotal;

    /// @custom:deprecated Never read or written. Retained solely to preserve the original UUPS
    /// storage layout; removing it would shift `rewardClaimed` and every mapping below it.
    /// Do not delete or repurpose without an explicit storage-layout review.
    uint256 public rewardMinted;

    /// @notice Cumulative reward actually paid out, in token wei
    /// @dev See the invariant documented on `rewardTotal`.
    uint256 public rewardClaimed;

    mapping(uint256 => RecyTypes.RecyInfo) public info;
    mapping(uint256 => RecyTypes.RecyMaterials[]) public materials;
    mapping(uint256 => RecyTypes.RecyReward) public reward;
    mapping(uint256 => uint8) public status;

    mapping(address => address) public funds;

    /**
     * @notice Modifier to check if caller owns the specified token or if it was the recycler or auditor involved with the specific report
     * @param _tokenId The token ID to check ownership for
     */
    modifier onlyTokenOwnerOrRecyclerOrAuditor(uint256 _tokenId) {
        RecyTypes.RecyInfo storage _info = info[_tokenId];
        address sender = _msgSender();
        require(
            ownerOf(_tokenId) == sender || _info.recycler == sender || _info.validator == sender,
            RecyErrors.NotReportOwner()
        );

        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable contract
     * @dev Replaces the constructor for upgradeable contracts. Rewards exist only on the token's
     *      issuance chain, so initialization rejects every other chain without changing this ABI.
     * @param _name The name of the nft
     * @param _symbol The symbol of the nft
     * @param _tokenAddress The address of the RECY OFT token.
     * @param _dataAddress The address of the data contract.
     * @param _protocolAddress The address of the protocol
     * @param _unlockDelay The delay in seconds before the reward can be claimed
     * @param _shareRecycler Percentage of the reward that goes to the recycler
     * @param _shareValidator Percentage of the reward that goes to the validator
     * @param _shareGenerator Percentage of the reward that goes to the generator
     * @param _shareProtocol Percentage of the reward that goes to the protocol
     *
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _tokenAddress,
        address _dataAddress,
        address _protocolAddress,
        uint64 _unlockDelay,
        uint8 _shareRecycler,
        uint8 _shareValidator,
        uint8 _shareGenerator,
        uint8 _shareProtocol
    ) public initializer {
        if (_tokenAddress == address(0) || _dataAddress == address(0)) {
            revert RecyErrors.AddressInvalid();
        }
        if (RecyToken(_tokenAddress).issuanceChainId() != block.chainid) {
            revert RecyErrors.RewardsUnavailableOnThisChain();
        }
        // A proxy must not be BORN outside the unlock-delay bounds either: the delay is the
        // EMERGENCY_ROLE reaction window (zero deletes it silently) and near-uint64.max values
        // wrap the unlock-date sum at validation into the past. Same bounds as setUnlockDelay.
        if (_unlockDelay < RecyConstants.MIN_UNLOCK_DELAY || _unlockDelay > RecyConstants.MAX_UNLOCK_DELAY) {
            revert RecyErrors.UnlockDelayOutOfBounds();
        }

        __ERC721_init(_name, _symbol);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        token = RecyToken(_tokenAddress);
        data = RecyReportData(_dataAddress);

        protocolAddress = _protocolAddress;
        unlockDelay = _unlockDelay;

        require(
            _shareRecycler + _shareValidator + _shareGenerator + _shareProtocol
                == RecyConstants.REWARD_TOTAL_PERCENTAGE,
            RecyErrors.RecyReportInvalidShareDistribution()
        );

        shareRecycler = _shareRecycler;
        shareValidator = _shareValidator;
        shareGenerator = _shareGenerator;
        shareProtocol = _shareProtocol;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(AUDITOR_ROLE, _msgSender());
        _grantRole(RECYCLER_ROLE, _msgSender());
        _grantRole(EMERGENCY_ROLE, _msgSender());
    }

    /**
     * @notice Required for UUPS upgrades
     * @dev Only admin can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @notice Get the version of the contract
     * @return The version string
     */
    function version() public pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Pauses reward claiming in case of emergency
     * @dev Only accounts with EMERGENCY_ROLE can pause reward claiming
     * @custom:emits Paused Event indicating emergency pause activation
     */
    function pauseRewardClaiming() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses reward claiming after emergency is resolved
     * @dev Only accounts with EMERGENCY_ROLE can unpause reward claiming
     * @custom:emits Unpaused Event indicating emergency pause deactivation
     */
    function unpauseRewardClaiming() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    /**
     * @notice Combines ERC721 with AccessControl interface support
     * @dev Checks if the contract supports a given interface, including ERC4906 for metadata updates
     * @param interfaceId The interface identifier to check for support
     * @return bool True if the interface is supported, false otherwise
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == RecyConstants.ERC4906_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    /**
     * @notice This function gets the tokenURI for this RecyReport.
     * @dev The tokenURI is dynamically generated, it will be based on the information like materials, validation and rewards.
     * @param _tokenId The id of the RecyReport.
     * @return _tokenUri a string which is the tokenURI of a RecyReport.
     *
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory _tokenUri) {
        _requireOwned(_tokenId);

        return data.tokenUriAttributes(
            _tokenId, status[_tokenId], token, reward[_tokenId], info[_tokenId], materials[_tokenId]
        );
    }

    /**
     * @notice This function gets the JSON metadata for this RecyReport
     * @dev The JSON is dynamically generated based on materials, validation status and rewards
     * @param _tokenId The id of the RecyReport
     * @return _tokenUri A JSON string containing the metadata of the RecyReport
     */
    function tokenJson(uint256 _tokenId) public view returns (string memory _tokenUri) {
        _requireOwned(_tokenId);

        return data.tokenJson(_tokenId, status[_tokenId], token, reward[_tokenId], info[_tokenId], materials[_tokenId]);
    }

    /**
     * @notice Mints a new empty Recycle Report NFT
     * @dev Creates a new NFT with RECYCLE_CREATED status and increments nftNextId
     * @custom:emits Transfer event from ERC721 standard
     */
    function mintRecyReport() external {
        uint256 nftId = nftNextId;
        _safeMint(_msgSender(), nftId);
        status[nftId] = RecyConstants.RECYCLE_CREATED;
        nftNextId = uint128(nftId + RecyConstants.NFT_ID_INCREMENT);
    }

    /**
     * @notice Validates the inputs shared by both report write paths
     * @dev Reverts on array-length mismatch, an empty report, a waste amount above the per-report
     *      cap, or a material id outside the catalogue the data contract exposes. An out-of-range
     *      id would make tokenURI and tokenJson revert forever, and `materials` is push-only, so
     *      the token could never be repaired — this is the only place it can be stopped.
     * @param _wasteAmount The total amount of waste recycled in milligrams
     * @param _materials Array of material type indices referencing RecyReportAttributes
     * @param _materialAmounts Array of amounts for each material type in milligrams
     * @param _recycleTypes Array of recycling process types used for each material
     * @param _recycleShapes Array of material shapes processed for each material
     */
    function _validateReportInput(
        uint128 _wasteAmount,
        uint32[] memory _materials,
        uint128[] memory _materialAmounts,
        uint32[] memory _recycleTypes,
        uint32[] memory _recycleShapes
    ) private view {
        if (
            _materials.length != _materialAmounts.length || _materials.length != _recycleTypes.length
                || _materials.length != _recycleShapes.length
        ) {
            revert RecyErrors.ArrayLengthMismatch();
        }

        require(_materials.length > 0, RecyErrors.EmptyMaterialsArray());
        require(_wasteAmount <= RecyConstants.MAX_WASTE_AMOUNT, RecyErrors.WasteAmountExceedsCap());

        // Read the catalogue size once; it cannot change while this call executes.
        uint256 materialsCount = data.materialsCount();
        for (uint256 i = 0; i < _materials.length; i++) {
            require(_materials[i] < materialsCount, RecyErrors.MaterialIdOutOfRange());
        }
    }

    /**
     * @notice Mints a new Recycle Report NFT with complete recycling data
     * @dev Creates NFT and populates it with recycling information, only callable by RECYCLER_ROLE
     * @param _generator The address that will receive the NFT (waste generator)
     * @param _recycleDate The timestamp when recycling occurred
     * @param _wasteAmount The total amount of waste recycled in milligrams
     * @param _materials Array of material type indices
     * @param _materialAmounts Array of amounts for each material type
     * @param _recycleTypes Array of recycling process types used
     * @param _recycleShapes Array of material shapes processed
     * @param _disposalMethod The disposal method used for processing
     * @custom:emits ReportResult Event containing recycling completion details
     * @custom:emits MetadataUpdate Event for NFT metadata refresh
     * @custom:emits Transfer Event from ERC721 standard
     */
    function mintRecyReportResult(
        address _generator,
        uint64 _recycleDate,
        uint128 _wasteAmount,
        uint32[] memory _materials,
        uint128[] memory _materialAmounts,
        uint32[] memory _recycleTypes,
        uint32[] memory _recycleShapes,
        uint32 _disposalMethod
    ) external onlyRole(RECYCLER_ROLE) {
        _validateReportInput(_wasteAmount, _materials, _materialAmounts, _recycleTypes, _recycleShapes);

        uint256 nftId = nftNextId;
        _safeMint(_generator, nftId);
        nftNextId = uint128(nftId + RecyConstants.NFT_ID_INCREMENT);

        RecyTypes.RecyInfo storage _info = info[nftId];
        _info.recycleDate = uint64(_recycleDate);
        _info.recycler = _msgSender();
        _info.wasteAmount = _wasteAmount;

        RecyTypes.RecyMaterials[] storage recyMaterials = materials[nftId];
        for (uint256 i = 0; i < _materials.length; i++) {
            recyMaterials.push(
                RecyTypes.RecyMaterials({
                    material: _materials[i],
                    recycleType: _recycleTypes[i],
                    recycleShape: _recycleShapes[i],
                    disposalMethod: _disposalMethod,
                    amountRecycled: _materialAmounts[i]
                })
            );
        }

        status[nftId] = RecyConstants.RECYCLE_COMPLETED;

        emit MetadataUpdate(nftId);
        emit ReportResult(nftId, _msgSender(), _info.recycleDate, _info.wasteAmount);
    }

    /**
     * @notice Updates an existing NFT with recycling data and materials information
     * @dev Populates recycling information for an existing token, only callable by RECYCLER_ROLE
     * @param _tokenId The ID of the existing NFT to update
     * @param _recycleDate The timestamp when recycling occurred
     * @param _wasteAmount The total amount of waste recycled in milligrams
     * @param _materials Array of material type indices referencing RecyReportAttributes
     * @param _materialAmounts Array of amounts for each material type in milligrams
     * @param _recycleTypes Array of recycling process types used for each material
     * @param _recycleShapes Array of material shapes processed for each material
     * @param _disposalMethod The disposal method identifier used for processing
     * @custom:emits ReportResult Event containing recycling completion details
     * @custom:emits MetadataUpdate Event for NFT metadata refresh
     */
    function setRecyReportResult(
        uint256 _tokenId,
        uint64 _recycleDate,
        uint128 _wasteAmount,
        uint32[] memory _materials,
        uint128[] memory _materialAmounts,
        uint32[] memory _recycleTypes,
        uint32[] memory _recycleShapes,
        uint32 _disposalMethod
    ) external onlyRole(RECYCLER_ROLE) {
        require(_ownerOf(_tokenId) != address(0), RecyErrors.NftNotExists());
        require(status[_tokenId] == RecyConstants.RECYCLE_CREATED, RecyErrors.RecyReportInvalidStatus());

        _validateReportInput(_wasteAmount, _materials, _materialAmounts, _recycleTypes, _recycleShapes);

        RecyTypes.RecyInfo storage _info = info[_tokenId];
        _info.recycler = _msgSender();
        _info.recycleDate = uint64(_recycleDate);
        _info.wasteAmount = _wasteAmount;

        RecyTypes.RecyMaterials[] storage recyMaterials = materials[_tokenId];
        for (uint256 i = 0; i < _materials.length; i++) {
            recyMaterials.push(
                RecyTypes.RecyMaterials({
                    material: _materials[i],
                    recycleType: _recycleTypes[i],
                    recycleShape: _recycleShapes[i],
                    disposalMethod: _disposalMethod,
                    amountRecycled: _materialAmounts[i]
                })
            );
        }

        status[_tokenId] = RecyConstants.RECYCLE_COMPLETED;

        emit MetadataUpdate(_tokenId);
        emit ReportResult(_tokenId, _msgSender(), _info.recycleDate, _info.wasteAmount);
    }

    /**
     * @notice Validates a completed recycling report and calculates rewards
     * @dev Only accounts with AUDITOR_ROLE can validate reports. Sets reward amount and unlock date.
     *      Requires dual control: the validator must not be the account that recorded the report,
     *      otherwise a single key holding both RECYCLER_ROLE and AUDITOR_ROLE could sign off on its
     *      own work and collect the generator, recycler and validator legs of the payout.
     *      Also refuses to promise more than the contract can pay, see the invariant on rewardTotal.
     * @param _tokenId The ID of the recycling report to validate
     * @custom:emits ReportValidated Event containing validation and reward details
     * @custom:emits MetadataUpdate Event for NFT metadata refresh
     */
    function validateRecyReport(uint256 _tokenId) external onlyRole(AUDITOR_ROLE) {
        require(
            status[_tokenId] == RecyConstants.RECYCLE_COMPLETED || status[_tokenId] == RecyConstants.RECYCLE_FLAGGED,
            RecyErrors.RecyReportNotCompleted()
        );

        RecyTypes.RecyInfo storage _info = info[_tokenId];
        require(_msgSender() != _info.recycler, RecyErrors.ValidatorCannotBeRecycler());

        _info.validator = _msgSender();
        _info.auditDate = uint64(block.timestamp);

        RecyTypes.RecyReward storage _reward = reward[_tokenId];

        // Bridging and burning change circulating supply but never the cumulative issuance that
        // selects a reward epoch.
        _reward.rewardAmount = RecyReward.calculateReward(_info.wasteAmount, token.totalIssued());
        _reward.rewardUnlockDate = uint64(block.timestamp + unlockDelay);

        rewardTotal += _reward.rewardAmount;

        // Solvency: outstanding obligations, which now include the reward added on the line above,
        // must stay fully covered by the contract's balance. This is `rewardTotal - rewardClaimed
        // <= balanceOf(this)` with the subtraction moved to the right-hand side so it cannot
        // underflow. Claimed rewards are deliberately excluded — they have already left the
        // contract, so counting them would reject validations the pool can comfortably pay.
        require(rewardTotal <= token.balanceOf(address(this)) + rewardClaimed, RecyErrors.InsufficientRewardBalance());

        status[_tokenId] = RecyConstants.RECYCLE_VALIDATED;

        emit MetadataUpdate(_tokenId);
        emit ReportValidated(_tokenId, _msgSender(), _info.auditDate, _reward.rewardAmount);
    }

    /**
     * @notice Invalidates a completed recycling report, closing it with no claimable reward
     * @dev Only accounts with AUDITOR_ROLE can invalidate reports. Deliberately records a zero
     *      reward: an invalidated report can never be claimed (claiming requires RECYCLE_VALIDATED),
     *      and the metadata renders a reward for any status above RECYCLE_COMPLETED, so writing a
     *      non-zero amount would advertise a payout that will never happen. `rewardTotal` is left
     *      alone because only validation adds to it and this path never accepts a validated report.
     * @param _tokenId The ID of the recycling report to invalidate
     * @custom:emits ReportInvalidated Event containing invalidation details
     * @custom:emits MetadataUpdate Event for NFT metadata refresh
     */
    function invalidateRecyReport(uint256 _tokenId) external onlyRole(AUDITOR_ROLE) {
        require(
            status[_tokenId] == RecyConstants.RECYCLE_COMPLETED || status[_tokenId] == RecyConstants.RECYCLE_FLAGGED,
            RecyErrors.RecyReportNotCompleted()
        );

        RecyTypes.RecyInfo storage _info = info[_tokenId];
        _info.validator = _msgSender();
        _info.auditDate = uint64(block.timestamp);

        RecyTypes.RecyReward storage _reward = reward[_tokenId];

        _reward.rewardAmount = 0;
        _reward.rewardUnlockDate = 0;

        status[_tokenId] = RecyConstants.RECYCLE_INVALIDATED;

        emit MetadataUpdate(_tokenId);
        emit ReportInvalidated(_tokenId, _msgSender(), _info.auditDate);
    }

    /**
     * @notice Claims and distributes rewards for a validated recycling report
     * @dev Only the NFT owner can claim rewards. Distributes tokens to all parties based on configured percentages
     * @param _tokenId The ID of the validated recycling report to claim rewards for
     * @custom:emits RewardClaimed Event containing reward distribution details
     * @custom:emits MetadataUpdate Event for NFT metadata refresh
     */
    function claimRecyReportReward(uint256 _tokenId) public onlyTokenOwnerOrRecyclerOrAuditor(_tokenId) whenNotPaused {
        require(status[_tokenId] == RecyConstants.RECYCLE_VALIDATED, RecyErrors.RecyReportNotValidated());

        RecyTypes.RecyReward storage _reward = reward[_tokenId];
        require(_reward.rewardUnlockDate <= block.timestamp, RecyErrors.RewardNotUnlocked());
        uint128 ra = _reward.rewardAmount;
        require(token.balanceOf(address(this)) >= ra, RecyErrors.InsufficientRewardBalance());

        rewardClaimed += uint256(ra);
        status[_tokenId] = RecyConstants.RECYCLE_REWARDED;

        RecyTypes.RecyInfo storage _info = info[_tokenId];

        address generator = ownerOf(_tokenId);
        SafeERC20.safeTransfer(
            IERC20(address(token)),
            funds[generator] == address(0) ? generator : funds[generator],
            (ra * shareGenerator) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        address recycler = _info.recycler;
        SafeERC20.safeTransfer(
            IERC20(address(token)),
            funds[recycler] == address(0) ? recycler : funds[recycler],
            (ra * shareRecycler) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        address auditor = _info.validator;
        SafeERC20.safeTransfer(
            IERC20(address(token)),
            funds[auditor] == address(0) ? auditor : funds[auditor],
            (ra * shareValidator) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        SafeERC20.safeTransfer(
            IERC20(address(token)), protocolAddress, (ra * shareProtocol) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        emit MetadataUpdate(_tokenId);
        emit RewardClaimed(_tokenId, _msgSender(), ra);
    }

    /**
     * @notice Retrieves all recycled materials data for a specific report
     * @dev Returns the complete array of materials with their recycling details
     * @param _tokenId The ID of the recycling report
     * @return RecyTypes.RecyMaterials[] Array of material information including amounts, types, and shapes
     */
    function getRecyReportMaterials(uint256 _tokenId) external view returns (RecyTypes.RecyMaterials[] memory) {
        return materials[_tokenId];
    }

    /**
     * @notice Gets the timestamp when rewards can be claimed for a specific report
     * @dev Returns the unlock date calculated during validation (validation time + unlock delay)
     * @param _tokenId The ID of the recycling report
     * @return uint64 Timestamp when rewards become claimable
     */
    function unlockDate(uint256 _tokenId) external view returns (uint64) {
        RecyTypes.RecyReward storage _reward = reward[_tokenId];
        return _reward.rewardUnlockDate;
    }

    /**
     * @notice Sets the caller's own fund address
     * @dev Self-service by design. `funds` is resolved at claim time while the reward amount is
     *      snapshotted at validation, so an admin able to set this for other accounts could
     *      redirect an already-earned payout. Only the account itself may change its destination.
     *      Set to address(0) to be paid directly.
     * @param _fundAddress The fund address to associate with the caller
     */
    function setFundsWallet(address _fundAddress) external {
        funds[_msgSender()] = _fundAddress;
    }

    function setDataContract(address _dataAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_dataAddress == address(0)) revert RecyErrors.AddressInvalid();
        data = RecyReportData(_dataAddress);
    }

    /**
     * @notice Sets the delay in seconds between a report's validation and its reward unlocking
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can update the delay. It applies to reports
     *      validated after this call; already-validated reports keep the unlock date snapshotted
     *      at validation time. Bounded to [MIN_UNLOCK_DELAY, MAX_UNLOCK_DELAY]: the delay is the
     *      reaction window in which EMERGENCY_ROLE can pause a fraudulent payout, so zero must be
     *      impossible by typo, and a value near type(uint64).max would wrap the unlock-date sum
     *      at validation into the past - zero by another name. `initialize` enforces the same
     *      bounds, so a proxy cannot be born outside them; the live proxy (initialized at 60s
     *      before the bounds existed) is grandfathered only until this setter is first called.
     * @param _unlockDelay The new delay in seconds
     * @custom:emits UnlockDelayChanged Event with the old and new delays
     */
    function setUnlockDelay(uint64 _unlockDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_unlockDelay < RecyConstants.MIN_UNLOCK_DELAY || _unlockDelay > RecyConstants.MAX_UNLOCK_DELAY) {
            revert RecyErrors.UnlockDelayOutOfBounds();
        }
        uint64 oldUnlockDelay = unlockDelay;
        unlockDelay = _unlockDelay;
        emit UnlockDelayChanged(oldUnlockDelay, _unlockDelay);
    }

    /**
     * @notice Sets the address that receives the protocol share of every claimed reward
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can update it. The zero address is rejected
     *      because the protocol leg of a claim would then revert, bricking every claim.
     * @param _protocolAddress The new protocol address
     * @custom:emits ProtocolAddressChanged Event with the old and new protocol addresses
     */
    function setProtocolAddress(address _protocolAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_protocolAddress == address(0)) revert RecyErrors.AddressInvalid();
        address oldProtocolAddress = protocolAddress;
        protocolAddress = _protocolAddress;
        emit ProtocolAddressChanged(oldProtocolAddress, _protocolAddress);
    }

    // =========================================================================
    // ERC-2771 Meta-Transaction Support
    // =========================================================================

    /**
     * @notice Returns the trusted forwarder address for ERC-2771 meta-transactions
     * @dev Overrides OZ's immutable forwarder with a storage-based one for admin flexibility
     * @return The address of the currently configured trusted forwarder
     */
    function trustedForwarder() public view override returns (address) {
        return _getForwarderStorage().trustedForwarder;
    }

    /**
     * @notice Sets the trusted forwarder address for ERC-2771 meta-transactions
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can update the forwarder. Set to address(0) to disable.
     * @param _forwarder The new trusted forwarder address
     * @custom:emits TrustedForwarderChanged Event with the old and new forwarder addresses
     */
    function setTrustedForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ForwarderStorage storage $ = _getForwarderStorage();
        address oldForwarder = $.trustedForwarder;
        $.trustedForwarder = _forwarder;
        emit TrustedForwarderChanged(oldForwarder, _forwarder);
    }

    function _getForwarderStorage() private pure returns (ForwarderStorage storage $) {
        assembly {
            $.slot := FORWARDER_STORAGE_LOCATION
        }
    }

    /**
     * @dev Resolve _msgSender conflict between ContextUpgradeable and ERC2771ContextUpgradeable
     */
    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /**
     * @dev Resolve _msgData conflict between ContextUpgradeable and ERC2771ContextUpgradeable
     */
    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @dev Resolve _contextSuffixLength conflict between ContextUpgradeable and ERC2771ContextUpgradeable
     */
    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
