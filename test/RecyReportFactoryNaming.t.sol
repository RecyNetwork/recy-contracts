// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyReport} from "../src/RecyReport.sol";
import {RecyReportAttributes} from "../src/RecyReportAttributes.sol";
import {RecyReportData} from "../src/RecyReportData.sol";
import {RecyReportFactory} from "../src/RecyReportFactory.sol";
import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyToken} from "../src/RecyToken.sol";
import {TestHelpers} from "./helpers/TestHelpers.sol";
import "forge-std/Test.sol";

// Expected-event declarations follow vm.expectEmit's cheatcode call; they are test fixtures,
// not protocol events reachable after an untrusted external call.
// forge-lint: disable-start(reentrancy-events)

/**
 * @title RecyReportFactoryNamingTest
 * @notice Tests for the proxy naming functionality in RecyReportFactory
 */
contract RecyReportFactoryNamingTest is Test, TestHelpers {
    RecyReportFactory factory;
    RecyToken token;
    RecyReportData dataContract;
    RecyReport implementation;
    address owner = address(this);
    address recycler = address(0x1);
    address protocolAddress = address(0x2);

    function setUp() public {
        // Deploy dependencies
        RecyReportAttributes attributes = new RecyReportAttributes();
        RecyReportSvg svg = new RecyReportSvg();
        dataContract = new RecyReportData(address(attributes), address(svg));
        token =
            new RecyToken("Test Token", "TEST", 1_000_000, address(deployTestEndpoint(TEST_EID)), owner, block.chainid);

        // Deploy implementation
        implementation = new RecyReport();

        // Deploy factory
        factory = new RecyReportFactory(address(implementation), address(dataContract));
    }

    function test_deployProxyWithName() public {
        string memory proxyName = "my-custom-proxy";

        address proxy = factory.deployProxy(proxyName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        // Verify the proxy is mapped correctly
        assertEq(factory.getProxyByName(proxyName), proxy);
        assertEq(factory.getNameByProxy(proxy), proxyName);
        assertTrue(factory.proxyNameExists(proxyName));
    }

    // The first deployment only occupies the name; the second call is expected to revert.
    // forge-lint: disable-next-item(unused-return)
    function test_cannotDeployProxyWithSameName() public {
        string memory proxyName = "duplicate-proxy";

        // Deploy first proxy
        factory.deployProxy(proxyName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        // Try to deploy second proxy with same name - should revert
        vm.expectRevert(RecyReportFactory.ProxyNameAlreadyExists.selector);
        factory.deployProxy(proxyName, "RECY2", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    // A reverting call cannot produce a return value to inspect.
    // forge-lint: disable-next-item(unused-return)
    function test_cannotDeployProxyWithEmptyName() public {
        vm.expectRevert(RecyReportFactory.InvalidProxyName.selector);
        factory.deployProxy("", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    // A reverting call cannot produce a return value to inspect.
    // forge-lint: disable-next-item(unused-return)
    function test_getProxyByNameNotFound() public {
        vm.expectRevert(RecyReportFactory.ProxyNotFound.selector);
        factory.getProxyByName("non-existent-proxy");
    }

    // A reverting call cannot produce a return value to inspect.
    // forge-lint: disable-next-item(unused-return)
    function test_getNameByProxyNotFound() public {
        vm.expectRevert(RecyReportFactory.ProxyNotFound.selector);
        factory.getNameByProxy(address(0x999));
    }

    function test_proxyNameExistsReturnsFalse() public view {
        assertFalse(factory.proxyNameExists("non-existent-proxy"));
    }

    // This bounded loop deliberately populates the registry; only names, not returned proxy
    // addresses, are under test.
    // forge-lint: disable-next-item(calls-loop, unused-return)
    function test_getAllProxyNames() public {
        string[] memory expectedNames = new string[](3);
        expectedNames[0] = "proxy-1";
        expectedNames[1] = "proxy-2";
        expectedNames[2] = "proxy-3";

        // Deploy proxies with specific names
        for (uint256 i = 0; i < expectedNames.length; i++) {
            factory.deployProxy(expectedNames[i], "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        }

        string[] memory actualNames = factory.getAllProxyNames();
        assertEq(actualNames.length, expectedNames.length);

        for (uint256 i = 0; i < expectedNames.length; i++) {
            assertEq(actualNames[i], expectedNames[i]);
        }
    }

    // These deployments are setup whose observable result is the registry count.
    // forge-lint: disable-next-item(unused-return)
    function test_getProxyNamesCount() public {
        assertEq(factory.getProxyNamesCount(), 0);

        // Deploy some proxies
        factory.deployProxy("proxy-1", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(factory.getProxyNamesCount(), 1);

        factory.deployProxy("proxy-2", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(factory.getProxyNamesCount(), 2);
    }

    // Event delivery is the observable result; the unpredictable proxy address is wildcarded.
    // forge-lint: disable-next-item(unused-return)
    function test_proxyNameEventEmission() public {
        string memory proxyName = "event-test-proxy";

        vm.expectEmit(false, true, true, false);
        emit RecyReportFactory.ProxyDeployed(address(0), address(this), proxyName);

        factory.deployProxy(proxyName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_bidirectionalMapping() public {
        string memory proxyName = "bidirectional-test";

        address proxy = factory.deployProxy(proxyName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        // Test name -> address mapping
        assertEq(factory.getProxyByName(proxyName), proxy);

        // Test address -> name mapping
        assertEq(factory.getNameByProxy(proxy), proxyName);

        // Test existence check
        assertTrue(factory.proxyNameExists(proxyName));
    }
}

// forge-lint: disable-end(reentrancy-events)
