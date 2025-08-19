// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReport.sol";
import "../config/ConfigManager.s.sol";

contract RecyReportDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get network configuration
        NetworkConfig memory config = getNetworkConfig(chainId);

        console.log("=== Starting Deployment ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", config.name);

        vm.startBroadcast();

        // Deploy the implementation contract
        RecyReport implementation = new RecyReport();

        vm.stopBroadcast();

        console.log("=== Manual Config Update Required ===");
        console.log("Add to config/contracts.json for chain", chainId, ":");
        console.log(
            "RecyReport upgradable implementation deployed to:",
            address(implementation)
        );
    }
}
