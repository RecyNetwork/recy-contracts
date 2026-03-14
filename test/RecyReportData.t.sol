// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {RecyReportData} from "../src/RecyReportData.sol";
import {RecyReportAttributes} from "../src/RecyReportAttributes.sol";
import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyErrors} from "../src/lib/RecyErrors.sol";
import {RecyTypes} from "../src/lib/RecyTypes.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./helpers/TestHelpers.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}
}

contract RecyReportDataHarness is RecyReportData {
    constructor(
        address _attributesAddress,
        address _svgAddress
    ) RecyReportData(_attributesAddress, _svgAddress) {}

    function exposed_getStatus(
        uint8 _status
    ) external pure returns (string memory) {
        return getStatus(_status);
    }

    function exposed_generateSvg(
        uint8 _status
    ) external view returns (string memory) {
        return generateSvg(_status);
    }

    function exposed_generateMaterialsText(
        RecyTypes.RecyMaterials[] memory _materials
    ) external view returns (string memory) {
        return generateMaterialsText(_materials);
    }

    function exposed_generateauditDateText(
        uint256 _auditDate
    ) external pure returns (string memory) {
        return generateauditDateText(_auditDate);
    }

    function exposed_generateRecycleDateText(
        uint256 _recycleDate
    ) external pure returns (string memory) {
        return generateRecycleDateText(_recycleDate);
    }

    function exposed_generateWasteAmountText(
        uint256 _wasteAmount
    ) external pure returns (string memory) {
        return generateWasteAmountText(_wasteAmount);
    }

    function exposed_generateRewardText(
        uint8 _status,
        RecyTypes.RecyReward memory _reward,
        ERC20 _token
    ) external view returns (string memory) {
        return generateRewardText(_status, _reward, _token);
    }

    function exposed_generateStatusText(
        uint8 _status
    ) external pure returns (string memory) {
        return generateStatusText(_status);
    }
}

contract RecyReportDataTest is Test, TestHelpers {
    RecyReportDataHarness public recyReportData;
    RecyReportAttributes public attributes;
    RecyReportSvg public recyReportSvg;
    MockToken public mockToken;

    function setUp() public {
        attributes = new RecyReportAttributes();
        recyReportSvg = new RecyReportSvg();
        mockToken = new MockToken();

        recyReportData = new RecyReportDataHarness(
            address(attributes),
            address(recyReportSvg)
        );
    }

    function test_constructor() public {
        // Test valid constructor
        RecyReportData newContract = new RecyReportData(
            address(attributes),
            address(recyReportSvg)
        );
        assertEq(address(newContract.attributes()), address(attributes));
        assertEq(address(newContract.svg()), address(recyReportSvg));
    }

    function test_constructor_invalidAddress() public {
        // Test constructor with invalid attributes address
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        new RecyReportData(address(0), address(recyReportSvg));
    }

    function test_getStatus() public view {
        // Test RECYCLE_CREATED status
        string memory createdStatus = recyReportData.exposed_getStatus(1); // RecyConstants.RECYCLE_CREATED
        assertEq(createdStatus, "Created", "RECYCLE_CREATED status mismatch");

        // Test RECYCLE_COMPLETED status
        string memory completedStatus = recyReportData.exposed_getStatus(2); // RecyConstants.RECYCLE_COMPLETED
        assertEq(
            completedStatus,
            "Completed",
            "RECYCLE_COMPLETED status mismatch"
        );

        // Test RECYCLE_VALIDATED status
        string memory validatedStatus = recyReportData.exposed_getStatus(3); // RecyConstants.RECYCLE_VALIDATED
        assertEq(
            validatedStatus,
            "Validated",
            "RECYCLE_VALIDATED status mismatch"
        );

        // Test RECYCLE_REWARDED status
        string memory rewardedStatus = recyReportData.exposed_getStatus(4); // RecyConstants.RECYCLE_REWARDED
        assertEq(
            rewardedStatus,
            "Rewarded",
            "RECYCLE_REWARDED status mismatch"
        );
    }

    function test_getStatus_invalidStatus() public {
        // Test invalid status should revert
        vm.expectRevert(RecyErrors.RecyReportInvalidStatus.selector);
        recyReportData.exposed_getStatus(5); // Invalid status

        vm.expectRevert(RecyErrors.RecyReportInvalidStatus.selector);
        recyReportData.exposed_getStatus(0); // Invalid status
    }

    function test_generateSvg() public view {
        // Test RECYCLE_CREATED status
        string memory createdSvg = recyReportData.exposed_generateSvg(
            RecyConstants.RECYCLE_CREATED
        );
        assertTrue(
            bytes(createdSvg).length > 0,
            "Created SVG should not be empty"
        );

        // Test RECYCLE_COMPLETED status
        string memory completedSvg = recyReportData.exposed_generateSvg(
            RecyConstants.RECYCLE_COMPLETED
        );
        assertTrue(
            bytes(completedSvg).length > 0,
            "Completed SVG should not be empty"
        );

        // Test RECYCLE_VALIDATED status (should return coins)
        string memory validatedSvg = recyReportData.exposed_generateSvg(
            RecyConstants.RECYCLE_VALIDATED
        );
        assertTrue(
            bytes(validatedSvg).length > 0,
            "Validated SVG should not be empty"
        );

        // Test RECYCLE_REWARDED status (should return coins)
        string memory rewardedSvg = recyReportData.exposed_generateSvg(
            RecyConstants.RECYCLE_REWARDED
        );
        assertTrue(
            bytes(rewardedSvg).length > 0,
            "Rewarded SVG should not be empty"
        );
    }

    function test_generateMaterialsText() public view {
        // Create test materials using helper
        RecyTypes.RecyMaterials[]
            memory materials = new RecyTypes.RecyMaterials[](2);
        materials[0] = createRecyMaterials(1, 1, 1, 1, 100);
        materials[1] = createRecyMaterials(2, 2, 2, 2, 200);

        string memory result = recyReportData.exposed_generateMaterialsText(
            materials
        );
        assertTrue(
            bytes(result).length > 0,
            "Materials text should not be empty"
        );

        // Should contain material information
        assertTrue(
            keccak256(bytes(result)) != keccak256(bytes("")),
            "Materials text should contain data"
        );
    }

    function test_generateauditDateText() public view {
        // Test with valid date
        uint256 validDate = 1234567890;
        string memory result = recyReportData.exposed_generateauditDateText(
            validDate
        );
        assertTrue(
            bytes(result).length > 0,
            "Validation date text should not be empty"
        );

        // Test with zero date
        string memory zeroResult = recyReportData.exposed_generateauditDateText(
            0
        );
        assertEq(
            bytes(zeroResult).length,
            0,
            "Zero validation date should return empty string"
        );
    }

    function test_generateRecycleDateText() public view {
        // Test with valid date
        uint256 validDate = 1234567890;
        string memory result = recyReportData.exposed_generateRecycleDateText(
            validDate
        );
        assertTrue(
            bytes(result).length > 0,
            "Recycle date text should not be empty"
        );

        // Test with zero date
        string memory zeroResult = recyReportData
            .exposed_generateRecycleDateText(0);
        assertEq(
            bytes(zeroResult).length,
            0,
            "Zero recycle date should return empty string"
        );
    }

    function test_generateWasteAmountText() public view {
        // Test with valid amount
        uint256 validAmount = 1000;
        string memory result = recyReportData.exposed_generateWasteAmountText(
            validAmount
        );
        assertTrue(
            bytes(result).length > 0,
            "Waste amount text should not be empty"
        );

        // Test with zero amount
        string memory zeroResult = recyReportData
            .exposed_generateWasteAmountText(0);
        assertEq(
            bytes(zeroResult).length,
            0,
            "Zero waste amount should return empty string"
        );
    }

    function test_generateRewardText() public view {
        // Create test reward using helper
        RecyTypes.RecyReward memory reward = createRecyReward(
            uint128(1000 * RecyConstants.ONE_E18),
            1234567890
        );

        // Test with status > 2 (VALIDATED)
        string memory validatedResult = recyReportData
            .exposed_generateRewardText(
                RecyConstants.RECYCLE_VALIDATED,
                reward,
                mockToken
            );
        assertTrue(
            bytes(validatedResult).length > 0,
            "Validated reward text should not be empty"
        );

        // Test with REWARDED status
        string memory rewardedResult = recyReportData
            .exposed_generateRewardText(
                RecyConstants.RECYCLE_REWARDED,
                reward,
                mockToken
            );
        assertTrue(
            bytes(rewardedResult).length > 0,
            "Rewarded text should not be empty"
        );

        // Test with status <= 2 (CREATED or COMPLETED)
        string memory createdResult = recyReportData.exposed_generateRewardText(
            RecyConstants.RECYCLE_CREATED,
            reward,
            mockToken
        );
        assertEq(
            bytes(createdResult).length,
            0,
            "Created status should return empty reward text"
        );
    }

    function test_generateStatusText() public view {
        string memory result = recyReportData.exposed_generateStatusText(
            RecyConstants.RECYCLE_CREATED
        );
        assertTrue(bytes(result).length > 0, "Status text should not be empty");

        // Should contain "Created"
        assertTrue(
            keccak256(bytes(result)) != keccak256(bytes("")),
            "Status text should contain data"
        );
    }

    function test_tokenUriAttributes() public view {
        // Create test data
        RecyTypes.RecyReward memory reward = RecyTypes.RecyReward({
            rewardAmount: uint128(1000 * RecyConstants.ONE_E18),
            rewardUnlockDate: 1234567890
        });

        RecyTypes.RecyInfo memory info = RecyTypes.RecyInfo({
            validator: address(0x123),
            recycler: address(0x456),
            recycleDate: 1234567890,
            auditDate: 1234567890,
            wasteAmount: 1000
        });

        RecyTypes.RecyMaterials[]
            memory materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = RecyTypes.RecyMaterials({
            material: 1,
            recycleType: 1,
            recycleShape: 1,
            disposalMethod: 1,
            amountRecycled: 100
        });

        string memory uri = recyReportData.tokenUriAttributes(
            1,
            RecyConstants.RECYCLE_VALIDATED,
            mockToken,
            reward,
            info,
            materials
        );

        assertTrue(bytes(uri).length > 0, "Token URI should not be empty");

        // Should start with data:application/json;base64,
        string memory expectedPrefix = "data:application/json;base64,";
        bytes memory uriBytes = bytes(uri);
        bytes memory prefixBytes = bytes(expectedPrefix);

        bool startsWithPrefix = true;
        if (uriBytes.length < prefixBytes.length) {
            startsWithPrefix = false;
        } else {
            for (uint256 i = 0; i < prefixBytes.length; i++) {
                if (uriBytes[i] != prefixBytes[i]) {
                    startsWithPrefix = false;
                    break;
                }
            }
        }

        assertTrue(
            startsWithPrefix,
            "Token URI should start with data:application/json;base64,"
        );
    }

    function test_tokenUriAttributesTest() public view {
        // Create test data
        RecyTypes.RecyReward memory reward = RecyTypes.RecyReward({
            rewardAmount: uint128(1000 * RecyConstants.ONE_E18),
            rewardUnlockDate: 1234567890
        });

        RecyTypes.RecyInfo memory info = RecyTypes.RecyInfo({
            validator: address(0x789),
            recycler: address(0xABC),
            recycleDate: 1234567890,
            auditDate: 1234567890,
            wasteAmount: 1000
        });

        RecyTypes.RecyMaterials[]
            memory materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = RecyTypes.RecyMaterials({
            material: 1,
            recycleType: 1,
            recycleShape: 1,
            disposalMethod: 1,
            amountRecycled: 100
        });

        string memory result = recyReportData.tokenJson(
            1,
            RecyConstants.RECYCLE_VALIDATED,
            mockToken,
            reward,
            info,
            materials
        );

        assertTrue(
            bytes(result).length > 0,
            "Token JSON test should not be empty"
        );

        // Should contain JSON structure
        assertTrue(
            keccak256(bytes(result)) != keccak256(bytes("")),
            "Token URI test should contain data"
        );
    }

    // ===== EDGE CASE TESTS =====

    function test_generateMaterialsTextWithSingleMaterial() public view {
        RecyTypes.RecyMaterials[]
            memory singleMaterial = new RecyTypes.RecyMaterials[](1);
        singleMaterial[0] = RecyTypes.RecyMaterials({
            material: 1,
            recycleType: 1,
            recycleShape: 1,
            disposalMethod: 1,
            amountRecycled: 500
        });

        string memory result = recyReportData.exposed_generateMaterialsText(
            singleMaterial
        );
        assertTrue(bytes(result).length > 0);
        assertTrue(contains(result, "Plastic"));
    }

    function test_generateauditDateTextWithMaxTimestamp() public view {
        uint256 maxTimestamp = type(uint256).max;
        string memory result = recyReportData.exposed_generateauditDateText(
            maxTimestamp
        );
        assertTrue(bytes(result).length > 0);
    }

    function test_generateRewardTextWithZeroReward() public view {
        RecyTypes.RecyReward memory zeroReward = RecyTypes.RecyReward({
            rewardAmount: 0,
            rewardUnlockDate: 1234567890
        });

        string memory result = recyReportData.exposed_generateRewardText(
            RecyConstants.RECYCLE_VALIDATED,
            zeroReward,
            mockToken
        );
        assertTrue(contains(result, "0"));
    }

    function test_generateStatusTextWithInvalidStatus() public {
        vm.expectRevert();
        recyReportData.exposed_generateStatusText(255);
    }

    function test_generateWasteAmountTextWithMaxAmount() public view {
        uint256 maxAmount = type(uint256).max;
        string memory result = recyReportData.exposed_generateWasteAmountText(
            maxAmount
        );
        assertTrue(bytes(result).length > 0);
    }

    function test_generateSvgWithAllStatuses() public view {
        for (uint8 i = 0; i <= 3; i++) {
            string memory result = recyReportData.exposed_generateSvg(i);
            assertTrue(bytes(result).length > 0);
            assertTrue(contains(result, "<svg"));
        }
    }

    // Helper function to check if a string contains a substring
    function contains(
        string memory str,
        string memory substring
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory subBytes = bytes(substring);

        if (subBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i <= strBytes.length - subBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < subBytes.length; j++) {
                if (strBytes[i + j] != subBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
