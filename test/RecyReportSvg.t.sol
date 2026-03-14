// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";

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
        for (uint256 i; i <= a.length - b.length; i++) {
            bool ok = true;
            for (uint256 j; j < b.length; j++) {
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

    function test_getRecycle() public view {
        string memory s = svg.getRecycle();
        assertTrue(bytes(s).length > 0, "empty svg");
        assertTrue(contains(s, "<svg"), "missing <svg>");
        assertTrue(contains(s, 'viewBox="0 0 549 549"'), "wrong viewBox");
        assertTrue(contains(s, 'fill="#000000"'), "wrong fill color");
        assertTrue(contains(s, "background-color:#00FF44"), "wrong background");
        assertTrue(contains(s, "</svg>"), "missing footer");
    }

    function test_getCoins_notRewarded() public view {
        string memory s = svg.getCoins(RecyConstants.RECYCLE_CREATED);
        assertTrue(bytes(s).length > 0, "empty svg");
        assertTrue(contains(s, 'viewBox="0 0 512 512"'), "wrong viewBox");
        assertTrue(contains(s, 'fill="#FFD700"'), "should be gold");
        assertTrue(contains(s, "</svg>"), "missing footer");
    }

    function test_getCoins_rewarded() public view {
        string memory s = svg.getCoins(RecyConstants.RECYCLE_REWARDED);
        assertTrue(bytes(s).length > 0, "empty svg");
        assertTrue(contains(s, 'viewBox="0 0 512 512"'), "wrong viewBox");
        assertTrue(contains(s, 'fill="#808080"'), "should be grey");
        assertTrue(contains(s, "</svg>"), "missing footer");
    }
}
