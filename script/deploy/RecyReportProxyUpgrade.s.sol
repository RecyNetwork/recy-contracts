// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyReport.sol";
import "../config/ConfigManager.s.sol";

/**
 * @title UpgradeProxy
 * @notice Script to upgrade a deployed proxy to a new implementation
 *
 * Usage Examples:
 *
 * Upgrade a specific proxy:
 * forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade \
 *   --sig "upgradeProxy(address,address)" <PROXY_ADDRESS> <NEW_IMPLEMENTATION_ADDRESS> \
 *   --rpc-url alfajores --account deployer --broadcast
 *
 * Upgrade all proxies to new implementation:
 * forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade \
 *   --sig "upgradeAllProxies(address)" <NEW_IMPLEMENTATION_ADDRESS> \
 *   --rpc-url alfajores --account deployer --broadcast
 *
 * Get current implementation of a proxy:
 * forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade \
 *   --sig "getCurrentImplementation(address)" <PROXY_ADDRESS> \
 *   --rpc-url alfajores
 */
contract RecyReportProxyUpgrade is Script, ConfigManager {
    RecyReportFactory factory;

    function setUp() public {
        // Get the current chain ID
        uint256 chainId = block.chainid;

        // Get network config using ConfigManager
        NetworkConfig memory config = getNetworkConfig(chainId);

        // Ensure factory address is not zero
        require(config.factory != address(0), "Factory address not found in config");

        factory = RecyReportFactory(config.factory);

        console.log("Using factory address from config:", config.factory);
        console.log("Network:", config.name);
    }

    /**
     * @notice Upgrade a specific proxy to a new implementation
     * @param proxy The proxy contract address to upgrade
     * @param newImplementation The new implementation contract address
     */
    function upgradeProxy(address proxy, address newImplementation) public {
        require(proxy != address(0), "Invalid proxy address");
        require(newImplementation != address(0), "Invalid implementation address");

        vm.startBroadcast();

        console.log("=== Upgrading Proxy Implementation ===");
        console.log("Proxy:", proxy);
        console.log("New Implementation:", newImplementation);

        // Get current implementation for comparison
        address currentImpl = _getCurrentImplementation(proxy);
        console.log("Current Implementation:", currentImpl);

        if (currentImpl == newImplementation) {
            console.log("WARNING: Proxy already uses this implementation");
            vm.stopBroadcast();
            return;
        }

        // Perform the upgrade via the factory (which has DEFAULT_ADMIN_ROLE)
        factory.upgradeProxy(proxy, newImplementation);

        // Verify the upgrade
        address newImpl = _getCurrentImplementation(proxy);
        require(newImpl == newImplementation, "Upgrade failed - implementation not updated");

        console.log("SUCCESS: Proxy upgraded successfully!");
        console.log("New Implementation:", newImpl);

        vm.stopBroadcast();
    }

    /**
     * @notice Upgrade all deployed proxies to a new implementation
     * @param newImplementation The new implementation contract address
     */
    function upgradeAllProxies(address newImplementation) public {
        require(newImplementation != address(0), "Invalid implementation address");

        vm.startBroadcast();

        console.log("=== Upgrading All Proxies ===");
        console.log("New Implementation:", newImplementation);

        // Get all deployed proxies
        uint256 pageSize = 50; // Process in batches
        uint256 page = 0;
        uint256 totalUpgraded = 0;

        while (true) {
            (address[] memory proxies,) = factory.getDeployedProxiesPaginated(page, pageSize);

            if (proxies.length == 0) break;

            console.log("Processing page:", page);
            console.log("Found proxies:", proxies.length);

            for (uint256 i = 0; i < proxies.length; i++) {
                address proxy = proxies[i];
                address currentImpl = _getCurrentImplementation(proxy);

                if (currentImpl != newImplementation) {
                    console.log("Upgrading proxy:", proxy);
                    factory.upgradeProxy(proxy, newImplementation);
                    totalUpgraded++;
                } else {
                    console.log("Proxy already up to date:", proxy);
                }
            }

            if (proxies.length < pageSize) break;
            page++;
        }

        console.log("SUCCESS: Upgrade complete!");
        console.log("Total proxies upgraded:", totalUpgraded);

        vm.stopBroadcast();
    }

    /**
     * @notice Get the current implementation address of a proxy
     * @param proxy The proxy contract address
     */
    function getCurrentImplementation(address proxy) public view {
        require(proxy != address(0), "Invalid proxy address");

        address implementation = _getCurrentImplementation(proxy);

        console.log("=== Proxy Implementation Info ===");
        console.log("Proxy:", proxy);
        console.log("Current Implementation:", implementation);

        // Check if this is a known implementation from config
        uint256 chainId = block.chainid;
        NetworkConfig memory config = getNetworkConfig(chainId);

        if (implementation == config.reportImplementation) {
            console.log("Status: Using current implementation from config");
        } else {
            console.log("Status: Using different implementation (possibly upgraded)");
        }
    }

    /**
     * @notice List all proxies and their current implementations
     */
    function listAllProxiesWithImplementations() public view {
        console.log("=== All Deployed Proxies ===");

        uint256 pageSize = 50;
        uint256 page = 0;

        while (true) {
            (address[] memory proxies,) = factory.getDeployedProxiesPaginated(page, pageSize);

            if (proxies.length == 0) break;

            console.log("Page:", page);
            console.log("Proxies found:", proxies.length);

            for (uint256 i = 0; i < proxies.length; i++) {
                address proxy = proxies[i];
                address implementation = _getCurrentImplementation(proxy);

                console.log("  Proxy", page * pageSize + i + 1, ":", proxy);
                console.log("    Implementation:", implementation);
            }

            if (proxies.length < pageSize) break;
            page++;
        }
    }

    /**
     * @notice Deploy a new implementation contract
     * @dev This deploys a new RecyReport implementation that can be used for upgrades
     */
    function deployNewImplementation() public {
        vm.startBroadcast();

        console.log("=== Deploying New Implementation ===");

        // Deploy new implementation
        RecyReport newImplementation = new RecyReport();

        console.log("SUCCESS: New implementation deployed at:", address(newImplementation));
        console.log("Use this address to upgrade proxies");

        vm.stopBroadcast();
    }

    /**
     * @notice Internal function to get the current implementation of a proxy
     * @param proxy The proxy contract address
     * @return The current implementation address
     */
    function _getCurrentImplementation(address proxy) internal view returns (address) {
        // Use the EIP-1967 standard storage slot for implementation
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        bytes32 implementationBytes = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implementationBytes)));
    }

    /**
     * @notice Check if a proxy needs upgrading by comparing with config
     * @param proxy The proxy contract address
     */
    function checkIfUpgradeNeeded(address proxy) public view {
        require(proxy != address(0), "Invalid proxy address");

        uint256 chainId = block.chainid;
        NetworkConfig memory config = getNetworkConfig(chainId);

        address currentImpl = _getCurrentImplementation(proxy);
        address configImpl = config.reportImplementation;

        console.log("=== Upgrade Check ===");
        console.log("Proxy:", proxy);
        console.log("Current Implementation:", currentImpl);
        console.log("Config Implementation:", configImpl);

        if (currentImpl == configImpl) {
            console.log("Status: UP TO DATE");
        } else {
            console.log("Status: UPGRADE NEEDED");
        }
    }
}
