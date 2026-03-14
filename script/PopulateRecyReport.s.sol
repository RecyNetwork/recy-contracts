// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/RecyReport.sol";
import "../src/RecyReportFactory.sol";
import "../src/RecyToken.sol";
import "./config/ConfigManager.s.sol";

contract PopulateRecyReportScript is Script, ConfigManager {
    function setUp() public {}

    /**
     * @dev Helper function to add recycling result for NFT #0
     */
    function _addResultToNFT0(RecyReport recyReport, uint256 tokenId) private {
        uint32[] memory materials = new uint32[](3);
        materials[0] = 0; // PLASTIC
        materials[1] = 1; // GLASS
        materials[2] = 2; // PAPER

        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 5000; // 5kg plastic
        amounts[1] = 2000; // 2kg glass
        amounts[2] = 1000; // 1kg paper

        uint32[] memory types = new uint32[](3);
        types[0] = 0; // PET
        types[1] = 0; // CLEAR_GLASS
        types[2] = 0; // CARDBOARD

        uint32[] memory shapes = new uint32[](3);
        shapes[0] = 0; // BOTTLE
        shapes[1] = 1; // JAR
        shapes[2] = 2; // SHEET

        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp - 1 days), // recycled yesterday
            8000, // total 8kg
            materials,
            amounts,
            types,
            shapes,
            0 // RECYCLING disposal method
        );
        console.log("Added result to NFT #%d", tokenId);
    }

    /**
     * @dev Helper function to add recycling result for NFT #1
     */
    function _addResultToNFT1(RecyReport recyReport, uint256 tokenId) private {
        uint32[] memory materials = new uint32[](2);
        materials[0] = 3; // METAL
        materials[1] = 4; // ORGANIC

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 3000; // 3kg metal
        amounts[1] = 4000; // 4kg organic

        uint32[] memory types = new uint32[](2);
        types[0] = 0; // ALUMINUM
        types[1] = 0; // FOOD_WASTE

        uint32[] memory shapes = new uint32[](2);
        shapes[0] = 0; // CAN
        shapes[1] = 3; // LOOSE

        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp - 2 days), // recycled 2 days ago
            7000, // total 7kg
            materials,
            amounts,
            types,
            shapes,
            1 // COMPOSTING disposal method
        );
        console.log("Added result to NFT #%d", tokenId);
    }

    /**
     * @dev Helper function to add recycling result for NFT #2
     */
    function _addResultToNFT2(RecyReport recyReport, uint256 tokenId) private {
        uint32[] memory materials = new uint32[](4);
        materials[0] = 0; // PLASTIC
        materials[1] = 1; // GLASS
        materials[2] = 2; // PAPER
        materials[3] = 5; // TEXTILE

        uint128[] memory amounts = new uint128[](4);
        amounts[0] = 2500; // 2.5kg plastic
        amounts[1] = 1500; // 1.5kg glass
        amounts[2] = 2000; // 2kg paper
        amounts[3] = 1000; // 1kg textile

        uint32[] memory types = new uint32[](4);
        types[0] = 1; // HDPE
        types[1] = 1; // COLORED_GLASS
        types[2] = 1; // NEWSPAPER
        types[3] = 0; // COTTON

        uint32[] memory shapes = new uint32[](4);
        shapes[0] = 0; // BOTTLE
        shapes[1] = 1; // JAR
        shapes[2] = 2; // SHEET
        shapes[3] = 4; // FABRIC

        recyReport.setRecyReportResult(
            tokenId,
            uint64(block.timestamp - 3 days), // recycled 3 days ago
            7000, // total 7kg
            materials,
            amounts,
            types,
            shapes,
            0 // RECYCLING disposal method
        );
        console.log("Added result to NFT #%d", tokenId);
    }

    function run() public {
        uint256 chainId = block.chainid;

        // Get network and proxy configuration
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, "default");

        require(networkConfig.factory != address(0), "RecyReportFactory contract not deployed");
        require(networkConfig.token != address(0), "Token contract not deployed");

        RecyReportFactory factory = RecyReportFactory(networkConfig.factory);
        RecyToken token = RecyToken(networkConfig.token);

        // Get the deployed proxy address from the factory
        (address[] memory proxies,) = factory.getDeployedProxiesPaginated(0, 1);
        require(proxies.length > 0, "No proxies deployed");

        address proxyAddress = proxies[0];
        RecyReport recyReport = RecyReport(proxyAddress);

        console.log("=== Populating RecyReport Contract ===");
        console.log("Chain ID:", chainId);
        console.log("Factory:", address(factory));
        console.log("RecyReport Proxy:", address(recyReport));
        console.log("Token:", address(token));

        // Warp to a future time to avoid unlock delay issues
        uint256 futureTime = block.timestamp + config.unlockDelay + 300; // 5 minutes extra buffer
        vm.warp(futureTime);
        console.log("Warped to future time: %d (current + %d seconds)", futureTime, config.unlockDelay + 300);

        vm.startBroadcast();

        // Get the broadcaster address (the account that will be doing the transactions)
        address broadcaster = msg.sender;
        console.log("Broadcaster:", broadcaster);

        // Grant necessary roles to the broadcaster through the factory
        if (!recyReport.hasRole(recyReport.RECYCLER_ROLE(), broadcaster)) {
            console.log("Granting RECYCLER_ROLE to broadcaster via factory...");
            factory.grantRecyclerRole(proxyAddress, broadcaster);
        }

        if (!recyReport.hasRole(recyReport.AUDITOR_ROLE(), broadcaster)) {
            console.log("Granting AUDITOR_ROLE to broadcaster via factory...");
            factory.grantAuditorRole(proxyAddress, broadcaster);
        }

        // Step 1: Mint 4 NFTs
        console.log("\n=== Step 1: Minting 4 NFTs ===");
        uint256 startTokenId = recyReport.nftNextId();

        for (uint256 i = 0; i < 4; i++) {
            recyReport.mintRecyReport();
            console.log("Minted NFT #%d", startTokenId + i);
        }

        // Step 2: Add recycling results to 3 of them
        console.log("\n=== Step 2: Adding Results to 3 NFTs ===");

        // Add result to NFT #0
        _addResultToNFT0(recyReport, startTokenId);

        // Add result to NFT #1
        _addResultToNFT1(recyReport, startTokenId + 1);

        // Add result to NFT #2
        _addResultToNFT2(recyReport, startTokenId + 2);

        // Step 3: Validate 2 of them
        console.log("\n=== Step 3: Validating 2 NFTs ===");

        // Validate NFT #0
        recyReport.validateRecyReport(startTokenId);
        console.log("Validated NFT #%d", startTokenId);

        // Validate NFT #1
        recyReport.validateRecyReport(startTokenId + 1);
        console.log("Validated NFT #%d", startTokenId + 1);

        // Step 4: Wait for unlock delay and claim one reward
        console.log("\n=== Step 4: Waiting for Unlock Delay ===");
        console.log("Unlock delay: %d seconds", config.unlockDelay);

        // Ensure the contract has enough tokens for rewards
        uint256 contractBalance = token.balanceOf(address(recyReport));
        if (contractBalance == 0) {
            console.log("Contract has no tokens, minting rewards...");
            // Mint some tokens to the contract for rewards
            token.mint(address(recyReport), 1000000 * 10 ** 18); // 1M tokens
            console.log("Minted 1M tokens to contract for rewards");
        }

        // Claim reward for NFT #0
        console.log("\n=== Step 5: Claiming Reward ===");
        address nftOwner = recyReport.ownerOf(startTokenId);
        console.log("NFT #%d owner: %s", startTokenId, vm.toString(nftOwner));
        console.log("Current blockchain time: %d", block.timestamp);
        console.log("Token unlock delay: %d seconds", config.unlockDelay);

        // Get the unlock date for debugging
        uint256 unlockDate = recyReport.unlockDate(startTokenId);
        console.log("Token unlock date: %d", unlockDate);

        vm.stopBroadcast();

        // Step 6: Display final status
        console.log("\n=== Final Status Summary ===");

        for (uint256 i = 0; i < 4; i++) {
            uint256 tokenId = startTokenId + i;
            uint8 tokenStatus = recyReport.status(tokenId);
            address owner = recyReport.ownerOf(tokenId);

            string memory statusText;
            if (tokenStatus == 1) statusText = "CREATED";
            else if (tokenStatus == 2) statusText = "COMPLETED";
            else if (tokenStatus == 3) statusText = "VALIDATED";
            else if (tokenStatus == 4) statusText = "REWARDED";
            else statusText = "UNKNOWN";

            console.log("NFT #%d - Status: %s - Owner: %s", tokenId, statusText, vm.toString(owner));
        }

        console.log("\n=== Population Complete ===");
        console.log("* 4 NFTs minted");
        console.log("* 3 NFTs with recycling results");
        console.log("* 2 NFTs validated");
    }
}
