// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyReport.sol";
import "../../src/RecyReportData.sol";
import "../config/ConfigManager.s.sol";

contract RecyReportFactoryDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get network configuration
        NetworkConfig memory config = getNetworkConfig(chainId);

        console.log("=== Deploying RecyReportFactory ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", config.name);

        // Check if required contracts are deployed
        require(config.reportData != address(0), "RecyReportData not deployed");
        require(config.token != address(0), "Token not deployed");

        vm.startBroadcast();

        // Deploy a new RecyReport implementation if not exists
        address implementation;
        if (config.reportImplementation != address(0)) {
            console.log(
                "Using existing RecyReport implementation at:",
                config.reportImplementation
            );
            implementation = config.reportImplementation;
        } else {
            console.log("Deploying new RecyReport implementation...");
            RecyReport newImplementation = new RecyReport();
            implementation = address(newImplementation);
            console.log(
                "RecyReport implementation deployed to:",
                implementation
            );
        }

        // Deploy the factory
        RecyReportFactory factory = new RecyReportFactory(
            implementation,
            config.reportData
        );

        vm.stopBroadcast();

        // Log deployment results
        console.log("=== Deployment Results ===");
        console.log("RecyReportFactory deployed to:", address(factory));
        console.log("Implementation contract:", implementation);
        console.log("Data contract:", config.reportData);
        console.log("Token contract:", config.token);

        // Get default proxy configuration for display
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, "default");

        console.log("\n=== Factory Configuration ===");
        console.log("Default name: RecyReport");
        console.log("Default symbol: cRECYr");
        console.log("Default unlock delay:", proxyConfig.unlockDelay);
        console.log("Default recycler share:", proxyConfig.shareRecycler);
        console.log("Default validator share:", proxyConfig.shareValidator);
        console.log("Default generator share:", proxyConfig.shareGenerator);
        console.log("Default protocol share:", proxyConfig.shareProtocol);

        console.log("\n=== Usage Instructions ===");
        console.log("To deploy a proxy, call:");
        console.log(
            "factory.deployProxy(name, symbol, tokenAddress, protocolAddress, unlockDelay, shareRecycler, shareValidator, shareGenerator, shareProtocol)"
        );
        console.log("\nTo check if a recycler has a proxy:");
        console.log("factory.hasRecyclerRole(proxyAddress, recyclerAddress)");
        console.log("\nTo get a recycler's proxy address:");
        console.log("factory.getProxyForRecycler(recyclerAddress)");
    }
}
