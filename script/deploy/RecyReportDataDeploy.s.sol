// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReportData.sol";
import "../../src/RecyReportAttributes.sol";
import "../../src/RecyReportSvg.sol";
import "../config/ConfigManager.s.sol";

contract RecyReportDataDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get network configuration
        NetworkConfig memory config = getNetworkConfig(chainId);

        console.log("=== RecyReportData Deployment ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", config.name);

        vm.startBroadcast();

        // Check if RecyReportAttributes is deployed
        RecyReportAttributes recyAttributes;
        if (config.reportAttributes != address(0)) {
            console.log(
                "Using existing RecyReportAttributes at:",
                config.reportAttributes
            );
            recyAttributes = RecyReportAttributes(config.reportAttributes);
        } else {
            console.log("Deploying new RecyReportAttributes...");
            recyAttributes = new RecyReportAttributes();
            console.log(
                "RecyReportAttributes deployed to:",
                address(recyAttributes)
            );
        }

        // Check if RecyReportSvg is deployed
        RecyReportSvg recySvg;
        if (config.reportSvg != address(0)) {
            console.log("Using existing RecyReportSvg at:", config.reportSvg);
            recySvg = RecyReportSvg(config.reportSvg);
        } else {
            console.log("Deploying new RecyReportSvg...");
            recySvg = new RecyReportSvg();
            console.log("RecyReportSvg deployed to:", address(recySvg));
        }

        // Deploy RecyReportData
        console.log("Deploying RecyReportData...");
        RecyReportData recyData = new RecyReportData(
            address(recyAttributes),
            address(recySvg)
        );

        vm.stopBroadcast();

        // Log deployment information
        console.log("=== Deployment Results ===");
        console.log("RecyReportData deployed to:", address(recyData));
        console.log("RecyReportAttributes address:", address(recyAttributes));
        console.log("RecyReportSvg address:", address(recySvg));

        // Verify the contract is properly initialized
        console.log("=== Contract Verification ===");
        console.log(
            "RecyReportData.attributes():",
            address(recyData.attributes())
        );
        console.log("RecyReportData.svg():", address(recyData.svg()));

        // Test basic functionality
        console.log("=== Functionality Test ===");
        try recyData.attributes().getMaterials() returns (
            string[] memory materials
        ) {
            console.log("Materials array length:", materials.length);
            console.log("Contract initialization successful!");
        } catch {
            console.log("Warning: Could not verify materials array");
        }

        try recyData.svg().getTrashcan() returns (string memory trashcan) {
            console.log("Trashcan SVG length:", bytes(trashcan).length);
            console.log("SVG generation working!");
        } catch {
            console.log("Warning: Could not verify SVG generation");
        }

        // Note: Configuration updates are disabled to prevent JSON corruption
        // Future versions will include a more robust configuration update mechanism

        console.log("=== Deployment Complete ===");
        console.log("To manually update configuration, use:");
        console.log("RecyReportAttributes:", address(recyAttributes));
        console.log("RecyReportSvg:", address(recySvg));
        console.log("RecyReportData:", address(recyData));
    }
}
