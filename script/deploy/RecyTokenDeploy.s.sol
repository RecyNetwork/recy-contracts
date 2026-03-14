// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../../src/RecyToken.sol";
import "../config/ConfigManager.s.sol";

contract RecyTokenDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        console.log("=== RecyToken (OFT) Deployment ===");
        console.log("Chain ID:", chainId);

        // Load network config for lzEndpoint
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        require(networkConfig.lzEndpoint != address(0), "lzEndpoint not configured for this chain");

        address delegate = address(0x3402ce3b5f88c852c0d6992C69A03095d1345BBd);

        vm.startBroadcast();

        // Token configuration
        string memory name = "RecyToken";
        string memory symbol = "cRECY";

        // Deploy RecyToken (OFT)
        console.log("Deploying RecyToken...");
        console.log("LZ Endpoint:", networkConfig.lzEndpoint);
        RecyToken token = new RecyToken(name, symbol, 0, networkConfig.lzEndpoint, delegate);

        vm.stopBroadcast();

        // Log deployment information
        console.log("=== Deployment Results ===");
        console.log("Deployer address:", msg.sender);
        console.log("Token deployed to:", address(token));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Token decimals:", token.decimals());
        console.log("Token owner:", token.owner());
        console.log("Initial supply:", token.totalSupply());

        console.log("=== Deployment Complete ===");
    }
}
