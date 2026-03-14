// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RecyReportAttributes} from "./RecyReportAttributes.sol";
import {RecyReportSvg} from "./RecyReportSvg.sol";
import {RecyConstants} from "./lib/RecyConstants.sol";
import {RecyTypes} from "./lib/RecyTypes.sol";
import {RecyErrors} from "./lib/RecyErrors.sol";

/**
 * @title RecyReportData
 * @notice Contract responsible for generating NFT metadata and visual representations for RecyReport NFTs
 * @dev Handles dynamic generation of tokenURI, JSON metadata, and SVG images based on recycling report status
 * @author Recy Protocol Team
 */
contract RecyReportData {
    /// @notice Immutable reference to the attributes contract for material type and recycling method lookups
    RecyReportAttributes public immutable attributes;

    /// @notice Immutable reference to the SVG generation contract for creating dynamic NFT images
    RecyReportSvg public immutable svg;

    /**
     * @notice Initializes the RecyReportData contract with required dependency contracts
     * @dev Sets immutable references to attributes and SVG generation contracts
     * @param _attributesAddress The address of the RecyReportAttributes contract for material data
     * @param _svgAddress The address of the RecyReportSvg contract for image generation
     */
    constructor(address _attributesAddress, address _svgAddress) {
        if (_attributesAddress == address(0)) {
            revert RecyErrors.AddressInvalid();
        }
        attributes = RecyReportAttributes(_attributesAddress);
        svg = RecyReportSvg(_svgAddress);
    }

    /**
     * @notice Generates the complete tokenURI for a RecyReport NFT with embedded SVG image
     * @dev Creates a base64-encoded data URI containing JSON metadata and SVG image for NFT marketplaces
     * @param _tokenId The unique identifier of the recycling report NFT
     * @param _status The current status of the recycling report (created, completed, validated, rewarded)
     * @param _token The ERC20 token contract used for rewards
     * @param _reward The reward information including amount and unlock date
     * @param _info The recycling information including dates, recycler, validator, and waste amount
     * @param _materials Array of recycled materials with their amounts and types
     * @return string Complete tokenURI as base64-encoded data URI for NFT metadata standard
     */
    function tokenUriAttributes(
        uint256 _tokenId,
        uint8 _status,
        ERC20 _token,
        RecyTypes.RecyReward memory _reward,
        RecyTypes.RecyInfo memory _info,
        RecyTypes.RecyMaterials[] memory _materials
    ) external view returns (string memory) {
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(generateSvg(_status))));

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"RecyReport #',
                        Strings.toString(_tokenId),
                        '", "description":"This is a Recycle Report NFT that was obtained by recycling materials."',
                        ',"image":"',
                        image,
                        '","attributes": [{"trait_type":"Status","value":"',
                        generateStatusText(_status),
                        '"}',
                        generateWasteAmountText(_info.wasteAmount),
                        generateRecycleDateText(_info.recycleDate),
                        generateauditDateText(_info.auditDate),
                        generateRewardText(_status, _reward, _token),
                        generateMaterialsText(_materials),
                        "]}"
                    )
                )
            )
        );
    }

    /**
     * @notice Generates JSON metadata for a RecyReport NFT without image data
     * @dev Creates raw JSON string with all NFT attributes and traits for external consumption
     * @param _tokenId The unique identifier of the recycling report NFT
     * @param _status The current status of the recycling report (1=created, 2=completed, 3=validated, 4=rewarded)
     * @param _token The ERC20 token contract used for reward payments
     * @param _reward The reward information including total amount and unlock timestamp
     * @param _info The recycling event information including participants and dates
     * @param _materials Array of recycled materials with detailed amounts and classifications
     * @return string Raw JSON string containing NFT metadata without base64 encoding
     */
    function tokenJson(
        uint256 _tokenId,
        uint8 _status,
        ERC20 _token,
        RecyTypes.RecyReward memory _reward,
        RecyTypes.RecyInfo memory _info,
        RecyTypes.RecyMaterials[] memory _materials
    ) external view returns (string memory) {
        return string.concat(
            '{"name":"RecyReport #',
            Strings.toString(_tokenId),
            '", "description":"This is a Recycle Report NFT that was obtained by recycling materials.","attributes": [',
            generateStatusText(_status),
            generateWasteAmountText(_info.wasteAmount),
            generateRecycleDateText(_info.recycleDate),
            generateauditDateText(_info.auditDate),
            generateRewardText(_status, _reward, _token),
            generateMaterialsText(_materials),
            "]}"
        );
    }

    function generateSvg(uint8 _status) internal view returns (string memory) {
        if (_status == RecyConstants.RECYCLE_CREATED) {
            return svg.getTrashcan();
        } else if (_status == RecyConstants.RECYCLE_COMPLETED) {
            return svg.getRecycle();
        } else {
            return svg.getCoins(_status);
        }
    }

    function generateMaterialsText(RecyTypes.RecyMaterials[] memory _materials)
        internal
        view
        returns (string memory materials)
    {
        for (uint256 i = 0; i < _materials.length; i++) {
            materials = string.concat(
                materials,
                ',{"trait_type":"',
                attributes.getMaterial(_materials[i].material),
                '","value":',
                Strings.toString(_materials[i].amountRecycled),
                ',"max_value":',
                Strings.toString(_materials[i].amountRecycled),
                "}"
            );
        }
    }

    function generateauditDateText(uint256 _auditDate) internal pure returns (string memory auditDate) {
        if (_auditDate > 0) {
            auditDate = string.concat(
                ',{"display_type":"date","trait_type":"Validation Date","value":', Strings.toString(_auditDate), "}"
            );
        }
    }

    function generateRecycleDateText(uint256 _recycleDate) internal pure returns (string memory recycleDate) {
        if (_recycleDate > 0) {
            recycleDate = string.concat(
                ',{"display_type":"date","trait_type":"Recycle Date","value":', Strings.toString(_recycleDate), "}"
            );
        }
    }

    function generateWasteAmountText(uint256 _wasteAmount) internal pure returns (string memory wasteAmount) {
        if (_wasteAmount > 0) {
            wasteAmount =
                string.concat(',{"trait_type":"Waste Amount (mg)","value":', Strings.toString(_wasteAmount), "}");
        }
    }

    function generateRewardText(uint8 _status, RecyTypes.RecyReward memory _reward, ERC20 _token)
        internal
        view
        returns (string memory reward)
    {
        if (_status > 2) {
            uint256 rewardPaid = _status == RecyConstants.RECYCLE_REWARDED ? _reward.rewardAmount : 0;
            reward = string.concat(
                ',{"trait_type":"Reward Claimed","value":',
                Strings.toString(rewardPaid / RecyConstants.ONE_E18),
                ',"max_value":',
                Strings.toString(_reward.rewardAmount / RecyConstants.ONE_E18),
                '},{"trait_type":"Reward Token","value":"',
                _token.symbol(),
                '"},{"display_type":"date","trait_type":"Reward Unlock Date","value":',
                Strings.toString(_reward.rewardUnlockDate),
                "}"
            );
        }
    }

    function generateStatusText(uint8 _status) internal pure returns (string memory status) {
        status = string.concat('{"trait_type":"Status","value":"', getStatus(_status), '"}');
    }

    function getStatus(uint8 _status) internal pure returns (string memory) {
        if (_status == RecyConstants.RECYCLE_CREATED) {
            return "Created";
        } else if (_status == RecyConstants.RECYCLE_COMPLETED) {
            return "Completed";
        } else if (_status == RecyConstants.RECYCLE_VALIDATED) {
            return "Validated";
        } else if (_status == RecyConstants.RECYCLE_REWARDED) {
            return "Rewarded";
        } else {
            revert RecyErrors.RecyReportInvalidStatus();
        }
    }
}
