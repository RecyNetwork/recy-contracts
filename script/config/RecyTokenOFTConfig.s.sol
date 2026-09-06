// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {stdJson} from "forge-std/StdJson.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ConfigManager} from "./ConfigManager.s.sol";

contract RecyTokenOFTConfig is ConfigManager {
    using stdJson for string;
    using SafeCast for uint256;

    uint256 internal constant REQUIRED_DVN_COUNT = 2;

    struct OFTConfig {
        string rpcAlias;
        uint32 eid;
        address sendLibrary;
        address receiveLibrary;
        address executor;
        uint32 maxMessageSize;
        address[] requiredDVNs;
        uint64 confirmations;
        uint128 lzReceiveGas;
        uint256[] peerChainIds;
    }

    function getOFTChainIds() public view returns (uint256[] memory chainIds) {
        string memory json = vm.readFile(CONFIG_PATH);
        string[] memory rootKeys = vm.parseJsonKeys(json, "$");
        uint256 count;

        for (uint256 i; i < rootKeys.length; ++i) {
            if (json.keyExists(string.concat(".", rootKeys[i], ".oft"))) ++count;
        }
        require(count != 0, "no OFT networks configured");

        chainIds = new uint256[](count);
        uint256 index;
        for (uint256 i; i < rootKeys.length; ++i) {
            if (json.keyExists(string.concat(".", rootKeys[i], ".oft"))) {
                chainIds[index++] = vm.parseUint(rootKeys[i]);
            }
        }

        _sortChainIds(chainIds);
        _validateOFTNetworkSet(json, chainIds);
    }

    function getOFTConfig(uint256 chainId) public view returns (OFTConfig memory config) {
        string memory json = vm.readFile(CONFIG_PATH);
        config = _readOFTConfig(json, chainId);
    }

    function _readOFTConfig(string memory json, uint256 chainId) private pure returns (OFTConfig memory config) {
        string memory prefix = string.concat(".", vm.toString(chainId), ".oft.");

        config.rpcAlias = json.readString(string.concat(prefix, "rpcAlias"));
        config.eid = json.readUint(string.concat(prefix, "eid")).toUint32();
        config.sendLibrary = json.readAddress(string.concat(prefix, "sendLibrary"));
        config.receiveLibrary = json.readAddress(string.concat(prefix, "receiveLibrary"));
        config.executor = json.readAddress(string.concat(prefix, "executor"));
        config.maxMessageSize = json.readUint(string.concat(prefix, "maxMessageSize")).toUint32();
        config.requiredDVNs = json.readAddressArray(string.concat(prefix, "requiredDVNs"));
        config.confirmations = json.readUint(string.concat(prefix, "confirmations")).toUint64();
        config.lzReceiveGas = json.readUint(string.concat(prefix, "lzReceiveGas")).toUint128();
        config.peerChainIds = json.readUintArray(string.concat(prefix, "peerChainIds"));

        _validateOFTConfig(chainId, config);
    }

    function _validateOFTConfig(uint256 chainId, OFTConfig memory config) internal pure {
        require(bytes(config.rpcAlias).length != 0, "OFT RPC alias is empty");
        require(config.eid != 0, "OFT eid is zero");
        require(config.sendLibrary != address(0), "OFT send library is zero");
        require(config.receiveLibrary != address(0), "OFT receive library is zero");
        require(config.sendLibrary != config.receiveLibrary, "OFT libraries must differ");
        require(config.executor != address(0), "OFT executor is zero");
        require(config.maxMessageSize != 0, "OFT max message size is zero");
        require(
            config.confirmations != 0 && config.confirmations != type(uint64).max, "OFT confirmations must be explicit"
        );
        require(config.lzReceiveGas != 0, "OFT receive gas is zero");
        require(config.requiredDVNs.length == REQUIRED_DVN_COUNT, "OFT requires exactly two DVNs");
        require(config.peerChainIds.length != 0, "OFT requires at least one peer chain");

        address previous;
        for (uint256 i; i < config.requiredDVNs.length; ++i) {
            address dvn = config.requiredDVNs[i];
            require(dvn > previous, "OFT DVNs must be nonzero and sorted");
            previous = dvn;
        }

        for (uint256 i; i < config.peerChainIds.length; ++i) {
            uint256 peerChainId = config.peerChainIds[i];
            require(peerChainId != 0, "OFT peer chain is zero");
            require(peerChainId != chainId, "OFT cannot peer with itself");
            for (uint256 j; j < i; ++j) {
                require(config.peerChainIds[j] != peerChainId, "OFT peer chain is duplicated");
            }
        }
    }

    function _validateOFTNetworkSet(string memory json, uint256[] memory chainIds) private pure {
        OFTConfig[] memory configs = new OFTConfig[](chainIds.length);
        address sharedOwner;
        uint256 sharedIssuanceChainId;

        for (uint256 i; i < chainIds.length; ++i) {
            uint256 chainId = chainIds[i];
            configs[i] = _readOFTConfig(json, chainId);
            string memory prefix = string.concat(".", vm.toString(chainId));
            address owner = json.readAddress(string.concat(prefix, ".addresses.tokenOwner"));
            uint256 issuanceChainId = json.readUint(string.concat(prefix, ".issuanceChainId"));

            require(owner != address(0), "OFT token owner is zero");
            require(issuanceChainId != 0, "OFT issuance chain is zero");
            if (i == 0) {
                sharedOwner = owner;
                sharedIssuanceChainId = issuanceChainId;
            } else {
                require(owner == sharedOwner, "OFT token owners differ");
                require(issuanceChainId == sharedIssuanceChainId, "OFT issuance chain IDs differ");
            }

            for (uint256 j; j < i; ++j) {
                require(configs[j].eid != configs[i].eid, "OFT EIDs must be unique");
            }
        }

        for (uint256 i; i < chainIds.length; ++i) {
            for (uint256 j; j < configs[i].peerChainIds.length; ++j) {
                uint256 peerChainId = configs[i].peerChainIds[j];
                (bool selected, uint256 peerIndex) = _findChainId(chainIds, peerChainId);
                require(selected, "OFT peer chain is not configured");
                require(_hasPeer(configs[peerIndex], chainIds[i]), "OFT peer chain IDs are not reciprocal");
            }
        }
    }

    function _findChainId(uint256[] memory chainIds, uint256 chainId) private pure returns (bool found, uint256 index) {
        for (uint256 i; i < chainIds.length; ++i) {
            if (chainIds[i] == chainId) return (true, i);
        }
    }

    function _hasPeer(OFTConfig memory config, uint256 chainId) private pure returns (bool) {
        for (uint256 i; i < config.peerChainIds.length; ++i) {
            if (config.peerChainIds[i] == chainId) return true;
        }
        return false;
    }

    function _sortChainIds(uint256[] memory chainIds) private pure {
        for (uint256 i = 1; i < chainIds.length; ++i) {
            uint256 chainId = chainIds[i];
            uint256 j = i;
            while (j != 0 && chainIds[j - 1] > chainId) {
                chainIds[j] = chainIds[j - 1];
                --j;
            }
            chainIds[j] = chainId;
        }
    }
}
