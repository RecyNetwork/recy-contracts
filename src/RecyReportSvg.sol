// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {RecyConstants} from "./lib/RecyConstants.sol";

contract RecyReportSvg is Ownable {
    constructor() Ownable(msg.sender) {}

    string private constant svgFooter = "</svg>";
    string private constant size = "1024";
    string private constant trashcan =
        "M22,5a1,1,0,0,1-1,1H3A1,1,0,0,1,3,4H8V3A1,1,0,0,1,9,2h6a1,1,0,0,1,1,1V4h5A1,1,0,0,1,22,5ZM4.934,21.071,4,8H20l-.934,13.071a1,1,0,0,1-1,.929H5.931A1,1,0,0,1,4.934,21.071ZM15,18a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0Zm-4,0a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0ZM7,18a1,1,0,0,0,2,0V12a1,1,0,0,0-2,0Z";
    string public constant recycle =
        "M548.799,0H0v548.799h548.799V0z M514.652,277.205c0,0,22.054,49.744-17.604,72.174c0,0-15.245,15.263-64.737,10.648l-48.565-84.196l97.137-56.426L514.652,277.205z M344.966,30.585c0,0,25.612,0.737,53.957,46.405l30.857,52.286l21.817-11.781l-22.613,49.431l-22.58,49.453l-53.721-8.219l-53.752-8.225l31.533-17.042L276.361,82.721c0,0-20.738-47.155-58.575-51.971L344.966,30.585z M93.152,454.826L28.682,345.244c0,0-12.335-22.463,12.711-70.006l29.462-53.101l-21.2-12.843l54.085-5.542l54.088-5.53l20.083,50.505l20.125,50.514l-30.646-18.596l-59.033,97.373C108.358,378.014,78.162,419.789,93.152,454.826z M229.619,491.182l-66.977-1.11c0,0-53.957-6.882-52.598-52.448c0,0-5.129-20.958,24.489-60.876l97.177,2.093L229.619,491.182z M213.276,184.576l-95.814-58.654l34.844-57.194c0,0,33.253-43.039,71.843-18.828c0,0,20.686,6.193,40.138,51.935L213.276,184.576z M462.88,465.704c0,0-12.824,22.155-66.472,25.396l-60.695,2.292v24.819l-32.755-43.391l-32.772-43.382l32.772-43.372l32.755-43.382v35.863h113.878c0,0,51.347,4.144,73.562-26.843L462.88,465.704z";
    string private constant coins =
        "M264.4 95.01c-35.6-.06-80.2 11.19-124.2 34.09C96.27 152 61.45 182 41.01 211.3c-20.45 29.2-25.98 56.4-15.92 75.8 10.07 19.3 35.53 30.4 71.22 30.4 35.69.1 80.29-11.2 124.19-34 44-22.9 78.8-53 99.2-82.2 20.5-29.2 25.9-56.4 15.9-75.8-10.1-19.3-35.5-30.49-71.2-30.49zm91.9 70.29c-3.5 15.3-11.1 31-21.8 46.3-22.6 32.3-59.5 63.8-105.7 87.8-46.2 24.1-93.1 36.2-132.5 36.2-18.6 0-35.84-2.8-50.37-8.7l10.59 20.4c10.08 19.4 35.47 30.5 71.18 30.5 35.7 0 80.3-11.2 124.2-34.1 44-22.8 78.8-52.9 99.2-82.2 20.4-29.2 26-56.4 15.9-75.7zm28.8 16.8c11.2 26.7 2.2 59.2-19.2 89.7-18.9 27.1-47.8 53.4-83.6 75.4 11.1 1.2 22.7 1.8 34.5 1.8 49.5 0 94.3-10.6 125.9-27.1 31.7-16.5 49.1-38.1 49.1-59.9 0-21.8-17.4-43.4-49.1-59.9-16.1-8.4-35.7-15.3-57.6-20zm106.7 124.8c-10.2 11.9-24.2 22.4-40.7 31-35 18.2-82.2 29.1-134.3 29.1-21.2 0-41.6-1.8-60.7-5.2-23.2 11.7-46.5 20.4-68.9 26.1 1.2.7 2.4 1.3 3.7 2 31.6 16.5 76.4 27.1 125.9 27.1s94.3-10.6 125.9-27.1c31.7-16.5 49.1-38.1 49.1-59.9z";

    function getSvgHeader(
        uint256 _viewbox,
        string memory bg
    ) private pure returns (string memory) {
        string memory viewbox = Strings.toString(_viewbox);
        return
            string.concat(
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

    function _getSvg(
        string memory path,
        uint256 viewbox,
        string memory color,
        string memory bg
    ) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    getSvgHeader(viewbox, bg),
                    '<path d="',
                    path,
                    '" fill="',
                    color,
                    '" />',
                    svgFooter
                )
            );
    }

    function getTrashcan() external pure returns (string memory) {
        return _getSvg(trashcan, 24, "#6644FF", "#000000");
    }

    function getRecycle() external pure returns (string memory) {
        return _getSvg(recycle, 549, "#000000", "#00FF44");
    }

    function getCoins(uint8 _status) external pure returns (string memory) {
        if (_status == RecyConstants.RECYCLE_REWARDED) {
            return _getSvg(coins, 512, "#808080", "#000000");
        } else {
            return _getSvg(coins, 512, "#FFD700", "#000000");
        }
    }
}
