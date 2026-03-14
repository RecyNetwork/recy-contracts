// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReportAttributes.sol";

contract RecyReportAttributesDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy RecyReportAttributes contract
        RecyReportAttributes recyAttributes = new RecyReportAttributes();

        vm.stopBroadcast();

        // Log deployment information
        console.log("=== RecyReportAttributes Deployment ===");
        console.log("RecyReportAttributes deployed to:", address(recyAttributes));
        console.log("Contract owner:", recyAttributes.owner());
        console.log("Total materials:", recyAttributes.getMaterials().length);
        console.log("Total material SVGs:", recyAttributes.getMaterialSvgs().length);
        console.log("Total recycle types:", recyAttributes.getRecycleTypes().length);
        console.log("Total recycle shapes:", recyAttributes.getRecycleShapes().length);
        console.log("Total disposal methods:", recyAttributes.getDisposalMethods().length);

        // Log some sample data
        console.log("Sample material[0]:", recyAttributes.material(0));
        console.log("Sample recycleType[0]:", recyAttributes.recycleType(0));
        console.log("Sample recycleShape[0]:", recyAttributes.recycleShape(0));
        console.log("Sample disposalMethod[0]:", recyAttributes.disposalMethod(0));

        console.log("=== Deployment Complete ===");
    }
}
