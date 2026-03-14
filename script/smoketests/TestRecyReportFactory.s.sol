// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyReport.sol";
import "./../config/ConfigManager.s.sol";

contract TestRecyReportFactoryScript is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get network and proxy configuration
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, "default");

        console.log("=== Testing RecyReportFactory ===");
        console.log("Chain ID:", chainId);

        // Get factory address from config
        address factoryAddress = networkConfig.factory;
        require(factoryAddress != address(0), "Factory address not found in config");
        console.log("Factory address:", factoryAddress);

        // Example recycler addresses
        address recycler1 = 0xA1B2c3d4e5f6789012345678901234567890ABcD;
        address recycler2 = 0xB2C3D4e5F6789012345678901234567890ABCdef;
        address recycler3 = 0xc3d4E5f6789012345678901234567890ABCdef12;

        vm.startBroadcast();

        RecyReportFactory factory = RecyReportFactory(factoryAddress);

        console.log("\n=== Deploying Proxies ===");

        // Deploy first proxy
        address proxy1 = factory.deployProxy(
            "test-proxy-1",
            "RECY",
            networkConfig.token,
            networkConfig.protocol,
            config.unlockDelay,
            config.shareRecycler,
            config.shareValidator,
            config.shareGenerator,
            config.shareProtocol
        );
        console.log("Deployed proxy1:", proxy1);

        // Test the deployed proxy
        RecyReport recyReport1 = RecyReport(proxy1);
        console.log("Proxy name:", recyReport1.name());
        console.log("Proxy symbol:", recyReport1.symbol());

        // Grant recycler role to recycler1
        factory.grantRecyclerRole(proxy1, recycler1);
        console.log("Granted RECYCLER_ROLE to recycler1:", factory.hasRecyclerRole(proxy1, recycler1));

        // Deploy second proxy
        address proxy2 = factory.deployProxy(
            "test-proxy-2",
            "RECY2",
            networkConfig.token,
            networkConfig.protocol,
            config.unlockDelay,
            config.shareRecycler,
            config.shareValidator,
            config.shareGenerator,
            config.shareProtocol
        );
        console.log("Deployed proxy2:", proxy2);

        // Grant recycler role to recycler2
        factory.grantRecyclerRole(proxy2, recycler2);

        // Deploy proxy with custom config
        address proxy3 = factory.deployProxy(
            "test-proxy-3",
            "cCRECY",
            networkConfig.token,
            networkConfig.protocol,
            3600, // 1 hour unlock delay
            70, // Higher recycler share
            10, // shareValidator
            15, // shareGenerator
            5 // shareProtocol
        );
        console.log("Deployed custom proxy:", proxy3);

        // Test the custom proxy
        RecyReport recyReport3 = RecyReport(proxy3);
        console.log("Custom proxy name:", recyReport3.name());
        console.log("Custom proxy symbol:", recyReport3.symbol());
        console.log("Custom unlock delay:", recyReport3.unlockDelay());
        console.log("Custom recycler share:", recyReport3.shareRecycler());

        // Grant recycler role to recycler3
        factory.grantRecyclerRole(proxy3, recycler3);

        vm.stopBroadcast();

        // Display factory statistics
        console.log("\n=== Factory Statistics ===");
        console.log("Total deployed proxies:", factory.getDeployedProxiesCount());

        // Get all deployed proxies
        address[] memory allProxies = factory.getAllDeployedProxies();
        console.log("All deployed proxies:");
        for (uint256 i = 0; i < allProxies.length; i++) {
            console.log("  Proxy", i, ":", allProxies[i]);
        }

        console.log("\n=== Test Complete ===");
        console.log("Factory successfully deployed", allProxies.length, "proxies with role management!");
    }
}
