// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../src/RecyReportFactory.sol";
import "../src/RecyReport.sol";
import "../src/RecyReportData.sol";
import "../src/RecyReportAttributes.sol";
import "../src/RecyReportSvg.sol";
import "../src/RecyToken.sol";
import "../src/lib/RecyErrors.sol";
import "./helpers/TestHelpers.sol";

contract RecyReportFactoryTest is Test, TestHelpers {
    RecyReportFactory factory;
    RecyReport implementation;
    RecyReportData dataContract;
    RecyToken token;

    address owner = address(this);
    address recycler1 = address(0x1);
    address recycler2 = address(0x2);
    address protocolAddress = address(0x3);

    uint256 private proxyCounter = 0;

    // Helper function to check if string starts with prefix
    function startsWith(
        string memory str,
        string memory prefix
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (prefixBytes.length > strBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        return true;
    }

    function setUp() public {
        // Deploy dependencies
        RecyReportAttributes attributes = new RecyReportAttributes();
        RecyReportSvg svg = new RecyReportSvg();
        dataContract = new RecyReportData(address(attributes), address(svg));
        MockLZEndpointForHelpers mockEndpoint = new MockLZEndpointForHelpers();
        token = new RecyToken(
            "Test Token",
            "TEST",
            1000000,
            address(mockEndpoint),
            owner
        );

        // Deploy implementation
        implementation = new RecyReport();

        // Deploy factory
        factory = new RecyReportFactory(
            address(implementation),
            address(dataContract)
        );
    }

    // Helper function for deploying proxies with standard test parameters
    function deployTestProxy() internal returns (address) {
        proxyCounter++;
        string memory proxyName = string(
            abi.encodePacked("test-proxy-", vm.toString(proxyCounter))
        );
        return
            factory.deployProxy(
                proxyName,
                "RECY",
                address(token),
                protocolAddress,
                3600,
                25,
                25,
                25,
                25
            );
    }

    function test_deployProxy() public {
        // Check initial state
        assertProxyCount(factory, 0);

        // Deploy proxy using helper
        address proxy = deployProxyWithFactory(factory, token);

        // Verify deployment
        assertProxyCount(factory, 1);

        // Test the deployed proxy
        RecyReport recyReport = RecyReport(proxy);
        assertTrue(startsWith(recyReport.name(), "RecyReport-"));
        assertEq(recyReport.symbol(), "RECY");
        assertEq(recyReport.unlockDelay(), 3600);
        assertEq(recyReport.shareRecycler(), 25);

        // Initially no roles are granted during deployment
        assertHasRole(recyReport, recyReport.RECYCLER_ROLE(), recycler1, false);

        // But factory can grant roles
        factory.grantRecyclerRole(proxy, recycler1);
        assertTrue(factory.hasRecyclerRole(proxy, recycler1));
    }

    function test_deployProxyWithCustomConfig() public {
        address proxy = factory.deployProxy(
            "custom-config-proxy",
            "cCUSTOM",
            address(token),
            protocolAddress,
            3600,
            70,
            10,
            15,
            5
        );

        RecyReport recyReport = RecyReport(proxy);
        assertEq(recyReport.name(), "custom-config-proxy");
        assertEq(recyReport.symbol(), "cCUSTOM");
        assertEq(recyReport.unlockDelay(), 3600);
        assertEq(recyReport.shareRecycler(), 70);
    }

    function test_deployMultipleProxies() public {
        // Deploy multiple proxies using helper
        address proxy1 = deployProxyWithFactory(factory, token);
        address proxy2 = deployProxyWithFactory(factory, token);

        // Verify different addresses
        assertTrue(proxy1 != proxy2);

        // Check factory state using helper
        assertProxyCount(factory, 2);

        address[] memory proxies = factory.getAllDeployedProxies();
        assertEq(proxies.length, 2);
        assertEq(proxies[0], proxy1);
        assertEq(proxies[1], proxy2);
    }

    function test_getPaginatedProxies() public {
        // Deploy multiple proxies
        for (uint256 i = 0; i < 5; i++) {
            deployTestProxy();
        }

        // Test pagination
        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(0, 3);
        assertEq(total, 5);
        assertEq(proxies.length, 3);

        // Test second page
        (address[] memory proxies2, uint256 total2) = factory
            .getDeployedProxiesPaginated(3, 3);
        assertEq(total2, 5);
        assertEq(proxies2.length, 2);

        // Test out of bounds
        (address[] memory proxies3, uint256 total3) = factory
            .getDeployedProxiesPaginated(10, 3);
        assertEq(total3, 5);
        assertEq(proxies3.length, 0);
    }

    function test_events() public {
        // We can't predict the exact proxy address, but we can check that the event is emitted
        // with the correct deployer address and proxy name
        vm.expectEmit(false, true, true, false); // Don't check first indexed parameter (proxy address)
        emit RecyReportFactory.ProxyDeployed(
            address(0),
            address(this),
            "test-proxy-1"
        );

        deployTestProxy();
    }

    function test_immutableValues() public view {
        assertEq(factory.implementation(), address(implementation));
        assertEq(factory.dataContract(), address(dataContract));
    }

    function test_grantAndRevokeAuditorRole() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();
        address auditor = address(0x999);

        // Initially should not have role
        assertFalse(factory.hasAuditorRole(proxy, auditor));

        // Grant role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AuditorRoleGranted(
            proxy,
            auditor,
            address(this)
        );
        factory.grantAuditorRole(proxy, auditor);

        // Check role was granted
        assertTrue(factory.hasAuditorRole(proxy, auditor));

        // Revoke role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AuditorRoleRevoked(
            proxy,
            auditor,
            address(this)
        );
        factory.revokeAuditorRole(proxy, auditor);

        // Check role was revoked
        assertFalse(factory.hasAuditorRole(proxy, auditor));
    }

    function test_grantAndRevokeRecyclerRole() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();
        address newRecycler = address(0x888);

        // Initially should not have role
        assertFalse(factory.hasRecyclerRole(proxy, newRecycler));

        // Grant role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.RecyclerRoleGranted(
            proxy,
            newRecycler,
            address(this)
        );
        factory.grantRecyclerRole(proxy, newRecycler);

        // Check role was granted
        assertTrue(factory.hasRecyclerRole(proxy, newRecycler));

        // Revoke role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.RecyclerRoleRevoked(
            proxy,
            newRecycler,
            address(this)
        );
        factory.revokeRecyclerRole(proxy, newRecycler);

        // Check role was revoked
        assertFalse(factory.hasRecyclerRole(proxy, newRecycler));
    }

    function test_roleManagementOnlyOwner() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();
        address auditor = address(0x999);

        // Try to grant role from non-owner address
        vm.prank(recycler1);
        vm.expectRevert();
        factory.grantAuditorRole(proxy, auditor);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.grantRecyclerRole(proxy, auditor);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.grantAdminRole(proxy, auditor);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.revokeAuditorRole(proxy, auditor);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.revokeRecyclerRole(proxy, auditor);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.revokeAdminRole(proxy, auditor);
    }

    function test_roleManagementInvalidProxy() public {
        address fakeProxy = address(0x777);
        address auditor = address(0x999);

        // Try to manage roles on non-deployed proxy
        vm.expectRevert("Proxy not deployed by factory");
        factory.grantAuditorRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.grantRecyclerRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.grantAdminRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.revokeAuditorRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.revokeRecyclerRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.revokeAdminRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.hasAuditorRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.hasRecyclerRole(fakeProxy, auditor);

        vm.expectRevert("Proxy not deployed by factory");
        factory.hasAdminRole(fakeProxy, auditor);
    }

    function test_roleCheckFunctions() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();
        address auditor = address(0x999);
        address newRecycler = address(0x888);

        // Grant roles
        factory.grantAuditorRole(proxy, auditor);
        factory.grantRecyclerRole(proxy, newRecycler);

        // Check roles exist
        assertTrue(factory.hasAuditorRole(proxy, auditor));
        assertTrue(factory.hasRecyclerRole(proxy, newRecycler));

        // Check roles don't exist for wrong addresses
        assertFalse(factory.hasAuditorRole(proxy, newRecycler));
        assertFalse(factory.hasRecyclerRole(proxy, auditor));
    }

    function test_grantAndRevokeAdminRole() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();
        address admin = address(0x777);

        // Initially should not have role (except for factory itself which gets all roles during initialization)
        assertFalse(factory.hasAdminRole(proxy, admin));

        // Grant role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AdminRoleGranted(proxy, admin, address(this));
        factory.grantAdminRole(proxy, admin);

        // Check role was granted
        assertTrue(factory.hasAdminRole(proxy, admin));

        // Revoke role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AdminRoleRevoked(proxy, admin, address(this));
        factory.revokeAdminRole(proxy, admin);

        // Check role was revoked
        assertFalse(factory.hasAdminRole(proxy, admin));
    }

    function test_grantAndRevokeEmergencyRole() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();

        address emergency = address(0x9);

        // Check initial state
        assertFalse(factory.hasEmergencyRole(proxy, emergency));

        // Grant role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.EmergencyRoleGranted(
            proxy,
            emergency,
            address(this)
        );
        factory.grantEmergencyRole(proxy, emergency);

        // Check role was granted
        assertTrue(factory.hasEmergencyRole(proxy, emergency));

        // Revoke role
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.EmergencyRoleRevoked(
            proxy,
            emergency,
            address(this)
        );
        factory.revokeEmergencyRole(proxy, emergency);

        // Check role was revoked
        assertFalse(factory.hasEmergencyRole(proxy, emergency));
    }

    // ===== CONSTRUCTOR EDGE CASES =====

    function test_constructorWithZeroImplementation() public {
        vm.expectRevert();
        new RecyReportFactory(address(0), address(dataContract));
    }

    function test_constructorWithZeroDataContract() public {
        vm.expectRevert();
        new RecyReportFactory(address(implementation), address(0));
    }

    // ===== DEPLOYMENT EDGE CASES =====

    function test_deployProxyWithZeroTokenAddress() public {
        vm.expectRevert();
        factory.deployProxy(
            "zero-token-proxy",
            "RECY",
            address(0), // Invalid token address
            protocolAddress,
            3600,
            25,
            25,
            25,
            25
        );
    }

    function test_deployProxyWithZeroProtocolAddress() public {
        // This should succeed - protocol address can be zero
        address proxy = factory.deployProxy(
            "zero-protocol-proxy",
            "RECY",
            address(token),
            address(0), // Zero protocol address
            3600,
            25,
            25,
            25,
            25
        );

        RecyReport report = RecyReport(proxy);
        assertEq(report.protocolAddress(), address(0));
    }

    function test_deployProxyWithMaxValues() public {
        address proxy = factory.deployProxy(
            "max-values-proxy",
            "RECY",
            address(token),
            protocolAddress,
            type(uint64).max,
            100,
            0,
            0,
            0
        );

        RecyReport report = RecyReport(proxy);
        assertEq(report.unlockDelay(), type(uint64).max);
        assertEq(report.shareRecycler(), 100);
    }

    function test_deployProxyWithZeroShares() public {
        // This should now revert due to invalid share distribution (0+0+0+0 != 100)
        vm.expectRevert(
            abi.encodeWithSelector(
                RecyErrors.RecyReportInvalidShareDistribution.selector
            )
        );
        factory.deployProxy(
            "zero-shares-proxy",
            "RECY",
            address(token),
            protocolAddress,
            3600,
            0,
            0,
            0,
            0
        );
    }

    function test_deployMultipleProxiesInSingleTransaction() public {
        address[] memory proxies = new address[](5);

        for (uint256 i = 0; i < 5; i++) {
            proxies[i] = deployTestProxy();
        }

        // Verify all proxies are different
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(proxies[i] != proxies[j]);
            }
        }

        assertEq(factory.getDeployedProxiesCount(), 5);
    }

    // ===== PAGINATION EDGE CASES =====

    function test_getPaginatedProxiesWithZeroOffset() public {
        for (uint256 i = 0; i < 3; i++) {
            deployTestProxy();
        }

        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(0, 2);

        assertEq(total, 3);
        assertEq(proxies.length, 2);
    }

    function test_getPaginatedProxiesWithOffsetEqualToTotal() public {
        for (uint256 i = 0; i < 3; i++) {
            deployTestProxy();
        }

        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(3, 5);

        assertEq(total, 3);
        assertEq(proxies.length, 0);
    }

    function test_getPaginatedProxiesWithZeroLimit() public {
        deployTestProxy();

        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(0, 0);

        assertEq(total, 1);
        assertEq(proxies.length, 0);
    }

    function test_getPaginatedProxiesFromEmptyList() public view {
        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(0, 10);

        assertEq(total, 0);
        assertEq(proxies.length, 0);
    }

    // ===== ROLE MANAGEMENT EDGE CASES =====

    function test_grantAuditorRoleToZeroAddress() public {
        address proxy = deployTestProxy();

        vm.expectRevert();
        factory.grantAuditorRole(proxy, address(0));
    }

    function test_grantRecyclerRoleToZeroAddress() public {
        address proxy = deployTestProxy();

        vm.expectRevert();
        factory.grantRecyclerRole(proxy, address(0));
    }

    function test_grantAdminRoleToZeroAddress() public {
        address proxy = deployTestProxy();

        vm.expectRevert();
        factory.grantAdminRole(proxy, address(0));
    }

    function test_revokeRoleFromZeroAddress() public {
        address proxy = deployTestProxy();

        // Should revert for zero address
        vm.expectRevert();
        factory.revokeAuditorRole(proxy, address(0));

        vm.expectRevert();
        factory.revokeRecyclerRole(proxy, address(0));

        vm.expectRevert();
        factory.revokeAdminRole(proxy, address(0));
    }

    function test_roleManagementWithInvalidProxy() public {
        address fakeProxy = address(0x999);

        vm.expectRevert();
        factory.grantAuditorRole(fakeProxy, recycler1);

        vm.expectRevert();
        factory.grantRecyclerRole(fakeProxy, recycler1);
    }

    function test_hasRoleWithNonExistentProxy() public {
        address fakeProxy = address(0x999);

        // Should revert for non-existent proxy
        vm.expectRevert("Proxy not deployed by factory");
        factory.hasAuditorRole(fakeProxy, recycler1);

        vm.expectRevert("Proxy not deployed by factory");
        factory.hasRecyclerRole(fakeProxy, recycler1);
    }

    // ===== GAS OPTIMIZATION TESTS =====

    function test_deployProxyGasConsumption() public {
        uint256 gasBefore = gasleft();
        deployTestProxy();
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (adjust based on actual measurements)
        assertTrue(gasUsed < 5_000_000); // 5M gas limit
        assertTrue(gasUsed > 100_000); // Should use some gas
    }

    // ===== MISSING TESTS FOR 100% COVERAGE =====

    function test_upgradeProxy() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();

        // Deploy a new implementation
        RecyReport newImplementation = new RecyReport();

        // Upgrade the proxy
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.ProxyUpgraded(
            proxy,
            address(newImplementation),
            address(this)
        );
        factory.upgradeProxy(proxy, address(newImplementation));

        // Verify the upgrade worked by checking the implementation
        RecyReport recyReport = RecyReport(proxy);
        // The proxy should still work with the new implementation
        assertTrue(startsWith(recyReport.name(), "test-proxy-"));
    }

    function test_upgradeProxyWithInvalidProxy() public {
        address fakeProxy = address(0x777);
        RecyReport newImplementation = new RecyReport();

        vm.expectRevert("Proxy not deployed by factory");
        factory.upgradeProxy(fakeProxy, address(newImplementation));
    }

    function test_upgradeProxyWithZeroImplementation() public {
        address proxy = deployTestProxy();

        vm.expectRevert("Invalid implementation address");
        factory.upgradeProxy(proxy, address(0));
    }

    function test_upgradeProxyOnlyOwner() public {
        address proxy = deployTestProxy();
        RecyReport newImplementation = new RecyReport();

        vm.prank(recycler1);
        vm.expectRevert();
        factory.upgradeProxy(proxy, address(newImplementation));
    }

    function test_grantEmergencyRoleToZeroAddress() public {
        address proxy = deployTestProxy();

        vm.expectRevert();
        factory.grantEmergencyRole(proxy, address(0));
    }

    function test_revokeEmergencyRoleFromZeroAddress() public {
        address proxy = deployTestProxy();

        vm.expectRevert();
        factory.revokeEmergencyRole(proxy, address(0));
    }

    function test_grantRoleWithZeroProxyAddress() public {
        address user = address(0x999);

        // Test all grant functions with zero proxy address
        vm.expectRevert("Invalid proxy address");
        factory.grantAuditorRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.grantRecyclerRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.grantAdminRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.grantEmergencyRole(address(0), user);
    }

    function test_revokeRoleWithZeroProxyAddress() public {
        address user = address(0x999);

        // Test all revoke functions with zero proxy address
        vm.expectRevert("Invalid proxy address");
        factory.revokeAuditorRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.revokeRecyclerRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.revokeAdminRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.revokeEmergencyRole(address(0), user);
    }

    function test_hasRoleWithZeroProxyAddress() public {
        address user = address(0x999);

        // Test all has role functions with zero proxy address
        vm.expectRevert("Invalid proxy address");
        factory.hasAuditorRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.hasRecyclerRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.hasAdminRole(address(0), user);

        vm.expectRevert("Invalid proxy address");
        factory.hasEmergencyRole(address(0), user);
    }

    function test_roleManagementWithNonDeployedProxy() public {
        address fakeProxy = address(0x888);
        address user = address(0x999);

        // Test emergency role management with non-deployed proxy
        vm.expectRevert("Proxy not deployed by factory");
        factory.grantEmergencyRole(fakeProxy, user);

        vm.expectRevert("Proxy not deployed by factory");
        factory.revokeEmergencyRole(fakeProxy, user);

        vm.expectRevert("Proxy not deployed by factory");
        factory.hasEmergencyRole(fakeProxy, user);

        // Test upgrade with non-deployed proxy (already covered above but for completeness)
        RecyReport newImplementation = new RecyReport();
        vm.expectRevert("Proxy not deployed by factory");
        factory.upgradeProxy(fakeProxy, address(newImplementation));
    }

    function test_allRoleEventEmissions() public {
        address proxy = deployTestProxy();
        address user = address(0x999);

        // Test all role grant events
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AuditorRoleGranted(proxy, user, address(this));
        factory.grantAuditorRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.RecyclerRoleGranted(proxy, user, address(this));
        factory.grantRecyclerRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AdminRoleGranted(proxy, user, address(this));
        factory.grantAdminRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.EmergencyRoleGranted(proxy, user, address(this));
        factory.grantEmergencyRole(proxy, user);

        // Test all role revoke events
        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AuditorRoleRevoked(proxy, user, address(this));
        factory.revokeAuditorRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.RecyclerRoleRevoked(proxy, user, address(this));
        factory.revokeRecyclerRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.AdminRoleRevoked(proxy, user, address(this));
        factory.revokeAdminRole(proxy, user);

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactory.EmergencyRoleRevoked(proxy, user, address(this));
        factory.revokeEmergencyRole(proxy, user);
    }

    function test_edgeCasePaginationLimitGreaterThanTotal() public {
        // Deploy 3 proxies
        for (uint256 i = 0; i < 3; i++) {
            deployTestProxy();
        }

        // Request more than available with offset + limit > total
        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(1, 10);

        assertEq(total, 3);
        assertEq(proxies.length, 2); // Should return only available proxies from offset 1
    }

    function test_extremePaginationValues() public {
        deployTestProxy();

        // Test with very large values
        (address[] memory proxies, uint256 total) = factory
            .getDeployedProxiesPaginated(type(uint256).max, 1);

        assertEq(total, 1);
        assertEq(proxies.length, 0); // Offset too large

        // Test with large limit but valid offset
        (address[] memory proxies2, uint256 total2) = factory
            .getDeployedProxiesPaginated(0, type(uint256).max);

        assertEq(total2, 1);
        assertEq(proxies2.length, 1); // Should return all available
    }

    // ===== END MISSING TESTS =====

    function test_upgradeProxyWithCallData() public {
        // Deploy a proxy first
        address proxy = deployTestProxy();

        // Deploy a new implementation
        RecyReport newImplementation = new RecyReport();

        // Test that upgrade works (already covered but ensuring complete execution)
        factory.upgradeProxy(proxy, address(newImplementation));

        // Verify the proxy still works after upgrade
        RecyReport recyReport = RecyReport(proxy);
        assertTrue(startsWith(recyReport.name(), "test-proxy-"));

        // Test that the factory can still manage roles after upgrade
        address user = address(0x999);
        factory.grantAuditorRole(proxy, user);
        assertTrue(factory.hasAuditorRole(proxy, user));
    }

    function test_upgradeMultipleProxies() public {
        // Deploy multiple proxies
        address proxy1 = deployTestProxy();
        address proxy2 = deployTestProxy();

        // Deploy new implementation
        RecyReport newImplementation = new RecyReport();

        // Upgrade both proxies
        factory.upgradeProxy(proxy1, address(newImplementation));
        factory.upgradeProxy(proxy2, address(newImplementation));

        // Verify both proxies work
        RecyReport recyReport1 = RecyReport(proxy1);
        RecyReport recyReport2 = RecyReport(proxy2);

        assertTrue(startsWith(recyReport1.name(), "test-proxy-"));
        assertTrue(startsWith(recyReport2.name(), "test-proxy-"));
    }

    function test_isDeployedProxyEdgeCases() public {
        // Deploy some proxies
        address proxy1 = deployTestProxy();
        address proxy2 = deployTestProxy();
        address proxy3 = deployTestProxy();

        // Test finding proxy in different positions (first, middle, last)
        assertFalse(factory.hasAuditorRole(proxy1, address(0x999))); // First proxy
        assertFalse(factory.hasAuditorRole(proxy2, address(0x999))); // Middle proxy
        assertFalse(factory.hasAuditorRole(proxy3, address(0x999))); // Last proxy

        // Verify they are all tracked
        address[] memory allProxies = factory.getAllDeployedProxies();
        assertEq(allProxies.length, 3);
        assertEq(allProxies[0], proxy1);
        assertEq(allProxies[1], proxy2);
        assertEq(allProxies[2], proxy3);
    }

    function test_deployProxyAndVerifyInitialization() public {
        address proxy = deployTestProxy();

        RecyReport recyReport = RecyReport(proxy);

        // Verify initialization was successful - this should hit all initialization code paths
        assertTrue(startsWith(recyReport.name(), "test-proxy-"));
        assertEq(recyReport.symbol(), "RECY");
        assertEq(recyReport.unlockDelay(), 3600);
        assertEq(recyReport.shareRecycler(), 25);
        assertEq(recyReport.shareValidator(), 25);
        assertEq(recyReport.shareGenerator(), 25);
        assertEq(recyReport.shareProtocol(), 25);

        // Verify the proxy is in deployed list
        assertTrue(factory.getDeployedProxiesCount() == 1);
    }

    // ===== FUND WALLET MANAGEMENT TESTS =====

    function test_setRecyclerFund() public {
        address proxy = deployTestProxy();
        address recycler = address(0x1001);
        address fundWallet = address(0x2001);

        // Set recycler fund wallet
        factory.setRecyclerFund(proxy, recycler, fundWallet);

        // Verify fund wallet was set
        RecyReport recyReport = RecyReport(proxy);
        assertEq(recyReport.funds(recycler), fundWallet);
    }

    function test_setAuditorFund() public {
        address proxy = deployTestProxy();
        address auditor = address(0x1002);
        address fundWallet = address(0x2002);

        // Set auditor fund wallet
        factory.setAuditorFund(proxy, auditor, fundWallet);

        // Verify fund wallet was set
        RecyReport recyReport = RecyReport(proxy);
        assertEq(recyReport.funds(auditor), fundWallet);
    }

    function test_setFundWalletOnlyOwner() public {
        address proxy = deployTestProxy();
        address user = address(0x999);
        address fundWallet = address(0x888);

        // Non-owner cannot set fund wallets
        vm.prank(recycler1);
        vm.expectRevert();
        factory.setRecyclerFund(proxy, user, fundWallet);

        vm.prank(recycler1);
        vm.expectRevert();
        factory.setAuditorFund(proxy, user, fundWallet);
    }

    function test_setFundWalletInvalidProxy() public {
        address fakeProxy = address(0x777);
        address user = address(0x999);
        address fundWallet = address(0x888);

        // Should revert for non-deployed proxy
        vm.expectRevert("Proxy not deployed by factory");
        factory.setRecyclerFund(fakeProxy, user, fundWallet);

        vm.expectRevert("Proxy not deployed by factory");
        factory.setAuditorFund(fakeProxy, user, fundWallet);
    }

    function test_setFundWalletZeroProxyAddress() public {
        address user = address(0x999);
        address fundWallet = address(0x888);

        // Should revert for zero proxy address
        vm.expectRevert("Invalid proxy address");
        factory.setRecyclerFund(address(0), user, fundWallet);

        vm.expectRevert("Invalid proxy address");
        factory.setAuditorFund(address(0), user, fundWallet);
    }

    function test_setFundWalletZeroUserAddress() public {
        address proxy = deployTestProxy();
        address fundWallet = address(0x888);

        // Should revert for zero user address
        vm.expectRevert("Invalid recycler address");
        factory.setRecyclerFund(proxy, address(0), fundWallet);

        vm.expectRevert("Invalid auditor address");
        factory.setAuditorFund(proxy, address(0), fundWallet);
    }

    function test_setFundWalletIntegrationWithRoles() public {
        address proxy = deployTestProxy();
        address recycler = address(0x1001);
        address auditor = address(0x1002);
        address recyclerFund = address(0x2001);
        address auditorFund = address(0x2002);

        // Grant roles first
        factory.grantRecyclerRole(proxy, recycler);
        factory.grantAuditorRole(proxy, auditor);

        // Set fund wallets
        factory.setRecyclerFund(proxy, recycler, recyclerFund);
        factory.setAuditorFund(proxy, auditor, auditorFund);

        // Verify both roles and fund wallets are set
        RecyReport recyReport = RecyReport(proxy);
        assertTrue(recyReport.hasRole(recyReport.RECYCLER_ROLE(), recycler));
        assertTrue(recyReport.hasRole(recyReport.AUDITOR_ROLE(), auditor));
        assertEq(recyReport.funds(recycler), recyclerFund);
        assertEq(recyReport.funds(auditor), auditorFund);
    }

    function test_updateFundWallet() public {
        address proxy = deployTestProxy();
        address user = address(0x1001);
        address fundWallet1 = address(0x2001);
        address fundWallet2 = address(0x2002);

        // Set initial fund wallet
        factory.setRecyclerFund(proxy, user, fundWallet1);

        RecyReport recyReport = RecyReport(proxy);
        assertEq(recyReport.funds(user), fundWallet1);

        // Update fund wallet
        factory.setRecyclerFund(proxy, user, fundWallet2);
        assertEq(recyReport.funds(user), fundWallet2);

        // Clear fund wallet (set to zero)
        factory.setRecyclerFund(proxy, user, address(0));
        assertEq(recyReport.funds(user), address(0));
    }

    // ===== END FUND WALLET MANAGEMENT TESTS =====
}
