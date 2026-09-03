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
        "Chemical",
        "Leachate",
        "Solid Inert Industrial Waste"
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
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 ",
        "M2.72,7.65a2.56,2.56,0,0,1,.56.24,4,4,0,0,0,4.1,0,2.6,2.6,0,0,1,2.56,0,4.15,4.15,0,0,0,4.12,0,2.6,2.6,0,0,1,2.56,0,4.25,4.25,0,0,0,2.08.56,3.88,3.88,0,0,0,2-.56,2.56,2.56,0,0,1,.56-.24,1,1,0,0,0-.56-1.92,4.45,4.45,0,0,0-1,.45,2.08,2.08,0,0,1-2.1,0,4.64,4.64,0,0,0-4.54,0,2.11,2.11,0,0,1-2.12,0,4.64,4.64,0,0,0-4.54,0,2.08,2.08,0,0,1-2.1,0,4.45,4.45,0,0,0-1-.45,1,1,0,1,0-.56,1.92Zm18,8.08a4.45,4.45,0,0,0-1,.45,2.08,2.08,0,0,1-2.1,0,4.64,4.64,0,0,0-4.54,0,2.11,2.11,0,0,1-2.12,0,4.64,4.64,0,0,0-4.54,0,2.08,2.08,0,0,1-2.1,0,4.45,4.45,0,0,0-1-.45,1,1,0,1,0-.56,1.92,2.56,2.56,0,0,1,.56.24,4,4,0,0,0,4.1,0,2.6,2.6,0,0,1,2.56,0,4.15,4.15,0,0,0,4.12,0,2.6,2.6,0,0,1,2.56,0,4.25,4.25,0,0,0,2.08.56,3.88,3.88,0,0,0,2-.56,2.56,2.56,0,0,1,.56-.24,1,1,0,0,0-.56-1.92Zm0-5a4.45,4.45,0,0,0-1,.45,2.08,2.08,0,0,1-2.1,0,4.64,4.64,0,0,0-4.54,0,2.11,2.11,0,0,1-2.12,0,4.64,4.64,0,0,0-4.54,0,2.08,2.08,0,0,1-2.1,0,4.45,4.45,0,0,0-1-.45A1,1,0,0,0,2,11.41a1,1,0,0,0,.68,1.24,2.56,2.56,0,0,1,.56.24,4,4,0,0,0,4.1,0,2.6,2.6,0,0,1,2.56,0,4.15,4.15,0,0,0,4.12,0,2.6,2.6,0,0,1,2.56,0,4.25,4.25,0,0,0,2.08.56,3.88,3.88,0,0,0,2-.56,2.56,2.56,0,0,1,.56-.24,1,1,0,0,0-.56-1.92Z",
        "M317.727 108.904l-95.192 96.592-26.93 86.815 17.54 36.723 20.417 9.287 33.182-55.082 11.297-3.61 61.75 26.85 20.26-12.998 4.47-43.7 11.42 53.634-10.622 14.162 3.772 1.64 5.238 6.5 6.832 34.343 55.977-66.775 13.98.23 22.397 28.575-9.453-52.244L434.01 166.81l-116.28-57.906zM123.61 120.896L94.08 173l-4.603 27.62 25.98-8.442 11.704 7.377.084.634 28.295 59.865 13.773-4.543 10.94 4.668 3.922 8.21 19.517-62.917-1.074-33.336-40.15-.522-29.732-23.78 34.06 10.888 42.49-7.727 26.034 15.88 36.282-36.815c-2.777-1.18-5.615-2.356-8.58-3.52l-79.58 10.126-3.528-.25-56.307-15.52zm249.33 36.422l47.058 66.02 2.107 62.51-25.283-59.698-65.322-60.404 41.44-8.428zm-262.2 55.32l-64.234 20.876-16.71 78.552 50.794 5.582.596-7.14 37.662-36.707-8.108-61.16zm56.688 62.45l-36.44 12.016-31.644 30.84 22.588 30.867 57.326 1.74 16.5-16.16-28.33-59.302zm110.666 24.19l-44.307 73.546-.033 57.14 97.264 12.216 44.242-19.528-17.666-88.806-79.5-34.567zM443.8 313.36l-46.843 55.876.287 1.774 65.147 13.887 25.78-14.926-44.37-56.613zm-138.382 15.89l39.23 22.842 13.41 50.658-26.82 23.838-45.015-2.553 38.562-28.242 2.483-39.23-21.85-27.312zm-238.37 53.838l-8.77 28.51 13.152 48.498 91.037-11.91 1.32-26.418-62.582-31.995-34.156-6.684z"
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
        require(
            index < material.length,
            "RecyReportAttributes.getMaterial: Invalid index"
        );
        return material[index];
    }

    function getMaterialSvg(uint256 index) public view returns (string memory) {
        require(
            index < materialSvg.length,
            "RecyReportAttributes.getMaterialSvg: Invalid index"
        );
        return materialSvg[index];
    }

    function getRecycleType(uint256 index) public view returns (string memory) {
        require(
            index < recycleType.length,
            "RecyReportAttributes.getRecycleType: Invalid index"
        );
        return recycleType[index];
    }

    function getDisposalMethod(
        uint256 index
    ) public view returns (string memory) {
        require(
            index < disposalMethod.length,
            "RecyReportAttributes.getDisposalMethod: Invalid index"
        );
        return disposalMethod[index];
    }

    function getRecycleShape(
        uint256 index
    ) public view returns (string memory) {
        require(
            index < recycleShape.length,
            "RecyReportAttributes.getRecycleShape: Invalid index"
        );
        return recycleShape[index];
    }

    function getMaterials() public view returns (string[] memory) {
        return material;
    }

    function getMaterialsCount() public view returns (uint256) {
        return material.length;
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

    function addMaterial(
        string memory newMaterial,
        string memory newMaterialSvg
    ) external onlyOwner {
        require(
            bytes(newMaterial).length > 0,
            "RecyReportAttributes.addMaterial: Material name cannot be empty"
        );
        require(
            bytes(newMaterialSvg).length > 0,
            "RecyReportAttributes.addMaterial: Material SVG cannot be empty"
        );
        material.push(newMaterial);
        materialSvg.push(newMaterialSvg);
    }

    function addRecycleType(string memory newRecycleType) external onlyOwner {
        recycleType.push(newRecycleType);
    }

    function addDisposalMethod(
        string memory newDisposalMethod
    ) external onlyOwner {
        disposalMethod.push(newDisposalMethod);
    }

    function addRecycleShape(string memory newRecycleShape) external onlyOwner {
        recycleShape.push(newRecycleShape);
    }
}
