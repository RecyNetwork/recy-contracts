// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title RecyReportIcons
/// @notice Duotone glyphs on a 24x24 grid. RecyReportSvg paints five layers back to front: `tone`
///         is filled with the slot accent tint, `body` is tinted and stroked, `line` is only
///         stroked, `detail` is only stroked at a fine 1 width for small inner shapes a full
///         stroke would clog, and `solid` is filled white and normally stroked. `solidFillOnly`
///         suppresses that stroke for sharp filled contours; independently, `accentOpaque` paints
///         both accent-filled layers at full opacity rather than their usual .35. Strokes are white, 1.5 wide
///         unless noted, with round caps and joins. IDs are the material, recycle type,
///         recycle shape and disposal method catalogue indices; zero and unknown IDs receive a neutral glyph.
/// @dev RecyReportSvg deploys this catalogue in its constructor so the glyph data does not count
///      against the renderer's own EIP-170 code-size limit.
contract RecyReportIcons {
    struct Glyph {
        string body;
        string tone;
        string line;
        string solid;
        string detail;
        bool solidFillOnly;
        bool accentOpaque;
    }

    string private constant FLAME =
        "M12 21a6.5 6.5 0 0 1-6.5-6.5c0-3.1 2.1-5.3 3.6-7.5.3 1.6 1.2 2.7 2.4 3.3-.5-3.4.9-5.8 3-7.3-.3 2.9.9 4.9 2.3 6.8 1 1.4 1.7 2.9 1.7 4.7A6.5 6.5 0 0 1 12 21Z";
    string private constant CYCLE = "M4.5 10A7.8 7.8 0 0 1 17.8 6.8M19.5 14A7.8 7.8 0 0 1 6.2 17.2";
    string private constant CYCLE_HEADS = "M19.4 9.7l-3.2-2L19.3 6ZM4.6 14.3l3.2 2-3.1 1.8Z";

    /// @notice Material glyph; zero and unknown IDs (including 13) fall back to the package.
    function material(uint32 id) external pure returns (Glyph memory) {
        if (id == 1) {
            // Plastic: PET bottle with three fine ribs and cap/neck join.
            return Glyph(
                "",
                "",
                "M10.5 4.3V7c0 1.2-3 1.6-3 3.8v9.7c3 .8 6 .8 9 0V10.8c0-2.2-3-2.6-3-3.8V4.3Z",
                "M10.7 2.8h2.7a.4.4 0 0 1 .4.4v.7a.4.4 0 0 1-.4.4H10.7a.4.4 0 0 1-.4-.4V3.2a.4.4 0 0 1 .4-.4Z",
                "M7.5 12.75c3 .8 6 .8 9 0m-9 2.5c3 .8 6 .8 9 0m-9 2.5c3 .8 6 .8 9 0",
                false,
                false
            );
        }
        if (id == 2) {
            // Glass: stemmed wine glass holding tinted wine with a filled stem joint.
            return Glyph(
                "",
                "M6.5 8h11c-.4 2.9-2.7 5-5.5 5S6.9 10.9 6.5 8Z",
                "M7 3H17c.4 1.4.6 2.8.6 4.1 0 3.4-2.5 6-5.5 6s-5.6-2.7-5.6-6c0-1.3.2-2.7.5-4.1ZM8.5 21h7",
                "M11.25 13H12.75V21H11.25Z",
                "",
                true,
                false
            );
        }
        if (id == 3) {
            // Metal: a crisp filled hex nut with a generous open circular center.
            return Glyph(
                "",
                "",
                "",
                "M12 3 19.8 7.5v9L12 21l-7.8-4.5v-9ZM8.5 12a3.5 3.5 0 1 0 7 0 3.5 3.5 0 1 0-7 0Z",
                "",
                true,
                false
            );
        }
        if (id == 4) {
            // Paper: tinted sheet with text lines and a solid folded corner.
            return Glyph(
                "M14 3H7.5C6.7 3 6 3.7 6 4.5v15c0 .8.7 1.5 1.5 1.5h9c.8 0 1.5-.7 1.5-1.5V7Z",
                "",
                "M9 11h6M9 14h6M9 17h3.5",
                "M14 3V6.3c0 .4.3.8.8.8H18Z",
                "",
                false,
                false
            );
        }
        if (id == 5) {
            // E-waste: mobile phone with an inset screen.
            return Glyph(
                "",
                "M8.5 6h7a.5.5 0 0 1 .5.5v10a.5.5 0 0 1-.5.5h-7a.5.5 0 0 1-.5-.5v-10a.5.5 0 0 1 .5-.5Z",
                "M8 2.5h8A1.5 1.5 0 0 1 17.5 4v16a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 20V4A1.5 1.5 0 0 1 8 2.5Z",
                "",
                "M10.5 4.5h3M10.5 19h3",
                false,
                false
            );
        }
        if (id == 6) {
            // Organic: tinted leaf with an unstroked, tapering solid stem and midrib.
            return Glyph(
                "M7 17C4.9 11.1 8.9 4.5 19.5 4.5 19.9 14.1 13.9 18.9 7 17Z",
                "",
                "",
                "M3.4 19.55C7.1 15.15 11.3 11.25 16 8.5C11.7 11.75 7.9 15.85 4.6 20.45A.75.75 0 0 1 3.4 19.55Z",
                "",
                true,
                false
            );
        }
        if (id == 7) {
            // Textile: tinted T-shirt.
            return Glyph(
                "M9.3 3.5 3.5 6.5 5.3 10.3 7 9.3V19.6c0 .4.3.8.8.8h8.5c.4 0 .8-.3.8-.8V9.3l1.8 1 1.8-3.7-5.7-3c-.4 1.3-1.5 2.2-2.7 2.2s-2.6-1-3-2.3Z",
                "",
                "",
                "",
                "",
                false,
                false
            );
        }
        if (id == 8) {
            // Hazardous: tinted warning triangle with an exclamation mark.
            return Glyph(
                "M13.7 6.1 19.6 16.5a2 2 0 0 1-1.8 3H6.2a2 2 0 0 1-1.8-3L10.3 6.1a2 2 0 0 1 3.4 0Z",
                "",
                "M12 9.5v4.3m0 2.7v.1",
                "",
                "",
                false,
                false
            );
        }
        if (id == 9) {
            // Chemical: Erlenmeyer flask with bubbling tinted liquid.
            return Glyph(
                "",
                "M7.5 14l-2 4.2A1.8 1.8 0 0 0 7 20.8H17a1.8 1.8 0 0 0 1.6-2.6L16.5 14Z",
                "M10 3.3V8.5a1 1 0 0 1-.1.4L5.5 18.2A1.8 1.8 0 0 0 7 20.8H17a1.8 1.8 0 0 0 1.6-2.6L14.1 8.9a1 1 0 0 1-.1-.4V3.3m-5.2 0h6.5M7.5 14h9m-6.2 4.3v.1m2-7.1v.1",
                "M12.7 17.4a.8.8 0 1 0 1.6 0 .8.8 0 1 0-1.6 0Z",
                "",
                false,
                false
            );
        }
        if (id == 10) {
            // Leachate: drop filled with tinted, rippling liquid.
            return Glyph(
                "",
                "M6 14.5c1-.7 2-.7 3 0s2 .7 3 0 2-.7 3 0 2 .7 3 0a6 6 0 0 1-12 0Z",
                "M12 3C9.2 6.9 6 10.6 6 14.5a6 6 0 0 0 12 0c0-3.9-3.2-7.6-6-11.5ZM6 14.5c1-.7 2-.7 3 0s2 .7 3 0 2-.7 3 0 2 .7 3 0",
                "",
                "",
                false,
                false
            );
        }
        if (id == 11) {
            // Solid inert industrial waste: rubble heap with tinted fractured chunks.
            return Glyph(
                "M7.3 14.3 8.8 10.5l4-2.2 3 2.7L11 15.3Zm8.2 6.2.8-4.5-.5-5 3 1.5 2.2 8Z",
                "",
                "M7.3 14.3l-3 2L3 20.5H15.5M11 15.3l-.7 5.2",
                "",
                "",
                false,
                false
            );
        }
        // Undefined and unknown materials (including 13): a taped package.
        return
            Glyph(
                "M12 3 20 7.5 12 12 4 7.5Z", "", "M20 7.5v9L12 21 4 16.5v-9M12 12v9M8 5.3 16 9.8", "", "", false, false
            );
    }

    /// @notice Recycle-type glyph; zero and unknown IDs fall back to the circular arrows.
    function recycleType(uint32 id) external pure returns (Glyph memory) {
        if (id == 1) return _compost();
        if (id == 2) return _flame();
        if (id == 3) {
            // Mechanical recycling: circular arrows around a gear with a full-accent hub band.
            return Glyph(
                "",
                "M10.75 12a1.25 1.25 0 1 0 2.5 0 1.25 1.25 0 1 0-2.5 0ZM11.05 12a.95.95 0 1 0 1.9 0 .95.95 0 1 0-1.9 0Z",
                CYCLE,
                string.concat(
                    CYCLE_HEADS,
                    " M11.2 9.5l.2-1.1h1.2l.2 1.1.9.6 1.1-.4.6 1-.9.8v1l.9.8-.6 1-1.1-.4-.9.6-.2 1.1H11.4l-.2-1.1-.9-.6-1.1.4-.6-1 .9-.8v-1l-.9-.8.6-1 1.1.4ZM10 12a2 2 0 1 0 4 0 2 2 0 1 0-4 0Z"
                ),
                "",
                false,
                true
            );
        }
        if (id == 4) {
            // Pyrolysis: sealed drum on a stand, heated by a fire underneath. The small fire is
            // drawn in fine strokes so its tongues stay legible.
            string memory fire =
                "M12 20.4a3 3 0 0 1-3-3c0-1.4 1-2.4 1.7-3.4.1.7.6 1.2 1.1 1.5-.2-1.6.4-2.7 1.4-3.4-.1 1.3.4 2.3 1.1 3.1.5.6.8 1.3.8 2.2A3 3 0 0 1 12 20.4Z";
            return Glyph(
                "M7.5 3.5h9a3.3 3.3 0 0 1 3.3 3.3 3.3 3.3 0 0 1-3.3 3.2h-9A3.3 3.3 0 0 1 4.3 6.8 3.3 3.3 0 0 1 7.5 3.5Z",
                fire,
                "M16.5 3.5a1.6 3.3 0 0 0 0 6.5M7.8 10 6.5 20.8M16.3 10 17.6 20.8m-14.3 0H20.8",
                "",
                fire,
                false,
                false
            );
        }
        if (id == 5) {
            // Refuse-derived fuel: jerrycan carrying a recycling loop in fine strokes.
            return Glyph(
                "M9.3 6h8a1.5 1.5 0 0 1 1.5 1.5v12A1.5 1.5 0 0 1 17.3 21H6.8a1.5 1.5 0 0 1-1.5-1.5V10.1a.8.8 0 0 1 .2-.6L8.8 6.2A.8.8 0 0 1 9.3 6Z",
                "",
                "M12.5 6V3.8h5.8V6",
                "M6.6 7.2l-.9-1a.4.4 0 0 0-.5.5l1 .9a.4.4 0 0 0 .4-.4Z",
                "M8.7 13A3.6 3.6 0 0 1 15.4 13M15.8 11.5 15.4 13 14 12.6M15.4 15.4A3.6 3.6 0 0 1 8.7 15.4M8.3 16.9 8.7 15.4 10.1 15.8",
                false,
                false
            );
        }
        if (id == 6) {
            // Thermal recycling: circular arrows around a thermometer.
            return Glyph(
                "M10.8 13V8.8a1.3 1.3 0 0 1 2.5 0v4.3a2.4 2.4 0 1 1-2.5-.1Z",
                "",
                CYCLE,
                string.concat(CYCLE_HEADS, " M10.4 15a1.6 1.6 0 1 0 3.2 0 1.6 1.6 0 1 0-3.2 0Z"),
                "",
                false,
                false
            );
        }
        // Undefined and unknown types: circular arrows around a hub.
        return Glyph("M10.4 12a1.6 1.6 0 1 0 3.2 0 1.6 1.6 0 1 0-3.2 0Z", "", CYCLE, CYCLE_HEADS, "", false, false);
    }

    /// @notice Recycle-shape glyph; zero and unknown IDs fall back to the basic shapes.
    function recycleShape(uint32 id) external pure returns (Glyph memory) {
        if (id == 1) {
            // Pellets: heap of capsule pellets.
            return Glyph(
                "",
                "M3.5 21C5 15.5 8.2 12.3 12 12.3s7 3.3 8.5 8.8Z",
                "M2.8 21H21.3",
                "M5.5 19.4l2.1-.3a.5.5 0 0 0-.1-1l-2.1.3a.5.5 0 0 0 .1 1Zm5.4 0 2.1.2a.5.5 0 0 0 .1-1L11 18.4a.5.5 0 0 0-.1 1Zm5.6-.1 2.1-.2a.5.5 0 0 0-.1-1l-2.1.2a.5.5 0 0 0 .1 1ZM8.1 15.6l2 .6a.5.5 0 0 0 .3-.9l-2-.7a.5.5 0 0 0-.3 1Zm5.8.4 2-.5a.5.5 0 0 0-.2-.9l-2.1.5a.5.5 0 0 0 .3.9Zm-2.5-2.8 1.8-1.1a.5.5 0 0 0-.6-.9l-1.8 1.1a.5.5 0 0 0 .6.9Z",
                "",
                false,
                false
            );
        }
        if (id == 2) {
            // Bricks: running-bond brick courses.
            return Glyph(
                "M3.5 4h7.3V7.8H3.6Zm9.8 0h7.3V7.8H13.4ZM3.5 10.3H5.9v3.8H3.5Zm4.9 0h7.3v3.8H8.4Zm9.7 0h2.4v3.8H18.1ZM3.5 16.5h7.3v3.8H3.6Zm9.8 0h7.3v3.8H13.4Z",
                "",
                "",
                "",
                "",
                false,
                false
            );
        }
        if (id == 3) {
            // Final product: lidded product box with a check mark.
            return Glyph(
                "M4.8 9.3H19.3V19c0 .8-.7 1.5-1.5 1.5H6.3c-.8 0-1.5-.7-1.5-1.5Z",
                "",
                "M4.5 5.3h15a1.3 1.3 0 0 1 1.3 1.2V8a1.3 1.3 0 0 1-1.3 1.3H4.5A1.3 1.3 0 0 1 3.3 8V6.5A1.3 1.3 0 0 1 4.5 5.3ZM9 14.5l2.1 2.1 4-4.1",
                "",
                "",
                false,
                false
            );
        }
        if (id == 4) {
            // Fertilizer: sack printed with a sprout.
            return Glyph(
                "M6.5 4.5c1.8.6 3.7.9 5.5.9s3.7-.3 5.5-.9c-.4 1.4-.4 2.6-.2 3.8C18.4 9.9 19 12 19 14.5c0 2.9-.7 5-2.2 6H7.3c-1.5-1-2.3-3.1-2.3-6 0-2.5.6-4.6 1.7-6.2.3-1.2.2-2.4-.2-3.7Z",
                "",
                "M12 17.8V13.3",
                "M12 15.3c-1.9.1-3.2-.9-3.4-2.9 1.9-.1 3.2.9 3.4 2.9Zm0-1.5c.1-2.1 1.5-3.3 3.5-3.3-.1 2.1-1.5 3.4-3.5 3.3Z",
                "",
                false,
                false
            );
        }
        // Undefined and unknown shapes: triangle, circle and square.
        return Glyph(
            "M8.1 4.8 10.4 9a1 1 0 0 1-.8 1.5H4.9A1 1 0 0 1 4.1 9L6.4 4.8a1 1 0 0 1 1.7 0ZM13.3 7a3.5 3.5 0 1 0 7 0 3.5 3.5 0 1 0-7 0ZM9.8 13.3h4.5a1.5 1.5 0 0 1 1.5 1.5v4.5a1.5 1.5 0 0 1-1.5 1.5H9.8a1.5 1.5 0 0 1-1.5-1.5V14.8a1.5 1.5 0 0 1 1.5-1.5Z",
            "",
            "",
            "",
            "",
            false,
            false
        );
    }

    /// @notice Disposal-method glyph; zero and unknown IDs fall back to the waste bin.
    function disposalMethod(uint32 id) external pure returns (Glyph memory) {
        if (id == 1) {
            // Landfill: layered heap topped by a garbage bag.
            return Glyph(
                "M2.8 20.5c1.1-3.6 2.5-6.1 4.7-6.5h9c2.2.4 3.6 2.9 4.8 6.5Z",
                "",
                "M4.9 17.5c1.2-.6 2.4-.6 3.5 0 1.2.6 2.4.6 3.6 0s2.4-.6 3.6 0 2.4.6 3.5 0",
                "M11.3 8.3c-1.6.4-2.7 1.5-2.7 3.1V13c0 1.1 1.1 1.8 3.4 1.8 2.4 0 3.4-.7 3.4-1.8V11.4c0-1.6-1.1-2.7-2.6-3.1Zm.4-.1c-.7 0-1.4-.3-1.9-1 .8-.3 1.5-.2 2.2.4Zm.6 0c.8 0 1.5-.3 1.9-1-.7-.3-1.5-.2-2.2.4Z",
                "",
                false,
                false
            );
        }
        if (id == 2) return _flame();
        if (id == 3) {
            // Recycling: three chasing arrows with full-accent heads and white outlines.
            return Glyph(
                "M16.1 11.3l-3.2-2L16 7.6Zm-3.4 8.3 3.3-1.7v3.5ZM7.2 12.5 7.1 16.3 4 14.5Z",
                "",
                "M8.4 10.4l2-3.5a1.8 1.8 0 0 1 3.2 0l.8 1.6m2.9 5 2 3.4a1.8 1.8 0 0 1-1.5 2.7H16m-5.8 0h-4a1.8 1.8 0 0 1-1.5-2.7l.8-1.5",
                "",
                "",
                false,
                true
            );
        }
        if (id == 4) return _compost();
        if (id == 5) {
            // Anaerobic digestion: a filled pipe joint avoids a stroke cap at the flame.
            string memory flame =
                "M17.9 8.6A2 2 0 0 1 16 6.7c0-1 .6-1.6 1-2.3.1.5.4.8.8 1-.2-1 .2-1.7.8-2.2 0 .9.3 1.5.7 2 .3.5.6.9.6 1.5a2 2 0 0 1-2 1.9Z";
            return Glyph(
                "",
                string.concat(
                    flame,
                    " M4.6 16.3c1.2-.5 2.5-.5 3.7 0s2.5.5 3.7 0 2.5-.5 3.7 0 2.4.5 3.7 0a8.5 8.5 0 0 1 1.1 4.2H3.5a8.5 8.5 0 0 1 1.1-4.2Z"
                ),
                "M3.5 20.5a8.5 8.5 0 0 1 17 0Z",
                "M11.25 12V7.8a.75.75 0 0 1 .75-.75H16.05C16.16 7.7 16.6 8.28 17.5 8.55H12.75V12Z M8.85 18.4a.65.65 0 1 0 1.3 0 .65.65 0 1 0-1.3 0ZM14 18.5a.5.5 0 1 0 1 0 .5.5 0 1 0-1 0ZM10.1 14.3a.5.5 0 1 0 1 0 .5.5 0 1 0-1 0ZM12.95 14.1a.45.45 0 1 0 .9 0 .45.45 0 1 0-.9 0Z",
                string.concat(flame, " M4.6 16.3c1.2-.5 2.5-.5 3.7 0s2.5.5 3.7 0 2.5.5 3.7 0 2.4.5 3.7 0"),
                true,
                false
            );
        }
        if (id == 6) {
            // Waste-to-energy: charged battery with a lightning bolt.
            return Glyph(
                "",
                "M5.3 7H13V17H5.3A2.3 2.3 0 0 1 3 14.8V9.3A2.3 2.3 0 0 1 5.3 7Z",
                "M5.3 7H16.5a2.3 2.3 0 0 1 2.3 2.3v5.5A2.3 2.3 0 0 1 16.5 17H5.3A2.3 2.3 0 0 1 3 14.8V9.3A2.3 2.3 0 0 1 5.3 7Z",
                "M19.7 10.3h.1a.2.2 0 0 1 .2.2v3.1a.2.2 0 0 1-.2.2h-.1a.2.2 0 0 1-.2-.2V10.5a.2.2 0 0 1 .2-.2Zm-7.3-.9-3.1 3.2h2l-.7 2 3.1-3.1h-2Z",
                "",
                false,
                false
            );
        }
        if (id == 7) {
            // Plasma gasification: electrified flame with a lightning core kept clear of its outline.
            return Glyph(FLAME, "", "", "M13.5 11.3 10.6 15.4h1.9l-.8 3.4 3.1-4.2H12.9Z", "", false, false);
        }
        // Undefined and unknown methods: waste bin.
        return Glyph(
            "M6 6.8H18l-.9 12.4c-.1.8-.7 1.4-1.5 1.4H8.5c-.8 0-1.4-.6-1.5-1.3Z",
            "",
            "M4.5 6.8h15m-10 0V5.3c0-.5.4-1 1-1h3c.6 0 1 .5 1 1V6.8M10 10.5v6.3m4-6.3v6.3",
            "",
            "",
            false,
            false
        );
    }

    /// @dev Composting (recycle type 1, disposal method 4): soil heap with a continuous filled sprout.
    function _compost() private pure returns (Glyph memory) {
        return Glyph(
            "M4.5 20.5c1-3.7 4-6 7.5-6s6.5 2.3 7.5 6Z",
            "",
            "",
            "M11.25 14.5V11.3C9.2 11.2 7.6 10 7.3 7.5C9.4 7.3 11.2 8.2 12 9.8C12.1 6.8 14.1 5.1 16.8 5.1C16.7 7.6 15.3 9.6 12.75 9.5V14.5Z",
            "",
            true,
            false
        );
    }

    /// @dev Incineration (recycle type 2, disposal method 2): plain tinted flame.
    function _flame() private pure returns (Glyph memory) {
        return Glyph(FLAME, "", "", "", "", false, false);
    }
}
