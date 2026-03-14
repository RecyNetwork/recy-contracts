// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyReport.sol";
import "../config/ConfigManager.s.sol";

/**
 * @title RecyReportProxyDeploy
 * @notice Script to deploy new proxies for the RecyReport implementation using the RecyReportFactory
 * @dev Factory address is automatically loaded from the config file
 */
contract RecyReportProxyDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get the proxy parameter or use "default" if not provided
        string memory proxyName = vm.envOr("proxy", string("default"));

        // Get network and proxy configuration
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, proxyName);

        require(
            networkConfig.factory != address(0),
            "Factory address not found in config. Please deploy the factory first."
        );

        console.log("=== Using RecyReportFactory ===");
        console.log("Chain ID:", chainId);
        console.log("Proxy Config:", proxyName);
        console.log("Network:", networkConfig.name);
        console.log("Factory Address:", networkConfig.factory);

        vm.startBroadcast();

        RecyReportFactory factory = RecyReportFactory(networkConfig.factory);

        console.log("\n=== Factory Information ===");
        console.log("Implementation:", factory.implementation());
        console.log("Data Contract:", factory.dataContract());
        console.log(
            "Total Deployed Proxies:",
            factory.getDeployedProxiesCount()
        );

        // Deploy proxy for recycler if they don't have one
        console.log("\n=== Deploying RecyReportproxy Proxy ===");

        address proxy = factory.deployProxy(
            proxyName,
            "RECY",
            networkConfig.token,
            networkConfig.protocol,
            config.unlockDelay,
            config.shareRecycler,
            config.shareValidator,
            config.shareGenerator,
            config.shareProtocol
        );
        console.log("Success! Proxy deployed at:", proxy);

        // Test the deployed proxy
        RecyReport recyReport1 = RecyReport(proxy);
        console.log("Proxy label:", proxyName);
        console.log("Proxy reportName:", recyReport1.name());
        console.log("Proxy symbol:", recyReport1.symbol());
        console.log("Unlock delay:", recyReport1.unlockDelay(), "seconds");
        console.log("Recycler share:", recyReport1.shareRecycler(), "%");

        vm.stopBroadcast();

        // Display final statistics
        console.log("\n=== Final Factory Statistics ===");
        console.log(
            "Total deployed proxies:",
            factory.getDeployedProxiesCount()
        );

        // Get all deployed proxies
        address[] memory allProxies = factory.getAllDeployedProxies();
        if (allProxies.length > 0) {
            console.log("\nAll deployed proxies:");
            for (uint256 i = 0; i < allProxies.length; i++) {
                console.log("  [%d] Proxy: %s ", i + 1, allProxies[i]);
            }
        }

        console.log("\n=== Completed ===");
    }
}
