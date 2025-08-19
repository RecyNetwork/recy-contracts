// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/RecyReport.sol";
import "../src/RecyReportData.sol";
import "../src/RecyReportAttributes.sol";
import "../src/RecyReportSvg.sol";
import "../src/RecyToken.sol";
import "../src/lib/RecyConstants.sol";
import "../src/lib/RecyErrors.sol";
import "../src/lib/RecyReward.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./helpers/TestHelpers.sol";

// Mock ERC721 receiver for testing
contract MockReceiver is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RecyReportTest is Test, TestHelpers, IERC721Receiver {
    RecyReport public recyReport;
    RecyReportData public recyData;
    RecyReportAttributes public recyAttributes;
    RecyReportSvg public recySvg;
    RecyToken public testToken;
    MockReceiver public mockReceiver;
    ERC1967Proxy public proxy;

    address public owner;
    address public user;
    address public recycler;
    address public validator;
    address public protocol;

    function setUp() public {
        owner = address(this);
        user = address(0x123);
        recycler = address(0x456);
        validator = address(0x789);
        protocol = address(0xABC);

        // Deploy test token
        testToken = new RecyToken(
            "Test Recy Token",
            "TRECY",
            18,
            1000000,
            address(this)
        );
        mockReceiver = new MockReceiver();

        // Deploy dependencies
        recyAttributes = new RecyReportAttributes();
        recySvg = new RecyReportSvg();
        recyData = new RecyReportData(
            address(recyAttributes),
            address(recySvg)
        );

        // Deploy implementation
        RecyReport implementation = new RecyReport();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "RecyReport Upgradeable",
            "RECYU",
            address(testToken),
            address(recyData),
            protocol,
            uint64(3600), // 1 hour unlock delay
            uint8(25), // 25% recycler share
            uint8(25), // 25% validator share
            uint8(25), // 25% generator share
            uint8(25) // 25% protocol share
        );

        // Deploy proxy with initialization
        proxy = new ERC1967Proxy(address(implementation), initData);
        recyReport = RecyReport(address(proxy));

        // Fund the contract with tokens for rewards
        testToken.transfer(address(recyReport), 10000 * 10 ** 18);

        // Grant necessary roles for testing
        grantStandardRoles(recyReport, RECYCLER, VALIDATOR);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function test_initialization() public view {
        assertEq(recyReport.name(), "RecyReport Upgradeable");
        assertEq(recyReport.symbol(), "RECYU");
        assertEq(address(recyReport.token()), address(testToken));
        assertEq(recyReport.protocolAddress(), protocol);
        assertEq(recyReport.unlockDelay(), 3600);
        assertEq(recyReport.shareRecycler(), 25);
        assertEq(recyReport.shareValidator(), 25);
        assertEq(recyReport.shareGenerator(), 25);
        assertEq(recyReport.shareProtocol(), 25);
        assertEq(recyReport.version(), "1.0.0");
    }

    function test_mintRecyReport() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        assertEq(recyReport.ownerOf(0), user);
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_CREATED);
        assertEq(recyReport.nftNextId(), 1);
    }

    function test_setRecyReportResult() public {
        // First mint a report
        vm.prank(user);
        recyReport.mintRecyReport();

        // Use helper to create standard material arrays
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        // Grant recycler role to owner for testing
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);

        // Set report result
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        assertReportStatus(recyReport, 0, RecyConstants.RECYCLE_COMPLETED);
        (, , , , uint128 wasteAmount) = recyReport.info(0);
        assertEq(wasteAmount, 1000000 * 10 ** 18);
    }

    function test_validateRecyReport() public {
        // Use helper to setup mint and complete report
        uint256 tokenId = mintAndCompleteReport(recyReport);

        // Grant auditor role and validate
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.validateRecyReport(tokenId);

        assertReportStatus(
            recyReport,
            tokenId,
            RecyConstants.RECYCLE_VALIDATED
        );

        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        assertGt(rewardAmount, 0);
    }

    function test_claimRecyReportReward() public {
        // Use helper to setup mint, complete, and validate report
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Fast forward time and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify claim was successful
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        assertGt(rewardAmount, 0);
    }

    function test_getRecyReportMaterials() public {
        // Use helper to setup mint and complete report
        uint256 tokenId = mintAndCompleteReport(recyReport);

        // Get materials from the completed report
        RecyTypes.RecyMaterials[] memory materials = recyReport
            .getRecyReportMaterials(tokenId);

        // Verify materials were recorded correctly - createTestMaterials creates 2 materials
        assertEq(materials.length, 2);
        assertEq(materials[0].material, 1); // Plastic
        assertEq(materials[0].amountRecycled, 1000); // 1000 grams
        assertEq(materials[1].material, 2); // Glass
        assertEq(materials[1].amountRecycled, 500); // 500 grams
    }

    function test_upgradeAuthorization() public {
        // Deploy new implementation
        RecyReport newImplementation = new RecyReport();

        // Only admin should be able to upgrade
        vm.prank(user);
        vm.expectRevert();
        recyReport.upgradeToAndCall(address(newImplementation), "");

        // Admin can upgrade
        recyReport.upgradeToAndCall(address(newImplementation), "");

        // Contract should still work after upgrade
        assertEq(recyReport.version(), "1.0.0");
    }

    function test_roleManagement() public {
        // Test granting roles
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);

        assertTrue(recyReport.hasRole(RecyConstants.RECYCLER_ROLE, recycler));
        assertTrue(recyReport.hasRole(RecyConstants.AUDITOR_ROLE, validator));

        // Test revoking roles
        recyReport.revokeRole(RecyConstants.RECYCLER_ROLE, recycler);
        assertFalse(recyReport.hasRole(RecyConstants.RECYCLER_ROLE, recycler));
    }

    function test_tokenURI() public {
        // Mint a report
        vm.prank(user);
        recyReport.mintRecyReport();

        // Should return a valid URI
        string memory uri = recyReport.tokenURI(0);
        assertGt(bytes(uri).length, 0);
    }

    function test_supportsInterface() public view {
        // Should support ERC721 interface
        assertTrue(recyReport.supportsInterface(0x80ac58cd));
        // Should support AccessControl interface
        assertTrue(recyReport.supportsInterface(0x7965db0b));
        // Should support ERC4906 interface
        assertTrue(recyReport.supportsInterface(0x49064906));
    }

    function test_getRecyReportMaterialsForEmptyReport() public {
        // Mint a report without completing it
        vm.prank(user);
        recyReport.mintRecyReport();

        // Get materials from incomplete report should return empty array
        RecyTypes.RecyMaterials[] memory reportMaterials = recyReport
            .getRecyReportMaterials(0);
        assertEq(reportMaterials.length, 0);
    }

    // ===== INITIALIZATION EDGE CASES =====

    function test_initializeWithZeroTokenAddress() public {
        RecyReport implementation = new RecyReport();

        // Test with zero token address
        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test",
            "TEST",
            address(0), // Zero token address
            address(recyData),
            protocol,
            3600,
            25,
            25,
            25,
            25
        );

        vm.expectRevert();
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_initializeWithZeroDataAddress() public {
        RecyReport implementation = new RecyReport();

        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test",
            "TEST",
            address(testToken),
            address(0), // Zero data address
            protocol,
            3600,
            25,
            25,
            25,
            25
        );

        vm.expectRevert();
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_initializeWithInvalidSharePercentages() public {
        RecyReport implementation = new RecyReport();

        // Test with shares that add up to more than 100%
        bytes memory initDataTooHigh = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test",
            "TEST",
            address(testToken),
            address(recyData),
            protocol,
            3600,
            50,
            50,
            50,
            50 // Adds up to 200%
        );

        // This should revert due to invalid share distribution
        vm.expectRevert(
            abi.encodeWithSelector(
                RecyErrors.RecyReportInvalidShareDistribution.selector
            )
        );
        new ERC1967Proxy(address(implementation), initDataTooHigh);

        // Test with shares that add up to less than 100%
        bytes memory initDataTooLow = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test",
            "TEST",
            address(testToken),
            address(recyData),
            protocol,
            3600,
            20,
            20,
            20,
            20 // Adds up to 80%
        );

        // This should also revert due to invalid share distribution
        vm.expectRevert(
            abi.encodeWithSelector(
                RecyErrors.RecyReportInvalidShareDistribution.selector
            )
        );
        new ERC1967Proxy(address(implementation), initDataTooLow);
    }

    function test_initializeWithValidSharePercentages() public {
        RecyReport implementation = new RecyReport();

        // Test with equal shares (25% each)
        bytes memory initDataEqual = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test Equal",
            "TEQ",
            address(testToken),
            address(recyData),
            protocol,
            3600,
            25,
            25,
            25,
            25 // Adds up to 100%
        );

        ERC1967Proxy testProxyEqual = new ERC1967Proxy(
            address(implementation),
            initDataEqual
        );
        RecyReport newReport1 = RecyReport(address(testProxyEqual));

        assertEq(newReport1.shareRecycler(), 25);
        assertEq(newReport1.shareValidator(), 25);
        assertEq(newReport1.shareGenerator(), 25);
        assertEq(newReport1.shareProtocol(), 25);

        // Test with unequal shares that still sum to 100%
        RecyReport implementation2 = new RecyReport();
        bytes memory initDataUnequal = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test Unequal",
            "TUQ",
            address(testToken),
            address(recyData),
            protocol,
            3600,
            40,
            30,
            20,
            10 // Adds up to 100%
        );

        ERC1967Proxy testProxyUnequal = new ERC1967Proxy(
            address(implementation2),
            initDataUnequal
        );
        RecyReport newReport2 = RecyReport(address(testProxyUnequal));

        assertEq(newReport2.shareRecycler(), 40);
        assertEq(newReport2.shareValidator(), 30);
        assertEq(newReport2.shareGenerator(), 20);
        assertEq(newReport2.shareProtocol(), 10);

        // Test with edge case: one gets most of the share
        RecyReport implementation3 = new RecyReport();
        bytes memory initDataEdge = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "Test Edge",
            "TED",
            address(testToken),
            address(recyData),
            protocol,
            3600,
            97,
            1,
            1,
            1 // Adds up to 100%
        );

        ERC1967Proxy testProxyEdge = new ERC1967Proxy(
            address(implementation3),
            initDataEdge
        );
        RecyReport newReport3 = RecyReport(address(testProxyEdge));

        assertEq(newReport3.shareRecycler(), 97);
        assertEq(newReport3.shareValidator(), 1);
        assertEq(newReport3.shareGenerator(), 1);
        assertEq(newReport3.shareProtocol(), 1);
    }

    function test_doubleInitialization() public {
        // Try to initialize an already initialized contract
        vm.expectRevert();
        recyReport.initialize(
            "Another Name",
            "ANOTHER",
            address(testToken),
            address(recyData),
            protocol,
            7200,
            30,
            30,
            30,
            10
        );
    }

    // ===== ACCESS CONTROL EDGE CASES =====

    function test_unauthorizedUpgrade() public {
        RecyReport newImplementation = new RecyReport();

        vm.prank(user);
        vm.expectRevert();
        recyReport.upgradeToAndCall(address(newImplementation), "");
    }

    function test_roleManagementEdgeCases() public {
        // Test self-revoke admin role (should work)
        assertTrue(
            recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this))
        );
        recyReport.revokeRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this));
        assertFalse(
            recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this))
        );
    }

    // ===== MINTING EDGE CASES =====

    function test_mintRecyReportFromZeroAddress() public {
        vm.prank(address(0));
        vm.expectRevert();
        recyReport.mintRecyReport();
    }

    function test_mintMultipleReportsSequentially() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user);
            recyReport.mintRecyReport();
            assertEq(recyReport.ownerOf(i), user);
        }
        assertEq(recyReport.nftNextId(), 5);
    }

    function test_mintMultipleReportsInSequence() public {
        // Test rapid sequential minting
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user);
            recyReport.mintRecyReport();
            assertEq(recyReport.ownerOf(i), user);
        }

        assertEq(recyReport.nftNextId(), 10);
    }

    // ===== RESULT SETTING EDGE CASES =====

    function test_setRecyReportResultWithEmptyArrays() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](0);
        uint128[] memory materialAmounts = new uint128[](0);
        uint32[] memory recycleTypes = new uint32[](0);
        uint32[] memory recycleShapes = new uint32[](0);

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );

        // Verify the report was set with no materials
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);
        RecyTypes.RecyMaterials[] memory reportMaterials = recyReport
            .getRecyReportMaterials(0);
        assertEq(reportMaterials.length, 0);
    }

    function test_setRecyReportResultWithMismatchedArrayLengths() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](2);
        uint128[] memory materialAmounts = new uint128[](1); // Mismatched length
        uint32[] memory recycleTypes = new uint32[](2);
        uint32[] memory recycleShapes = new uint32[](2);

        materials[0] = 0;
        materials[1] = 1;
        materialAmounts[0] = 1000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleTypes[1] = 1;
        recycleShapes[0] = 0;
        recycleShapes[1] = 1;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        vm.expectRevert();
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );
    }

    function test_setRecyReportResultWithMaxValues() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = type(uint32).max;
        materialAmounts[0] = type(uint128).max;
        recycleTypes[0] = type(uint32).max;
        recycleShapes[0] = type(uint32).max;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        recyReport.setRecyReportResult(
            0,
            type(uint64).max,
            type(uint128).max,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            type(uint32).max
        );

        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);
    }

    function test_setRecyReportResultOnNonExistentToken() public {
        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        recyReport.setRecyReportResult(
            999, // Non-existent token
            uint64(block.timestamp),
            1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );

        // The function succeeded, so the token now has data
        assertEq(recyReport.status(999), RecyConstants.RECYCLE_COMPLETED);
    }

    function test_setRecyReportResultTwice() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);

        // First set
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );

        // Try to set result again - should succeed and overwrite
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp + 100),
            2,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            2
        );

        // Verify the result was updated
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);
    }

    function test_setRecyReportResultWithUnauthorizedUser() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        vm.prank(user); // Not a recycler
        vm.expectRevert();
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );
    }

    // ===== VALIDATION EDGE CASES =====

    function test_validateNonExistentReport() public {
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        vm.expectRevert();
        recyReport.validateRecyReport(999);
    }

    function test_validateUncompletedReport() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        vm.expectRevert();
        recyReport.validateRecyReport(0);
    }

    function test_validateAlreadyValidatedReport() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Try to validate again (should fail)
        vm.prank(validator);
        vm.expectRevert();
        recyReport.validateRecyReport(tokenId);
    }

    function test_validateWithUnauthorizedUser() public {
        // Setup: mint and complete a report
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        vm.prank(user); // Not an auditor
        vm.expectRevert();
        recyReport.validateRecyReport(0);
    }

    // ===== REWARD CLAIMING EDGE CASES =====

    function test_claimRewardBeforeUnlock() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Don't warp - try to claim immediately (before unlock)
        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRewardTwice() public {
        // Setup: mint, complete, and validate a report with realistic amounts
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Verify the report is validated
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_VALIDATED);

        // First claim - should succeed
        vm.warp(block.timestamp + 3601);

        // Check that the reward can be claimed
        uint64 unlockTime = recyReport.unlockDate(tokenId);
        assertTrue(unlockTime > 0);
        assertTrue(block.timestamp >= unlockTime);

        vm.prank(user);
        recyReport.claimRecyReportReward(tokenId);

        // Verify the status changed to rewarded
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);

        // Try to claim again
        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRewardForNonExistentToken() public {
        vm.warp(block.timestamp + 3601);

        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(999);
    }

    function test_claimRewardForUnvalidatedReport() public {
        // Setup: mint and complete a report (but don't validate)
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        vm.warp(block.timestamp + 3601);
        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(0);
    }

    function test_claimRewardByNonOwner() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        vm.warp(block.timestamp + 3601);

        // Test with a completely different address that has no connection to the report
        address unauthorizedUser = address(0x9999);
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    // ===== TOKEN URI EDGE CASES =====

    function test_tokenURIForNonExistentToken() public {
        vm.expectRevert();
        recyReport.tokenURI(999);
    }

    function test_tokenURIAfterBurn() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        // This would require implementing burn functionality
        // For now, test that tokenURI works for existing token
        string memory uri = recyReport.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
    }

    // ===== MATERIALS GETTER EDGE CASES =====

    function test_getRecyReportMaterialsForNonExistentToken() public view {
        // This function might return empty array instead of reverting
        RecyTypes.RecyMaterials[] memory materials = recyReport
            .getRecyReportMaterials(999);
        assertEq(materials.length, 0);
    }

    function test_getRecyReportMaterialsForMintedReport() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        RecyTypes.RecyMaterials[] memory materials = recyReport
            .getRecyReportMaterials(0);
        assertEq(materials.length, 0);
    }

    // ===== UNLOCK DATE EDGE CASES =====

    function test_unlockDateForNonExistentToken() public view {
        // This function might return 0 instead of reverting
        uint64 unlockTime = recyReport.unlockDate(999);
        assertEq(unlockTime, 0);
    }

    function test_unlockDateForUnvalidatedReport() public {
        // Setup: mint and complete a report (but don't validate)
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000000 * 10 ** 18;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        uint64 unlockTime = recyReport.unlockDate(0);
        assertEq(unlockTime, 0); // Should be 0 for unvalidated reports
    }

    function test_unlockDateCalculation() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        uint64 unlockTime = recyReport.unlockDate(tokenId);
        assertTrue(unlockTime > uint64(block.timestamp));
        assertTrue(unlockTime <= uint64(block.timestamp + 3600));
    }

    // ===== INTERFACE SUPPORT EDGE CASES =====

    function test_supportsInterfaceForUnknownInterface() public view {
        // Test with random interface ID
        assertFalse(recyReport.supportsInterface(0x12345678));
    }

    function test_supportsInterfaceForKnownInterfaces() public view {
        // Test ERC721 interface
        assertTrue(recyReport.supportsInterface(0x80ac58cd));

        // Test ERC165 interface
        assertTrue(recyReport.supportsInterface(0x01ffc9a7));

        // Test AccessControl interface
        assertTrue(recyReport.supportsInterface(0x7965db0b));
    }

    // ===== VERSION EDGE CASES =====

    function test_versionConsistency() public view {
        string memory version = recyReport.version();
        assertEq(version, "1.0.0");
    }

    // ===== REENTRANCY TESTS =====

    function test_noReentrancyInMint() public {
        // Basic test - would need malicious contract for full reentrancy test
        vm.prank(user);
        recyReport.mintRecyReport();

        // Verify state is consistent
        assertEq(recyReport.nftNextId(), 1);
        assertEq(recyReport.ownerOf(0), user);
    }

    function test_noReentrancyInClaimReward() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Claim reward
        vm.warp(block.timestamp + 3601);
        vm.prank(user);
        recyReport.claimRecyReportReward(tokenId);

        // Verify reward was claimed only once
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    // ============ Emergency Controls Tests ============

    function test_pauseRewardClaiming() public {
        address emergencyController = address(0xE001);

        // Grant emergency role
        recyReport.grantRole(RecyConstants.EMERGENCY_ROLE, emergencyController);

        // Emergency controller can pause
        vm.prank(emergencyController);
        recyReport.pauseRewardClaiming();

        assertTrue(recyReport.paused(), "Contract should be paused");
    }

    function test_unpauseRewardClaiming() public {
        address emergencyController = address(0xE002);

        // Grant emergency role
        recyReport.grantRole(RecyConstants.EMERGENCY_ROLE, emergencyController);

        // Pause first
        vm.prank(emergencyController);
        recyReport.pauseRewardClaiming();

        // Then unpause
        vm.prank(emergencyController);
        recyReport.unpauseRewardClaiming();

        assertFalse(recyReport.paused(), "Contract should be unpaused");
    }

    function test_onlyEmergencyRoleCanPause() public {
        address regularUser = address(0xE003);

        // Regular user cannot pause
        vm.prank(regularUser);
        vm.expectRevert();
        recyReport.pauseRewardClaiming();

        // Protocol address cannot pause unless they have emergency role
        vm.prank(protocol);
        vm.expectRevert();
        recyReport.pauseRewardClaiming();
    }

    function test_claimRewardBlockedWhenPaused() public {
        address emergencyController = address(0xE004);

        // Grant emergency role
        recyReport.grantRole(RecyConstants.EMERGENCY_ROLE, emergencyController);
        // Grant recycler role to owner for setRecyReportResult
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        // Grant auditor role to validator for validateRecyReport
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);

        // Create and validate a report first
        vm.prank(user);
        recyReport.mintRecyReport();

        // Set report result as recycler (owner has recycler role by default)
        (
            uint32[] memory materials,
            uint128[] memory amounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Validate the report
        vm.prank(validator);
        recyReport.validateRecyReport(0);

        // Fast forward past unlock time
        vm.warp(block.timestamp + 2 hours);

        // Pause the contract
        vm.prank(emergencyController);
        recyReport.pauseRewardClaiming();

        // Attempt to claim reward - should fail
        vm.prank(user);
        vm.expectRevert(); // EnforcedPause error in OpenZeppelin v5
        recyReport.claimRecyReportReward(0);
    }

    function test_claimRewardWorksWhenNotPaused() public {
        // Grant recycler role to owner for setRecyReportResult
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        // Grant auditor role to validator for validateRecyReport
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);

        // Create and validate a report first
        vm.prank(user);
        recyReport.mintRecyReport();

        // Set report result as recycler
        (
            uint32[] memory materials,
            uint128[] memory amounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        recyReport.setRecyReportResult(
            0,
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Validate the report
        vm.prank(validator);
        recyReport.validateRecyReport(0);

        // Fast forward past unlock time
        vm.warp(block.timestamp + 2 hours);

        // Claim reward - should work normally
        vm.prank(user);
        recyReport.claimRecyReportReward(0);

        // Verify status changed to rewarded
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_REWARDED);
    }

    function test_emergencyPauseEvents() public {
        address emergencyController = address(0xE005);

        // Grant emergency role
        recyReport.grantRole(RecyConstants.EMERGENCY_ROLE, emergencyController);

        // Test pause event
        vm.prank(emergencyController);
        vm.expectEmit(true, false, false, false);
        emit Paused(emergencyController);
        recyReport.pauseRewardClaiming();

        // Test unpause event
        vm.prank(emergencyController);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(emergencyController);
        recyReport.unpauseRewardClaiming();
    }

    function test_tokenJson() public {
        // Mint and set up a recycling report - token stays with owner (this contract)
        recyReport.mintRecyReport();
        uint256 tokenId = 0;

        // Add some recycling data
        uint32[] memory materials = new uint32[](2);
        materials[0] = 0; // PLASTIC
        materials[1] = 1; // GLASS

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 1000; // 1kg
        amounts[1] = 500; // 0.5kg

        uint32[] memory types = new uint32[](2);
        types[0] = 0; // PET
        types[1] = 0; // CLEAR_GLASS

        uint32[] memory shapes = new uint32[](2);
        shapes[0] = 0; // BOTTLE
        shapes[1] = 1; // JAR

        vm.prank(RECYCLER);
        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1500,
            materials,
            amounts,
            types,
            shapes,
            0
        );

        // Validate the report
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);

        // Test tokenJson function - no need to transfer token since tokenJson is a view function
        string memory jsonResult = recyReport.tokenJson(tokenId);

        // Verify the JSON contains expected structure
        assertTrue(
            bytes(jsonResult).length > 0,
            "JSON result should not be empty"
        );
    }

    function test_tokenJsonForNonExistentToken() public {
        // Test tokenJson with non-existent token
        vm.expectRevert();
        recyReport.tokenJson(999);
    }

    function test_mintRecyReportResult() public {
        // Just try to call the function with minimal data
        uint32[] memory materials = new uint32[](1);
        materials[0] = 0;

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1000;

        uint32[] memory types = new uint32[](1);
        types[0] = 0;

        uint32[] memory shapes = new uint32[](1);
        shapes[0] = 0;

        vm.prank(RECYCLER);
        recyReport.mintRecyReportResult(
            address(mockReceiver),
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            types,
            shapes,
            0
        );
    }

    function test_mintRecyReportResultWithMismatchedArrays() public {
        // Test with mismatched array lengths - should revert before any mint happens
        uint32[] memory materials = new uint32[](2);
        materials[0] = 0;
        materials[1] = 1;

        uint128[] memory amounts = new uint128[](3); // Different length
        amounts[0] = 500;
        amounts[1] = 500;
        amounts[2] = 0;

        uint32[] memory types = new uint32[](2);
        types[0] = 0;
        types[1] = 0;

        uint32[] memory shapes = new uint32[](2);
        shapes[0] = 0;
        shapes[1] = 1;

        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.ArrayLengthMismatch.selector);
        recyReport.mintRecyReportResult(
            address(mockReceiver),
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            types,
            shapes,
            0
        );
    }

    function test_mintRecyReportResultUnauthorized() public {
        // Test unauthorized minting
        address generator = user;
        uint32[] memory materials = new uint32[](1);
        uint128[] memory amounts = new uint128[](1);
        uint32[] memory types = new uint32[](1);
        uint32[] memory shapes = new uint32[](1);

        // Use an address that doesn't have RECYCLER_ROLE
        address unauthorizedUser = address(0x999);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        recyReport.mintRecyReportResult(
            generator,
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            types,
            shapes,
            0
        );
    }

    function test_claimRewardWithInsufficientBalance() public {
        // Deploy a separate token contract with no initial balance for the test
        RecyToken emptyToken = new RecyToken(
            "Empty Test Token",
            "EMPTY",
            18,
            0, // No initial supply
            address(this)
        );

        // Deploy a new RecyReport with the empty token
        RecyReport emptyRecyReport = new RecyReport();
        ERC1967Proxy emptyProxy = new ERC1967Proxy(
            address(emptyRecyReport),
            abi.encodeCall(
                RecyReport.initialize,
                (
                    "Empty Test NFT",
                    "EMPTY",
                    address(emptyToken),
                    address(recyData),
                    protocol,
                    86400, // 1 day unlock delay
                    25, // 25% to recycler
                    25, // 25% to validator
                    25, // 25% to generator
                    25 // 25% to protocol
                )
            )
        );
        RecyReport emptyRecyReportProxy = RecyReport(address(emptyProxy));

        // Grant roles
        emptyRecyReportProxy.grantRole(
            emptyRecyReportProxy.RECYCLER_ROLE(),
            recycler
        );
        emptyRecyReportProxy.grantRole(
            emptyRecyReportProxy.AUDITOR_ROLE(),
            validator
        );

        // Set up a validated report - mint to mock receiver
        emptyRecyReportProxy.mintRecyReport();
        uint256 tokenId = 0;

        // Transfer the token to mock receiver first so it can be claimed later
        emptyRecyReportProxy.transferFrom(
            address(this),
            address(mockReceiver),
            tokenId
        );

        uint32[] memory materials = new uint32[](1);
        materials[0] = 0;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1000;
        uint32[] memory types = new uint32[](1);
        types[0] = 0;
        uint32[] memory shapes = new uint32[](1);
        shapes[0] = 0;

        vm.prank(recycler);
        emptyRecyReportProxy.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            types,
            shapes,
            0
        );

        vm.prank(validator);
        emptyRecyReportProxy.validateRecyReport(tokenId);

        // Advance time to unlock the reward
        vm.warp(block.timestamp + 86400 + 1);

        // Try to claim reward - should fail due to insufficient balance (no tokens in contract)
        vm.expectRevert(RecyErrors.InsufficientRewardBalance.selector);
        vm.prank(address(mockReceiver));
        emptyRecyReportProxy.claimRecyReportReward(tokenId);
    }

    function test_unlockDateForValidatedReport() public {
        // Set up and validate a report
        recyReport.mintRecyReport();
        uint256 tokenId = 0;

        uint32[] memory materials = new uint32[](1);
        materials[0] = 0;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1000;
        uint32[] memory types = new uint32[](1);
        types[0] = 0;
        uint32[] memory shapes = new uint32[](1);
        shapes[0] = 0;

        vm.prank(RECYCLER);
        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1000,
            materials,
            amounts,
            types,
            shapes,
            0
        );

        uint256 validationTime = block.timestamp + 100;
        vm.warp(validationTime);

        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);

        // Check unlock date - validation happens at current block.timestamp (101) + unlock delay (3600)
        uint64 actualUnlockDate = recyReport.unlockDate(tokenId);
        uint64 expectedUnlockDate = uint64(block.timestamp + 3600); // current timestamp + unlock delay
        assertEq(actualUnlockDate, expectedUnlockDate);
    }

    // Events from OpenZeppelin Pausable
    event Paused(address account);
    event Unpaused(address account);

    // ===== FUND WALLET TESTS =====

    function test_setFundsWallet() public {
        address fundWallet = address(0x999);

        // Only admin should be able to set fund wallets
        vm.prank(user);
        vm.expectRevert();
        recyReport.setFundsWallet(user, fundWallet);

        // Admin can set fund wallet
        recyReport.setFundsWallet(user, fundWallet);

        // Verify fund wallet is set
        assertEq(recyReport.funds(user), fundWallet);
    }

    function test_claimRecyReportRewardWithFundWallets() public {
        // Setup fund wallets
        address generatorFund = address(0x2001);
        address recyclerFund = address(0x2002);
        address validatorFund = address(0x2003);

        // Set fund wallets for all participants
        recyReport.setFundsWallet(USER, generatorFund);
        recyReport.setFundsWallet(RECYCLER, recyclerFund);
        recyReport.setFundsWallet(VALIDATOR, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share (25% each)
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(generatorFund);
        uint256 recInitial = testToken.balanceOf(recyclerFund);
        uint256 valInitial = testToken.balanceOf(validatorFund);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify fund wallets received the rewards
        assertEq(
            testToken.balanceOf(generatorFund),
            genInitial + expectedAmount,
            "Generator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(recyclerFund),
            recInitial + expectedAmount,
            "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(protocol),
            protInitial + expectedAmount,
            "Protocol should receive reward directly"
        );

        // Verify original addresses did NOT receive rewards
        assertEq(
            testToken.balanceOf(USER),
            0,
            "Generator should not receive direct reward"
        );
        assertEq(
            testToken.balanceOf(RECYCLER),
            0,
            "Recycler should not receive direct reward"
        );
        assertEq(
            testToken.balanceOf(VALIDATOR),
            0,
            "Validator should not receive direct reward"
        );
    }

    function test_claimRecyReportRewardPartialFundWallets() public {
        // Only set fund wallet for recycler, not for generator or validator
        address recyclerFund = address(0x2002);
        recyReport.setFundsWallet(RECYCLER, recyclerFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(USER);
        uint256 recFundInitial = testToken.balanceOf(recyclerFund);
        uint256 valInitial = testToken.balanceOf(VALIDATOR);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify mixed distribution
        assertEq(
            testToken.balanceOf(USER),
            genInitial + expectedAmount,
            "Generator should receive direct reward (no fund wallet set)"
        );
        assertEq(
            testToken.balanceOf(recyclerFund),
            recFundInitial + expectedAmount,
            "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(VALIDATOR),
            valInitial + expectedAmount,
            "Validator should receive direct reward (no fund wallet set)"
        );
        assertEq(
            testToken.balanceOf(protocol),
            protInitial + expectedAmount,
            "Protocol should receive reward"
        );

        // Verify recycler did NOT receive direct reward
        assertEq(
            testToken.balanceOf(RECYCLER),
            0,
            "Recycler should not receive direct reward"
        );
    }

    function test_claimRecyReportRewardNoFundWallets() public {
        // Complete test setup without any fund wallets (original behavior)
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(USER);
        uint256 recInitial = testToken.balanceOf(RECYCLER);
        uint256 valInitial = testToken.balanceOf(VALIDATOR);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify all participants receive direct rewards
        assertEq(
            testToken.balanceOf(USER),
            genInitial + expectedAmount,
            "Generator should receive direct reward"
        );
        assertEq(
            testToken.balanceOf(RECYCLER),
            recInitial + expectedAmount,
            "Recycler should receive direct reward"
        );
        assertEq(
            testToken.balanceOf(VALIDATOR),
            valInitial + expectedAmount,
            "Validator should receive direct reward"
        );
        assertEq(
            testToken.balanceOf(protocol),
            protInitial + expectedAmount,
            "Protocol should receive reward"
        );
    }

    function test_fundWalletWithZeroAddress() public {
        address generator = USER;

        // Set fund wallet to zero address (should behave like no fund wallet)
        recyReport.setFundsWallet(generator, address(0));

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);

        // Record initial balance
        uint256 generatorInitialBalance = testToken.balanceOf(generator);

        // Fast forward and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, generator);

        // Calculate expected amount
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Verify generator receives direct reward (zero address fund wallet ignored)
        assertEq(
            testToken.balanceOf(generator),
            generatorInitialBalance + expectedAmount,
            "Generator should receive direct reward when fund wallet is zero address"
        );
    }

    function test_updateFundWallet() public {
        address user1 = address(0x1111);
        address fundWallet1 = address(0x2222);
        address fundWallet2 = address(0x3333);

        // Set initial fund wallet
        recyReport.setFundsWallet(user1, fundWallet1);
        assertEq(recyReport.funds(user1), fundWallet1);

        // Update fund wallet
        recyReport.setFundsWallet(user1, fundWallet2);
        assertEq(recyReport.funds(user1), fundWallet2);

        // Clear fund wallet (set to zero)
        recyReport.setFundsWallet(user1, address(0));
        assertEq(recyReport.funds(user1), address(0));
    }

    function test_fundWalletRewardDistributionAccuracy() public {
        // Deploy a new contract with different shares
        RecyReport implementation = new RecyReport();

        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "RecyReport Test",
            "RECYT",
            address(testToken),
            address(recyData),
            protocol,
            uint64(3600),
            uint8(40), // 40% recycler share
            uint8(30), // 30% validator share
            uint8(20), // 20% generator share
            uint8(10) // 10% protocol share
        );

        ERC1967Proxy testProxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        RecyReport testReport = RecyReport(address(testProxy));

        // Fund the contract and grant roles
        testToken.transfer(address(testReport), 10000 * 10 ** 18);
        grantStandardRoles(testReport, RECYCLER, VALIDATOR);

        // Setup fund wallets
        address generatorFund = address(0x4001);
        address recyclerFund = address(0x4002);
        address validatorFund = address(0x4003);

        testReport.setFundsWallet(USER, generatorFund);
        testReport.setFundsWallet(RECYCLER, recyclerFund);
        testReport.setFundsWallet(VALIDATOR, validatorFund);

        // Complete setup and claim
        uint256 tokenId = mintCompleteAndValidateReport(testReport);
        (uint128 rewardAmount, ) = testReport.reward(tokenId);

        fastForwardAndClaimReward(testReport, tokenId, USER);

        // Verify correct distribution with custom percentages
        assertEq(testToken.balanceOf(generatorFund), (rewardAmount * 20) / 100);
        assertEq(testToken.balanceOf(recyclerFund), (rewardAmount * 40) / 100);
        assertEq(testToken.balanceOf(validatorFund), (rewardAmount * 30) / 100);
        assertEq(testToken.balanceOf(protocol), (rewardAmount * 10) / 100);
    }

    // ===== ACCESS CONTROL TESTS FOR REWARD CLAIMING =====

    function test_claimRewardByRecycler() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        vm.warp(block.timestamp + 3601);

        // Test that the specific recycler involved can claim
        vm.prank(recycler);
        recyReport.claimRecyReportReward(tokenId);

        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardByValidator() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        vm.warp(block.timestamp + 3601);

        // Test that the specific validator involved can claim
        vm.prank(validator);
        recyReport.claimRecyReportReward(tokenId);

        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardByUnauthorizedRecycler() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Create another recycler that has the role but wasn't involved in this report
        address otherRecycler = address(0x8888);
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, otherRecycler);

        vm.warp(block.timestamp + 3601);

        // Test that a different recycler cannot claim
        vm.prank(otherRecycler);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRewardByUnauthorizedValidator() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(
            recyReport,
            user,
            recycler,
            validator
        );

        // Create another validator that has the role but wasn't involved in this report
        address otherValidator = address(0x7777);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, otherValidator);

        vm.warp(block.timestamp + 3601);

        // Test that a different validator cannot claim
        vm.prank(otherValidator);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRewardAccessControlComprehensive() public {
        // Test 1: Create and claim by owner
        uint256 tokenId1 = completeTestSetup(
            recyReport,
            address(0x1001),
            address(0x1002),
            address(0x1003)
        );
        uint64 unlockTime1 = recyReport.unlockDate(tokenId1);
        vm.warp(unlockTime1 + 1);
        vm.prank(address(0x1001));
        recyReport.claimRecyReportReward(tokenId1);

        // Test 2: Create and claim by recycler
        uint256 tokenId2 = completeTestSetup(
            recyReport,
            address(0x2001),
            address(0x2002),
            address(0x2003)
        );
        uint64 unlockTime2 = recyReport.unlockDate(tokenId2);
        vm.warp(unlockTime2 + 1);
        vm.prank(address(0x2002));
        recyReport.claimRecyReportReward(tokenId2);

        // Test 3: Create and claim by validator
        uint256 tokenId3 = completeTestSetup(
            recyReport,
            address(0x3001),
            address(0x3002),
            address(0x3003)
        );
        uint64 unlockTime3 = recyReport.unlockDate(tokenId3);
        vm.warp(unlockTime3 + 1);
        vm.prank(address(0x3003));
        recyReport.claimRecyReportReward(tokenId3);

        // Test 4: Create and try to claim by unauthorized user (should fail)
        uint256 tokenId4 = completeTestSetup(
            recyReport,
            address(0x4001),
            address(0x4002),
            address(0x4003)
        );
        uint64 unlockTime4 = recyReport.unlockDate(tokenId4);
        vm.warp(unlockTime4 + 1);
        vm.prank(address(0x9999));
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId4);
    }

    function test_claimRewardWithFundWalletsByRecycler() public {
        // Setup fund wallets
        address generatorFund = address(0x2001);
        address recyclerFund = address(0x2002);
        address validatorFund = address(0x2003);

        recyReport.setFundsWallet(USER, generatorFund);
        recyReport.setFundsWallet(RECYCLER, recyclerFund);
        recyReport.setFundsWallet(VALIDATOR, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(generatorFund);
        uint256 recInitial = testToken.balanceOf(recyclerFund);
        uint256 valInitial = testToken.balanceOf(validatorFund);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward BY RECYCLER
        vm.warp(block.timestamp + 3601);
        vm.prank(RECYCLER);
        recyReport.claimRecyReportReward(tokenId);

        // Verify rewards went to fund wallets
        assertEq(
            testToken.balanceOf(generatorFund),
            genInitial + expectedAmount,
            "Generator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(recyclerFund),
            recInitial + expectedAmount,
            "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(protocol),
            protInitial + expectedAmount,
            "Protocol should receive reward directly"
        );
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardWithFundWalletsByValidator() public {
        // Setup fund wallets
        address generatorFund = address(0x3001);
        address recyclerFund = address(0x3002);
        address validatorFund = address(0x3003);

        recyReport.setFundsWallet(USER, generatorFund);
        recyReport.setFundsWallet(RECYCLER, recyclerFund);
        recyReport.setFundsWallet(VALIDATOR, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount, ) = recyReport.reward(tokenId);
        uint128 expectedAmount = (rewardAmount * 25) / 100;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(generatorFund);
        uint256 recInitial = testToken.balanceOf(recyclerFund);
        uint256 valInitial = testToken.balanceOf(validatorFund);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward BY VALIDATOR
        vm.warp(block.timestamp + 3601);
        vm.prank(VALIDATOR);
        recyReport.claimRecyReportReward(tokenId);

        // Verify rewards went to fund wallets
        assertEq(
            testToken.balanceOf(generatorFund),
            genInitial + expectedAmount,
            "Generator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(recyclerFund),
            recInitial + expectedAmount,
            "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(protocol),
            protInitial + expectedAmount,
            "Protocol should receive reward directly"
        );
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    // ===== END ACCESS CONTROL TESTS =====

    // ===== END FUND WALLET TESTS =====
}
