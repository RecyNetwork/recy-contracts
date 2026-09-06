// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {RecyReportData} from "../../src/RecyReportData.sol";
import {RecyConstants} from "../../src/lib/RecyConstants.sol";
import {RecyTypes} from "../../src/lib/RecyTypes.sol";

/// @dev Test-only implementation of the proxy layout that existed before ERC-2771 support was added.
contract RecyReportOriginalLayout is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    RecyReportData private data;
    ERC20 public token;

    bytes32 public constant AUDITOR_ROLE = RecyConstants.AUDITOR_ROLE;
    bytes32 public constant RECYCLER_ROLE = RecyConstants.RECYCLER_ROLE;
    bytes32 public constant EMERGENCY_ROLE = RecyConstants.EMERGENCY_ROLE;

    address public protocolAddress;

    uint128 public nftNextId;
    uint64 public unlockDelay;
    uint8 public shareRecycler;
    uint8 public shareValidator;
    uint8 public shareGenerator;
    uint8 public shareProtocol;

    uint256 public rewardTotal;
    uint256 public rewardMinted;
    uint256 public rewardClaimed;

    mapping(uint256 => RecyTypes.RecyInfo) public info;
    mapping(uint256 => RecyTypes.RecyMaterials[]) public materials;
    mapping(uint256 => RecyTypes.RecyReward) public reward;
    mapping(uint256 => uint8) public status;
    mapping(address => address) public funds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address tokenAddress,
        address dataAddress,
        address protocolAddress_,
        uint64 unlockDelay_,
        uint8 shareRecycler_,
        uint8 shareValidator_,
        uint8 shareGenerator_,
        uint8 shareProtocol_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __AccessControl_init();
        __Pausable_init();

        data = RecyReportData(dataAddress);
        token = ERC20(tokenAddress);
        protocolAddress = protocolAddress_;
        unlockDelay = unlockDelay_;
        shareRecycler = shareRecycler_;
        shareValidator = shareValidator_;
        shareGenerator = shareGenerator_;
        shareProtocol = shareProtocol_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AUDITOR_ROLE, msg.sender);
        _grantRole(RECYCLER_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    function seedValidatedReport(address generator, address recycler, address validator, address fundWallet)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 tokenId = nftNextId;
        _mint(generator, tokenId);
        nftNextId = uint128(tokenId + 1);

        info[tokenId] = RecyTypes.RecyInfo({
            validator: validator,
            recycler: recycler,
            recycleDate: 1_700_000_001,
            auditDate: 1_700_000_002,
            wasteAmount: 1_234_567
        });
        materials[tokenId].push(
            RecyTypes.RecyMaterials({
                material: 7, recycleType: 8, recycleShape: 9, disposalMethod: 10, amountRecycled: 1_234_567
            })
        );
        reward[tokenId] = RecyTypes.RecyReward({rewardAmount: 777 ether, rewardUnlockDate: 1_700_000_003});
        status[tokenId] = RecyConstants.RECYCLE_VALIDATED;
        funds[generator] = fundWallet;

        rewardTotal = 900 ether;
        rewardMinted = 800 ether;
        rewardClaimed = 123 ether;

        _grantRole(RECYCLER_ROLE, recycler);
        _grantRole(AUDITOR_ROLE, validator);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
