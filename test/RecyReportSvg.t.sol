// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";
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
        assertTrue(contains(s, 'viewBox="0 0 24 24"'));
        assertTrue(contains(s, 'fill="#6644FF"'));
        assertEq(countOccurrences(s, 'class="category-slot"'), 0);
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

    /// @dev The `d` of the first path: the main artwork, drawn before the classification slots.
    function mainArt(string memory image) internal pure returns (string memory) {
        bytes memory source = bytes(image);
        uint256 start = firstIndex(image, '<path d="') + 9;
        uint256 end = start;
        while (source[end] != '"') ++end;
        bytes memory art = new bytes(end - start);
        for (uint256 i = 0; i < art.length; ++i) {
            art[i] = source[start + i];
        }
        return string(art);
    }

    function test_recycleRendersFourOrderedCategoriesEvenWhenUndefined() public view {
        uint32[4] memory classifications = [uint32(1), 3, 4, 5];
        string memory image = svg.getRecycle(classifications);
        assertTrue(contains(image, 'viewBox="0 0 549 549"'));
        assertTrue(contains(image, "background-color:#00FF44"));
        assertTrue(contains(image, 'fill="#000000"'));
        assertEq(countOccurrences(image, 'class="category-slot"'), 4);
        assertEq(countOccurrences(image, 'width="25%"'), 4);
        assertTrue(contains(image, 'data-category="material" data-id="1" x="0%"'));
        assertTrue(contains(image, 'data-category="recycle-type" data-id="3" x="25%"'));
        assertTrue(contains(image, 'data-category="recycle-shape" data-id="4" x="50%"'));
        assertTrue(contains(image, 'data-category="disposal-method" data-id="5" x="75%"'));
        assertTrue(firstIndex(image, 'data-category="material"') < firstIndex(image, 'data-category="recycle-type"'));
        assertTrue(
            firstIndex(image, 'data-category="recycle-type"') < firstIndex(image, 'data-category="recycle-shape"')
        );
        assertTrue(
            firstIndex(image, 'data-category="recycle-shape"') < firstIndex(image, 'data-category="disposal-method"')
        );
        assertTrue(firstIndex(image, 'fill="#000000"') < firstIndex(image, 'class="category-slot"'));
        assertEq(countOccurrences(svg.getRecycle([uint32(0), 0, 0, 0]), 'class="category-slot"'), 4);
    }

    function test_coinSlotsOverlayMainIconWithStatusSpecificAccent() public view {
        uint32[4] memory classifications = [uint32(7), 2, 3, 4];
        string memory validated = svg.getCoins(RecyConstants.RECYCLE_VALIDATED, classifications);
        assertTrue(contains(validated, 'viewBox="0 0 512 512"'));
        assertTrue(contains(validated, 'fill="#FFD700"'));
        assertTrue(contains(validated, 'stroke="#FFD700"'));
        assertEq(countOccurrences(validated, 'class="category-slot"'), 4);
        assertTrue(firstIndex(validated, 'fill="#FFD700"') < firstIndex(validated, 'class="category-slot"'));
        assertTrue(contains(validated, 'data-category="material" data-id="7" x="0%"'));
        assertTrue(contains(validated, 'data-category="recycle-type" data-id="2" x="25%"'));
        assertTrue(contains(validated, 'data-category="recycle-shape" data-id="3" x="50%"'));
        assertTrue(contains(validated, 'data-category="disposal-method" data-id="4" x="75%"'));

        string memory rewarded = svg.getCoins(RecyConstants.RECYCLE_REWARDED, classifications);
        assertTrue(contains(rewarded, 'fill="#808080"'));
        assertTrue(contains(rewarded, 'stroke="#808080"'));
        assertEq(countOccurrences(rewarded, 'class="category-slot"'), 4);
    }

    function test_flaggedAndInvalidatedDrawOwnArtworkInsteadOfCoins() public view {
        uint32[4] memory classifications = [uint32(7), 2, 3, 4];
        string memory coins = mainArt(svg.getCoins(RecyConstants.RECYCLE_VALIDATED, classifications));

        string memory flagged = svg.getCoins(RecyConstants.RECYCLE_FLAGGED, classifications);
        assertTrue(contains(flagged, 'fill="#FF8C00"'));
        assertTrue(contains(flagged, 'stroke="#FF8C00"'));
        assertEq(countOccurrences(flagged, 'class="category-slot"'), 4);
        assertTrue(firstIndex(flagged, 'fill="#FF8C00"') < firstIndex(flagged, 'class="category-slot"'));

        string memory invalidated = svg.getCoins(RecyConstants.RECYCLE_INVALIDATED, classifications);
        assertTrue(contains(invalidated, 'fill="#ff0000"'));
        assertTrue(contains(invalidated, 'stroke="#ff0000"'));
        assertEq(countOccurrences(invalidated, 'class="category-slot"'), 4);
        assertTrue(firstIndex(invalidated, 'fill="#ff0000"') < firstIndex(invalidated, 'class="category-slot"'));

        assertNotEq(mainArt(flagged), coins, "flagged must not reuse the coin artwork");
        assertNotEq(mainArt(invalidated), coins, "invalidated must not reuse the coin artwork");
        assertNotEq(mainArt(flagged), mainArt(invalidated), "flag and stamp must differ");
    }

    function test_unknownIdsRenderCategoryFallbackWithoutDroppingSlots() public view {
        uint32[4] memory unknown = [uint32(13), type(uint32).max, type(uint32).max, type(uint32).max];
        assertEq(svg.getMaterialIcon(13), svg.getMaterialIcon(0));
        assertEq(svg.getRecycleTypeIcon(type(uint32).max), svg.getRecycleTypeIcon(0));
        assertEq(svg.getRecycleShapeIcon(type(uint32).max), svg.getRecycleShapeIcon(0));
        assertEq(svg.getDisposalMethodIcon(type(uint32).max), svg.getDisposalMethodIcon(0));
        string memory image = svg.getRecycle(unknown);
        assertEq(countOccurrences(image, 'class="category-slot"'), 4);
        assertTrue(contains(image, 'data-category="material" data-id="13"'));
        assertTrue(contains(image, 'data-category="recycle-type" data-id="4294967295"'));
        assertTrue(contains(image, 'data-category="recycle-shape" data-id="4294967295"'));
        assertTrue(contains(image, 'data-category="disposal-method" data-id="4294967295"'));
        assertEq(countOccurrences(svg.getCoins(RecyConstants.RECYCLE_REWARDED, unknown), 'class="category-slot"'), 4);
    }
}
