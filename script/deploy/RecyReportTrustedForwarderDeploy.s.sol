// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import "../config/ConfigManager.s.sol";

contract RecyReportTrustedForwarderDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get network configuration
        NetworkConfig memory config = getNetworkConfig(chainId);

        console.log("=== Starting Trusted Forwarder Deployment ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", config.name);

        vm.startBroadcast();

        // Deploy the ERC2771Forwarder with a descriptive EIP-712 domain name
        ERC2771Forwarder forwarder = new ERC2771Forwarder(
            "RecyReportForwarder"
        );

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("ERC2771Forwarder deployed to:", address(forwarder));
        console.log("");
        console.log("=== Next Steps ===");
        console.log(
            "1. Add forwarder address to config/contracts.json for chain",
            chainId
        );
        console.log(
            "2. Call setTrustedForwarder(forwarderAddress) on each RecyReport proxy"
        );
    }
}
