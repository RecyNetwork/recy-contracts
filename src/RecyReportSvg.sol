// SPDX-License-Identifier: MIT

pragma solidity 0.8.36;

import {RecyReportIcons} from "./RecyReportIcons.sol";
import {RecyConstants} from "./lib/RecyConstants.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RecyReportSvg is Ownable {
    /// @notice Glyph catalogue for the classification slots, deployed with this renderer so its
    ///         path data does not count against the renderer's EIP-170 code-size limit.
    RecyReportIcons public immutable icons;

    constructor() Ownable(msg.sender) {
        icons = new RecyReportIcons();
    }

    string private constant svgFooter = "</svg>";
    string private constant size = "1024";
    string private constant trashcan =
        "M22,5a1,1,0,0,1-1,1H3A1,1,0,0,1,3,4H8V3A1,1,0,0,1,9,2h6a1,1,0,0,1,1,1V4h5A1,1,0,0,1,22,5ZM4.934,21.071,4,8H20l-.934,13.071a1,1,0,0,1-1,.929H5.931A1,1,0,0,1,4.934,21.071ZM15,18a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0Zm-4,0a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0ZM7,18a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0Z";
    string public constant recycle =
        "M548.799,0H0v548.799h548.799V0z M514.652,277.205c0,0,22.054,49.744-17.604,72.174c0,0-15.245,15.263-64.737,10.648l-48.565-84.196l97.137-56.426L514.652,277.205z M344.966,30.585c0,0,25.612,0.737,53.957,46.405l30.857,52.286l21.817-11.781l-22.613,49.431l-22.58,49.453l-53.721-8.219l-53.752-8.225l31.533-17.042L276.361,82.721c0,0-20.738-47.155-58.575-51.971L344.966,30.585z M93.152,454.826L28.682,345.244c0,0-12.335-22.463,12.711-70.006l29.462-53.101l-21.2-12.843l54.085-5.542l54.088-5.53l20.083,50.505l20.125,50.514l-30.646-18.596l-59.033,97.373C108.358,378.014,78.162,419.789,93.152,454.826z M229.619,491.182l-66.977-1.11c0,0-53.957-6.882-52.598-52.448c0,0-5.129-20.958,24.489-60.876l97.177,2.093L229.619,491.182z M213.276,184.576l-95.814-58.654l34.844-57.194c0,0,33.253-43.039,71.843-18.828c0,0,20.686,6.193,40.138,51.935L213.276,184.576z M462.88,465.704c0,0-12.824,22.155-66.472,25.396l-60.695,2.292v24.819l-32.755-43.391l-32.772-43.382l32.772-43.372l32.755-43.382v35.863h113.878c0,0,51.347,4.144,73.562-26.843L462.88,465.704z";
    string private constant coins =
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 29.2-25.98 56.4-15.92 75.8 10.07 19.3 35.53 30.4 71.22 30.4 35.69.1 80.29-11.2 124.19-34 44-22.9 78.8-53 99.2-82.2 20.5-29.2 25.9-56.4 15.9-75.8-10.1-19.3-35.5-30.49-71.2-30.49zm91.9 70.29c-3.5 15.3-11.1 31-21.8 46.3-22.6 32.3-59.5 63.8-105.7 87.8-46.2 24.1-93.1 36.2-132.5 36.2-18.6 0-35.84-2.8-50.37-8.7l10.59 20.4c10.08 19.4 35.47 30.5 71.18 30.5 35.7 0 80.3-11.2 124.2-34.1 44-22.8 78.8-52.9 99.2-82.2 20.4-29.2 26-56.4 15.9-75.7zm28.8 16.8c11.2 26.7 2.2 59.2-19.2 89.7-18.9 27.1-47.8 53.4-83.6 75.4 11.1 1.2 22.7 1.8 34.5 1.8 49.5 0 94.3-10.6 125.9-27.1 31.7-16.5 49.1-38.1 49.1-59.9 0-21.8-17.4-43.4-49.1-59.9-16.1-8.4-35.7-15.3-57.6-20zm106.7 124.8c-10.2 11.9-24.2 22.4-40.7 31-35 18.2-82.2 29.1-134.3 29.1-21.2 0-41.6-1.8-60.7-5.2-23.2 11.7-46.5 20.4-68.9 26.1 1.2.7 2.4 1.3 3.7 2 31.6 16.5 76.4 27.1 125.9 27.1s94.3-10.6 125.9-27.1c31.7-16.5 49.1-38.1 49.1-59.9z";
    string private constant flag =
        "M101 37A15 15 0 1 1 71 37A15 15 0 1 1 101 37ZM83 51L97 48 183 365 169 365ZM114 59C161 48 207 53 255 87C327 134 364 163 436 89C416 154 389 198 348 198C295 200 239 164 190 170C174 172 159 181 149 191Z";
    string private constant rejectedStamp =
        "M101 235.8 A160 160 0 0 1 368 81.7 L356.2 88.5 A147 147 0 0 0 112.8 229 Z M411 156.2 A160 160 0 0 1 144 310.3 L155.8 303.5 A147 147 0 0 0 399.2 163 Z M144.9 210.5 A112 112 0 0 1 324.1 107.1 L318.4 110.3 A106 106 0 0 0 150.6 207.2 Z M367.1 181.5 A112 112 0 0 1 187.9 284.9 L193.6 281.7 A106 106 0 0 0 361.4 184.8 Z M126.5 173.2 L129.6 180.4 L137.4 181.1 L131.5 186.3 L133.3 194 L126.5 190 L119.7 194 L121.5 186.3 L115.6 181.1 L123.4 180.4 Z M146.4 114.7 L149.5 121.9 L157.3 122.6 L151.4 127.8 L153.1 135.5 L146.4 131.5 L139.6 135.5 L141.3 127.8 L135.4 122.6 L143.2 121.9 Z M191 71.9 L194.1 79.1 L201.9 79.9 L196 85.1 L197.8 92.7 L191 88.7 L184.2 92.7 L186 85.1 L180.1 79.9 L187.9 79.1 Z M250.3 54.6 L253.4 61.8 L261.3 62.6 L255.4 67.8 L257.1 75.4 L250.3 71.4 L243.6 75.4 L245.3 67.8 L239.4 62.6 L247.2 61.8 Z M310.9 66.7 L314.1 73.9 L321.9 74.6 L316 79.8 L317.7 87.5 L310.9 83.5 L304.2 87.5 L305.9 79.8 L300 74.6 L307.8 73.9 Z M385.5 195.8 L388.6 203 L396.4 203.8 L390.5 209 L392.3 216.6 L385.5 212.6 L378.7 216.6 L380.5 209 L374.6 203.8 L382.4 203 Z M365.6 254.3 L368.8 261.6 L376.6 262.3 L370.7 267.5 L372.4 275.2 L365.6 271.1 L358.9 275.2 L360.6 267.5 L354.7 262.3 L362.5 261.6 Z M321 297.1 L324.1 304.3 L331.9 305 L326 310.2 L327.8 317.9 L321 313.9 L314.2 317.9 L316 310.2 L310.1 305 L317.9 304.3 Z M261.7 314.4 L264.8 321.6 L272.6 322.3 L266.7 327.5 L268.4 335.2 L261.7 331.2 L254.9 335.2 L256.6 327.5 L250.7 322.3 L258.6 321.6 Z M201.1 302.3 L204.2 309.5 L212 310.3 L206.1 315.5 L207.8 323.1 L201.1 319.1 L194.3 323.1 L196 315.5 L190.1 310.3 L197.9 309.5 Z M65.6 256.3 L403.4 61.3 Q412 56.3 417 64.9 L450 122.1 Q455 130.7 446.4 135.7 L108.6 330.7 Q100 335.7 95 327.1 L62 269.9 Q57 261.3 65.6 256.3 Z M99.8 258.5 L123.8 300 L132.5 295 L123.5 279.4 L129.5 275.9 L148.9 285.5 L159.3 279.5 L136.7 268.3 C141.3 262.3 142.6 254.6 140.1 250.2 C135.6 242.4 128.4 242 119.7 247 Z M113 261.3 L122.5 255.8 C126.8 253.3 130.9 254.4 132.9 257.8 C134.9 261.3 133.3 264.5 129 267 L119.5 272.5 Z M139.6 235.5 L163.6 277 L194 259.5 L189.5 251.7 L168.7 263.7 L163.2 254.2 L179.6 244.7 L175.1 236.9 L158.7 246.4 L153.7 237.8 L174.5 225.8 L170 218 Z M174.3 215.5 L178.8 223.3 L198.7 211.8 L210.2 231.7 C213.2 236.9 212.5 239.6 208.1 242.1 C202.9 245.1 198.8 244 195.5 240.2 L189.2 247.3 C195.4 254.1 203.1 255.4 212.6 249.9 C223 243.9 224.7 234.8 219.2 225.3 L203.7 198.5 Z M208.1 196 L232.1 237.5 L262.4 220 L257.9 212.2 L237.1 224.2 L231.6 214.7 L248 205.2 L243.5 197.4 L227.1 206.9 L222.1 198.3 L242.9 186.3 L238.4 178.5 Z M281.5 165.1 C271.4 161.7 265.6 161.6 259.5 165.1 C249.1 171.1 247.2 183.8 254.7 196.8 C262.2 209.7 274.1 214.4 284.5 208.4 C292.3 203.9 295.5 197.4 295.5 189.4 L284.8 190.9 C285.1 195.4 283.5 198.6 280 200.6 C274 204.1 268.4 200.4 263.4 191.8 C258.4 183.1 258 176.4 264 172.9 C267.5 170.9 271.1 171.1 274.8 173.6 Z M280.8 154 L285.8 162.6 L297.9 155.6 L316.9 188.5 L325.6 183.5 L306.6 150.6 L318.7 143.6 L313.7 135 Z M318 132.5 L342 174 L372.4 156.5 L367.9 148.7 L347.1 160.7 L341.6 151.2 L358 141.7 L353.5 133.9 L337.1 143.4 L332.1 134.8 L352.9 122.8 L348.4 115 Z M352.7 112.5 L376.7 154 L392.3 145 C405.3 137.5 407.7 125.7 400.2 112.8 C392.7 99.8 381.3 96 368.3 103.5 Z M367.2 115.6 L372.4 112.6 C380.2 108.1 386.2 110.5 390.7 118.3 C395.2 126 394.2 132.4 386.4 136.9 L381.2 139.9 Z";

    function getSvgHeader(uint256 _viewbox, string memory bg) private pure returns (string memory) {
        string memory viewbox = Strings.toString(_viewbox);
        return string.concat(
            '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="',
            size,
            '" height="',
            size,
            '" viewBox="0 0 ',
            viewbox,
            " ",
            viewbox,
            '" style="background-color:',
            bg,
            '">'
        );
    }

    function _getSvg(string memory path, uint256 viewbox, string memory color, string memory bg)
        private
        pure
        returns (string memory)
    {
        return string.concat(getSvgHeader(viewbox, bg), '<path d="', path, '" fill="', color, '" />', svgFooter);
    }

    /// @dev Slot tile: dark rounded square outlined in the accent, holding the glyph's layers.
    function _tile(RecyReportIcons.Glyph memory glyph, string memory accent) private pure returns (string memory) {
        string memory tint = string.concat('fill="', accent, '" fill-opacity=".35"');
        return string.concat(
            '<rect x="8" y="8" width="84" height="84" rx="18" fill="#171717" stroke="',
            accent,
            '" stroke-width="2"/><svg x="22" y="22" width="56" height="56" viewBox="0 0 24 24"><g fill="none" stroke="#FFFFFF" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill-rule="evenodd">',
            _layer(glyph.tone, string.concat(tint, ' stroke="none"')),
            _layer(glyph.body, tint),
            _layer(glyph.line, ""),
            _layer(glyph.detail, 'stroke-width="1"'),
            _layer(glyph.solid, glyph.solidFillOnly ? 'fill="#FFFFFF" stroke="none"' : 'fill="#FFFFFF"'),
            "</g></svg>"
        );
    }

    function _layer(string memory d, string memory paint) private pure returns (string memory) {
        return bytes(d).length == 0 ? "" : string.concat('<path d="', d, '" ', paint, "/>");
    }

    function _categorySlot(
        string memory x,
        string memory category,
        uint32 id,
        RecyReportIcons.Glyph memory glyph,
        string memory accent
    ) private pure returns (string memory) {
        return string.concat(
            '<svg class="category-slot" data-category="',
            category,
            '" data-id="',
            Strings.toString(id),
            '" x="',
            x,
            '" y="74%" width="25%" height="24%" viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet">',
            _tile(glyph, accent),
            svgFooter
        );
    }

    /// @dev A slot tile as a standalone 256px image, in the recycle image's green accent.
    function _iconSvg(RecyReportIcons.Glyph memory glyph) private pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 100 100">',
            _tile(glyph, "#00FF44"),
            svgFooter
        );
    }

    function _getSvgWithCategories(
        string memory path,
        uint256 viewbox,
        string memory color,
        string memory bg,
        uint32[4] calldata classifications
    ) private view returns (string memory) {
        string memory accent = viewbox == 549 ? "#00FF44" : color;
        return string.concat(
            getSvgHeader(viewbox, bg),
            '<path d="',
            path,
            '" fill="',
            color,
            '" />',
            _categorySlot("0%", "material", classifications[0], icons.material(classifications[0]), accent),
            _categorySlot("25%", "recycle-type", classifications[1], icons.recycleType(classifications[1]), accent),
            _categorySlot("50%", "recycle-shape", classifications[2], icons.recycleShape(classifications[2]), accent),
            _categorySlot(
                "75%", "disposal-method", classifications[3], icons.disposalMethod(classifications[3]), accent
            ),
            svgFooter
        );
    }

    function getTrashcan() external pure returns (string memory) {
        return _getSvg(trashcan, 24, "#6644FF", "#000000");
    }

    /// @notice Returns the recycle image with material, recycle type, shape and disposal method slots.
    /// @param classifications Catalogue IDs in category order, including undefined IDs.
    function getRecycle(uint32[4] calldata classifications) external view returns (string memory) {
        return _getSvgWithCategories(recycle, 549, "#000000", "#00FF44", classifications);
    }

    /// @notice Returns the post-completion status image with four classification slots in front of the main icon.
    /// @dev Keeps the `getCoins` name for ABI compatibility although flagged and invalidated reports draw no coins.
    /// @param _status Report status: flagged orange flag, invalidated red stamp, rewarded grey coins, else gold coins.
    /// @param classifications Catalogue IDs in material, recycle type, shape, disposal method order.
    function getCoins(uint8 _status, uint32[4] calldata classifications) external view returns (string memory) {
        if (_status == RecyConstants.RECYCLE_REWARDED) {
            return _getSvgWithCategories(coins, 512, "#808080", "#000000", classifications);
        } else if (_status == RecyConstants.RECYCLE_INVALIDATED) {
            return _getSvgWithCategories(rejectedStamp, 512, "#ff0000", "#000000", classifications);
        } else if (_status == RecyConstants.RECYCLE_FLAGGED) {
            return _getSvgWithCategories(flag, 512, "#FF8C00", "#000000", classifications);
        } else {
            return _getSvgWithCategories(coins, 512, "#FFD700", "#000000", classifications);
        }
    }

    /// @notice Standalone SVG of a material slot tile, drawn exactly as on the recycle image.
    /// @dev Zero and unknown IDs render the material fallback glyph.
    function getMaterialIcon(uint32 materialId) external view returns (string memory) {
        return _iconSvg(icons.material(materialId));
    }

    /// @notice Standalone SVG of a recycle-type slot tile, drawn exactly as on the recycle image.
    /// @dev Zero and unknown IDs render the recycle-type fallback glyph.
    function getRecycleTypeIcon(uint32 recycleTypeId) external view returns (string memory) {
        return _iconSvg(icons.recycleType(recycleTypeId));
    }

    /// @notice Standalone SVG of a recycle-shape slot tile, drawn exactly as on the recycle image.
    /// @dev Zero and unknown IDs render the recycle-shape fallback glyph.
    function getRecycleShapeIcon(uint32 recycleShapeId) external view returns (string memory) {
        return _iconSvg(icons.recycleShape(recycleShapeId));
    }

    /// @notice Standalone SVG of a disposal-method slot tile, drawn exactly as on the recycle image.
    /// @dev Zero and unknown IDs render the disposal-method fallback glyph.
    function getDisposalMethodIcon(uint32 disposalMethodId) external view returns (string memory) {
        return _iconSvg(icons.disposalMethod(disposalMethodId));
    }
}
