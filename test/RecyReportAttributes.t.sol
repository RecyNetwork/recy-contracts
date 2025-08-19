// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {RecyReportAttributes} from "../src/RecyReportAttributes.sol";
import "./helpers/TestHelpers.sol";

contract RecyReportAttributesTest is Test, TestHelpers {
    RecyReportAttributes public recyReportAttributes;

    function setUp() public {
        recyReportAttributes = new RecyReportAttributes();
    }

    /// @notice Test getMaterial returns the correct string value for index 1
    function test_getMaterial() public view {
        assertEq(recyReportAttributes.getMaterial(1), "Plastic");
    }

    /// @notice Test getMaterial reverts when index is out of bounds
    function test_getMaterial_reverts() public {
        uint256 len = recyReportAttributes.getMaterials().length;
        vm.expectRevert("RecyReportAttributes.getMaterial: Invalid index");
        recyReportAttributes.getMaterial(len);
    }

    /// @notice Test getMaterialSvg returns the correct SVG string for a valid index
    function test_getMaterialSvg() public view {
        // compare against auto‐getter materialSvg(index)
        string memory expected = recyReportAttributes.materialSvg(2);
        assertEq(
            recyReportAttributes.getMaterialSvg(2),
            expected,
            "getMaterialSvg index 2 mismatch"
        );
    }

    /// @notice Test getMaterialSvg reverts when index >= length
    function test_getMaterialSvg_reverts() public {
        uint256 len = recyReportAttributes.getMaterialSvgs().length;
        vm.expectRevert("RecyReportAttributes.getMaterialSvg: Invalid index");
        recyReportAttributes.getMaterialSvg(len);
    }

    /// @notice Test getRecycleType returns the correct string value for index 2
    function test_getRecycleType() public view {
        assertEq(recyReportAttributes.getRecycleType(2), "Incineration");
    }

    /// @notice Test getRecycleType reverts when index is out of bounds
    function test_getRecycleType_reverts() public {
        uint256 len = recyReportAttributes.getRecycleTypes().length;
        vm.expectRevert("RecyReportAttributes.getRecycleType: Invalid index");
        recyReportAttributes.getRecycleType(len);
    }

    /// @notice Test getDisposalMethod returns the correct string value for index 3
    function test_getDisposalMethod() public view {
        assertEq(recyReportAttributes.getDisposalMethod(3), "Recycling");
    }

    /// @notice Test getDisposalMethod reverts when index is out of bounds
    function test_getDisposalMethod_reverts() public {
        uint256 len = recyReportAttributes.getDisposalMethods().length;
        vm.expectRevert(
            "RecyReportAttributes.getDisposalMethod: Invalid index"
        );
        recyReportAttributes.getDisposalMethod(len);
    }

    /// @notice Test getRecycleShape returns the correct string value for index 1
    function test_getRecycleShape() public view {
        assertEq(recyReportAttributes.getRecycleShape(1), "Pellets");
    }

    /// @notice Test getRecycleShape reverts when index is out of bounds
    function test_getRecycleShape_reverts() public {
        uint256 len = recyReportAttributes.getRecycleShapes().length;
        vm.expectRevert("RecyReportAttributes.getRecycleShape: Invalid index");
        recyReportAttributes.getRecycleShape(len);
    }

    /// @notice Test array getters return the full lists
    function test_arrayGetters() public view {
        string[] memory mats = recyReportAttributes.getMaterials();
        string[] memory types = recyReportAttributes.getRecycleTypes();
        string[] memory disposals = recyReportAttributes.getDisposalMethods();
        string[] memory shapes = recyReportAttributes.getRecycleShapes();

        // spot‐check lengths and contents
        assertEq(mats.length, 11);
        assertEq(mats[0], "Undefined");
        assertEq(types.length, 7);
        assertEq(types[0], "Undefined");
        assertEq(disposals.length, 8);
        assertEq(disposals[0], "Undefined");
        assertEq(shapes.length, 3);
        assertEq(shapes[0], "Undefined");
    }

    /// @notice Test getMaterialSvgs returns the full array
    function test_getMaterialSvgs_fullArrays() public view {
        string[] memory svgs = recyReportAttributes.getMaterialSvgs();
        assertEq(
            svgs.length,
            recyReportAttributes.getMaterials().length,
            "getMaterialSvgs length mismatch"
        );
    }

    /// @notice Test getMaterials returns the complete array
    function test_getMaterials_fullArray() public view {
        string[] memory mats = recyReportAttributes.getMaterials();
        // expected length per source: 11
        assertEq(mats.length, 11, "getMaterials length");
        // spot‐check first and last
        assertEq(mats[0], "Undefined", "materials[0]");
        assertEq(mats[10], "Chemical", "materials[10]");
    }

    /// @notice Test getRecycleTypes returns the complete array
    function test_getRecycleTypes_fullArray() public view {
        string[] memory types = recyReportAttributes.getRecycleTypes();
        // expected length per source: 7
        assertEq(types.length, 7, "getRecycleTypes length");
        assertEq(types[0], "Undefined", "types[0]");
        assertEq(types[6], "Thermal Recycling", "types[6]");
    }

    /// @notice Test getDisposalMethods returns the complete array
    function test_getDisposalMethods_fullArray() public view {
        string[] memory disposals = recyReportAttributes.getDisposalMethods();
        // expected length per source: 8
        assertEq(disposals.length, 8, "getDisposalMethods length");
        assertEq(disposals[0], "Undefined", "disposals[0]");
        assertEq(disposals[7], "Plasma Gasification", "disposals[7]");
    }

    /// @notice Test getRecycleShapes returns the complete array
    function test_getRecycleShapes_fullArray() public view {
        string[] memory shapes = recyReportAttributes.getRecycleShapes();
        // expected length per source: 3
        assertEq(shapes.length, 3, "getRecycleShapes length");
        assertEq(shapes[0], "Undefined", "shapes[0]");
        assertEq(shapes[2], "Bricks", "shapes[2]");
    }

    /// @notice Test addMaterial pushes both name and SVG
    function test_addMaterial_success() public {
        string memory newMat = "MyMaterial";
        string memory newSvg = "<svg>...</svg>";
        uint256 beforeNames = recyReportAttributes.getMaterials().length;
        uint256 beforeSvgs = recyReportAttributes.getMaterialSvgs().length;

        recyReportAttributes.addMaterial(newMat, newSvg);

        string[] memory names = recyReportAttributes.getMaterials();
        string[] memory svgs = recyReportAttributes.getMaterialSvgs();

        assertEq(names.length, beforeNames + 1, "names length");
        assertEq(svgs.length, beforeSvgs + 1, "svgs length");
        assertEq(names[beforeNames], newMat, "pushed name");
        assertEq(svgs[beforeSvgs], newSvg, "pushed svg");
    }

    /// @notice Test addMaterial reverts on empty name
    function test_addMaterial_emptyName_reverts() public {
        expectRevertWithMessage(
            "RecyReportAttributes.addMaterial: Material name cannot be empty"
        );
        recyReportAttributes.addMaterial("", "<svg/>");
    }

    /// @notice Test addMaterial reverts on empty SVG
    function test_addMaterial_emptySvg_reverts() public {
        expectRevertWithMessage(
            "RecyReportAttributes.addMaterial: Material SVG cannot be empty"
        );
        recyReportAttributes.addMaterial("TestMat", "");
    }

    /// @notice Test addRecycleType pushes a new entry
    function test_addRecycleType() public {
        string memory newType = "TestRecycle";
        uint256 oldLen = recyReportAttributes.getRecycleTypes().length;
        recyReportAttributes.addRecycleType(newType);
        string[] memory afterr = recyReportAttributes.getRecycleTypes();
        assertEq(afterr.length, oldLen + 1);
        assertEq(afterr[oldLen], newType);
    }

    /// @notice Test addDisposalMethod pushes a new entry
    function test_addDisposalMethod() public {
        string memory newDisp = "TestDisposal";
        uint256 oldLen = recyReportAttributes.getDisposalMethods().length;
        recyReportAttributes.addDisposalMethod(newDisp);
        string[] memory afterr = recyReportAttributes.getDisposalMethods();
        assertEq(afterr.length, oldLen + 1);
        assertEq(afterr[oldLen], newDisp);
    }

    /// @notice Test addRecycleShape pushes a new entry
    function test_addRecycleShape() public {
        string memory newShape = "TestShape";
        uint256 oldLen = recyReportAttributes.getRecycleShapes().length;
        recyReportAttributes.addRecycleShape(newShape);
        string[] memory afterr = recyReportAttributes.getRecycleShapes();
        assertEq(afterr.length, oldLen + 1);
        assertEq(afterr[oldLen], newShape);
    }

    // ===== BOUNDARY TESTS FOR GETTERS =====

    function test_getMaterialAtBoundaries() public view {
        uint256 materialCount = recyReportAttributes.getMaterials().length;

        // Test first valid index
        string memory first = recyReportAttributes.getMaterial(0);
        assertEq(first, "Undefined");

        // Test last valid index
        string memory last = recyReportAttributes.getMaterial(
            materialCount - 1
        );
        assertTrue(bytes(last).length > 0);
    }

    function testFuzz_getMaterialWithInvalidIndex(uint256 index) public {
        uint256 materialCount = recyReportAttributes.getMaterials().length;
        vm.assume(index >= materialCount);

        vm.expectRevert();
        recyReportAttributes.getMaterial(index);
    }

    function test_getMaterialSvgAtBoundaries() public view {
        uint256 svgCount = recyReportAttributes.getMaterialSvgs().length;

        // Test first valid index
        string memory first = recyReportAttributes.getMaterialSvg(0);
        assertTrue(bytes(first).length > 0);

        // Test last valid index
        string memory last = recyReportAttributes.getMaterialSvg(svgCount - 1);
        assertTrue(bytes(last).length > 0);
    }

    function testFuzz_getMaterialSvgWithInvalidIndex(uint256 index) public {
        uint256 svgCount = recyReportAttributes.getMaterialSvgs().length;
        vm.assume(index >= svgCount);

        vm.expectRevert();
        recyReportAttributes.getMaterialSvg(index);
    }

    function test_getRecycleTypeAtBoundaries() public view {
        uint256 typeCount = recyReportAttributes.getRecycleTypes().length;

        // Test first valid index
        string memory first = recyReportAttributes.getRecycleType(0);
        assertEq(first, "Undefined");

        // Test last valid index
        string memory last = recyReportAttributes.getRecycleType(typeCount - 1);
        assertTrue(bytes(last).length > 0);
    }

    function testFuzz_getRecycleTypeWithInvalidIndex(uint256 index) public {
        uint256 typeCount = recyReportAttributes.getRecycleTypes().length;
        vm.assume(index >= typeCount);

        vm.expectRevert();
        recyReportAttributes.getRecycleType(index);
    }

    function test_getDisposalMethodAtBoundaries() public view {
        uint256 methodCount = recyReportAttributes.getDisposalMethods().length;

        // Test first valid index
        string memory first = recyReportAttributes.getDisposalMethod(0);
        assertEq(first, "Undefined");

        // Test last valid index
        string memory last = recyReportAttributes.getDisposalMethod(
            methodCount - 1
        );
        assertTrue(bytes(last).length > 0);
    }

    function testFuzz_getDisposalMethodWithInvalidIndex(uint256 index) public {
        uint256 methodCount = recyReportAttributes.getDisposalMethods().length;
        vm.assume(index >= methodCount);

        vm.expectRevert();
        recyReportAttributes.getDisposalMethod(index);
    }

    function test_getRecycleShapeAtBoundaries() public view {
        uint256 shapeCount = recyReportAttributes.getRecycleShapes().length;

        // Test first valid index
        string memory first = recyReportAttributes.getRecycleShape(0);
        assertEq(first, "Undefined");

        // Test last valid index
        string memory last = recyReportAttributes.getRecycleShape(
            shapeCount - 1
        );
        assertTrue(bytes(last).length > 0);
    }

    function testFuzz_getRecycleShapeWithInvalidIndex(uint256 index) public {
        uint256 shapeCount = recyReportAttributes.getRecycleShapes().length;
        vm.assume(index >= shapeCount);

        vm.expectRevert();
        recyReportAttributes.getRecycleShape(index);
    }

    // ===== ARRAY CONSISTENCY TESTS =====

    function test_materialArraysConsistentLength() public view {
        uint256 materialCount = recyReportAttributes.getMaterials().length;
        uint256 svgCount = recyReportAttributes.getMaterialSvgs().length;

        assertEq(materialCount, svgCount);
    }

    function test_arrayContentsConsistency() public view {
        string[] memory materials = recyReportAttributes.getMaterials();
        string[] memory svgs = recyReportAttributes.getMaterialSvgs();

        // Verify that each material has a corresponding SVG
        for (uint256 i = 0; i < materials.length; i++) {
            assertTrue(bytes(materials[i]).length > 0);
            assertTrue(bytes(svgs[i]).length > 0);
        }
    }

    function test_arrayOrderConsistency() public view {
        // Test that getter functions return same values as array access
        string[] memory materials = recyReportAttributes.getMaterials();

        for (uint256 i = 0; i < materials.length; i++) {
            assertEq(materials[i], recyReportAttributes.getMaterial(i));
        }
    }

    // ===== ADDING MATERIALS EDGE CASES =====

    function test_addMaterialWithWhitespaceOnly() public {
        // This should succeed as there's no whitespace validation
        recyReportAttributes.addMaterial("   ", "   ");

        uint256 materialCount = recyReportAttributes.getMaterials().length;
        string memory lastMaterial = recyReportAttributes.getMaterial(
            materialCount - 1
        );
        assertEq(lastMaterial, "   ");
    }

    function test_addMaterialWithValidData() public {
        uint256 initialCount = recyReportAttributes.getMaterials().length;

        recyReportAttributes.addMaterial("TestMaterial", "<svg>test</svg>");

        uint256 newCount = recyReportAttributes.getMaterials().length;
        assertEq(newCount, initialCount + 1);

        string memory newMaterial = recyReportAttributes.getMaterial(
            initialCount
        );
        string memory newSvg = recyReportAttributes.getMaterialSvg(
            initialCount
        );

        assertEq(newMaterial, "TestMaterial");
        assertEq(newSvg, "<svg>test</svg>");
    }

    function test_addMultipleMaterials() public {
        uint256 initialCount = recyReportAttributes.getMaterials().length;

        for (uint256 i = 0; i < 5; i++) {
            string memory name = string(
                abi.encodePacked("Material", vm.toString(i))
            );
            string memory svg = string(
                abi.encodePacked("<svg>", vm.toString(i), "</svg>")
            );

            recyReportAttributes.addMaterial(name, svg);
        }

        uint256 finalCount = recyReportAttributes.getMaterials().length;
        assertEq(finalCount, initialCount + 5);

        // Verify all materials were added correctly
        for (uint256 i = 0; i < 5; i++) {
            string memory expectedName = string(
                abi.encodePacked("Material", vm.toString(i))
            );
            string memory expectedSvg = string(
                abi.encodePacked("<svg>", vm.toString(i), "</svg>")
            );

            assertEq(
                recyReportAttributes.getMaterial(initialCount + i),
                expectedName
            );
            assertEq(
                recyReportAttributes.getMaterialSvg(initialCount + i),
                expectedSvg
            );
        }
    }

    function test_addMaterialWithLongStrings() public {
        string
            memory longName = "This is a very long material name that tests the boundary conditions of string storage in Solidity contracts and ensures that extremely long strings are handled correctly";
        string
            memory longSvg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect x='0' y='0' width='100' height='100' fill='red'/><circle cx='50' cy='50' r='25' fill='blue'/><text x='50' y='50' text-anchor='middle'>Very Long SVG Content</text></svg>";

        uint256 initialCount = recyReportAttributes.getMaterials().length;

        recyReportAttributes.addMaterial(longName, longSvg);

        assertEq(recyReportAttributes.getMaterial(initialCount), longName);
        assertEq(recyReportAttributes.getMaterialSvg(initialCount), longSvg);
    }

    function test_addMaterialWithSpecialCharacters() public {
        string memory specialName = "Material!@#$%^&*()_+-=[]{}|;':\",./<>?";
        string memory specialSvg = "<svg>!@#$%^&*()_+-=[]{}|;':\",./<>?</svg>";

        uint256 initialCount = recyReportAttributes.getMaterials().length;

        recyReportAttributes.addMaterial(specialName, specialSvg);

        assertEq(recyReportAttributes.getMaterial(initialCount), specialName);
        assertEq(recyReportAttributes.getMaterialSvg(initialCount), specialSvg);
    }

    function test_addMaterialWithUnicodeCharacters() public {
        string memory unicodeName = unicode"Material Unicode Test";
        string memory unicodeSvg = unicode"<svg>unicode test</svg>";

        uint256 initialCount = recyReportAttributes.getMaterials().length;

        recyReportAttributes.addMaterial(unicodeName, unicodeSvg);

        assertEq(recyReportAttributes.getMaterial(initialCount), unicodeName);
        assertEq(recyReportAttributes.getMaterialSvg(initialCount), unicodeSvg);
    }

    function test_addMaterialWithNumbersOnly() public {
        string memory numberName = "12345";
        string memory numberSvg = "<svg>67890</svg>";

        uint256 initialCount = recyReportAttributes.getMaterials().length;

        recyReportAttributes.addMaterial(numberName, numberSvg);

        assertEq(recyReportAttributes.getMaterial(initialCount), numberName);
        assertEq(recyReportAttributes.getMaterialSvg(initialCount), numberSvg);
    }

    // ===== ADDING OTHER TYPES EDGE CASES =====

    function test_addRecycleTypeWithEmptyString() public {
        // This should succeed as there's no validation in the contract
        recyReportAttributes.addRecycleType("");

        uint256 typeCount = recyReportAttributes.getRecycleTypes().length;
        string memory lastType = recyReportAttributes.getRecycleType(
            typeCount - 1
        );
        assertEq(lastType, "");
    }

    function test_addRecycleTypeWithValidString() public {
        uint256 initialCount = recyReportAttributes.getRecycleTypes().length;

        recyReportAttributes.addRecycleType("TestRecycleType");

        uint256 newCount = recyReportAttributes.getRecycleTypes().length;
        assertEq(newCount, initialCount + 1);

        string memory newType = recyReportAttributes.getRecycleType(
            initialCount
        );
        assertEq(newType, "TestRecycleType");
    }

    function test_addDisposalMethodWithEmptyString() public {
        // This should succeed as there's no validation in the contract
        recyReportAttributes.addDisposalMethod("");

        uint256 methodCount = recyReportAttributes.getDisposalMethods().length;
        string memory lastMethod = recyReportAttributes.getDisposalMethod(
            methodCount - 1
        );
        assertEq(lastMethod, "");
    }

    function test_addDisposalMethodWithValidString() public {
        uint256 initialCount = recyReportAttributes.getDisposalMethods().length;

        recyReportAttributes.addDisposalMethod("TestDisposalMethod");

        uint256 newCount = recyReportAttributes.getDisposalMethods().length;
        assertEq(newCount, initialCount + 1);

        string memory newMethod = recyReportAttributes.getDisposalMethod(
            initialCount
        );
        assertEq(newMethod, "TestDisposalMethod");
    }

    function test_addRecycleShapeWithEmptyString() public {
        // This should succeed as there's no validation in the contract
        recyReportAttributes.addRecycleShape("");

        uint256 shapeCount = recyReportAttributes.getRecycleShapes().length;
        string memory lastShape = recyReportAttributes.getRecycleShape(
            shapeCount - 1
        );
        assertEq(lastShape, "");
    }

    function test_addRecycleShapeWithValidString() public {
        uint256 initialCount = recyReportAttributes.getRecycleShapes().length;

        recyReportAttributes.addRecycleShape("TestRecycleShape");

        uint256 newCount = recyReportAttributes.getRecycleShapes().length;
        assertEq(newCount, initialCount + 1);

        string memory newShape = recyReportAttributes.getRecycleShape(
            initialCount
        );
        assertEq(newShape, "TestRecycleShape");
    }

    // ===== STRESS TESTS =====

    function test_addManyMaterials() public {
        uint256 initialCount = recyReportAttributes.getMaterials().length;
        uint256 addCount = 50; // Reduced to avoid gas limits

        for (uint256 i = 0; i < addCount; i++) {
            string memory name = string(
                abi.encodePacked("StressMaterial", vm.toString(i))
            );
            string memory svg = string(
                abi.encodePacked("<svg>stress", vm.toString(i), "</svg>")
            );

            recyReportAttributes.addMaterial(name, svg);
        }

        uint256 finalCount = recyReportAttributes.getMaterials().length;
        assertEq(finalCount, initialCount + addCount);

        // Verify random samples
        assertEq(
            recyReportAttributes.getMaterial(initialCount),
            "StressMaterial0"
        );
        assertEq(
            recyReportAttributes.getMaterial(initialCount + 25),
            "StressMaterial25"
        );
        assertEq(
            recyReportAttributes.getMaterial(initialCount + addCount - 1),
            "StressMaterial49"
        );
    }

    // ===== INTEGRATION TESTS =====

    function test_attributesAfterMultipleAdditions() public {
        // Add one of each type
        recyReportAttributes.addMaterial("NewMaterial", "<svg>new</svg>");
        recyReportAttributes.addRecycleType("NewType");
        recyReportAttributes.addDisposalMethod("NewMethod");
        recyReportAttributes.addRecycleShape("NewShape");

        // Verify they can all be accessed
        uint256 materialCount = recyReportAttributes.getMaterials().length;
        uint256 typeCount = recyReportAttributes.getRecycleTypes().length;
        uint256 methodCount = recyReportAttributes.getDisposalMethods().length;
        uint256 shapeCount = recyReportAttributes.getRecycleShapes().length;

        assertEq(
            recyReportAttributes.getMaterial(materialCount - 1),
            "NewMaterial"
        );
        assertEq(recyReportAttributes.getRecycleType(typeCount - 1), "NewType");
        assertEq(
            recyReportAttributes.getDisposalMethod(methodCount - 1),
            "NewMethod"
        );
        assertEq(
            recyReportAttributes.getRecycleShape(shapeCount - 1),
            "NewShape"
        );
    }
}
