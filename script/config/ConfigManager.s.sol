// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract ConfigManager is Script {
    using stdJson for string;
    using SafeCast for uint256;

    string constant CONFIG_PATH = "./config/contracts.json";

    struct NetworkConfig {
        string name;
        address token;
        address protocol;
        address tokenOwner;
        address reportImplementation;
        address reportAttributes;
        address reportSvg;
        address reportData;
        address factory;
        address lzEndpoint;
        uint256 issuanceChainId;
    }

    struct ProxyConfig {
        string name;
        string symbol;
        address proxy;
        address[] recyclers;
        address[] recyclerFunds;
        address[] auditors;
        address[] auditorFunds;
        address[] admins;
        address[] emergency;
        uint64 unlockDelay;
        uint8 shareRecycler;
        uint8 shareValidator;
        uint8 shareGenerator;
        uint8 shareProtocol;
    }

    // Multichain scripts deliberately read and select one network config per bounded chain iteration.
    // forge-lint: disable-next-item(calls-loop)
    function getNetworkConfig(uint256 chainId) public view returns (NetworkConfig memory) {
        string memory json = vm.readFile(CONFIG_PATH);
        string memory chainIdStr = vm.toString(chainId);

        NetworkConfig memory config;
        config.name = json.readString(string.concat(".", chainIdStr, ".name"));
        config.issuanceChainId = json.readUint(string.concat(".", chainIdStr, ".issuanceChainId"));

        // Read contract addresses using helper function
        _readContractAddresses(json, chainIdStr, config);

        return config;
    }

    function getProxyConfig(uint256 chainId, string memory proxyName) public view returns (ProxyConfig memory) {
        string memory json = vm.readFile(CONFIG_PATH);
        string memory chainIdStr = vm.toString(chainId);

        ProxyConfig memory config;
        string memory basePath = string.concat(".", chainIdStr, ".proxies.", proxyName);
        config.name = json.readString(string.concat(basePath, ".name"));
        config.symbol = json.readString(string.concat(basePath, ".symbol"));

        // Read proxy address
        _readProxyAddress(json, chainIdStr, proxyName, config);

        // Read settings using helper function
        _readProxySettings(json, chainIdStr, proxyName, config);

        // Read role arrays using helper function
        _readRoleArrays(json, chainIdStr, proxyName, config);

        return config;
    }

    // Each iterated network must parse its own configured addresses; these are read-only cheatcode calls.
    // forge-lint: disable-next-item(calls-loop)
    function _readContractAddresses(string memory json, string memory chainIdStr, NetworkConfig memory config)
        internal
        pure
    {
        // Read token address
        string memory tokenStr = json.readString(string.concat(".", chainIdStr, ".contracts.token"));
        if (_isValidAddress(tokenStr)) {
            config.token = vm.parseAddress(tokenStr);
        }

        // Read protocol address
        string memory protocolStr = json.readString(string.concat(".", chainIdStr, ".addresses.protocol"));
        if (_isValidAddress(protocolStr)) {
            config.protocol = vm.parseAddress(protocolStr);
        }

        // Read token owner address
        string memory tokenOwnerStr = json.readString(string.concat(".", chainIdStr, ".addresses.tokenOwner"));
        if (_isValidAddress(tokenOwnerStr)) {
            config.tokenOwner = vm.parseAddress(tokenOwnerStr);
        }

        // Read reportImplementation address
        string memory reportStr = json.readString(string.concat(".", chainIdStr, ".contracts.reportImplementation"));
        if (_isValidAddress(reportStr)) {
            config.reportImplementation = vm.parseAddress(reportStr);
        }

        // Read reportAttributes address
        string memory reportAttributesStr =
            json.readString(string.concat(".", chainIdStr, ".contracts.reportAttributes"));
        if (_isValidAddress(reportAttributesStr)) {
            config.reportAttributes = vm.parseAddress(reportAttributesStr);
        }

        // Read reportSvg address
        string memory reportSvgStr = json.readString(string.concat(".", chainIdStr, ".contracts.reportSvg"));
        if (_isValidAddress(reportSvgStr)) {
            config.reportSvg = vm.parseAddress(reportSvgStr);
        }

        // Read reportData address
        string memory reportDataStr = json.readString(string.concat(".", chainIdStr, ".contracts.reportData"));
        if (_isValidAddress(reportDataStr)) {
            config.reportData = vm.parseAddress(reportDataStr);
        }

        // Read factory address
        string memory factoryStr = json.readString(string.concat(".", chainIdStr, ".contracts.factory"));
        if (_isValidAddress(factoryStr)) {
            config.factory = vm.parseAddress(factoryStr);
        }

        // Read LayerZero endpoint address
        string memory lzEndpointStr = json.readString(string.concat(".", chainIdStr, ".addresses.lzEndpoint"));
        if (_isValidAddress(lzEndpointStr)) {
            config.lzEndpoint = vm.parseAddress(lzEndpointStr);
        }
    }

    function _readProxyAddress(
        string memory json,
        string memory chainIdStr,
        string memory proxyName,
        ProxyConfig memory config
    ) internal pure {
        string memory proxyStr = json.readString(string.concat(".", chainIdStr, ".proxies.", proxyName, ".address"));
        if (_isValidAddress(proxyStr)) {
            config.proxy = vm.parseAddress(proxyStr);
        }
    }

    function _readProxySettings(
        string memory json,
        string memory chainIdStr,
        string memory proxyName,
        ProxyConfig memory config
    ) internal pure {
        string memory basePath = string.concat(".", chainIdStr, ".proxies.", proxyName, ".settings");

        config.unlockDelay = json.readUint(string.concat(basePath, ".unlockDelay")).toUint64();
        config.shareRecycler = json.readUint(string.concat(basePath, ".shareRecycler")).toUint8();
        config.shareValidator = json.readUint(string.concat(basePath, ".shareValidator")).toUint8();
        config.shareGenerator = json.readUint(string.concat(basePath, ".shareGenerator")).toUint8();
        config.shareProtocol = json.readUint(string.concat(basePath, ".shareProtocol")).toUint8();
    }

    function _readRoleArrays(
        string memory json,
        string memory chainIdStr,
        string memory proxyName,
        ProxyConfig memory config
    ) internal pure {
        string memory basePath = string.concat(".", chainIdStr, ".proxies.", proxyName);

        // Read recyclers array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".recyclers")) returns (
            address[] memory recyclerAddresses
        ) {
            config.recyclers = recyclerAddresses;
        } catch {
            config.recyclers = new address[](0);
        }
        // Read recyclerFunds array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".recyclerFunds")) returns (
            address[] memory recyclerFundAddresses
        ) {
            config.recyclerFunds = recyclerFundAddresses;
        } catch {
            config.recyclerFunds = new address[](0);
        }
        // Read auditors array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".auditors")) returns (
            address[] memory auditorAddresses
        ) {
            config.auditors = auditorAddresses;
        } catch {
            config.auditors = new address[](0);
        }
        // Read auditorFunds array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".auditorFunds")) returns (
            address[] memory auditorFundAddresses
        ) {
            config.auditorFunds = auditorFundAddresses;
        } catch {
            config.auditorFunds = new address[](0);
        }
        // Read admins array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".admins")) returns (
            address[] memory adminAddresses
        ) {
            config.admins = adminAddresses;
        } catch {
            config.admins = new address[](0);
        }
        // Read emergency array
        try vm.parseJsonAddressArray(json, string.concat(basePath, ".emergency")) returns (
            address[] memory emergencyAddresses
        ) {
            config.emergency = emergencyAddresses;
        } catch {
            config.emergency = new address[](0);
        }
    }

    function _isValidAddress(string memory addressStr) internal pure returns (bool) {
        return
            bytes(addressStr).length > 0
                && keccak256(abi.encodePacked(addressStr)) != keccak256(abi.encodePacked("null"));
    }
}
