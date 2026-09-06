// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyReport} from "../../src/RecyReport.sol";
import {RecyReportFactoryV2} from "../../src/RecyReportFactoryV2.sol";
import {RecyToken} from "../../src/RecyToken.sol";
import {ConfigManager} from "../config/ConfigManager.s.sol";
import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RecyReportProxyDeploy
 * @notice Deploys a fresh configured RecyReport proxy through RecyReportFactoryV2
 * @dev The `proxy` environment variable selects the config object (default: "default").
 *      This entry point never adopts or reuses an existing config slot or factory name.
 */
contract RecyReportProxyDeploy is Script, ConfigManager {
    function run() public {
        uint256 chainId = block.chainid;
        string memory proxyKey = vm.envOr("proxy", string("default"));
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, proxyKey);

        require(networkConfig.factory != address(0), "factory is not configured");
        require(networkConfig.factory.code.length != 0, "factory has no code");
        RecyReportFactoryV2 factory = RecyReportFactoryV2(networkConfig.factory);

        _assertFreshProxyPlan(factory, networkConfig, proxyConfig);

        address broadcaster = _broadcastSender();
        require(broadcaster == networkConfig.tokenOwner, "broadcaster is not the configured token owner");

        console.log("=== Deploying RecyReport proxy through RecyReportFactoryV2 ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", networkConfig.name);
        console.log("Proxy config key:", proxyKey);
        console.log("Proxy name:", proxyConfig.name);
        console.log("Proxy symbol:", proxyConfig.symbol);
        console.log("Factory:", address(factory));
        console.log("Factory owner:", factory.owner());
        console.log("Implementation:", factory.implementation());
        console.log("Data contract:", factory.dataContract());

        vm.startBroadcast();
        address proxyAddress = factory.deployProxy(
            proxyConfig.name,
            proxyConfig.symbol,
            networkConfig.token,
            networkConfig.protocol,
            proxyConfig.unlockDelay,
            proxyConfig.shareRecycler,
            proxyConfig.shareValidator,
            proxyConfig.shareGenerator,
            proxyConfig.shareProtocol
        );
        vm.stopBroadcast();

        RecyReport deployedProxy = RecyReport(proxyAddress);
        _assertDeployedProxy(factory, deployedProxy, networkConfig, proxyConfig);

        console.log("=== Deployment Results ===");
        console.log("RecyReport proxy deployed to:", proxyAddress);
        console.log("Proxy name:", deployedProxy.name());
        console.log("Proxy symbol:", deployedProxy.symbol());
        console.log("Unlock delay:", deployedProxy.unlockDelay(), "seconds");
        console.log("Recycler share:", deployedProxy.shareRecycler(), "%");
        console.log("Total factory proxies:", factory.getDeployedProxiesCount());
        console.log("Record the proxy address in the selected config entry before running ManageRoles.");
    }

    function _assertFreshProxyPlan(
        RecyReportFactoryV2 factory,
        NetworkConfig memory networkConfig,
        ProxyConfig memory proxyConfig
    ) private view {
        require(networkConfig.issuanceChainId != 0, "issuance chain is not configured");
        require(block.chainid == networkConfig.issuanceChainId, "report proxy must deploy on the issuance chain");
        require(networkConfig.tokenOwner != address(0), "token owner is not configured");
        require(networkConfig.protocol != address(0), "protocol address is not configured");

        require(networkConfig.token != address(0), "token is not configured");
        require(networkConfig.token.code.length != 0, "token has no code");
        RecyToken token = RecyToken(networkConfig.token);
        require(token.issuanceChainId() == networkConfig.issuanceChainId, "token issuance chain mismatch");
        require(token.owner() == networkConfig.tokenOwner, "token owner mismatch");

        require(networkConfig.reportImplementation != address(0), "report implementation is not configured");
        require(networkConfig.reportImplementation.code.length != 0, "report implementation has no code");
        require(networkConfig.reportData != address(0), "report data is not configured");
        require(networkConfig.reportData.code.length != 0, "report data has no code");
        require(factory.implementation() == networkConfig.reportImplementation, "factory implementation is not blessed");
        require(factory.dataContract() == networkConfig.reportData, "factory data contract is not blessed");
        require(factory.owner() == networkConfig.tokenOwner, "factory owner mismatch");

        require(bytes(proxyConfig.name).length != 0, "proxy name is not configured");
        require(bytes(proxyConfig.name).length <= factory.MAX_PROXY_NAME_LENGTH(), "proxy name is too long");
        require(bytes(proxyConfig.symbol).length != 0, "proxy symbol is not configured");
        require(proxyConfig.proxy == address(0), "proxy is already configured");
        require(factory.proxyByName(proxyConfig.name) == address(0), "proxy name is already registered");
    }

    function _assertDeployedProxy(
        RecyReportFactoryV2 factory,
        RecyReport deployedProxy,
        NetworkConfig memory networkConfig,
        ProxyConfig memory proxyConfig
    ) private view {
        address proxyAddress = address(deployedProxy);
        require(proxyAddress.code.length != 0, "deployed proxy has no code");
        require(factory.isDeployedProxy(proxyAddress), "factory did not register deployed proxy");
        require(factory.proxyByName(proxyConfig.name) == proxyAddress, "factory name mapping mismatch");
        require(
            keccak256(bytes(deployedProxy.name())) == keccak256(bytes(proxyConfig.name)), "deployed proxy name mismatch"
        );
        require(
            keccak256(bytes(deployedProxy.symbol())) == keccak256(bytes(proxyConfig.symbol)),
            "deployed proxy symbol mismatch"
        );
        require(address(deployedProxy.token()) == networkConfig.token, "deployed proxy token mismatch");
        require(deployedProxy.protocolAddress() == networkConfig.protocol, "deployed proxy protocol mismatch");
        require(deployedProxy.unlockDelay() == proxyConfig.unlockDelay, "deployed proxy unlock delay mismatch");
        require(deployedProxy.shareRecycler() == proxyConfig.shareRecycler, "deployed proxy recycler share mismatch");
        require(deployedProxy.shareValidator() == proxyConfig.shareValidator, "deployed proxy validator share mismatch");
        require(deployedProxy.shareGenerator() == proxyConfig.shareGenerator, "deployed proxy generator share mismatch");
        require(deployedProxy.shareProtocol() == proxyConfig.shareProtocol, "deployed proxy protocol share mismatch");
        require(factory.hasAdminRole(proxyAddress, address(factory)), "factory lacks proxy admin role");
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
