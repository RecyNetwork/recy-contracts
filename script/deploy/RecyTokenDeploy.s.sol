// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyToken.sol";
import "../config/ConfigManager.s.sol";

contract RecyTokenDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        console.log("=== SimpleToken Deployment ===");
        console.log("Chain ID:", chainId);

        vm.startBroadcast();

        // Token configuration
        string memory name = "RecyToken";
        string memory symbol = "cRECY";
        uint8 decimals = 18;

        // Deploy RecyToken
        console.log("Deploying RecyToken...");
        RecyToken token = new RecyToken(
            name,
            symbol,
            decimals,
            0,
            address(0x3402ce3b5f88c852c0d6992C69A03095d1345BBd)
        );

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
        console.log("Owner balance:", token.balanceOf(msg.sender));

        // Display token information
        console.log("=== Token Information ===");
        console.log(
            "Total Supply:",
            token.totalSupply() / 10 ** token.decimals(),
            "tokens"
        );
        console.log(
            "Owner Balance:",
            token.balanceOf(msg.sender) / 10 ** token.decimals(),
            "tokens"
        );

        console.log("=== Deployment Complete ===");
    }
}
