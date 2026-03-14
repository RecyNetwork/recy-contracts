// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/RecyReportFactory.sol";
import "./config/ConfigManager.s.sol";

/**
 * @title ManageRoles
 * @notice Example script showing how to use the new role management functions
 */
contract ManageRoles is Script, ConfigManager {
    RecyReportFactory factory;
    RecyReport proxy;

    function setUp() public {
        // Get the current chain ID
        uint256 chainId = block.chainid;

        // Get network config using ConfigManager
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, "default");

        // Ensure factory address is not zero
        require(networkConfig.factory != address(0), "Factory address not found in config");

        factory = RecyReportFactory(networkConfig.factory);

        proxy = RecyReport(proxyConfig.proxy);

        console.log("Using factory address from config:", networkConfig.factory);
        console.log("Network:", networkConfig.name);
    }

    /**
     * @notice Grant auditor role to an address on a specific proxy
     * @param auditor The address to grant auditor role to
     */
    function grantAuditor(address auditor) public {
        vm.startBroadcast();

        console.log("Granting auditor role to:", auditor);
        console.log("On proxy:", address(proxy));

        factory.grantAuditorRole(address(proxy), auditor);

        console.log("Auditor role granted successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Grant recycler role to an address on a specific proxy
     * @param recycler The address to grant recycler role to
     */
    function grantRecycler(address recycler) public {
        vm.startBroadcast();

        console.log("Granting recycler role to:", recycler);
        console.log("On proxy:", address(proxy));

        factory.grantRecyclerRole(address(proxy), recycler);

        console.log("Recycler role granted successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Revoke auditor role from an address on a specific proxy
     * @param auditor The address to revoke auditor role from
     */
    function revokeAuditor(address auditor) public {
        vm.startBroadcast();

        console.log("Revoking auditor role from:", auditor);
        console.log("On proxy:", address(proxy));

        factory.revokeAuditorRole(address(proxy), auditor);

        console.log("Auditor role revoked successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Revoke recycler role from an address on a specific proxy
     * @param recycler The address to revoke recycler role from
     */
    function revokeRecycler(address recycler) public {
        vm.startBroadcast();

        console.log("Revoking recycler role from:", recycler);
        console.log("On proxy:", address(proxy));

        factory.revokeRecyclerRole(address(proxy), recycler);

        console.log("Recycler role revoked successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Grant emergency role to an address on a specific proxy
     * @param emergency The address to grant emergency role to
     */
    function grantEmergency(address emergency) public {
        vm.startBroadcast();

        console.log("Granting emergency role to:", emergency);
        console.log("On proxy:", address(proxy));

        factory.grantEmergencyRole(address(proxy), emergency);

        console.log("Emergency role granted successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Revoke emergency role from an address on a specific proxy
     * @param emergency The address to revoke emergency role from
     */
    function revokeEmergency(address emergency) public {
        vm.startBroadcast();

        console.log("Revoking emergency role from:", emergency);
        console.log("On proxy:", address(proxy));

        factory.revokeEmergencyRole(address(proxy), emergency);

        console.log("Emergency role revoked successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Check if an address has auditor role on a specific proxy
     * @param auditor The address to check
     */
    function checkAuditor(address auditor) public view {
        bool hasRole = factory.hasAuditorRole(address(proxy), auditor);

        console.log("Checking auditor role for:", auditor);
        console.log("On proxy:", address(proxy));
        console.log("Has auditor role:", hasRole);
    }

    /**
     * @notice Check if an address has recycler role on a specific proxy
     * @param recycler The address to check
     */
    function checkRecycler(address recycler) public view {
        bool hasRole = factory.hasRecyclerRole(address(proxy), recycler);

        console.log("Checking recycler role for:", recycler);
        console.log("On proxy:", address(proxy));
        console.log("Has recycler role:", hasRole);
    }

    /**
     * @notice Check if an address has emergency role on a specific proxy
     * @param emergency The address to check
     */
    function checkEmergency(address emergency) public view {
        bool hasRole = factory.hasEmergencyRole(address(proxy), emergency);

        console.log("Checking emergency role for:", emergency);
        console.log("On proxy:", address(proxy));
        console.log("Has emergency role:", hasRole);
    }

    /**
     * @notice List all deployed proxies (paginated)
     */
    function listProxies() public view {
        console.log("Listing deployed proxies...");

        uint256 pageSize = 10;
        uint256 page = 0;

        while (true) {
            (address[] memory proxies, uint256 total) = factory.getDeployedProxiesPaginated(page, pageSize);

            if (proxies.length == 0) break;

            console.log("Page", page, "- Total proxies:", total);

            for (uint256 i = 0; i < proxies.length; i++) {
                console.log("  Proxy", page * pageSize + i + 1, ":", proxies[i]);
            }

            if (proxies.length < pageSize) break;
            page++;
        }
    }

    /**
     * @notice Apply all roles from the ConfigManager to the proxy
     * @dev Reads recyclers, auditors, and admins arrays from config and grants roles
     */
    function applyAllRolesFromConfig() public {
        vm.startBroadcast();

        // Get the current chain ID and config
        uint256 chainId = block.chainid;
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, "default");

        console.log("Applying all roles from config...");
        console.log("Network:", networkConfig.name);
        console.log("Proxy address:", address(proxy));

        // Apply admin roles
        console.log("Granting admin roles to", config.admins.length, "addresses:");
        for (uint256 i = 0; i < config.admins.length; i++) {
            address admin = config.admins[i];
            console.log("  Granting admin role to:", admin);
            factory.grantAdminRole(address(proxy), admin);
        }

        // Apply recycler roles and fund wallets
        console.log("Granting recycler roles to", config.recyclers.length, "addresses:");
        for (uint256 i = 0; i < config.recyclers.length; i++) {
            address recycler = config.recyclers[i];
            console.log("  Granting recycler role to:", recycler);
            factory.grantRecyclerRole(address(proxy), recycler);

            // Set fund wallet if available
            if (i < config.recyclerFunds.length && config.recyclerFunds[i] != address(0)) {
                address fundWallet = config.recyclerFunds[i];
                console.log("    Setting fund wallet for recycler:", fundWallet);
                proxy.setFundsWallet(recycler, fundWallet);
            }
        }

        // Apply auditor roles and fund wallets
        console.log("Granting auditor roles to", config.auditors.length, "addresses:");
        for (uint256 i = 0; i < config.auditors.length; i++) {
            address auditor = config.auditors[i];
            console.log("  Granting auditor role to:", auditor);
            factory.grantAuditorRole(address(proxy), auditor);

            // Set fund wallet if available
            if (i < config.auditorFunds.length && config.auditorFunds[i] != address(0)) {
                address fundWallet = config.auditorFunds[i];
                console.log("    Setting fund wallet for auditor:", fundWallet);
                proxy.setFundsWallet(auditor, fundWallet);
            }
        }

        // Apply emergency roles
        console.log("Granting emergency roles to", config.emergency.length, "addresses:");
        for (uint256 i = 0; i < config.emergency.length; i++) {
            address emergencyAddr = config.emergency[i];
            console.log("  Granting emergency role to:", emergencyAddr);
            factory.grantEmergencyRole(address(proxy), emergencyAddr);
        }

        console.log("All roles applied successfully!");

        vm.stopBroadcast();
    }
}
