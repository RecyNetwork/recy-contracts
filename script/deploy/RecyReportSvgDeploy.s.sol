// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../src/RecyReportSvg.sol";
import "forge-std/Script.sol";

contract RecyReportSvgDeploy is Script {
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
        console.log("Recycle SVG constant defined:", bytes(recySvg.recycle()).length > 0);

        uint32[4] memory classifications = [uint32(1), 3, 4, 3]; // Plastic / mechanical / fertilizer / recycling
        // Exercise the four-slot category strip on both non-created image surfaces.
        console.log("Testing SVG generation with material/type/shape/disposal slots:");
        try recySvg.getCoins(3, classifications) returns (
            string memory /* coinsValidated */
        ) {
            console.log("Coins SVG for VALIDATED status generated successfully");
        } catch {
            console.log("Error generating coins SVG for VALIDATED status");
        }
        try recySvg.getCoins(4, classifications) returns (
            string memory /* coinsRewarded */
        ) {
            console.log("Coins SVG for REWARDED status generated successfully");
        } catch {
            console.log("Error generating coins SVG for REWARDED status");
        }
        try recySvg.getRecycle(classifications) returns (
            string memory /* recycleSvg */
        ) {
            console.log("Recycle SVG generated successfully");
        } catch {
            console.log("Error generating recycle SVG");
        }
        try recySvg.getTrashcan() returns (
            string memory /* trashcanSvg */
        ) {
            console.log("Trashcan SVG generated successfully");
        } catch {
            console.log("Error generating trashcan SVG");
        }
        console.log("=== Deployment Complete ===");
    }
}
