// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyReportFactoryV2} from "../../src/RecyReportFactoryV2.sol";
import {RecyToken} from "../../src/RecyToken.sol";
import {ConfigManager} from "../config/ConfigManager.s.sol";
import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract RecyReportFactoryDeploy is Script, ConfigManager {
    function run() public {
        uint256 chainId = block.chainid;
        string memory proxyKey = vm.envOr("proxy", string("default"));
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, proxyKey);

        _assertFreshFactoryPlan(networkConfig, proxyConfig);

        address broadcaster = _broadcastSender();
        require(broadcaster == networkConfig.tokenOwner, "broadcaster is not the configured token owner");

        console.log("=== Deploying RecyReportFactoryV2 ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", networkConfig.name);
        console.log("Configured owner:", networkConfig.tokenOwner);
        console.log("Implementation:", networkConfig.reportImplementation);
        console.log("Data contract:", networkConfig.reportData);
        console.log("Proxy config key:", proxyKey);
        console.log("Proxy name:", proxyConfig.name);
        console.log("Proxy symbol:", proxyConfig.symbol);

        vm.startBroadcast();
        RecyReportFactoryV2 factory =
            new RecyReportFactoryV2(networkConfig.reportImplementation, networkConfig.reportData);
        vm.stopBroadcast();

        require(factory.owner() == networkConfig.tokenOwner, "factory owner mismatch");
        require(factory.implementation() == networkConfig.reportImplementation, "factory implementation mismatch");
        require(factory.dataContract() == networkConfig.reportData, "factory data contract mismatch");

        console.log("=== Deployment Results ===");
        console.log("RecyReportFactoryV2 deployed to:", address(factory));
        console.log("Factory owner:", factory.owner());
        console.log("Configured NFT name:", proxyConfig.name);
        console.log("Configured NFT symbol:", proxyConfig.symbol);
        console.log("Unlock delay:", proxyConfig.unlockDelay);
        console.log("Recycler share:", proxyConfig.shareRecycler);
        console.log("Validator share:", proxyConfig.shareValidator);
        console.log("Generator share:", proxyConfig.shareGenerator);
        console.log("Protocol share:", proxyConfig.shareProtocol);
        console.log("Record the factory address in config/contracts.json before running RecyReportProxyDeploy.");
    }

    function _assertFreshFactoryPlan(NetworkConfig memory networkConfig, ProxyConfig memory proxyConfig) private view {
        require(networkConfig.issuanceChainId != 0, "issuance chain is not configured");
        require(block.chainid == networkConfig.issuanceChainId, "report stack must deploy on the issuance chain");
        require(networkConfig.tokenOwner != address(0), "token owner is not configured");
        require(networkConfig.factory == address(0), "factory is already configured");
        require(proxyConfig.proxy == address(0), "proxy is already configured");

        require(networkConfig.reportImplementation != address(0), "report implementation is not configured");
        require(networkConfig.reportImplementation.code.length != 0, "report implementation has no code");
        require(networkConfig.reportData != address(0), "report data is not configured");
        require(networkConfig.reportData.code.length != 0, "report data has no code");
        require(networkConfig.token != address(0), "token is not configured");
        require(networkConfig.token.code.length != 0, "token has no code");

        require(bytes(proxyConfig.name).length != 0, "proxy name is not configured");
        require(bytes(proxyConfig.symbol).length != 0, "proxy symbol is not configured");

        RecyToken token = RecyToken(networkConfig.token);
        require(token.issuanceChainId() == networkConfig.issuanceChainId, "token issuance chain mismatch");
        require(token.owner() == networkConfig.tokenOwner, "token owner mismatch");
    }

    function _broadcastSender() private returns (address broadcaster) {
        vm.startBroadcast();
        // forge-lint: disable-next-line(unused-return)
        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();
        vm.stopBroadcast();

        require(mode == VmSafe.CallerMode.RecurrentBroadcast, "Foundry broadcast signer is unavailable");
        return sender;
    }
}
