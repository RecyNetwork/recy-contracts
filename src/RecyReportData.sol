// SPDX-License-Identifier: MIT

pragma solidity 0.8.36;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {RecyReportAttributes} from "./RecyReportAttributes.sol";
import {RecyReportSvg} from "./RecyReportSvg.sol";
import {RecyConstants} from "./lib/RecyConstants.sol";
import {RecyErrors} from "./lib/RecyErrors.sol";
import {RecyTypes} from "./lib/RecyTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
     * @dev Sets immutable references to attributes and SVG generation contracts. Both addresses must be
     *      non-zero and the attributes contract must expose a non-empty material catalogue, otherwise
     *      deployment reverts.
     * @param _attributesAddress The address of the RecyReportAttributes contract for material data
     * @param _svgAddress The address of the RecyReportSvg contract for image generation
     */
    constructor(address _attributesAddress, address _svgAddress) {
        if (_attributesAddress == address(0)) {
            revert RecyErrors.AddressInvalid();
        }
        if (_svgAddress == address(0)) {
            revert RecyErrors.AddressInvalid();
        }
        // RecyReport bounds material ids at write time by reading materialsCount(). Reject an
        // attributes contract that cannot answer that query, or whose catalogue is empty, at deploy
        // time rather than letting every report write revert after the report upgrade.
        if (RecyReportAttributes(_attributesAddress).getMaterials().length == 0) {
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
        string memory image = string.concat(
            "data:image/svg+xml;base64,", Base64.encode(bytes(generateSvg(_status, _materials)))
        );

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
                        '","attributes": [',
                        generateStatusText(_status),
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

    /**
     * @notice Returns the number of materials registered in the attributes catalogue
     * @dev Derived from RecyReportAttributes.getMaterials, which the currently deployed attributes
     *      contract also implements; consumed by RecyReport to reject out-of-range material ids at
     *      write time
     * @return uint256 Number of catalogue entries; valid material ids are 0 to count - 1
     */
    function materialsCount() external view returns (uint256) {
        return attributes.getMaterials().length;
    }

    /**
     * @notice Generates the status image with the selected material and its associated process icons
     * @param _status The recycling report status
     * @param _materials Recycled material rows whose positive weights determine the classification
     * @return string SVG image for the report
     */
    function generateSvg(uint8 _status, RecyTypes.RecyMaterials[] memory _materials)
        internal
        view
        returns (string memory)
    {
        if (_status == RecyConstants.RECYCLE_CREATED) {
            return svg.getTrashcan();
        }

        uint32[4] memory classifications = _topClassification(_materials);
        if (_status == RecyConstants.RECYCLE_COMPLETED) {
            return svg.getRecycle(classifications);
        }
        return svg.getCoins(_status, classifications);
    }

    /**
     * @notice Selects the top material and one actual row's recycling classifications
     * @dev Material totals use uint256; ties retain the first positive material occurrence.
     *      The representative is the heaviest positive row of that material (first on ties).
     * @param _materials Material rows, potentially containing repeated ids
     * @return classifications Material, recycle type, recycle shape, disposal method
     */
    function _topClassification(RecyTypes.RecyMaterials[] memory _materials)
        internal
        pure
        returns (uint32[4] memory classifications)
    {
        uint256 winningTotal = 0;
        uint256 winningRow = 0;
        for (uint256 i = 0; i < _materials.length; i++) {
            uint32 id = _materials[i].material;
            uint128 amount = _materials[i].amountRecycled;
            if (amount == 0) continue;

            // Only the first positive occurrence computes a material's aggregate.
            bool seen = false;
            for (uint256 j = 0; j < i; j++) {
                if (_materials[j].amountRecycled != 0 && _materials[j].material == id) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;

            uint256 total = amount;
            uint128 rowWeight = amount;
            uint256 representative = i;
            for (uint256 j = i + 1; j < _materials.length; j++) {
                if (_materials[j].material != id || _materials[j].amountRecycled == 0) continue;
                uint128 weight = _materials[j].amountRecycled;
                total += weight;
                if (weight > rowWeight) {
                    rowWeight = weight;
                    representative = j;
                }
            }
            if (total > winningTotal) {
                winningTotal = total;
                winningRow = representative;
            }
        }

        if (winningTotal != 0) {
            RecyTypes.RecyMaterials memory row = _materials[winningRow];
            classifications = [row.material, row.recycleType, row.recycleShape, row.disposalMethod];
        }
    }

    function generateMaterialsText(RecyTypes.RecyMaterials[] memory _materials)
        internal
        view
        returns (string memory materials)
    {
        for (uint256 i = 0; i < _materials.length; i++) {
            // Read-time tolerance: an id outside the attributes catalogue would otherwise revert and
            // permanently brick both tokenURI and tokenJson for the token, which is unrecoverable
            // because materials are push-only and have no repair path.
            string memory materialName;
            // Every material has a distinct live catalogue lookup; the catch is required so one
            // malformed entry cannot brick rendering for the entire report.
            // forge-lint: disable-next-line(calls-loop)
            try attributes.getMaterial(_materials[i].material) returns (string memory name) {
                materialName = name;
            } catch {
                materialName = "Unknown Material";
            }

            materials = string.concat(
                materials,
                ',{"trait_type":"',
                materialName,
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
        } else if (_status == RecyConstants.RECYCLE_INVALIDATED) {
            return "Invalidated";
        } else if (_status == RecyConstants.RECYCLE_REWARDED) {
            return "Rewarded";
        } else if (_status == RecyConstants.RECYCLE_FLAGGED) {
            return "Flagged";
        } else {
            return "Unknown";
        }
    }
}
