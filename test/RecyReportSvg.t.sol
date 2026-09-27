// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";
import {RecyErrors} from "../src/lib/RecyErrors.sol";
import {Test} from "forge-std/Test.sol";

contract RecyReportSvgTest is Test {
    RecyReportSvg public svg;

    function setUp() public {
        svg = new RecyReportSvg();
    }

    /// @dev helper to check substring
    function contains(string memory where, string memory what) internal pure returns (bool) {
        bytes memory a = bytes(where);
        bytes memory b = bytes(what);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i <= a.length - b.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < b.length; j++) {
                if (a[i + j] != b[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function test_owner() public view {
        assertEq(svg.owner(), address(this));
    }

    function test_getTrashcan() public view {
        string memory s = svg.getTrashcan();
        assertTrue(bytes(s).length > 0, "empty svg");
        assertTrue(contains(s, "<svg"), "missing <svg>");
        assertTrue(contains(s, 'viewBox="0 0 24 24"'), "wrong viewBox");
        assertTrue(contains(s, 'fill="#6644FF"'), "wrong fill color");
        assertTrue(contains(s, "</svg>"), "missing footer");
    }

    function countOccurrences(string memory where, string memory what) internal pure returns (uint256 count) {
        bytes memory a = bytes(where);
        bytes memory b = bytes(what);
        if (b.length > a.length) return 0;
        for (uint256 i = 0; i <= a.length - b.length; ++i) {
            bool matchFound = true;
            for (uint256 j = 0; j < b.length; ++j) {
                if (a[i + j] != b[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) ++count;
        }
    }

    function firstIndex(string memory where, string memory what) internal pure returns (uint256) {
        bytes memory a = bytes(where);
        bytes memory b = bytes(what);
        if (b.length > a.length) return type(uint256).max;
        for (uint256 i = 0; i <= a.length - b.length; ++i) {
            bool matchFound = true;
            for (uint256 j = 0; j < b.length; ++j) {
                if (a[i + j] != b[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) return i;
        }
        return type(uint256).max;
    }

    // Rendering each cardinality deliberately makes repeated calls to the fixture contract.
    // forge-lint: disable-next-item(calls-loop)
    function test_recycleBadgeCountsAndPlacement() public view {
        uint32[] memory ids = new uint32[](3);
        ids[0] = 1;
        ids[1] = 4;
        ids[2] = 3;
        for (uint256 n = 0; n <= 3; ++n) {
            uint32[] memory selected = new uint32[](n);
            for (uint256 j = 0; j < n; ++j) {
                selected[j] = ids[j];
            }
            string memory image = svg.getRecycle(selected);
            assertEq(countOccurrences(image, 'class="material-badge"'), n);
            assertTrue(contains(image, 'viewBox="0 0 549 549"'));
            assertTrue(contains(image, 'fill="#000000"'));
            assertTrue(contains(image, "background-color:#00FF44"));
            assertTrue(contains(image, "</svg>"));
        }
        string memory three = svg.getRecycle(ids);
        assertTrue(contains(three, 'cx="174" cy="465"'));
        assertTrue(contains(three, 'cx="274" cy="465"'));
        assertTrue(contains(three, 'cx="374" cy="465"'));
        assertTrue(firstIndex(three, svg.getMaterialIcon(1)) < firstIndex(three, svg.getMaterialIcon(4)));
        assertTrue(firstIndex(three, svg.getMaterialIcon(4)) < firstIndex(three, svg.getMaterialIcon(3)));
    }

    // Rendering each cardinality deliberately makes repeated calls to the fixture contract.
    // forge-lint: disable-next-item(calls-loop)
    function test_coinBadgeCountsLayeringAndStatusColours() public view {
        uint32[] memory ids = new uint32[](3);
        ids[0] = 7;
        ids[1] = 8;
        ids[2] = 10;
        for (uint256 n = 0; n <= 3; ++n) {
            uint32[] memory selected = new uint32[](n);
            for (uint256 j = 0; j < n; ++j) {
                selected[j] = ids[j];
            }
            string memory image = svg.getCoins(RecyConstants.RECYCLE_VALIDATED, selected);
            assertEq(countOccurrences(image, 'class="material-badge"'), n);
            assertTrue(contains(image, 'viewBox="0 0 512 512"'));
            assertTrue(contains(image, 'fill="#FFD700"'));
            if (n > 0) {
                assertTrue(firstIndex(image, "M264.4 95.01") < firstIndex(image, 'class="material-badge"'));
                assertTrue(contains(image, svg.getMaterialIcon(selected[n - 1])));
            }
        }
        assertTrue(contains(svg.getCoins(RecyConstants.RECYCLE_REWARDED, ids), 'fill="#808080"'));
        assertTrue(contains(svg.getCoins(RecyConstants.RECYCLE_INVALIDATED, ids), 'fill="#ff0000"'));
        assertTrue(contains(svg.getCoins(RecyConstants.RECYCLE_FLAGGED, ids), 'fill="#FFD700"'));
        assertTrue(contains(svg.getCoins(RecyConstants.RECYCLE_INVALIDATED, ids), 'stroke="#ff0000"'));
    }

    // Every frozen catalogue entry is rendered through the same two public image surfaces.
    // forge-lint: disable-next-item(calls-loop)
    function test_materialCatalogueAndFallback() public view {
        assertNotEq(svg.getMaterialIcon(2), svg.getMaterialIcon(5));
        assertNotEq(svg.getMaterialIcon(5), svg.getMaterialIcon(6));
        assertEq(svg.getMaterialIcon(0), svg.getMaterialIcon(12));
        assertEq(svg.getMaterialIcon(12), svg.getMaterialIcon(type(uint32).max));
        assertNotEq(svg.getMaterialIcon(11), svg.getMaterialIcon(12));
        for (uint32 id = 1; id <= 11; ++id) {
            uint32[] memory selected = new uint32[](1);
            selected[0] = id;
            assertTrue(contains(svg.getRecycle(selected), svg.getMaterialIcon(id)));
            assertTrue(contains(svg.getCoins(RecyConstants.RECYCLE_VALIDATED, selected), svg.getMaterialIcon(id)));
        }
        uint32[] memory unknown = new uint32[](2);
        unknown[0] = 12;
        unknown[1] = type(uint32).max;
        assertEq(countOccurrences(svg.getRecycle(unknown), svg.getMaterialIcon(0)), 2);
        assertEq(countOccurrences(svg.getCoins(RecyConstants.RECYCLE_REWARDED, unknown), svg.getMaterialIcon(0)), 2);
    }

    // A rejected call cannot return a value for assertion.
    // forge-lint: disable-next-item(unused-return)
    function test_revertsAboveThreeBadges() public {
        uint32[] memory four = new uint32[](4);
        vm.expectRevert(RecyErrors.TooManyMaterialIcons.selector);
        svg.getRecycle(four);
        vm.expectRevert(RecyErrors.TooManyMaterialIcons.selector);
        svg.getCoins(RecyConstants.RECYCLE_INVALIDATED, four);
    }
}
