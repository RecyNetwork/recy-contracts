// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
    ERC20 public token;

    bytes32 public constant AUDITOR_ROLE = RecyConstants.AUDITOR_ROLE;
    bytes32 public constant RECYCLER_ROLE = RecyConstants.RECYCLER_ROLE;
    bytes32 public constant EMERGENCY_ROLE = RecyConstants.EMERGENCY_ROLE;

    /// @notice The trusted forwarder address for ERC-2771 meta-transactions (storage-based for flexibility)
    address private _storedTrustedForwarder;

    event TrustedForwarderChanged(address indexed oldForwarder, address indexed newForwarder);
    event ReportResult(uint256 indexed tokenId, address indexed recycler, uint64 recycleDate, uint128 wasteAmount);
    event ReportValidated(uint256 indexed tokenId, address indexed validator, uint64 auditDate, uint128 rewardAmount);
    event ReportInvalidated(uint256 indexed tokenId, address indexed validator, uint64 inauditDate);
    event RewardClaimed(uint256 tokenId, address indexed claimant, uint128 rewardAmount);

    address public protocolAddress;

    uint128 public nftNextId;
    uint64 public unlockDelay; // Delay in seconds before the reward can be claimed
    uint8 public shareRecycler; // Percentage of the reward that goes to the recycler
    uint8 public shareValidator; // Percentage of the reward that goes to the validator
    uint8 public shareGenerator; // Percentage of the reward that goes to the generator
    uint8 public shareProtocol; // Percentage of the reward that goes to the protocol

    uint256 public rewardTotal;
    uint256 public rewardMinted;
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
     * @dev Replaces the constructor for upgradeable contracts
     * @param _name The name of the nft
     * @param _symbol The symbol of the nft
     * @param _tokenAddress The address of the token contract (ERC20).
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

        __ERC721_init(_name, _symbol);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        token = ERC20(_tokenAddress);
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
        require(ownerOf(_tokenId) != address(0), RecyErrors.NftNotExists());

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
        require(ownerOf(_tokenId) != address(0), RecyErrors.NftNotExists());

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
        if (
            _materials.length != _materialAmounts.length || _materials.length != _recycleTypes.length
                || _materials.length != _recycleShapes.length
        ) {
            revert RecyErrors.ArrayLengthMismatch();
        }

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
        if (
            _materials.length != _materialAmounts.length || _materials.length != _recycleTypes.length
                || _materials.length != _recycleShapes.length
        ) {
            revert RecyErrors.ArrayLengthMismatch();
        }

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
     * @dev Only accounts with AUDITOR_ROLE can validate reports. Sets reward amount and unlock date
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
        _info.validator = _msgSender();
        _info.auditDate = uint64(block.timestamp);

        RecyTypes.RecyReward storage _reward = reward[_tokenId];

        _reward.rewardAmount = RecyReward.calculateReward(_info.wasteAmount, token.totalSupply());
        _reward.rewardUnlockDate = uint64(block.timestamp + unlockDelay);

        rewardTotal += _reward.rewardAmount;
        status[_tokenId] = RecyConstants.RECYCLE_VALIDATED;

        emit MetadataUpdate(_tokenId);
        emit ReportValidated(_tokenId, _msgSender(), _info.auditDate, _reward.rewardAmount);
    }

    /**
     * @notice Validates a completed recycling report and calculates rewards
     * @dev Only accounts with AUDITOR_ROLE can validate reports. Sets reward amount and unlock date
     * @param _tokenId The ID of the recycling report to validate
     * @custom:emits ReportValidated Event containing validation and reward details
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

        _reward.rewardAmount = RecyReward.calculateReward(_info.wasteAmount, token.totalSupply());
        _reward.rewardUnlockDate = uint64(block.timestamp + unlockDelay);

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
        token.transfer(
            funds[generator] == address(0) ? generator : funds[generator],
            (ra * shareGenerator) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        address recycler = _info.recycler;
        token.transfer(
            funds[recycler] == address(0) ? recycler : funds[recycler],
            (ra * shareRecycler) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        address auditor = _info.validator;
        token.transfer(
            funds[auditor] == address(0) ? auditor : funds[auditor],
            (ra * shareValidator) / RecyConstants.REWARD_TOTAL_PERCENTAGE
        );

        token.transfer(protocolAddress, (ra * shareProtocol) / RecyConstants.REWARD_TOTAL_PERCENTAGE);

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
     * @notice Sets the fund address for a signatory
     * @dev Accounts can only set their own fund address
     * @param _fundAddress The fund address to associate with the caller
     */
    function setFundsWallet(address _signatory, address _fundAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        funds[_signatory] = _fundAddress;
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
        return _storedTrustedForwarder;
    }

    /**
     * @notice Sets the trusted forwarder address for ERC-2771 meta-transactions
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can update the forwarder. Set to address(0) to disable.
     * @param _forwarder The new trusted forwarder address
     * @custom:emits TrustedForwarderChanged Event with the old and new forwarder addresses
     */
    function setTrustedForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldForwarder = _storedTrustedForwarder;
        _storedTrustedForwarder = _forwarder;
        emit TrustedForwarderChanged(oldForwarder, _forwarder);
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
