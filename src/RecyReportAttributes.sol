// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable.sol";

contract RecyReportAttributes is Ownable {
    constructor() Ownable(msg.sender) {}

    string[] public material = [
        "Undefined",
        "Plastic",
        "Glass",
        "Metal",
        "Paper",
        "Glass",
        "E-Waste",
        "Organic",
        "Textile",
        "Hazardous",
        "Chemical"
    ];

    string[] public materialSvg = [
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 "
    ];

    string[] public recycleType = [
        "Undefined",
        "Composting",
        "Incineration",
        "Mechanical Recycling",
        "Pyrolysis",
        "Refuse-Derived Fuel",
        "Thermal Recycling"
    ];

    string[] public recycleShape = ["Undefined", "Pellets", "Bricks"];

    string[] public disposalMethod = [
        "Undefined",
        "Landfill",
        "Incineration",
        "Recycling",
        "Composting",
        "Anaerobic Digestion",
        "Waste-to-Energy",
        "Plasma Gasification"
    ];

    function getMaterial(uint256 index) public view returns (string memory) {
        require(index < material.length, "RecyReportAttributes.getMaterial: Invalid index");
        return material[index];
    }

    function getMaterialSvg(uint256 index) public view returns (string memory) {
        require(index < materialSvg.length, "RecyReportAttributes.getMaterialSvg: Invalid index");
        return materialSvg[index];
    }

    function getRecycleType(uint256 index) public view returns (string memory) {
        require(index < recycleType.length, "RecyReportAttributes.getRecycleType: Invalid index");
        return recycleType[index];
    }

    function getDisposalMethod(uint256 index) public view returns (string memory) {
        require(index < disposalMethod.length, "RecyReportAttributes.getDisposalMethod: Invalid index");
        return disposalMethod[index];
    }

    function getRecycleShape(uint256 index) public view returns (string memory) {
        require(index < recycleShape.length, "RecyReportAttributes.getRecycleShape: Invalid index");
        return recycleShape[index];
    }

    function getMaterials() public view returns (string[] memory) {
        return material;
    }

    function getMaterialSvgs() public view returns (string[] memory) {
        return materialSvg;
    }

    function getRecycleTypes() public view returns (string[] memory) {
        return recycleType;
    }

    function getDisposalMethods() public view returns (string[] memory) {
        return disposalMethod;
    }

    function getRecycleShapes() public view returns (string[] memory) {
        return recycleShape;
    }

    function addMaterial(string memory newMaterial, string memory newMaterialSvg) external onlyOwner {
        require(bytes(newMaterial).length > 0, "RecyReportAttributes.addMaterial: Material name cannot be empty");
        require(bytes(newMaterialSvg).length > 0, "RecyReportAttributes.addMaterial: Material SVG cannot be empty");
        material.push(newMaterial);
        materialSvg.push(newMaterialSvg);
    }

    function addRecycleType(string memory newRecycleType) external onlyOwner {
        recycleType.push(newRecycleType);
    }

    function addDisposalMethod(string memory newDisposalMethod) external onlyOwner {
        disposalMethod.push(newDisposalMethod);
    }

    function addRecycleShape(string memory newRecycleShape) external onlyOwner {
        recycleShape.push(newRecycleShape);
    }
}
