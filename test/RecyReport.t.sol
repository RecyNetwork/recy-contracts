// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../src/RecyReport.sol";
import "../src/RecyReportAttributes.sol";
import "../src/RecyReportData.sol";
import "../src/RecyReportSvg.sol";
import "../src/RecyToken.sol";
import "../src/lib/RecyConstants.sol";
import "../src/lib/RecyErrors.sol";
import "../src/lib/RecyReward.sol";
import "./helpers/RecyReportOriginalLayout.sol";
import "./helpers/TestHelpers.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/Test.sol";

// Mock ERC721 receiver for testing
contract MockReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @dev ERC20 whose transfer returns false instead of reverting — the non-reverting failure mode
/// SafeERC20 exists to catch. Balances are seeded directly because transfer is deliberately inert.
/// It mirrors RecyToken's issuance getters because report initialization and reward calculation
/// require them; transfer remains the only deliberately non-standard behavior under test.
contract FalseReturnToken {
    uint256 public totalSupply = 1_000_000 * 10 ** 18;
    uint256 public totalIssued = 1_000_000 * 10 ** 18;
    uint256 public immutable issuanceChainId;
    mapping(address => uint256) public balanceOf;

    constructor() {
        issuanceChainId = block.chainid;
    }

    function seed(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

// Getter-focused tests deliberately skip unrelated tuple members; batch tests intentionally call
// the contract repeatedly; expected-event declarations must follow vm.expectEmit cheatcode calls.
// These test-only patterns do not represent ignored production results or callback-sensitive logs.
/// forge-lint: disable-start(unused-return,calls-loop,reentrancy-events)
contract RecyReportTest is Test, TestHelpers, IERC721Receiver {
    RecyReport public recyReport;
    RecyReportData public recyData;
    RecyReportAttributes public recyAttributes;
    RecyReportSvg public recySvg;
    RecyToken public testToken;
    MockReceiver public mockReceiver;
    ERC1967Proxy public proxy;
    address public tokenEndpoint;

    address public owner;
    address public user;
    address public recycler;
    address public validator;
    address public protocol;

    // Independently derived expectations, computed by hand rather than mirrored from the contract's
    // own formulas, so that a change to the reward math or the share split is caught rather than
    // reproduced. testToken's cumulative issuance is 1_000_000e18, at or below RecyReward.FIRST_EPOCH
    // (2_138_428e18), so the divisor is FIRST_EPOCH_REWARD = 1e6 and the reward for a report is
    // wasteAmount_mg * 1e18 / 1e6 = wasteAmount_mg * 1e12. The shared helpers record 1500 mg.
    uint128 internal constant EXPECTED_REWARD_1500MG = 1_500_000_000_000_000;
    uint256 internal constant EXPECTED_SHARE_25_OF_1500MG = 375_000_000_000_000;

    function setUp() public {
        owner = address(this);
        user = address(0x123);
        recycler = address(0x456);
        validator = address(0x789);
        protocol = address(0xABC);

        // Deploy test token
        tokenEndpoint = address(deployTestEndpoint(TEST_EID));
        testToken = new RecyToken("Test Recy Token", "TRECY", 1_000_000, tokenEndpoint, address(this), block.chainid);
        mockReceiver = new MockReceiver();

        // Deploy dependencies
        recyAttributes = new RecyReportAttributes();
        recySvg = new RecyReportSvg();
        recyData = new RecyReportData(address(recyAttributes), address(recySvg));

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
        assertTrue(testToken.transfer(address(recyReport), 10_000 * 10 ** 18));

        // Grant necessary roles for testing
        grantStandardRoles(recyReport, RECYCLER, VALIDATOR);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
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

        // Set report result at exactly the per-report cap; the bound is inclusive
        recyReport.setRecyReportResult(
            0,
            SafeCast.toUint64(block.timestamp),
            RecyConstants.MAX_WASTE_AMOUNT,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        assertReportStatus(recyReport, 0, RecyConstants.RECYCLE_COMPLETED);
        (,,,, uint128 wasteAmount) = recyReport.info(0);
        assertEq(wasteAmount, RecyConstants.MAX_WASTE_AMOUNT);
    }

    function test_validateRecyReport() public {
        // Use helper to setup mint and complete report
        uint256 tokenId = mintAndCompleteReport(recyReport);

        // Grant auditor role and validate
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.validateRecyReport(tokenId);

        assertReportStatus(recyReport, tokenId, RecyConstants.RECYCLE_VALIDATED);

        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertGt(rewardAmount, 0);
    }

    function test_claimRecyReportReward() public {
        // Use helper to setup mint, complete, and validate report
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Fast forward time and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify claim was successful
        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertGt(rewardAmount, 0);
    }

    function test_getRecyReportMaterials() public {
        // Use helper to setup mint and complete report
        uint256 tokenId = mintAndCompleteReport(recyReport);

        // Get materials from the completed report
        RecyTypes.RecyMaterials[] memory materials = recyReport.getRecyReportMaterials(tokenId);

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

    function test_upgradeFromOriginalLayoutPreservesStateAndForwarder() public {
        RecyReportOriginalLayout originalImplementation = new RecyReportOriginalLayout();
        ERC1967Proxy originalProxy = new ERC1967Proxy(
            address(originalImplementation),
            abi.encodeCall(
                RecyReportOriginalLayout.initialize,
                (
                    "Original Layout Report",
                    "ORIGINAL",
                    address(testToken),
                    address(recyData),
                    protocol,
                    60,
                    60,
                    10,
                    20,
                    10
                )
            )
        );
        RecyReportOriginalLayout originalReport = RecyReportOriginalLayout(address(originalProxy));
        address fundWallet = address(0xF00D);
        originalReport.seedValidatedReport(user, recycler, validator, fundWallet);
        assertTrue(testToken.transfer(address(originalProxy), 1000 ether));
        uint256 proxyTokenBalance = testToken.balanceOf(address(originalProxy));
        uint256 tokenSupply = testToken.totalSupply();
        uint256 tokenIssued = testToken.totalIssued();

        RecyReport newImplementation = new RecyReport();
        originalReport.upgradeToAndCall(address(newImplementation), "");
        RecyReport upgradedReport = RecyReport(address(originalProxy));

        assertEq(upgradedReport.trustedForwarder(), address(0), "legacy protocol address became the forwarder");
        _assertOriginalLayoutState(upgradedReport, fundWallet, proxyTokenBalance, tokenSupply, tokenIssued);

        address forwarder = address(0xF01);
        upgradedReport.setTrustedForwarder(forwarder);
        assertEq(upgradedReport.trustedForwarder(), forwarder);
        assertTrue(upgradedReport.isTrustedForwarder(forwarder));
        _assertOriginalLayoutState(upgradedReport, fundWallet, proxyTokenBalance, tokenSupply, tokenIssued);

        address forwardedSender = address(0xBEEF);
        bytes memory forwardedCallData =
            abi.encodePacked(abi.encodeCall(RecyReport.mintRecyReport, ()), forwardedSender);
        vm.prank(forwarder);
        (bool success,) = address(upgradedReport).call(forwardedCallData);

        assertTrue(success);
        assertEq(upgradedReport.ownerOf(1), forwardedSender);
        assertEq(upgradedReport.nftNextId(), 2);
    }

    function _assertOriginalLayoutState(
        RecyReport report,
        address fundWallet,
        uint256 proxyTokenBalance,
        uint256 tokenSupply,
        uint256 tokenIssued
    ) internal view {
        assertEq(report.name(), "Original Layout Report");
        assertEq(report.symbol(), "ORIGINAL");
        assertEq(address(report.token()), address(testToken));
        assertEq(
            address(uint160(uint256(vm.load(address(report), bytes32(uint256(0)))))),
            address(recyData),
            "data slot changed"
        );
        assertEq(report.protocolAddress(), protocol);
        assertEq(report.nftNextId(), 1);
        assertEq(report.unlockDelay(), 60);
        assertEq(report.shareRecycler(), 60);
        assertEq(report.shareValidator(), 10);
        assertEq(report.shareGenerator(), 20);
        assertEq(report.shareProtocol(), 10);
        assertEq(report.rewardTotal(), 900 ether);
        assertEq(report.rewardMinted(), 800 ether);
        assertEq(report.rewardClaimed(), 123 ether);

        (address infoValidator, address infoRecycler, uint64 recycleDate, uint64 auditDate, uint128 wasteAmount) =
            report.info(0);
        assertEq(infoValidator, validator);
        assertEq(infoRecycler, recycler);
        assertEq(recycleDate, 1_700_000_001);
        assertEq(auditDate, 1_700_000_002);
        assertEq(wasteAmount, 1_234_567);

        RecyTypes.RecyMaterials[] memory storedMaterials = report.getRecyReportMaterials(0);
        assertEq(storedMaterials.length, 1);
        assertEq(storedMaterials[0].material, 7);
        assertEq(storedMaterials[0].recycleType, 8);
        assertEq(storedMaterials[0].recycleShape, 9);
        assertEq(storedMaterials[0].disposalMethod, 10);
        assertEq(storedMaterials[0].amountRecycled, 1_234_567);

        (uint128 rewardAmount, uint64 rewardUnlockDate) = report.reward(0);
        assertEq(rewardAmount, 777 ether);
        assertEq(rewardUnlockDate, 1_700_000_003);
        assertEq(report.status(0), RecyConstants.RECYCLE_VALIDATED);
        assertEq(report.funds(user), fundWallet);
        assertEq(report.ownerOf(0), user);
        assertTrue(report.hasRole(report.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(report.hasRole(RecyConstants.RECYCLER_ROLE, recycler));
        assertTrue(report.hasRole(RecyConstants.AUDITOR_ROLE, validator));
        assertEq(testToken.balanceOf(address(report)), proxyTokenBalance);
        assertEq(testToken.totalSupply(), tokenSupply);
        assertEq(testToken.totalIssued(), tokenIssued);
        assertEq(testToken.owner(), address(this));
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
        RecyTypes.RecyMaterials[] memory reportMaterials = recyReport.getRecyReportMaterials(0);
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

    function test_initializeRejectsOutOfBoundsUnlockDelay() public {
        // Same bounds as setUnlockDelay, enforced at birth: without this, a new proxy (e.g. via
        // RecyReportFactoryV2.deployProxy) could be born with no reaction window at all, or with
        // a wrap-inducing delay that stores unlock dates in the past.
        RecyReport implementation = new RecyReport();

        uint64[3] memory badDelays = [uint64(0), RecyConstants.MIN_UNLOCK_DELAY - 1, type(uint64).max];
        for (uint256 i = 0; i < badDelays.length; i++) {
            bytes memory initData = abi.encodeCall(
                RecyReport.initialize,
                ("Test", "TEST", address(testToken), address(recyData), protocol, badDelays[i], 25, 25, 25, 25)
            );
            vm.expectRevert(RecyErrors.UnlockDelayOutOfBounds.selector);
            new ERC1967Proxy(address(implementation), initData);
        }

        // Both bounds inclusive at birth.
        RecyReport atMin = RecyReport(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        RecyReport.initialize,
                        (
                            "Test",
                            "TEST",
                            address(testToken),
                            address(recyData),
                            protocol,
                            RecyConstants.MIN_UNLOCK_DELAY,
                            25,
                            25,
                            25,
                            25
                        )
                    )
                )
            )
        );
        assertEq(atMin.unlockDelay(), RecyConstants.MIN_UNLOCK_DELAY);
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

    function test_initializeRejectsZeroProtocolAddressWithZeroProtocolShare() public {
        RecyReport implementation = new RecyReport();
        bytes memory initData = abi.encodeCall(
            RecyReport.initialize,
            (
                "Test",
                "TEST",
                address(testToken),
                address(recyData),
                address(0),
                RecyConstants.MIN_UNLOCK_DELAY,
                34,
                33,
                33,
                0
            )
        );

        // Even a zero-value ERC20 transfer rejects address(0), so a zero protocol share did not
        // make this configuration safe: every otherwise valid claim still reverted.
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
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
        vm.expectRevert(abi.encodeWithSelector(RecyErrors.RecyReportInvalidShareDistribution.selector));
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
        vm.expectRevert(abi.encodeWithSelector(RecyErrors.RecyReportInvalidShareDistribution.selector));
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

        ERC1967Proxy testProxyEqual = new ERC1967Proxy(address(implementation), initDataEqual);
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

        ERC1967Proxy testProxyUnequal = new ERC1967Proxy(address(implementation2), initDataUnequal);
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

        ERC1967Proxy testProxyEdge = new ERC1967Proxy(address(implementation3), initDataEdge);
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
            "Another Name", "ANOTHER", address(testToken), address(recyData), protocol, 7200, 30, 30, 30, 10
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
        assertTrue(recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this)));
        recyReport.revokeRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this));
        assertFalse(recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), address(this)));
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

        // A report with no materials passes every length-parity check but describes nothing and
        // still earns a reward from _wasteAmount alone. It is now rejected outright.
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        vm.expectRevert(RecyErrors.EmptyMaterialsArray.selector);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 1
        );

        // The report is untouched and still claimable by a later, well-formed write
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_CREATED);
        assertEq(recyReport.getRecyReportMaterials(0).length, 0);
    }

    function test_mintRecyReportResultWithEmptyArraysReverts() public {
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createEmptyArrays();

        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.EmptyMaterialsArray.selector);
        recyReport.mintRecyReportResult(
            user, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 1
        );

        // Nothing was minted
        assertEq(recyReport.nftNextId(), 0);
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
            0, SafeCast.toUint64(block.timestamp), 1, materials, materialAmounts, recycleTypes, recycleShapes, 1
        );
    }

    function test_setRecyReportResultWithMaxValues() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createMaxValueArrays();

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);

        // type(uint128).max waste is now rejected: uncapped, it mints an unbounded reward claim.
        vm.expectRevert(RecyErrors.WasteAmountExceedsCap.selector);
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

        // Even within the waste cap, a type(uint32).max material id is rejected. Left unchecked it
        // makes tokenURI and tokenJson revert forever, and materials[] is push-only, so the token
        // could never be repaired.
        vm.expectRevert(RecyErrors.MaterialIdOutOfRange.selector);
        recyReport.setRecyReportResult(
            0,
            type(uint64).max,
            RecyConstants.MAX_WASTE_AMOUNT,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            type(uint32).max
        );

        // Neither attempt left a trace, and the metadata still renders
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_CREATED);
        assertEq(recyReport.getRecyReportMaterials(0).length, 0);
        assertGt(bytes(recyReport.tokenURI(0)).length, 0);
    }

    function test_materialIdJustPastCatalogueIsRejected() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint256 count = recyData.materialsCount();
        assertGt(count, 0);

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = 1000;

        // The catalogue is zero-indexed, so `count` itself is the first invalid id
        materials[0] = SafeCast.toUint32(count);
        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.MaterialIdOutOfRange.selector);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        // ...and `count - 1` is the last valid one
        materials[0] = SafeCast.toUint32(count - 1);
        vm.prank(RECYCLER);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);
    }

    function test_mintRecyReportResultRejectsOutOfRangeMaterialAndOversizeWaste() public {
        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = 1000;

        materials[0] = SafeCast.toUint32(recyData.materialsCount());
        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.MaterialIdOutOfRange.selector);
        recyReport.mintRecyReportResult(
            user, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        materials[0] = 0;
        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.WasteAmountExceedsCap.selector);
        recyReport.mintRecyReportResult(
            user,
            SafeCast.toUint64(block.timestamp),
            RecyConstants.MAX_WASTE_AMOUNT + 1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Neither rejected call minted a token
        assertEq(recyReport.nftNextId(), 0);
    }

    function test_setRecyReportResultOnNonExistentToken() public {
        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        // Writing to an unminted id used to succeed, corrupting rewardTotal for a token nobody
        // owns and pre-poisoning materials[] for an id that has not been minted yet. The existence
        // check fires first: an unminted id also has status 0, so the status guard would reject it
        // too, but the caller deserves the accurate reason.
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);
        vm.expectRevert(RecyErrors.NftNotExists.selector);
        recyReport.setRecyReportResult(
            999, // Non-existent token
            SafeCast.toUint64(block.timestamp),
            1,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1
        );

        assertEq(recyReport.status(999), 0);
        assertEq(recyReport.getRecyReportMaterials(999).length, 0);
    }

    function test_setRecyReportResultTwice() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, owner);

        // First set: CREATED -> COMPLETED
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1, materials, materialAmounts, recycleTypes, recycleShapes, 1
        );
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);

        // A second set is now rejected. Materials append rather than replace, so re-writing a
        // report only ever grew it; worse, the same path could reset a REWARDED report owned by a
        // third party back to COMPLETED and have it validated again.
        vm.expectRevert(RecyErrors.RecyReportInvalidStatus.selector);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp + 100), 2, materials, materialAmounts, recycleTypes, recycleShapes, 2
        );

        // The first write is intact and was not appended to
        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED);
        assertEq(recyReport.getRecyReportMaterials(0).length, 1);
        (,,,, uint128 wasteAmount) = recyReport.info(0);
        assertEq(wasteAmount, 1);
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
            0, SafeCast.toUint64(block.timestamp), 1, materials, materialAmounts, recycleTypes, recycleShapes, 1
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
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

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
        materialAmounts[0] = 1500;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1500, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        vm.prank(user); // Not an auditor
        vm.expectRevert();
        recyReport.validateRecyReport(0);
    }

    // ===== REWARD CLAIMING EDGE CASES =====

    function test_claimRewardBeforeUnlock() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

        // Don't warp - try to claim immediately (before unlock)
        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRewardTwice() public {
        // Setup: mint, complete, and validate a report with realistic amounts
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

        // Verify the report is validated
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_VALIDATED);

        // First claim - should succeed
        vm.warp(block.timestamp + 3601);

        // Check that the reward can be claimed
        uint64 unlockTime = recyReport.unlockDate(tokenId);
        assertTrue(unlockTime > 0);
        // This warp-controlled test asserts the protocol's time boundary; validator skew is not a
        // risk in deterministic test time.
        /// forge-lint: disable-next-line(block-timestamp)
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
        materialAmounts[0] = 1500;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1500, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        vm.warp(block.timestamp + 3601);
        vm.prank(user);
        vm.expectRevert();
        recyReport.claimRecyReportReward(0);
    }

    function test_claimRewardByNonOwner() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

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
        RecyTypes.RecyMaterials[] memory materials = recyReport.getRecyReportMaterials(999);
        assertEq(materials.length, 0);
    }

    function test_getRecyReportMaterialsForMintedReport() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        RecyTypes.RecyMaterials[] memory materials = recyReport.getRecyReportMaterials(0);
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
        materialAmounts[0] = 1500;
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            0, SafeCast.toUint64(block.timestamp), 1500, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        uint64 unlockTime = recyReport.unlockDate(0);
        assertEq(unlockTime, 0); // Should be 0 for unvalidated reports
    }

    function test_unlockDateCalculation() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

        uint64 unlockTime = recyReport.unlockDate(tokenId);
        // Deterministic test time is compared deliberately to the stored protocol deadline.
        /// forge-lint: disable-next-line(block-timestamp)
        assertTrue(unlockTime > SafeCast.toUint64(block.timestamp));
        /// forge-lint: disable-next-line(block-timestamp)
        assertTrue(unlockTime <= SafeCast.toUint64(block.timestamp + 3600));
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
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

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
            0, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, recycleTypes, recycleShapes, 0
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
            0, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, recycleTypes, recycleShapes, 0
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
            tokenId, SafeCast.toUint64(block.timestamp), 1500, materials, amounts, types, shapes, 0
        );

        // Validate the report
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);

        // Test tokenJson function - no need to transfer token since tokenJson is a view function
        string memory jsonResult = recyReport.tokenJson(tokenId);

        // Verify the JSON contains expected structure
        assertTrue(bytes(jsonResult).length > 0, "JSON result should not be empty");
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
            address(mockReceiver), SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
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
            address(mockReceiver), SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
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
            generator, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
        );
    }

    function test_validateRevertsWhenRewardCannotBeFunded() public {
        // Deploy a separate token contract with no initial balance for the test
        RecyToken emptyToken = new RecyToken(
            "Empty Test Token",
            "EMPTY",
            0, // No initial supply
            tokenEndpoint,
            address(this),
            block.chainid
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
                    86_400, // 1 day unlock delay
                    25, // 25% to recycler
                    25, // 25% to validator
                    25, // 25% to generator
                    25 // 25% to protocol
                )
            )
        );
        RecyReport emptyRecyReportProxy = RecyReport(address(emptyProxy));

        // Grant roles
        emptyRecyReportProxy.grantRole(emptyRecyReportProxy.RECYCLER_ROLE(), recycler);
        emptyRecyReportProxy.grantRole(emptyRecyReportProxy.AUDITOR_ROLE(), validator);

        emptyRecyReportProxy.mintRecyReport();
        uint256 tokenId = 0;

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
            tokenId, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
        );

        // The protocol refuses to promise what it cannot pay. Previously this validation succeeded
        // and only the eventual claim failed, leaving rewardTotal inflated by an unpayable amount
        // that RecyDistribution would then try to mint against.
        vm.prank(validator);
        vm.expectRevert(RecyErrors.InsufficientRewardBalance.selector);
        emptyRecyReportProxy.validateRecyReport(tokenId);

        assertEq(emptyRecyReportProxy.status(tokenId), RecyConstants.RECYCLE_COMPLETED);
        assertEq(emptyRecyReportProxy.rewardTotal(), 0);
    }

    function test_claimRewardWithInsufficientBalance() public {
        // The claim-time balance check still guards the case the validation-time solvency check
        // cannot see: the balance falling after validation.
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Read the balance first: vm.prank applies to the very next external call, and evaluating
        // balanceOf inline would consume it.
        uint256 pool = testToken.balanceOf(address(recyReport));
        vm.prank(address(recyReport));
        assertTrue(testToken.transfer(address(0xDEAD), pool));
        assertEq(testToken.balanceOf(address(recyReport)), 0);

        vm.warp(block.timestamp + 3601);
        vm.prank(USER);
        vm.expectRevert(RecyErrors.InsufficientRewardBalance.selector);
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_claimRevertsWhenTokenReturnsFalseInsteadOfReverting() public {
        // cRECY reverts on failed transfers, so every other claim test would pass identically with
        // raw token.transfer. This pins the one behaviour SafeERC20 was adopted for: a token that
        // signals failure by returning false must not let a claim "succeed" unpaid. Before the
        // SafeERC20 change the claim below completed, set REWARDED, and paid nobody.
        FalseReturnToken falseToken = new FalseReturnToken();

        RecyReport impl = new RecyReport();
        ERC1967Proxy falseProxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                RecyReport.initialize,
                ("False Token NFT", "FALSE", address(falseToken), address(recyData), protocol, 3600, 25, 25, 25, 25)
            )
        );
        RecyReport report = RecyReport(address(falseProxy));
        falseToken.seed(address(report), 10_000 * 10 ** 18);

        report.grantRole(report.RECYCLER_ROLE(), recycler);
        report.grantRole(report.AUDITOR_ROLE(), validator);

        vm.prank(user);
        report.mintRecyReport();
        uint256 tokenId = 0;

        uint32[] memory materials = new uint32[](1);
        uint128[] memory amounts = new uint128[](1);
        uint32[] memory types = new uint32[](1);
        uint32[] memory shapes = new uint32[](1);
        amounts[0] = 1000;

        vm.prank(recycler);
        report.setRecyReportResult(
            tokenId, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
        );
        vm.prank(validator);
        report.validateRecyReport(tokenId);

        vm.warp(block.timestamp + 3601);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        report.claimRecyReportReward(tokenId);

        // The whole claim must unwind: no REWARDED status, no claimed accounting, no vanished funds.
        assertEq(report.status(tokenId), RecyConstants.RECYCLE_VALIDATED);
        assertEq(report.rewardClaimed(), 0);
        assertEq(falseToken.balanceOf(address(report)), 10_000 * 10 ** 18);
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
            tokenId, SafeCast.toUint64(block.timestamp), 1000, materials, amounts, types, shapes, 0
        );

        uint256 validationTime = block.timestamp + 100;
        vm.warp(validationTime);

        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);

        // Check unlock date - validation happens at current block.timestamp (101) + unlock delay (3600)
        uint64 actualUnlockDate = recyReport.unlockDate(tokenId);
        uint64 expectedUnlockDate = SafeCast.toUint64(block.timestamp + 3600); // current timestamp + unlock delay
        assertEq(actualUnlockDate, expectedUnlockDate);
    }

    // Events from OpenZeppelin Pausable
    event Paused(address account);
    event Unpaused(address account);

    // ===== FUND WALLET TESTS =====

    /// @dev Fund wallets are self-service, so every participant must set its own.
    function _setStandardFundWallets(
        RecyReport report,
        address generatorFund,
        address recyclerFund,
        address validatorFund
    ) private {
        vm.prank(USER);
        report.setFundsWallet(generatorFund);
        vm.prank(RECYCLER);
        report.setFundsWallet(recyclerFund);
        vm.prank(VALIDATOR);
        report.setFundsWallet(validatorFund);
    }

    function test_setFundsWallet() public {
        address fundWallet = address(0x999);

        // Any account may set its own fund wallet, with no role required
        vm.prank(user);
        recyReport.setFundsWallet(fundWallet);
        assertEq(recyReport.funds(user), fundWallet);

        // An admin cannot reach somebody else's entry. address(this) holds DEFAULT_ADMIN_ROLE, and
        // its write lands on its own slot. funds[] is resolved at claim time while the reward is
        // snapshotted at validation, so an admin able to write here could have redirected an
        // already-earned payout in the block before the owner claimed it.
        recyReport.setFundsWallet(address(0xBEEF));
        assertEq(recyReport.funds(user), fundWallet, "admin must not redirect another account's payout");
        assertEq(recyReport.funds(address(this)), address(0xBEEF));
    }

    function test_claimRecyReportRewardWithFundWallets() public {
        // Setup fund wallets
        address generatorFund = address(0x2001);
        address recyclerFund = address(0x2002);
        address validatorFund = address(0x2003);

        // Set fund wallets for all participants
        _setStandardFundWallets(recyReport, generatorFund, recyclerFund, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Independent expectation: 1500 mg at the FIRST_EPOCH divisor, split 25% four ways
        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");
        uint256 expectedAmount = EXPECTED_SHARE_25_OF_1500MG;

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
            testToken.balanceOf(recyclerFund), recInitial + expectedAmount, "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(testToken.balanceOf(protocol), protInitial + expectedAmount, "Protocol should receive reward directly");

        // Verify original addresses did NOT receive rewards
        assertEq(testToken.balanceOf(USER), 0, "Generator should not receive direct reward");
        assertEq(testToken.balanceOf(RECYCLER), 0, "Recycler should not receive direct reward");
        assertEq(testToken.balanceOf(VALIDATOR), 0, "Validator should not receive direct reward");
    }

    function test_claimRecyReportRewardPartialFundWallets() public {
        // Only set fund wallet for recycler, not for generator or validator
        address recyclerFund = address(0x2002);
        vm.prank(RECYCLER);
        recyReport.setFundsWallet(recyclerFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");
        uint256 expectedAmount = EXPECTED_SHARE_25_OF_1500MG;

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
        assertEq(testToken.balanceOf(protocol), protInitial + expectedAmount, "Protocol should receive reward");

        // Verify recycler did NOT receive direct reward
        assertEq(testToken.balanceOf(RECYCLER), 0, "Recycler should not receive direct reward");
    }

    function test_claimRecyReportRewardNoFundWallets() public {
        // Complete test setup without any fund wallets (original behavior)
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");
        uint256 expectedAmount = EXPECTED_SHARE_25_OF_1500MG;

        // Record initial balances
        uint256 genInitial = testToken.balanceOf(USER);
        uint256 recInitial = testToken.balanceOf(RECYCLER);
        uint256 valInitial = testToken.balanceOf(VALIDATOR);
        uint256 protInitial = testToken.balanceOf(protocol);

        // Fast forward and claim reward
        fastForwardAndClaimReward(recyReport, tokenId, USER);

        // Verify all participants receive direct rewards
        assertEq(testToken.balanceOf(USER), genInitial + expectedAmount, "Generator should receive direct reward");
        assertEq(testToken.balanceOf(RECYCLER), recInitial + expectedAmount, "Recycler should receive direct reward");
        assertEq(testToken.balanceOf(VALIDATOR), valInitial + expectedAmount, "Validator should receive direct reward");
        assertEq(testToken.balanceOf(protocol), protInitial + expectedAmount, "Protocol should receive reward");
    }

    function test_fundWalletWithZeroAddress() public {
        address generator = USER;

        // Set fund wallet to zero address (should behave like no fund wallet)
        vm.prank(generator);
        recyReport.setFundsWallet(address(0));

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount
        (uint128 rewardAmount,) = recyReport.reward(tokenId);

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
        vm.prank(user1);
        recyReport.setFundsWallet(fundWallet1);
        assertEq(recyReport.funds(user1), fundWallet1);

        // Update fund wallet
        vm.prank(user1);
        recyReport.setFundsWallet(fundWallet2);
        assertEq(recyReport.funds(user1), fundWallet2);

        // Clear fund wallet (set to zero)
        vm.prank(user1);
        recyReport.setFundsWallet(address(0));
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

        ERC1967Proxy testProxy = new ERC1967Proxy(address(implementation), initData);
        RecyReport testReport = RecyReport(address(testProxy));

        // Fund the contract and grant roles
        assertTrue(testToken.transfer(address(testReport), 10_000 * 10 ** 18));
        grantStandardRoles(testReport, RECYCLER, VALIDATOR);

        // Setup fund wallets
        address generatorFund = address(0x4001);
        address recyclerFund = address(0x4002);
        address validatorFund = address(0x4003);

        _setStandardFundWallets(testReport, generatorFund, recyclerFund, validatorFund);

        // Complete setup and claim
        uint256 tokenId = mintCompleteAndValidateReport(testReport);
        (uint128 rewardAmount,) = testReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");

        fastForwardAndClaimReward(testReport, tokenId, USER);

        // Independent expectations for the 40/30/20/10 split of a 1_500_000_000_000_000 wei reward.
        // Written out rather than recomputed from the shares so a change to either the split or the
        // division in claimRecyReportReward is caught instead of mirrored.
        assertEq(testToken.balanceOf(generatorFund), 300_000_000_000_000, "generator should get 20%");
        assertEq(testToken.balanceOf(recyclerFund), 600_000_000_000_000, "recycler should get 40%");
        assertEq(testToken.balanceOf(validatorFund), 450_000_000_000_000, "validator should get 30%");
        assertEq(testToken.balanceOf(protocol), 150_000_000_000_000, "protocol should get 10%");
    }

    // ===== ACCESS CONTROL TESTS FOR REWARD CLAIMING =====

    function test_claimRewardByRecycler() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

        vm.warp(block.timestamp + 3601);

        // Test that the specific recycler involved can claim
        vm.prank(recycler);
        recyReport.claimRecyReportReward(tokenId);

        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardByValidator() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

        vm.warp(block.timestamp + 3601);

        // Test that the specific validator involved can claim
        vm.prank(validator);
        recyReport.claimRecyReportReward(tokenId);

        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardByUnauthorizedRecycler() public {
        // Setup: mint, complete, and validate a report
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

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
        uint256 tokenId = completeTestSetup(recyReport, user, recycler, validator);

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
        uint256 tokenId1 = completeTestSetup(recyReport, address(0x1001), address(0x1002), address(0x1003));
        uint64 unlockTime1 = recyReport.unlockDate(tokenId1);
        vm.warp(unlockTime1 + 1);
        vm.prank(address(0x1001));
        recyReport.claimRecyReportReward(tokenId1);

        // Test 2: Create and claim by recycler
        uint256 tokenId2 = completeTestSetup(recyReport, address(0x2001), address(0x2002), address(0x2003));
        uint64 unlockTime2 = recyReport.unlockDate(tokenId2);
        vm.warp(unlockTime2 + 1);
        vm.prank(address(0x2002));
        recyReport.claimRecyReportReward(tokenId2);

        // Test 3: Create and claim by validator
        uint256 tokenId3 = completeTestSetup(recyReport, address(0x3001), address(0x3002), address(0x3003));
        uint64 unlockTime3 = recyReport.unlockDate(tokenId3);
        vm.warp(unlockTime3 + 1);
        vm.prank(address(0x3003));
        recyReport.claimRecyReportReward(tokenId3);

        // Test 4: Create and try to claim by unauthorized user (should fail)
        uint256 tokenId4 = completeTestSetup(recyReport, address(0x4001), address(0x4002), address(0x4003));
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

        _setStandardFundWallets(recyReport, generatorFund, recyclerFund, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");
        uint256 expectedAmount = EXPECTED_SHARE_25_OF_1500MG;

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
            testToken.balanceOf(recyclerFund), recInitial + expectedAmount, "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(testToken.balanceOf(protocol), protInitial + expectedAmount, "Protocol should receive reward directly");
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_claimRewardWithFundWalletsByValidator() public {
        // Setup fund wallets
        address generatorFund = address(0x3001);
        address recyclerFund = address(0x3002);
        address validatorFund = address(0x3003);

        _setStandardFundWallets(recyReport, generatorFund, recyclerFund, validatorFund);

        // Complete test setup
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // Get reward amount and calculate expected share
        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, EXPECTED_REWARD_1500MG, "reward math changed");
        uint256 expectedAmount = EXPECTED_SHARE_25_OF_1500MG;

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
            testToken.balanceOf(recyclerFund), recInitial + expectedAmount, "Recycler fund wallet should receive reward"
        );
        assertEq(
            testToken.balanceOf(validatorFund),
            valInitial + expectedAmount,
            "Validator fund wallet should receive reward"
        );
        assertEq(testToken.balanceOf(protocol), protInitial + expectedAmount, "Protocol should receive reward directly");
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    // ===== END ACCESS CONTROL TESTS =====

    // ===== END FUND WALLET TESTS =====

    // ===== TRUSTED FORWARDER TESTS =====

    function test_trustedForwarderDefaultsToZero() public view {
        assertEq(recyReport.trustedForwarder(), address(0), "Trusted forwarder should default to address(0)");
    }

    function test_isTrustedForwarderReturnsFalseByDefault() public view {
        assertFalse(recyReport.isTrustedForwarder(address(0x999)), "No address should be trusted forwarder by default");
    }

    function test_setTrustedForwarder() public {
        address forwarder = address(0xF01);

        vm.expectEmit(true, true, false, false);
        emit RecyReport.TrustedForwarderChanged(address(0), forwarder);

        recyReport.setTrustedForwarder(forwarder);

        assertEq(recyReport.trustedForwarder(), forwarder, "Trusted forwarder should be updated");
        assertTrue(recyReport.isTrustedForwarder(forwarder), "isTrustedForwarder should return true for set address");
    }

    function test_setTrustedForwarderOnlyAdmin() public {
        address forwarder = address(0xF01);

        vm.prank(user);
        vm.expectRevert();
        recyReport.setTrustedForwarder(forwarder);
    }

    function test_setTrustedForwarderToZeroDisables() public {
        address forwarder = address(0xF01);
        recyReport.setTrustedForwarder(forwarder);
        assertTrue(recyReport.isTrustedForwarder(forwarder));

        vm.expectEmit(true, true, false, false);
        emit RecyReport.TrustedForwarderChanged(forwarder, address(0));

        recyReport.setTrustedForwarder(address(0));

        assertEq(recyReport.trustedForwarder(), address(0), "Trusted forwarder should be disabled");
        assertFalse(recyReport.isTrustedForwarder(forwarder));
    }

    function test_setTrustedForwarderUpdate() public {
        address forwarder1 = address(0xF01);
        address forwarder2 = address(0xF02);

        recyReport.setTrustedForwarder(forwarder1);
        assertEq(recyReport.trustedForwarder(), forwarder1);

        vm.expectEmit(true, true, false, false);
        emit RecyReport.TrustedForwarderChanged(forwarder1, forwarder2);

        recyReport.setTrustedForwarder(forwarder2);

        assertEq(recyReport.trustedForwarder(), forwarder2);
        assertFalse(recyReport.isTrustedForwarder(forwarder1));
        assertTrue(recyReport.isTrustedForwarder(forwarder2));
    }

    function test_mintRecyReportViaForwarder() public {
        address forwarder = address(0xF01);
        address realUser = address(0xBEEF);

        recyReport.setTrustedForwarder(forwarder);

        // Simulate forwarder call: calldata = function selector + real sender appended (20 bytes)
        bytes memory callData = abi.encodeWithSelector(RecyReport.mintRecyReport.selector);
        bytes memory forwardedCallData = abi.encodePacked(callData, realUser);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Forwarded mintRecyReport should succeed");

        // The NFT should be owned by realUser, not the forwarder
        assertEq(recyReport.ownerOf(0), realUser, "NFT should be minted to the real user, not the forwarder");
    }

    function test_mintRecyReportResultViaForwarder() public {
        address forwarder = address(0xF01);
        address realRecycler = address(0xCAFE);
        address generator = address(0xDADA);

        recyReport.setTrustedForwarder(forwarder);
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, realRecycler);

        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        bytes memory callData = abi.encodeWithSelector(
            RecyReport.mintRecyReportResult.selector,
            generator,
            SafeCast.toUint64(block.timestamp),
            uint128(1000),
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            uint32(0)
        );
        bytes memory forwardedCallData = abi.encodePacked(callData, realRecycler);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Forwarded mintRecyReportResult should succeed");

        // NFT owned by generator, recycler recorded as realRecycler
        assertEq(recyReport.ownerOf(0), generator);
        (, address infoRecycler,,,) = recyReport.info(0);
        assertEq(infoRecycler, realRecycler, "Recycler should be the real sender, not the forwarder");
    }

    function test_validateRecyReportViaForwarder() public {
        address forwarder = address(0xF01);
        address realAuditor = address(0xABCD);

        recyReport.setTrustedForwarder(forwarder);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, realAuditor);

        // First, create a report to validate
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        vm.prank(RECYCLER);
        recyReport.mintRecyReportResult(
            user, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        // Validate via forwarder
        bytes memory callData = abi.encodeWithSelector(RecyReport.validateRecyReport.selector, uint256(0));
        bytes memory forwardedCallData = abi.encodePacked(callData, realAuditor);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Forwarded validateRecyReport should succeed");

        assertEq(recyReport.status(0), RecyConstants.RECYCLE_VALIDATED, "Report should be validated");
        (address infoValidator,,,,) = recyReport.info(0);
        assertEq(infoValidator, realAuditor, "Validator should be the real sender, not the forwarder");
    }

    function test_claimRecyReportRewardViaForwarder() public {
        address forwarder = address(0xF01);

        recyReport.setTrustedForwarder(forwarder);

        // Create and validate a report
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        vm.prank(RECYCLER);
        recyReport.mintRecyReportResult(
            user, SafeCast.toUint64(block.timestamp), 1000, materials, materialAmounts, recycleTypes, recycleShapes, 0
        );

        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(0);

        // Fast forward past unlock delay
        vm.warp(block.timestamp + 3601);

        // Claim via forwarder as the NFT owner (user)
        bytes memory callData = abi.encodeWithSelector(RecyReport.claimRecyReportReward.selector, uint256(0));
        bytes memory forwardedCallData = abi.encodePacked(callData, user);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Forwarded claimRecyReportReward should succeed");

        assertEq(recyReport.status(0), RecyConstants.RECYCLE_REWARDED, "Report should be rewarded");
    }

    function test_forwarderCannotSpoofWithoutBeingTrusted() public {
        address untrustedForwarder = address(0xBAD);
        address realUser = address(0xBEEF);

        // Do NOT set as trusted forwarder

        bytes memory callData = abi.encodeWithSelector(RecyReport.mintRecyReport.selector);
        bytes memory forwardedCallData = abi.encodePacked(callData, realUser);

        vm.prank(untrustedForwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Call should succeed but mint to forwarder address");

        // NFT should be minted to the untrustedForwarder (msg.sender), not realUser
        assertEq(
            recyReport.ownerOf(0),
            untrustedForwarder,
            "NFT should be minted to msg.sender when forwarder is not trusted"
        );
    }

    function test_forwarderRoleCheckUsesRealSender() public {
        address forwarder = address(0xF01);
        address unauthorizedUser = address(0xDEAD);

        recyReport.setTrustedForwarder(forwarder);
        // unauthorizedUser does NOT have RECYCLER_ROLE

        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        bytes memory callData = abi.encodeWithSelector(
            RecyReport.mintRecyReportResult.selector,
            user,
            SafeCast.toUint64(block.timestamp),
            uint128(1000),
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            uint32(0)
        );
        bytes memory forwardedCallData = abi.encodePacked(callData, unauthorizedUser);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertFalse(success, "Should revert because real sender lacks RECYCLER_ROLE");
    }

    function test_setRecyReportResultViaForwarder() public {
        address forwarder = address(0xF01);
        address realRecycler = address(0xCAFE);

        recyReport.setTrustedForwarder(forwarder);
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, realRecycler);

        // First mint an empty report
        vm.prank(user);
        recyReport.mintRecyReport();

        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        bytes memory callData = abi.encodeWithSelector(
            RecyReport.setRecyReportResult.selector,
            uint256(0),
            SafeCast.toUint64(block.timestamp),
            uint128(2000),
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            uint32(0)
        );
        bytes memory forwardedCallData = abi.encodePacked(callData, realRecycler);

        vm.prank(forwarder);
        (bool success,) = address(recyReport).call(forwardedCallData);
        assertTrue(success, "Forwarded setRecyReportResult should succeed");

        assertEq(recyReport.status(0), RecyConstants.RECYCLE_COMPLETED, "Report should be completed");
        (, address infoRecycler,,,) = recyReport.info(0);
        assertEq(infoRecycler, realRecycler, "Recycler should be the real sender");
    }

    function test_directCallStillWorksWithForwarderSet() public {
        address forwarder = address(0xF01);
        recyReport.setTrustedForwarder(forwarder);

        // Direct call (not through forwarder) should still work normally
        vm.prank(user);
        recyReport.mintRecyReport();

        assertEq(recyReport.ownerOf(0), user, "Direct call should still use msg.sender");
    }

    // ===== END TRUSTED FORWARDER TESTS =====

    // ===== INVALIDATE RECY REPORT TESTS =====

    function test_invalidateRecyReport() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);
        (, address recyclerBefore, uint64 recycleDateBefore,, uint128 wasteAmountBefore) = recyReport.info(tokenId);
        assertGt(recycleDateBefore, 0);
        assertGt(wasteAmountBefore, 0);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);

        assertReportStatus(recyReport, tokenId, RecyConstants.RECYCLE_INVALIDATED);

        (address infoValidator, address infoRecycler, uint64 recycleDate, uint64 auditDate, uint128 wasteAmount) =
            recyReport.info(tokenId);
        assertEq(infoValidator, validator);
        assertGt(auditDate, 0);
        assertEq(infoRecycler, recyclerBefore);
        assertEq(recycleDate, recycleDateBefore);
        assertEq(wasteAmount, wasteAmountBefore);

        // An invalidated report can never be claimed, so it must not record a reward. It used to,
        // and RecyReportData renders a reward for any status above COMPLETED, so the NFT
        // advertised a payout that would never arrive.
        (uint128 rewardAmount, uint64 rewardUnlockDate) = recyReport.reward(tokenId);
        assertEq(rewardAmount, 0);
        assertEq(rewardUnlockDate, 0);
        assertEq(recyReport.unlockDate(tokenId), 0);
    }

    function test_invalidateRecyReportEmitsEvents() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);

        vm.expectEmit(true, true, false, true);
        emit RecyReport.ReportInvalidated(tokenId, validator, SafeCast.toUint64(block.timestamp));

        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);
    }

    function test_invalidateRecyReportWithUnauthorizedUser() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);

        vm.prank(user); // Not an auditor
        vm.expectRevert();
        recyReport.invalidateRecyReport(tokenId);
    }

    function test_invalidateNonExistentReport() public {
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        vm.expectRevert();
        recyReport.invalidateRecyReport(999);
    }

    function test_invalidateUncompletedReport() public {
        vm.prank(user);
        recyReport.mintRecyReport();

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        vm.expectRevert();
        recyReport.invalidateRecyReport(0);
    }

    function test_invalidateAlreadyValidatedReport() public {
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        vm.prank(VALIDATOR);
        vm.expectRevert();
        recyReport.invalidateRecyReport(tokenId);
    }

    function test_invalidateAlreadyInvalidatedReport() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);

        vm.prank(validator);
        vm.expectRevert();
        recyReport.invalidateRecyReport(tokenId);
    }

    function test_invalidateRewardedReport() public {
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        fastForwardAndClaimReward(recyReport, tokenId, USER);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        vm.expectRevert();
        recyReport.invalidateRecyReport(tokenId);
    }

    function test_invalidatedReportCannotBeClaimed() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);

        vm.warp(block.timestamp + 3601);
        vm.prank(USER);
        vm.expectRevert();
        recyReport.claimRecyReportReward(tokenId);
    }

    function test_invalidatedReportCannotBeRevalidated() public {
        uint256 tokenId = mintAndCompleteReport(recyReport);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);

        vm.prank(validator);
        vm.expectRevert();
        recyReport.validateRecyReport(tokenId);
    }

    function test_invalidateDoesNotAffectRewardTotal() public {
        uint256 rewardTotalBefore = recyReport.rewardTotal();

        uint256 tokenId = mintAndCompleteReport(recyReport);

        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.invalidateRecyReport(tokenId);

        assertEq(recyReport.rewardTotal(), rewardTotalBefore);
    }

    // ===== END INVALIDATE RECY REPORT TESTS =====

    // ===== SECURITY REGRESSION TESTS =====

    /// @dev Mint a report to `owner_` and record a result against it as `recycler_`.
    function _mintCompletedReport(address owner_, address recycler_, uint128 wasteAmount)
        private
        returns (uint256 tokenId)
    {
        tokenId = recyReport.nftNextId();
        vm.prank(owner_);
        recyReport.mintRecyReport();

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = wasteAmount;

        vm.prank(recycler_);
        recyReport.setRecyReportResult(
            tokenId,
            SafeCast.toUint64(block.timestamp),
            wasteAmount,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );
    }

    function test_singleKeyWithBothRolesCannotDrainTreasury() public {
        // Reproduces the live principal that holds RECYCLER and AUDITOR with no admin role.
        // Three transactions used to be enough: mint to self with a huge waste amount, self
        // validate, claim. Generator + recycler + validator is 90% of the payout, all to one actor.
        address selfDealer = address(0x5f3CD35206c0526b837766d48D022522a9910b64);
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, selfDealer);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, selfDealer);
        assertFalse(recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), selfDealer), "no admin role needed");

        uint256 treasuryBefore = testToken.balanceOf(address(recyReport));

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = 1000;

        // Leg 1: the waste amount that made the drain worth doing is refused outright. At the live
        // FALLBACK divisor 9e17 mg mints a 9,000,000 cRECY claim from one report.
        vm.prank(selfDealer);
        vm.expectRevert(RecyErrors.WasteAmountExceedsCap.selector);
        recyReport.mintRecyReportResult(
            selfDealer,
            SafeCast.toUint64(block.timestamp),
            9e17,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Leg 2: sized down to something the pool could actually pay, the key still cannot sign
        // off on its own report.
        vm.prank(selfDealer);
        recyReport.mintRecyReportResult(
            selfDealer,
            SafeCast.toUint64(block.timestamp),
            1000,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );
        uint256 tokenId = 0;
        assertEq(recyReport.ownerOf(tokenId), selfDealer);

        vm.prank(selfDealer);
        vm.expectRevert(RecyErrors.ValidatorCannotBeRecycler.selector);
        recyReport.validateRecyReport(tokenId);

        // Nothing was promised, so RecyDistribution has nothing to mint against either.
        assertEq(recyReport.rewardTotal(), 0);
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_COMPLETED);

        vm.warp(block.timestamp + 3601);
        vm.prank(selfDealer);
        vm.expectRevert(RecyErrors.RecyReportNotValidated.selector);
        recyReport.claimRecyReportReward(tokenId);

        assertEq(testToken.balanceOf(selfDealer), 0, "attacker must receive nothing");
        assertEq(testToken.balanceOf(address(recyReport)), treasuryBefore, "treasury must not move");
    }

    function test_validateRequiresAnAuditorOtherThanTheRecycler() public {
        address dualRole = address(0xD0A1);
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, dualRole);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, dualRole);

        uint256 tokenId = _mintCompletedReport(USER, dualRole, 1500);

        vm.prank(dualRole);
        vm.expectRevert(RecyErrors.ValidatorCannotBeRecycler.selector);
        recyReport.validateRecyReport(tokenId);

        // A genuinely independent auditor is accepted
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);

        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_VALIDATED);
        (address infoValidator, address infoRecycler,,,) = recyReport.info(tokenId);
        assertEq(infoRecycler, dualRole);
        assertEq(infoValidator, VALIDATOR);
    }

    function test_validateRevertsWhenOutstandingObligationsExceedBalance() public {
        uint256 treasury = testToken.balanceOf(address(recyReport));
        assertEq(treasury, 10_000 * 10 ** 18);

        // 6e9 mg is 6_000e18 wei at the FIRST_EPOCH divisor: 60% of the pool.
        uint256 tokenA = _mintCompletedReport(USER, RECYCLER, 6e9);
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenA);
        assertEq(recyReport.rewardTotal(), 6000 * 10 ** 18);

        uint256 tokenB = _mintCompletedReport(USER, RECYCLER, 6e9);

        // Taken alone the second reward fits inside the balance, so the per-token check at claim
        // time would have waved it through. Together the two cannot both be paid.
        (uint128 rewardA,) = recyReport.reward(tokenA);
        assertLe(rewardA, treasury, "the per-token check alone would have passed");

        vm.prank(VALIDATOR);
        vm.expectRevert(RecyErrors.InsufficientRewardBalance.selector);
        recyReport.validateRecyReport(tokenB);

        assertEq(recyReport.rewardTotal(), 6000 * 10 ** 18, "a rejected validation must not be counted");
        assertEq(recyReport.status(tokenB), RecyConstants.RECYCLE_COMPLETED);
    }

    function test_validateSucceedsAfterAnEarlierRewardWasClaimed() public {
        // The solvency check measures outstanding obligations only. rewardTotal is never
        // decremented and includes already-paid rewards, while the balance drops as claims settle,
        // so a check that counted claimed amounts would reject a validation the pool can fund.
        uint256 tokenA = _mintCompletedReport(USER, RECYCLER, 6e9); // 6_000e18 wei
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenA);

        vm.warp(block.timestamp + 3601);
        vm.prank(USER);
        recyReport.claimRecyReportReward(tokenA);

        assertEq(recyReport.rewardTotal(), 6000 * 10 ** 18);
        assertEq(recyReport.rewardClaimed(), 6000 * 10 ** 18);
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), 0, "nothing is owed");
        assertEq(testToken.balanceOf(address(recyReport)), 4000 * 10 ** 18);

        // A report worth the entire remaining balance is therefore payable.
        uint256 tokenB = _mintCompletedReport(USER, RECYCLER, 4e9); // 4_000e18 wei
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenB);

        assertEq(recyReport.status(tokenB), RecyConstants.RECYCLE_VALIDATED);
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), 4000 * 10 ** 18);
    }

    function test_rewardedReportCannotBeResetAndRevalidated() public {
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);
        fastForwardAndClaimReward(recyReport, tokenId, USER);
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
        assertEq(recyReport.rewardTotal(), EXPECTED_REWARD_1500MG);
        assertEq(recyReport.rewardClaimed(), EXPECTED_REWARD_1500MG);

        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = 1500;

        // The double-count path was: reset a REWARDED report to COMPLETED, then validate it again,
        // adding its reward to rewardTotal a second time and enabling a second claim.
        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.RecyReportInvalidStatus.selector);
        recyReport.setRecyReportResult(
            tokenId,
            SafeCast.toUint64(block.timestamp),
            1500,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Validating a REWARDED report directly is refused too
        vm.prank(VALIDATOR);
        vm.expectRevert(RecyErrors.RecyReportNotCompleted.selector);
        recyReport.validateRecyReport(tokenId);

        assertEq(recyReport.rewardTotal(), EXPECTED_REWARD_1500MG, "rewardTotal must not be inflated");
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), 0);
    }

    function test_rewardAccountingInvariantAcrossLifecycle() public {
        assertEq(recyReport.rewardTotal(), 0);
        assertEq(recyReport.rewardClaimed(), 0);

        // Completing a report owes nothing; only validation creates an obligation.
        uint256 claimable = _mintCompletedReport(USER, RECYCLER, 1500);
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), 0);

        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(claimable);
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), EXPECTED_REWARD_1500MG);

        // An invalidated report adds nothing and advertises nothing.
        uint256 rejected = _mintCompletedReport(USER, RECYCLER, 1500);
        vm.prank(VALIDATOR);
        recyReport.invalidateRecyReport(rejected);

        assertEq(recyReport.status(rejected), RecyConstants.RECYCLE_INVALIDATED);
        (uint128 rejectedReward, uint64 rejectedUnlock) = recyReport.reward(rejected);
        assertEq(rejectedReward, 0, "an invalidated report must not advertise a payout");
        assertEq(rejectedUnlock, 0);
        assertEq(
            recyReport.rewardTotal() - recyReport.rewardClaimed(),
            EXPECTED_REWARD_1500MG,
            "invalidation must not change outstanding obligations"
        );

        vm.warp(block.timestamp + 3601);

        // The invalidated report is not claimable...
        vm.prank(USER);
        vm.expectRevert(RecyErrors.RecyReportNotValidated.selector);
        recyReport.claimRecyReportReward(rejected);

        // ...and settling the validated one closes the books exactly.
        vm.prank(USER);
        recyReport.claimRecyReportReward(claimable);
        assertEq(recyReport.rewardClaimed(), EXPECTED_REWARD_1500MG);
        assertEq(recyReport.rewardTotal() - recyReport.rewardClaimed(), 0);
    }

    function test_payoutSplitMatchesIndependentExpectedAmounts() public {
        uint256 tokenId = mintCompleteAndValidateReport(recyReport);

        // 1500 mg at the FIRST_EPOCH divisor is 1_500_000_000_000_000 wei. The four legs of the
        // 25/25/25/25 split are written out rather than recomputed from shareRecycler and friends,
        // so a mistake in either the reward math or the split arithmetic surfaces here instead of
        // being mirrored by the assertion.
        (uint128 rewardAmount,) = recyReport.reward(tokenId);
        assertEq(rewardAmount, 1_500_000_000_000_000);

        uint256 treasuryBefore = testToken.balanceOf(address(recyReport));

        fastForwardAndClaimReward(recyReport, tokenId, USER);

        assertEq(testToken.balanceOf(USER), 375_000_000_000_000, "generator leg");
        assertEq(testToken.balanceOf(RECYCLER), 375_000_000_000_000, "recycler leg");
        assertEq(testToken.balanceOf(VALIDATOR), 375_000_000_000_000, "validator leg");
        assertEq(testToken.balanceOf(protocol), 375_000_000_000_000, "protocol leg");
        assertEq(
            treasuryBefore - testToken.balanceOf(address(recyReport)),
            1_500_000_000_000_000,
            "the four legs must sum to the whole reward"
        );
        assertEq(recyReport.rewardClaimed(), 1_500_000_000_000_000);
    }

    function test_setUnlockDelay() public {
        assertEq(recyReport.unlockDelay(), 3600);

        vm.expectEmit(false, false, false, true);
        emit RecyReport.UnlockDelayChanged(3600, 86_400);
        recyReport.setUnlockDelay(86_400);
        assertEq(recyReport.unlockDelay(), 86_400);

        // Applies to reports validated after the change
        uint256 tokenId = _mintCompletedReport(USER, RECYCLER, 1500);
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);
        assertEq(recyReport.unlockDate(tokenId), SafeCast.toUint64(block.timestamp + 86_400));
    }

    function test_setUnlockDelayOnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        recyReport.setUnlockDelay(7200);
        assertEq(recyReport.unlockDelay(), 3600);
    }

    function test_setUnlockDelayRejectsOutOfBounds() public {
        // The delay is the protocol's only reaction window (EMERGENCY_ROLE sees a fraudulent
        // validation and pauses before the claim opens). Zero would remove it silently; a value
        // near type(uint64).max wraps the uint64 unlock-date sum at validation into the PAST,
        // which is the same thing. Bounds make neither reachable by admin typo.
        vm.expectRevert(RecyErrors.UnlockDelayOutOfBounds.selector);
        recyReport.setUnlockDelay(0);

        vm.expectRevert(RecyErrors.UnlockDelayOutOfBounds.selector);
        recyReport.setUnlockDelay(RecyConstants.MIN_UNLOCK_DELAY - 1);

        vm.expectRevert(RecyErrors.UnlockDelayOutOfBounds.selector);
        recyReport.setUnlockDelay(RecyConstants.MAX_UNLOCK_DELAY + 1);

        vm.expectRevert(RecyErrors.UnlockDelayOutOfBounds.selector);
        recyReport.setUnlockDelay(type(uint64).max); // pre-bounds, this meant instant claims

        // Both bounds are inclusive.
        recyReport.setUnlockDelay(RecyConstants.MIN_UNLOCK_DELAY);
        assertEq(recyReport.unlockDelay(), RecyConstants.MIN_UNLOCK_DELAY);
        recyReport.setUnlockDelay(RecyConstants.MAX_UNLOCK_DELAY);
        assertEq(recyReport.unlockDelay(), RecyConstants.MAX_UNLOCK_DELAY);
    }

    function test_setUnlockDelayDoesNotAffectAlreadyValidatedReports() public {
        // The docstring promises snapshot semantics: the unlock date is fixed at validation and
        // a later delay change must not move it, in either direction.
        uint256 tokenId = _mintCompletedReport(USER, RECYCLER, 1500);
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);
        uint64 snapshotted = recyReport.unlockDate(tokenId);
        assertEq(snapshotted, SafeCast.toUint64(block.timestamp + 3600));

        recyReport.setUnlockDelay(RecyConstants.MAX_UNLOCK_DELAY);
        assertEq(recyReport.unlockDate(tokenId), snapshotted, "raising the delay must not push it out");

        recyReport.setUnlockDelay(RecyConstants.MIN_UNLOCK_DELAY);
        assertEq(recyReport.unlockDate(tokenId), snapshotted, "lowering the delay must not pull it in");

        // And the snapshotted date still governs the claim.
        vm.warp(block.timestamp + 3601);
        vm.prank(USER);
        recyReport.claimRecyReportReward(tokenId);
        assertEq(recyReport.status(tokenId), RecyConstants.RECYCLE_REWARDED);
    }

    function test_setProtocolAddress() public {
        address newProtocol = address(0xC0FFEE);

        vm.expectEmit(true, true, false, false);
        emit RecyReport.ProtocolAddressChanged(protocol, newProtocol);
        recyReport.setProtocolAddress(newProtocol);
        assertEq(recyReport.protocolAddress(), newProtocol);
    }

    function test_setProtocolAddressRejectsZero() public {
        // A zero protocolAddress reverts the protocol leg of every claim, bricking all payouts
        vm.expectRevert(RecyErrors.AddressInvalid.selector);
        recyReport.setProtocolAddress(address(0));
        assertEq(recyReport.protocolAddress(), protocol);
    }

    function test_setProtocolAddressOnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        recyReport.setProtocolAddress(address(0xC0FFEE));
        assertEq(recyReport.protocolAddress(), protocol);
    }

    // ===== END SECURITY REGRESSION TESTS =====
}
/// forge-lint: disable-end(unused-return,calls-loop,reentrancy-events)
