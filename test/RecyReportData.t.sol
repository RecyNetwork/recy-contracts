// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyReportAttributes} from "../src/RecyReportAttributes.sol";
import {RecyReportData} from "../src/RecyReportData.sol";
import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";
import {RecyErrors} from "../src/lib/RecyErrors.sol";
import {RecyTypes} from "../src/lib/RecyTypes.sol";
import "./helpers/TestHelpers.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test, console} from "forge-std/Test.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}
}

/// @dev Mirrors the RecyReportAttributes contract that is already deployed: it exposes
///      getMaterials() but predates getMaterialsCount(). Phase 1 ships a single
///      RecyReportData deployment against exactly this shape, so it must be supported.
contract LiveShapeAttributes {
    string[] private materials = [
        "Undefined",
        "Plastic",
        "Glass",
        "Metal",
        "Paper",
        "Glass",
        "E-Waste",
        "Organic",
        "Textile",
        "Hazardous",
        "Chemical",
        "Leachate",
        "Solid Inert Industrial Waste"
    ];

    function getMaterials() external view returns (string[] memory) {
        return materials;
    }

    function getMaterial(uint256 index) external view returns (string memory) {
        require(index < materials.length, "RecyReportAttributes.getMaterial: Invalid index");
        return materials[index];
    }
}

/// @dev An address that cannot answer the catalogue query at all.
contract IncompatibleAttributes {}

contract EmptyCatalogueAttributes {
    function getMaterials() external pure returns (string[] memory) {
        return new string[](0);
    }
}

contract RecyReportDataHarness is RecyReportData {
    constructor(address _attributesAddress, address _svgAddress) RecyReportData(_attributesAddress, _svgAddress) {}

    function exposed_getStatus(uint8 _status) external pure returns (string memory) {
        return getStatus(_status);
    }

    function exposed_generateSvg(uint8 _status) external view returns (string memory) {
        return generateSvg(_status);
    }

    function exposed_generateMaterialsText(RecyTypes.RecyMaterials[] memory _materials)
        external
        view
        returns (string memory)
    {
        return generateMaterialsText(_materials);
    }

    function exposed_generateauditDateText(uint256 _auditDate) external pure returns (string memory) {
        return generateauditDateText(_auditDate);
    }

    function exposed_generateRecycleDateText(uint256 _recycleDate) external pure returns (string memory) {
        return generateRecycleDateText(_recycleDate);
    }

    function exposed_generateWasteAmountText(uint256 _wasteAmount) external pure returns (string memory) {
        return generateWasteAmountText(_wasteAmount);
    }

    function exposed_generateRewardText(uint8 _status, RecyTypes.RecyReward memory _reward, ERC20 _token)
        external
        view
        returns (string memory)
    {
        return generateRewardText(_status, _reward, _token);
    }

    function exposed_generateStatusText(uint8 _status) external pure returns (string memory) {
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

        recyReportData = new RecyReportDataHarness(address(attributes), address(recyReportSvg));
    }

    function test_constructor() public {
        // Test valid constructor
        RecyReportData newContract = new RecyReportData(address(attributes), address(recyReportSvg));
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
        assertEq(completedStatus, "Completed", "RECYCLE_COMPLETED status mismatch");

        // Test RECYCLE_VALIDATED status
        string memory validatedStatus = recyReportData.exposed_getStatus(3); // RecyConstants.RECYCLE_VALIDATED
        assertEq(validatedStatus, "Validated", "RECYCLE_VALIDATED status mismatch");

        // Test RECYCLE_REWARDED status
        string memory rewardedStatus = recyReportData.exposed_getStatus(4); // RecyConstants.RECYCLE_REWARDED
        assertEq(rewardedStatus, "Rewarded", "RECYCLE_REWARDED status mismatch");

        // Test RECYCLE_INVALIDATED status
        string memory invalidatedStatus = recyReportData.exposed_getStatus(5); // RecyConstants.RECYCLE_INVALIDATED
        assertEq(invalidatedStatus, "Invalidated", "RECYCLE_INVALIDATED status mismatch");
    }

    function test_getStatus_flaggedAndUnknown() public view {
        // RECYCLE_FLAGGED (6) renders instead of bricking metadata
        assertEq(
            recyReportData.exposed_getStatus(RecyConstants.RECYCLE_FLAGGED),
            "Flagged",
            "RECYCLE_FLAGGED status mismatch"
        );

        // Statuses outside the state machine degrade to "Unknown" rather than revert
        assertEq(recyReportData.exposed_getStatus(7), "Unknown", "Unhandled status should render Unknown");
        assertEq(recyReportData.exposed_getStatus(0), "Unknown", "Uninitialized status should render Unknown");
        assertEq(recyReportData.exposed_getStatus(255), "Unknown", "Max status should render Unknown");
    }

    function test_generateSvg() public view {
        // Test RECYCLE_CREATED status
        string memory createdSvg = recyReportData.exposed_generateSvg(RecyConstants.RECYCLE_CREATED);
        assertTrue(bytes(createdSvg).length > 0, "Created SVG should not be empty");

        // Test RECYCLE_COMPLETED status
        string memory completedSvg = recyReportData.exposed_generateSvg(RecyConstants.RECYCLE_COMPLETED);
        assertTrue(bytes(completedSvg).length > 0, "Completed SVG should not be empty");

        // Test RECYCLE_VALIDATED status (should return coins)
        string memory validatedSvg = recyReportData.exposed_generateSvg(RecyConstants.RECYCLE_VALIDATED);
        assertTrue(bytes(validatedSvg).length > 0, "Validated SVG should not be empty");

        // Test RECYCLE_REWARDED status (should return coins)
        string memory rewardedSvg = recyReportData.exposed_generateSvg(RecyConstants.RECYCLE_REWARDED);
        assertTrue(bytes(rewardedSvg).length > 0, "Rewarded SVG should not be empty");
    }

    function test_generateMaterialsText() public view {
        // Create test materials using helper
        RecyTypes.RecyMaterials[] memory materials = new RecyTypes.RecyMaterials[](2);
        materials[0] = createRecyMaterials(1, 1, 1, 1, 100);
        materials[1] = createRecyMaterials(2, 2, 2, 2, 200);

        string memory result = recyReportData.exposed_generateMaterialsText(materials);
        assertTrue(bytes(result).length > 0, "Materials text should not be empty");

        // Should contain material information
        assertTrue(keccak256(bytes(result)) != keccak256(bytes("")), "Materials text should contain data");
    }

    function test_generateauditDateText() public view {
        // Test with valid date
        uint256 validDate = 1_234_567_890;
        string memory result = recyReportData.exposed_generateauditDateText(validDate);
        assertTrue(bytes(result).length > 0, "Validation date text should not be empty");

        // Test with zero date
        string memory zeroResult = recyReportData.exposed_generateauditDateText(0);
        assertEq(bytes(zeroResult).length, 0, "Zero validation date should return empty string");
    }

    function test_generateRecycleDateText() public view {
        // Test with valid date
        uint256 validDate = 1_234_567_890;
        string memory result = recyReportData.exposed_generateRecycleDateText(validDate);
        assertTrue(bytes(result).length > 0, "Recycle date text should not be empty");

        // Test with zero date
        string memory zeroResult = recyReportData.exposed_generateRecycleDateText(0);
        assertEq(bytes(zeroResult).length, 0, "Zero recycle date should return empty string");
    }

    function test_generateWasteAmountText() public view {
        // Test with valid amount
        uint256 validAmount = 1000;
        string memory result = recyReportData.exposed_generateWasteAmountText(validAmount);
        assertTrue(bytes(result).length > 0, "Waste amount text should not be empty");

        // Test with zero amount
        string memory zeroResult = recyReportData.exposed_generateWasteAmountText(0);
        assertEq(bytes(zeroResult).length, 0, "Zero waste amount should return empty string");
    }

    function test_generateRewardText() public view {
        // Create test reward using helper
        RecyTypes.RecyReward memory reward =
            createRecyReward(SafeCast.toUint128(1000 * RecyConstants.ONE_E18), 1_234_567_890);

        // Test with status > 2 (VALIDATED)
        string memory validatedResult =
            recyReportData.exposed_generateRewardText(RecyConstants.RECYCLE_VALIDATED, reward, mockToken);
        assertTrue(bytes(validatedResult).length > 0, "Validated reward text should not be empty");

        // Test with REWARDED status
        string memory rewardedResult =
            recyReportData.exposed_generateRewardText(RecyConstants.RECYCLE_REWARDED, reward, mockToken);
        assertTrue(bytes(rewardedResult).length > 0, "Rewarded text should not be empty");

        // Test with status <= 2 (CREATED or COMPLETED)
        string memory createdResult =
            recyReportData.exposed_generateRewardText(RecyConstants.RECYCLE_CREATED, reward, mockToken);
        assertEq(bytes(createdResult).length, 0, "Created status should return empty reward text");
    }

    function test_generateStatusText() public view {
        string memory result = recyReportData.exposed_generateStatusText(RecyConstants.RECYCLE_CREATED);
        assertTrue(bytes(result).length > 0, "Status text should not be empty");

        // Should contain "Created"
        assertTrue(keccak256(bytes(result)) != keccak256(bytes("")), "Status text should contain data");
    }

    function test_tokenUriAttributes() public view {
        // Create test data
        RecyTypes.RecyReward memory reward = RecyTypes.RecyReward({
            rewardAmount: SafeCast.toUint128(1000 * RecyConstants.ONE_E18), rewardUnlockDate: 1_234_567_890
        });

        RecyTypes.RecyInfo memory info = RecyTypes.RecyInfo({
            validator: address(0x123),
            recycler: address(0x456),
            recycleDate: 1_234_567_890,
            auditDate: 1_234_567_890,
            wasteAmount: 1000
        });

        RecyTypes.RecyMaterials[] memory materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = RecyTypes.RecyMaterials({
            material: 1, recycleType: 1, recycleShape: 1, disposalMethod: 1, amountRecycled: 100
        });

        string memory uri =
            recyReportData.tokenUriAttributes(1, RecyConstants.RECYCLE_VALIDATED, mockToken, reward, info, materials);

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

        assertTrue(startsWithPrefix, "Token URI should start with data:application/json;base64,");
    }

    function test_tokenUriAttributesTest() public view {
        // Create test data
        RecyTypes.RecyReward memory reward = RecyTypes.RecyReward({
            rewardAmount: SafeCast.toUint128(1000 * RecyConstants.ONE_E18), rewardUnlockDate: 1_234_567_890
        });

        RecyTypes.RecyInfo memory info = RecyTypes.RecyInfo({
            validator: address(0x789),
            recycler: address(0xABC),
            recycleDate: 1_234_567_890,
            auditDate: 1_234_567_890,
            wasteAmount: 1000
        });

        RecyTypes.RecyMaterials[] memory materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = RecyTypes.RecyMaterials({
            material: 1, recycleType: 1, recycleShape: 1, disposalMethod: 1, amountRecycled: 100
        });

        string memory result =
            recyReportData.tokenJson(1, RecyConstants.RECYCLE_VALIDATED, mockToken, reward, info, materials);

        assertTrue(bytes(result).length > 0, "Token JSON test should not be empty");

        // Should contain JSON structure
        assertTrue(keccak256(bytes(result)) != keccak256(bytes("")), "Token URI test should contain data");
    }

    // ===== EDGE CASE TESTS =====

    function test_generateMaterialsTextWithSingleMaterial() public view {
        RecyTypes.RecyMaterials[] memory singleMaterial = new RecyTypes.RecyMaterials[](1);
        singleMaterial[0] = RecyTypes.RecyMaterials({
            material: 1, recycleType: 1, recycleShape: 1, disposalMethod: 1, amountRecycled: 500
        });

        string memory result = recyReportData.exposed_generateMaterialsText(singleMaterial);
        assertTrue(bytes(result).length > 0);
        assertTrue(contains(result, "Plastic"));
    }

    function test_generateauditDateTextWithMaxTimestamp() public view {
        uint256 maxTimestamp = type(uint256).max;
        string memory result = recyReportData.exposed_generateauditDateText(maxTimestamp);
        assertTrue(bytes(result).length > 0);
    }

    function test_generateRewardTextWithZeroReward() public view {
        RecyTypes.RecyReward memory zeroReward =
            RecyTypes.RecyReward({rewardAmount: 0, rewardUnlockDate: 1_234_567_890});

        string memory result =
            recyReportData.exposed_generateRewardText(RecyConstants.RECYCLE_VALIDATED, zeroReward, mockToken);
        assertTrue(contains(result, "0"));
    }

    function test_generateStatusTextWithInvalidStatus() public view {
        assertEq(
            recyReportData.exposed_generateStatusText(255),
            '{"trait_type":"Status","value":"Unknown"}',
            "Unhandled status should render a well-formed Unknown trait"
        );
    }

    function test_generateWasteAmountTextWithMaxAmount() public view {
        uint256 maxAmount = type(uint256).max;
        string memory result = recyReportData.exposed_generateWasteAmountText(maxAmount);
        assertTrue(bytes(result).length > 0);
    }

    // This bounded four-status sweep intentionally renders once per status.
    // forge-lint: disable-next-item(calls-loop)
    function test_generateSvgWithAllStatuses() public view {
        for (uint8 i = 0; i <= 3; i++) {
            string memory result = recyReportData.exposed_generateSvg(i);
            assertTrue(bytes(result).length > 0);
            assertTrue(contains(result, "<svg"));
        }
    }

    // ===== METADATA INTEGRITY TESTS =====

    function _sampleReward() internal pure returns (RecyTypes.RecyReward memory) {
        return RecyTypes.RecyReward({
            rewardAmount: SafeCast.toUint128(1000 * RecyConstants.ONE_E18), rewardUnlockDate: 1_234_567_890
        });
    }

    function _sampleInfo() internal pure returns (RecyTypes.RecyInfo memory) {
        return RecyTypes.RecyInfo({
            validator: address(0x123),
            recycler: address(0x456),
            recycleDate: 1_234_567_890,
            auditDate: 1_234_567_890,
            wasteAmount: 1000
        });
    }

    /// @dev A report with no dates, no waste amount and no reward, so the rendered
    ///      attributes array is exactly [Status, material] and can be indexed reliably.
    function _minimalInfo() internal pure returns (RecyTypes.RecyInfo memory) {
        return RecyTypes.RecyInfo({
            validator: address(0x123), recycler: address(0x456), recycleDate: 0, auditDate: 0, wasteAmount: 0
        });
    }

    function _oneMaterial(uint32 materialId) internal pure returns (RecyTypes.RecyMaterials[] memory materials) {
        materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = RecyTypes.RecyMaterials({
            material: materialId, recycleType: 1, recycleShape: 1, disposalMethod: 1, amountRecycled: 100
        });
    }

    /// @notice The tokenURI payload must decode to a document a strict JSON parser
    ///         accepts, with the Status trait emitted as one object rather than a
    ///         trait object smuggled into a string value.
    function test_tokenUriAttributesDecodesToValidJson() public view {
        string memory uri = recyReportData.tokenUriAttributes(
            1, RecyConstants.RECYCLE_REWARDED, mockToken, _sampleReward(), _sampleInfo(), _oneMaterial(1)
        );

        string memory json = decodeJsonDataUri(uri);

        // Strict parse of the whole document; the unescaped quotes emitted before
        // the fix make this revert.
        string[] memory topLevelKeys = vm.parseJsonKeys(json, "$");
        assertEq(topLevelKeys.length, 4, "Top-level key count");

        // The Status trait must carry exactly trait_type and value.
        string[] memory statusKeys = vm.parseJsonKeys(json, ".attributes[0]");
        assertEq(statusKeys.length, 2, "Status trait key count");
        assertEq(statusKeys[0], "trait_type", "Status trait key 0");
        assertEq(statusKeys[1], "value", "Status trait key 1");
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Status", "Status trait_type");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "Rewarded", "Status value should be the plain label");

        // Regression guard for the double-wrapped trait object.
        assertFalse(contains(json, '"value":"{'), "Status trait should not be double-wrapped");
    }

    /// @notice tokenJson and tokenURI must both render a material id outside the
    ///         catalogue instead of reverting; stored ids are push-only and cannot
    ///         be repaired on the report contract.
    function test_metadataSurvivesOutOfRangeMaterialId() public view {
        RecyTypes.RecyReward memory noReward = RecyTypes.RecyReward({rewardAmount: 0, rewardUnlockDate: 0});

        string memory json = recyReportData.tokenJson(
            1, RecyConstants.RECYCLE_CREATED, mockToken, noReward, _minimalInfo(), _oneMaterial(type(uint32).max)
        );
        assertEq(
            vm.parseJsonString(json, ".attributes[1].trait_type"),
            "Unknown Material",
            "tokenJson out-of-range material trait"
        );
        assertEq(vm.parseJsonUint(json, ".attributes[1].value"), 100, "tokenJson out-of-range material amount");

        string memory uri = recyReportData.tokenUriAttributes(
            1, RecyConstants.RECYCLE_CREATED, mockToken, noReward, _minimalInfo(), _oneMaterial(type(uint32).max)
        );
        assertEq(
            vm.parseJsonString(decodeJsonDataUri(uri), ".attributes[1].trait_type"),
            "Unknown Material",
            "tokenURI out-of-range material trait"
        );
    }

    /// @notice Empty-material reports remain mintable (plan §8.4), so both render paths must
    ///         emit strictly valid JSON for a zero-length materials array: the Status trait
    ///         carries no leading comma and every later fragment brings its own, so an empty
    ///         tail must not leave a dangling separator.
    function test_metadataValidJsonWithEmptyMaterialsArray() public view {
        RecyTypes.RecyMaterials[] memory noMaterials = new RecyTypes.RecyMaterials[](0);

        string memory json = recyReportData.tokenJson(
            1, RecyConstants.RECYCLE_CREATED, mockToken, _sampleReward(), _sampleInfo(), noMaterials
        );
        // Strict parse: a dangling comma or unterminated array reverts here.
        string[] memory keys = vm.parseJsonKeys(json, "$");
        assertEq(keys.length, 3, "tokenJson top-level key count");
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Status", "first trait is Status");

        string memory uri = recyReportData.tokenUriAttributes(
            1, RecyConstants.RECYCLE_CREATED, mockToken, _sampleReward(), _sampleInfo(), noMaterials
        );
        string memory uriJson = decodeJsonDataUri(uri);
        string[] memory uriKeys = vm.parseJsonKeys(uriJson, "$");
        assertEq(uriKeys.length, 4, "tokenURI top-level key count");
        assertEq(vm.parseJsonString(uriJson, ".attributes[0].trait_type"), "Status", "first trait is Status");
    }

    /// @notice The catalogue boundary: the last valid id still resolves, the first
    ///         invalid id degrades, and in-range ids are unaffected by the fallback.
    function test_materialRenderingAtCatalogueBoundary() public view {
        uint32 count = SafeCast.toUint32(recyReportData.materialsCount());

        assertEq(_renderMaterialTrait(count - 1), "Solid Inert Industrial Waste", "Last catalogue id should resolve");
        assertEq(_renderMaterialTrait(count), "Unknown Material", "First id past the catalogue should degrade");
        assertEq(_renderMaterialTrait(1), "Plastic", "In-range id should be unaffected");
    }

    function _renderMaterialTrait(uint32 materialId) internal view returns (string memory) {
        string memory json = recyReportData.tokenJson(
            1,
            RecyConstants.RECYCLE_CREATED,
            mockToken,
            RecyTypes.RecyReward({rewardAmount: 0, rewardUnlockDate: 0}),
            _minimalInfo(),
            _oneMaterial(materialId)
        );
        return vm.parseJsonString(json, ".attributes[1].trait_type");
    }

    function test_constructor_invalidSvgAddress() public {
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        new RecyReportData(address(attributes), address(0));
    }

    /// @notice Phase 1 ships as a single RecyReportData deployment pointed at the
    ///         attributes contract that is already live, which predates
    ///         getMaterialsCount(). Nothing here may depend on that function.
    function test_worksAgainstDeployedAttributesShape() public {
        LiveShapeAttributes liveShape = new LiveShapeAttributes();
        RecyReportData data = new RecyReportData(address(liveShape), address(recyReportSvg));

        assertEq(data.materialsCount(), 13, "materialsCount against the deployed attributes shape");

        RecyTypes.RecyReward memory noReward = RecyTypes.RecyReward({rewardAmount: 0, rewardUnlockDate: 0});
        string memory json =
            data.tokenJson(1, RecyConstants.RECYCLE_CREATED, mockToken, noReward, _minimalInfo(), _oneMaterial(12));
        assertEq(
            vm.parseJsonString(json, ".attributes[1].trait_type"),
            "Solid Inert Industrial Waste",
            "live catalogue label should render"
        );
    }

    /// @notice An address that cannot answer the catalogue query must not silently
    ///         become the metadata backend.
    function test_constructor_rejectsIncompatibleAttributes() public {
        IncompatibleAttributes bad = new IncompatibleAttributes();
        vm.expectRevert();
        new RecyReportData(address(bad), address(recyReportSvg));
    }

    function test_constructor_rejectsEmptyCatalogue() public {
        EmptyCatalogueAttributes empty = new EmptyCatalogueAttributes();
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        new RecyReportData(address(empty), address(recyReportSvg));
    }

    function test_materialsCount() public {
        assertEq(recyReportData.materialsCount(), 13, "materialsCount should mirror the catalogue");
        assertEq(
            attributes.getMaterialsCount(),
            attributes.getMaterials().length,
            "getMaterialsCount should equal getMaterials length"
        );

        // The passthrough must be live, not a snapshot taken at construction.
        attributes.addMaterial("NewMaterial", "<svg>new</svg>");
        assertEq(recyReportData.materialsCount(), 14, "materialsCount should track catalogue growth");
    }

    // Helper function to check if a string contains a substring
    function contains(string memory str, string memory substring) internal pure returns (bool) {
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

    /// @dev Strips the data URI prefix and base64-decodes the JSON payload.
    function decodeJsonDataUri(string memory uri) internal pure returns (string memory) {
        bytes memory uriBytes = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        require(uriBytes.length > prefix.length, "decodeJsonDataUri: too short");
        for (uint256 i = 0; i < prefix.length; i++) {
            // Prefix validation must reject the first mismatching byte.
            // forge-lint: disable-next-line(require-revert-in-loop)
            require(uriBytes[i] == prefix[i], "decodeJsonDataUri: bad prefix");
        }

        bytes memory payload = new bytes(uriBytes.length - prefix.length);
        for (uint256 i = 0; i < payload.length; i++) {
            payload[i] = uriBytes[prefix.length + i];
        }
        return string(base64Decode(payload));
    }

    /// @dev Standard-alphabet base64 decoder; forge-std only ships an encoder.
    function base64Decode(bytes memory input) internal pure returns (bytes memory output) {
        require(input.length >= 4 && input.length % 4 == 0, "base64Decode: bad length");

        uint256 padding = 0;
        if (input[input.length - 1] == "=") padding++;
        if (input[input.length - 2] == "=") padding++;

        // This division is exact because the length invariant above requires complete four-byte groups.
        // forge-lint: disable-next-line(divide-before-multiply)
        output = new bytes((input.length / 4) * 3 - padding);
        uint256 outIndex = 0;
        for (uint256 i = 0; i < input.length; i += 4) {
            uint256 chunk = (base64Value(input[i]) << 18) | (base64Value(input[i + 1]) << 12)
                | (base64Value(input[i + 2]) << 6) | base64Value(input[i + 3]);

            output[outIndex++] = bytes1(uint8((chunk >> 16) & 0xff));
            if (outIndex < output.length) {
                output[outIndex++] = bytes1(uint8((chunk >> 8) & 0xff));
            }
            if (outIndex < output.length) {
                output[outIndex++] = bytes1(uint8(chunk & 0xff));
            }
        }
    }

    // Invalid alphabet bytes must still revert when this helper is reached from the decode loop.
    // forge-lint: disable-next-item(require-revert-in-loop)
    function base64Value(bytes1 char) internal pure returns (uint256) {
        uint8 code = uint8(char);
        if (code >= 0x41 && code <= 0x5A) return code - 0x41; // A-Z
        if (code >= 0x61 && code <= 0x7A) return code - 0x61 + 26; // a-z
        if (code >= 0x30 && code <= 0x39) return code - 0x30 + 52; // 0-9
        if (code == 0x2B) return 62; // +
        if (code == 0x2F) return 63; // /
        if (code == 0x3D) return 0; // = padding
        revert("base64Decode: invalid character");
    }
}
