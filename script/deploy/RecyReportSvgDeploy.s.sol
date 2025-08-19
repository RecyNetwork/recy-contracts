// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReportSvg.sol";

contract RecyReportSvgDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy RecyReportSvg contract
        RecyReportSvg recySvg = new RecyReportSvg();

        vm.stopBroadcast();

        // Log deployment information
        console.log("=== RecyReportSvg Deployment ===");
        console.log("RecyReportSvg deployed to:", address(recySvg));
        console.log("Contract owner:", recySvg.owner());

        // Test some functionality
        console.log(
            "Recycle SVG constant defined:",
            bytes(recySvg.recycle()).length > 0
        );

        // Test SVG generation for different statuses
        console.log("Testing SVG generation:");
        try recySvg.getCoins(0) returns (string memory /* coinsCreated */) {
            console.log("Coins SVG for CREATED status generated successfully");
        } catch {
            console.log("Error generating coins SVG for CREATED status");
        }

        try recySvg.getCoins(4) returns (string memory /* coinsRewarded */) {
            console.log("Coins SVG for REWARDED status generated successfully");
        } catch {
            console.log("Error generating coins SVG for REWARDED status");
        }

        try recySvg.getRecycle() returns (string memory /* recycleSvg */) {
            console.log("Recycle SVG generated successfully");
        } catch {
            console.log("Error generating recycle SVG");
        }

        try recySvg.getTrashcan() returns (string memory /* trashcanSvg */) {
            console.log("Trashcan SVG generated successfully");
        } catch {
            console.log("Error generating trashcan SVG");
        }

        console.log("=== Deployment Complete ===");
    }
}
