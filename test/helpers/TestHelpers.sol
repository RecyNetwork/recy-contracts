// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../../src/RecyReport.sol";
import "../../src/RecyReportData.sol";
import "../../src/RecyReportAttributes.sol";
import "../../src/RecyReportSvg.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyToken.sol";
import "../../src/lib/RecyConstants.sol";
import "../../src/lib/RecyTypes.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title TestHelpers
 * @notice Common helper functions for tests to avoid code duplication
 */
contract TestHelpers is Test {
    // Common test addresses
    address constant OWNER = address(0x1001);
    address constant USER = address(0x1002);
    address constant RECYCLER = address(0x1003);
    address constant VALIDATOR = address(0x1004);
    address constant PROTOCOL = address(0x1005);
    address constant MALICIOUS_USER = address(0x1006);

    function _deployMockEndpoint() internal returns (address) {
        MockLZEndpointForHelpers mock = new MockLZEndpointForHelpers();
        return address(mock);
    }

    /**
     * @notice Create a complete test setup with all contracts deployed
     */
    function createCompleteTestSetup()
        internal
        returns (
            RecyReport recyReport,
            RecyReportData recyData,
            RecyReportAttributes recyAttributes,
            RecyReportSvg recySvg,
            RecyToken testToken,
            RecyReportFactory factory
        )
    {
        // Deploy mock token
        testToken = new RecyToken(
            "Test Token",
            "TEST",
            1000000,
            _deployMockEndpoint(),
            OWNER
        );

        // Deploy dependencies
        recyAttributes = new RecyReportAttributes();
        recySvg = new RecyReportSvg();
        recyData = new RecyReportData(
            address(recyAttributes),
            address(recySvg)
        );

        // Deploy implementation
        RecyReport implementation = new RecyReport();

        // Deploy factory
        factory = new RecyReportFactory(
            address(implementation),
            address(recyData)
        );

        // Deploy proxy with proper initialization
        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "RecyReport Upgradeable",
            "RECYU",
            address(testToken),
            address(recyData),
            PROTOCOL,
            3600,
            25,
            25,
            25,
            25
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        recyReport = RecyReport(address(proxy));

        // Fund the contract with tokens for rewards
        vm.prank(OWNER);
        testToken.transfer(address(recyReport), 10000 * 10 ** 18);
    }

    /**
     * @notice Create a minimal RecyReport setup for basic testing
     */
    function createMinimalRecyReportSetup()
        internal
        returns (RecyReport recyReport, RecyToken testToken)
    {
        testToken = new RecyToken(
            "Test Token",
            "TEST",
            1000000,
            _deployMockEndpoint(),
            OWNER
        );

        RecyReportAttributes recyAttributes = new RecyReportAttributes();
        RecyReportSvg recySvg = new RecyReportSvg();
        RecyReportData recyData = new RecyReportData(
            address(recyAttributes),
            address(recySvg)
        );

        RecyReport implementation = new RecyReport();

        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            "RecyReport",
            "RECY",
            address(testToken),
            address(recyData),
            PROTOCOL,
            3600,
            25,
            25,
            25,
            25
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        recyReport = RecyReport(address(proxy));

        vm.prank(OWNER);
        testToken.transfer(address(recyReport), 10000 * 10 ** 18);
    }

    /**
     * @notice Create test materials array
     */
    function createTestMaterials()
        internal
        pure
        returns (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        )
    {
        materials = new uint32[](2);
        materialAmounts = new uint128[](2);
        recycleTypes = new uint32[](2);
        recycleShapes = new uint32[](2);

        materials[0] = 1; // Plastic
        materialAmounts[0] = 1000; // 1000 grams (no decimals)
        recycleTypes[0] = 1;
        recycleShapes[0] = 1;

        materials[1] = 2; // Glass
        materialAmounts[1] = 500; // 500 grams (no decimals)
        recycleTypes[1] = 2;
        recycleShapes[1] = 2;
    }

    /**
     * @notice Setup roles for a RecyReport contract
     */
    function setupRoles(RecyReport recyReport) internal {
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, RECYCLER);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, VALIDATOR);
        recyReport.grantRole(recyReport.DEFAULT_ADMIN_ROLE(), OWNER);
    }

    /**
     * @notice Mint and complete a RecyReport for testing
     */
    function mintAndCompleteReport(
        RecyReport recyReport
    ) internal returns (uint256 tokenId) {
        // Mint report
        vm.prank(USER);
        recyReport.mintRecyReport();
        tokenId = 0;

        // Complete report
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createTestMaterials();

        vm.prank(RECYCLER);
        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1500, // Total: 1000 + 500 grams
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            1 // disposalMethod
        );
    }

    /**
     * @notice Mint, complete, and validate a RecyReport
     */
    function mintCompleteAndValidateReport(
        RecyReport recyReport
    ) internal returns (uint256 tokenId) {
        tokenId = mintAndCompleteReport(recyReport);

        // Validate report
        vm.prank(VALIDATOR);
        recyReport.validateRecyReport(tokenId);
    }

    /**
     * @notice Create empty arrays for testing edge cases
     */
    function createEmptyArrays()
        internal
        pure
        returns (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        )
    {
        materials = new uint32[](0);
        materialAmounts = new uint128[](0);
        recycleTypes = new uint32[](0);
        recycleShapes = new uint32[](0);
    }

    /**
     * @notice Create mismatched length arrays for testing
     */
    function createMismatchedArrays()
        internal
        pure
        returns (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        )
    {
        materials = new uint32[](2);
        materialAmounts = new uint128[](3); // Different length
        recycleTypes = new uint32[](2);
        recycleShapes = new uint32[](2);

        materials[0] = 1;
        materials[1] = 2;
        materialAmounts[0] = 1000;
        materialAmounts[1] = 2000;
        materialAmounts[2] = 3000;
        recycleTypes[0] = 1;
        recycleTypes[1] = 2;
        recycleShapes[0] = 1;
        recycleShapes[1] = 2;
    }

    /**
     * @notice Create arrays with maximum values for boundary testing
     */
    function createMaxValueArrays()
        internal
        pure
        returns (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        )
    {
        materials = new uint32[](1);
        materialAmounts = new uint128[](1);
        recycleTypes = new uint32[](1);
        recycleShapes = new uint32[](1);

        materials[0] = type(uint32).max;
        materialAmounts[0] = type(uint128).max;
        recycleTypes[0] = type(uint32).max;
        recycleShapes[0] = type(uint32).max;
    }

    /**
     * @notice Expect a specific custom error
     */
    function expectCustomError(bytes4 selector) internal {
        vm.expectRevert(selector);
    }

    /**
     * @notice Check if address has a specific role
     */
    function assertHasRole(
        RecyReport recyReport,
        bytes32 role,
        address account,
        bool shouldHave
    ) internal view {
        if (shouldHave) {
            assertTrue(recyReport.hasRole(role, account));
        } else {
            assertFalse(recyReport.hasRole(role, account));
        }
    }

    /**
     * @notice Assert NFT ownership
     */
    function assertNftOwnership(
        RecyReport recyReport,
        uint256 tokenId,
        address expectedOwner
    ) internal view {
        assertEq(recyReport.ownerOf(tokenId), expectedOwner);
    }

    /**
     * @notice Assert report status
     */
    function assertReportStatus(
        RecyReport recyReport,
        uint256 tokenId,
        uint8 expectedStatus
    ) internal view {
        assertEq(recyReport.status(tokenId), expectedStatus);
    }

    /**
     * @notice Fast forward time and claim reward
     */
    function fastForwardAndClaimReward(
        RecyReport recyReport,
        uint256 tokenId,
        address claimer
    ) internal {
        vm.warp(block.timestamp + 3601); // Past unlock delay
        vm.prank(claimer);
        recyReport.claimRecyReportReward(tokenId);
    }

    /**
     * @notice Complete test setup: mint, set result, and validate with realistic amounts
     */
    function completeTestSetup(
        RecyReport recyReport,
        address user,
        address recycler,
        address validator
    ) internal returns (uint256 tokenId) {
        // Get the next token ID before minting
        tokenId = recyReport.nftNextId();

        // Mint report
        vm.prank(user);
        recyReport.mintRecyReport();

        // Setup with realistic amounts
        uint32[] memory materials = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000; // 1000 grams
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;

        // Grant role and set result
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        vm.prank(recycler);
        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1000, // Total amount matches materialAmounts
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Grant role and validate
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, validator);
        vm.prank(validator);
        recyReport.validateRecyReport(tokenId);
    }

    // ===== ADDITIONAL HELPER FUNCTIONS FOR DEDUPLICATION =====

    /**
     * @notice Create single material array (commonly used pattern)
     */
    function createSingleMaterialArray()
        internal
        pure
        returns (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        )
    {
        materials = new uint32[](1);
        materialAmounts = new uint128[](1);
        recycleTypes = new uint32[](1);
        recycleShapes = new uint32[](1);

        materials[0] = 0;
        materialAmounts[0] = 1000; // Realistic amount in grams
        recycleTypes[0] = 0;
        recycleShapes[0] = 0;
    }

    /**
     * @notice Setup a complete factory test environment
     */
    function setupFactoryTest()
        internal
        returns (
            RecyReportFactory factory,
            RecyToken testToken,
            RecyReport implementation,
            RecyReportData dataContract
        )
    {
        testToken = new RecyToken(
            "Test Token",
            "TEST",
            1000000,
            _deployMockEndpoint(),
            OWNER
        );

        RecyReportAttributes attributes = new RecyReportAttributes();
        RecyReportSvg svg = new RecyReportSvg();
        dataContract = new RecyReportData(address(attributes), address(svg));

        implementation = new RecyReport();

        factory = new RecyReportFactory(
            address(implementation),
            address(dataContract)
        );
    }

    /**
     * @notice Deploy proxy using factory with test configuration
     */
    function deployProxyWithFactory(
        RecyReportFactory factory,
        RecyToken testToken
    ) internal returns (address proxy) {
        // Generate a unique name using block timestamp and gasleft
        string memory uniqueName = string(
            abi.encodePacked(
                "RecyReport-",
                vm.toString(block.timestamp),
                "-",
                vm.toString(gasleft())
            )
        );
        proxy = factory.deployProxy(
            uniqueName,
            "RECY",
            address(testToken),
            PROTOCOL,
            3600, // unlockDelay
            25, // shareRecycler
            25, // shareValidator
            25, // shareGenerator
            25 // shareProtocol
        );
    }

    /**
     * @notice Deploy proxy using factory with test configuration and custom name
     */
    function deployProxyWithFactory(
        RecyReportFactory factory,
        string memory proxyName,
        RecyToken testToken
    ) internal returns (address proxy) {
        proxy = factory.deployProxy(
            proxyName,
            "RECY",
            address(testToken),
            PROTOCOL,
            3600, // unlockDelay
            25, // shareRecycler
            25, // shareValidator
            25, // shareGenerator
            25 // shareProtocol
        );
    }

    /**
     * @notice Grant standard roles to a RecyReport (owner already has admin)
     */
    function grantStandardRoles(
        RecyReport recyReport,
        address recycler,
        address auditor
    ) internal {
        recyReport.grantRole(RecyConstants.RECYCLER_ROLE, recycler);
        recyReport.grantRole(RecyConstants.AUDITOR_ROLE, auditor);
    }

    /**
     * @notice Complete workflow: mint -> set result -> validate -> claim reward
     */
    function completeReportWorkflow(
        RecyReport recyReport,
        address reporter,
        address recyclerRole,
        address auditorRole
    ) internal returns (uint256 tokenId) {
        // Setup roles
        grantStandardRoles(recyReport, recyclerRole, auditorRole);

        // Mint
        vm.prank(reporter);
        recyReport.mintRecyReport();
        tokenId = 0;

        // Complete
        (
            uint32[] memory materials,
            uint128[] memory materialAmounts,
            uint32[] memory recycleTypes,
            uint32[] memory recycleShapes
        ) = createSingleMaterialArray();

        vm.prank(recyclerRole);
        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp),
            1000000 * 10 ** 18,
            materials,
            materialAmounts,
            recycleTypes,
            recycleShapes,
            0
        );

        // Validate
        vm.prank(auditorRole);
        recyReport.validateRecyReport(tokenId);

        // Fast forward and claim
        vm.warp(block.timestamp + 3601);
        vm.prank(reporter);
        recyReport.claimRecyReportReward(tokenId);
    }

    /**
     * @notice Assert token balance change
     */
    function assertBalanceChange(
        RecyToken token,
        address account,
        uint256 expectedBalance
    ) internal view {
        assertEq(token.balanceOf(account), expectedBalance);
    }

    /**
     * @notice Assert total supply change
     */
    function assertTotalSupplyChange(
        RecyToken token,
        uint256 expectedSupply
    ) internal view {
        assertEq(token.totalSupply(), expectedSupply);
    }

    /**
     * @notice Perform mint operation with prank
     */
    function mintAsOwner(
        RecyToken token,
        address to,
        uint256 amount,
        address owner
    ) internal {
        vm.prank(owner);
        token.mint(to, amount);
    }

    /**
     * @notice Perform burn operation with prank
     */
    function burnAsOwner(
        RecyToken token,
        uint256 amount,
        address owner
    ) internal {
        vm.prank(owner);
        token.burn(amount);
    }

    /**
     * @notice Create RecyMaterials struct for RecyReportData tests
     */
    function createRecyMaterials(
        uint8 material,
        uint8 recycleType,
        uint8 recycleShape,
        uint8 disposalMethod,
        uint128 amountRecycled
    ) internal pure returns (RecyTypes.RecyMaterials memory) {
        return
            RecyTypes.RecyMaterials({
                material: material,
                recycleType: recycleType,
                recycleShape: recycleShape,
                disposalMethod: disposalMethod,
                amountRecycled: amountRecycled
            });
    }

    /**
     * @notice Create standard RecyMaterials array for data tests
     */
    function createStandardRecyMaterialsArray()
        internal
        pure
        returns (RecyTypes.RecyMaterials[] memory materials)
    {
        materials = new RecyTypes.RecyMaterials[](1);
        materials[0] = createRecyMaterials(1, 1, 1, 1, 100);
    }

    /**
     * @notice Create RecyReward struct
     */
    function createRecyReward(
        uint128 rewardAmount,
        uint64 rewardUnlockDate
    ) internal pure returns (RecyTypes.RecyReward memory) {
        return
            RecyTypes.RecyReward({
                rewardAmount: rewardAmount,
                rewardUnlockDate: rewardUnlockDate
            });
    }

    /**
     * @notice Create RecyInfo struct
     */
    function createRecyInfo(
        address validator,
        address recycler,
        uint64 recycleDate,
        uint64 auditDate,
        uint128 wasteAmount
    ) internal pure returns (RecyTypes.RecyInfo memory) {
        return
            RecyTypes.RecyInfo({
                validator: validator,
                recycler: recycler,
                recycleDate: recycleDate,
                auditDate: auditDate,
                wasteAmount: wasteAmount
            });
    }

    /**
     * @notice Add standard material to attributes contract
     */
    function addStandardMaterial(
        RecyReportAttributes attributes,
        string memory name,
        string memory svg
    ) internal {
        attributes.addMaterial(name, svg);
    }

    /**
     * @notice Expect specific revert message
     */
    function expectRevertWithMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }

    /**
     * @notice Assert factory proxy count
     */
    function assertProxyCount(
        RecyReportFactory factory,
        uint256 expectedCount
    ) internal view {
        assertEq(factory.getDeployedProxiesCount(), expectedCount);
    }

    /**
     * @notice Get paginated proxies and assert count
     */
    function assertPaginatedProxies(
        RecyReportFactory factory,
        uint256 offset,
        uint256 limit,
        uint256 expectedLength,
        uint256 expectedTotal
    ) internal view {
        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(offset, limit);
        assertEq(proxies.length, expectedLength);
        assertEq(total, expectedTotal);
    }

    /**
     * @notice Deploy RecyReport with custom share percentages
     */
    function deployRecyReportWithShares(
        string memory name,
        string memory symbol,
        address tokenAddress,
        uint8 recyclerShare,
        uint8 validatorShare,
        uint8 generatorShare,
        uint8 protocolShare
    ) internal returns (RecyReport) {
        // Deploy dependencies
        RecyReportAttributes customAttributes = new RecyReportAttributes();
        RecyReportSvg customSvg = new RecyReportSvg();
        RecyReportData customData = new RecyReportData(
            address(customAttributes),
            address(customSvg)
        );

        RecyReport implementation = new RecyReport();

        bytes memory initData = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            name,
            symbol,
            tokenAddress,
            address(customData),
            PROTOCOL,
            3600,
            recyclerShare,
            validatorShare,
            generatorShare,
            protocolShare
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        return RecyReport(address(proxy));
    }

    /**
     * @notice Assert that share percentages are set correctly
     */
    function assertSharePercentages(
        RecyReport recyReport,
        uint8 expectedRecycler,
        uint8 expectedValidator,
        uint8 expectedGenerator,
        uint8 expectedProtocol
    ) internal view {
        assertEq(recyReport.shareRecycler(), expectedRecycler);
        assertEq(recyReport.shareValidator(), expectedValidator);
        assertEq(recyReport.shareGenerator(), expectedGenerator);
        assertEq(recyReport.shareProtocol(), expectedProtocol);
    }
}

contract MockLZEndpointForHelpers {
    function setDelegate(address) external {}
}
