// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Outline-only paths on a 24x24 grid; render with no fill, a 1.75 stroke,
///         and round caps and joins. IDs are the existing material, recycle type,
///         recycle shape and disposal method catalogue indices, respectively.
///         Zero and unknown IDs receive a neutral icon specific to their category.
library RecyReportIcons {
    string private constant COMPOST =
        "M4 15h16l-2 5H6l-2-5Z M12 15V9 M12 11c-3 0-5-2-5-5 3 0 5 2 5 5Z M12 10c0-3 2-5 5-5 0 3-2 5-5 5Z";
    string private constant INCINERATION = "M12 4c0 4 6 6 6 10a6 6 0 0 1-12 0c0-3 3-5 4-7 0 3 1 4 2 4 1-2 1-5 0-7Z";

    /// @notice A material glyph; material 13 and all other unknown IDs use a plain package.
    function material(uint32 id) internal pure returns (string memory) {
        if (id == 1) {
            // Plastic: long bottle, distinct neck, cap and two shallow ribs.
            return "M10 4h4v3h-4z M10 7v1l-2 2v8a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2v-8l-2-2V7 M9 13h6 M9 16h6";
        }
        if (id == 2) {
            // Glass: stemmed wineglass with a visible bowl and liquid line.
            return "M6 4h12l-1 7a5 5 0 0 1-10 0L6 4Z M7 9h10 M12 16v4m-4 0h8";
        }
        if (id == 3) {
            // Metal: cylindrical can with an elliptical top and curved base.
            return "M5 5a7 2 0 1 0 14 0 7 2 0 1 0-14 0 M5 5v14a7 2 0 0 0 14 0V5 M9 11h6";
        }
        if (id == 4) {
            return "M6 4h9l4 4v12H6z M15 4v4h4 M9 12h7 M9 15h7 M9 18h5";
        }
        if (id == 5) {
            // E-waste: a monitor with a simple circuit trace on its screen.
            return "M4 5h16v11H4z M9 20h6m-3-4v4 M8 9h3l2 3h3 M8 12h1";
        }
        if (id == 6) {
            return "M19 4C10 4 5 8 5 15a5 5 0 0 0 5 5c7 0 10-8 9-16Z M7 18c2-4 5-7 9-10";
        }
        if (id == 7) {
            return "M8 4h8l4 3-2 4-2-1v10H8V10l-2 1-2-4 4-3Z M9 4a3 3 0 0 0 6 0";
        }
        if (id == 8) {
            return "M12 4 21 20H3L12 4Z M12 10v5 M12 18v.1";
        }
        if (id == 9) {
            return "M9 4h6 M10 4v6L5 18a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2l-5-8V4 M7 15h10";
        }
        if (id == 10) {
            return "M12 4C9 9 7 12 7 15a5 5 0 0 0 10 0c0-3-2-6-5-11Z M8 15c1-1 2-1 4 0s3 1 4 0";
        }
        if (id == 11) {
            return "M4 5h16v14H4z M4 10h16 M4 15h16 M9 5v5 M15 10v5 M9 15v4";
        }
        return "M4 8 12 4 20 8v9l-8 4-8-4V8Z M4 8l8 4 8-4m-8 4v9";
    }

    /// @notice Recycling process (0/unknown: a generic cyclic process).
    function recycleType(uint32 id) internal pure returns (string memory) {
        if (id == 1) return COMPOST;
        if (id == 2) return INCINERATION;
        if (id == 3) {
            // Mechanical recycling: circulation around a four-spoke gear.
            return "M7 9a6 6 0 0 1 10-2 M17 4v3h-3 M17 15a6 6 0 0 1-10 2 M7 20v-3h3 M12 10a2 2 0 1 0 0 4 2 2 0 1 0 0-4 M12 8v2m0 4v2m-4-4h2m4 0h2";
        }
        if (id == 4) {
            // Pyrolysis: heat is contained inside a closed chamber.
            return "M5 6h14v14H5z M8 10h8 M12 13c-1 1-2 2-2 3a2 2 0 0 0 4 0c0-1-1-2-2-3Z M8 4v2m4-2v2m4-2v2";
        }
        if (id == 5) {
            return "M8 4h8l4 4v8l-4 4H8l-4-4V8l4-4Z M8 11h8 M8 14h8 M12 11v3";
        }
        if (id == 6) {
            return "M5 19h14 M7 16c-2-2 2-3 0-5s2-3 0-5 M12 16c-2-2 2-3 0-5s2-3 0-5 M17 16c-2-2 2-3 0-5s2-3 0-5";
        }
        return
            "M5 9a7 7 0 0 1 12-3l2 1 M19 5v2h-2 M19 15a7 7 0 0 1-12 3l-2-1 M5 19v-2h2 M12 10a2 2 0 1 0 0 4 2 2 0 1 0 0-4";
    }

    /// @notice Physical output shape (0/unknown: basic geometric forms).
    function recycleShape(uint32 id) internal pure returns (string memory) {
        if (id == 1) {
            // Four equally sized pellets, with room between outlines.
            return "M10.5 8a2.5 2.5 0 1 0-5 0 2.5 2.5 0 1 0 5 0 M18.5 8a2.5 2.5 0 1 0-5 0 2.5 2.5 0 1 0 5 0 M10.5 16a2.5 2.5 0 1 0-5 0 2.5 2.5 0 1 0 5 0 M18.5 16a2.5 2.5 0 1 0-5 0 2.5 2.5 0 1 0 5 0";
        }
        if (id == 2) {
            return "M4 9 12 5l8 4-8 4-8-4Z M4 9v8l8 4 8-4V9 M12 13v8";
        }
        if (id == 3) {
            // Final product: checked, closed package (not the paper material).
            return "M4 8h16v12H4z M4 8l3-4h10l3 4 M9 14l2 2 4-4";
        }
        if (id == 4) {
            // Fertilizer: granules below a small sprout.
            return "M12 14V8 M12 10c-3 0-5-2-5-5 3 0 5 2 5 5Z M12 9c0-3 2-5 5-5 0 3-2 5-5 5Z M5 19a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0 M10.5 19a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0 M16 19a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0";
        }
        return "M4 18 8 10l4 8H4Z M13 7a3 3 0 1 0 6 0 3 3 0 1 0-6 0 M13 13h7v7h-7z";
    }

    /// @notice Disposal route (0/unknown: a neutral destination tray and arrow).
    function disposalMethod(uint32 id) internal pure returns (string memory) {
        if (id == 1) {
            // Landfill: a layered, terraced earth mound.
            return "M4 20h16l-2-4H6l-2 4Z M6 16l2-4h8l2 4 M8 12l2-4h4l2 4";
        }
        if (id == 2) return INCINERATION;
        if (id == 3) {
            return "M9 5h4a4 4 0 0 1 4 4 M14 7l3 2 2-3 M19 12l1 3a4 4 0 0 1-4 4h-2 M17 16l-3 3 3 2 M10 19H8a4 4 0 0 1-3-6l1-2 M4 14l2-3 3 2";
        }
        if (id == 4) return COMPOST;
        if (id == 5) {
            // Anaerobic digestion: domed, sealed biogas vessel with vent.
            return "M5 10h14v8a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-8Z M7 10a5 5 0 0 1 10 0 M12 5V3h5v3 M9 15a1 1 0 1 0 2 0 1 1 0 1 0-2 0 M14 16a1 1 0 1 0 2 0 1 1 0 1 0-2 0";
        }
        if (id == 6) {
            // Waste-to-energy: generating plant with two stacks and a bolt.
            return "M4 20h16 M6 20V9h12v11 M9 9V5h3v4 M14 9V4h3v5 M12 11l-2 4h3l-1 3 3-5h-3l1-2";
        }
        if (id == 7) {
            // Plasma gasification: bolt between electrodes in a chamber.
            return "M5 5h14v15H5z M8 9h8 M8 17h8 M13 10l-4 5h3l-1 2 4-5h-3l1-2";
        }
        return "M5 17v3h14v-3 M12 4v11m-4-4 4 4 4-4";
    }
}
