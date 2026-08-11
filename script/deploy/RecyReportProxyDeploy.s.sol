// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../../src/RecyReportFactory.sol";
import "../../src/RecyReport.sol";
import "../config/ConfigManager.s.sol";

/**
 * @title RecyReportProxyDeploy
 * @notice Script to deploy new proxies for the RecyReport implementation using the RecyReportFactory
 * @dev Factory address is automatically loaded from the config file.
 *
 *      Environment flags:
 *      - `proxy`                 name of the proxy config to deploy (default: "default")
 *      - `ALLOW_PROXY_REUSE`     opt in to adopting a pre-existing proxy registered under that name
 *      - `ALLOW_STALE_FACTORY`   opt in to deploying through a factory whose immutable
 *                                implementation/dataContract are not the blessed pair in config
 *
 *      Both flags default to false: this script fails loudly rather than silently producing a
 *      proxy of unknown provenance or a proxy born without the Phase 1/2 security fixes.
 */
contract RecyReportProxyDeploy is Script, ConfigManager {
    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;

        // Get the proxy parameter or use "default" if not provided
        string memory proxyName = vm.envOr("proxy", string("default"));

        // Get network and proxy configuration
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, proxyName);

        require(
            networkConfig.factory != address(0), "Factory address not found in config. Please deploy the factory first."
        );

        console.log("=== Using RecyReportFactory ===");
        console.log("Chain ID:", chainId);
        console.log("Proxy Config:", proxyName);
        console.log("Network:", networkConfig.name);
        console.log("Factory Address:", networkConfig.factory);

        RecyReportFactory factory = RecyReportFactory(networkConfig.factory);

        console.log("\n=== Factory Information ===");
        console.log("Implementation:", factory.implementation());
        console.log("Data Contract:", factory.dataContract());
        console.log("Total Deployed Proxies:", factory.getDeployedProxiesCount());

        _assertFactoryServesBlessedCode(factory, networkConfig);

        // Check if proxy with this name already exists
        address existingProxy = factory.proxyByName(proxyName);

        address proxy;

        if (existingProxy != address(0)) {
            // `deployProxy` is permissionless (src/RecyReportFactory.sol:96) and proxy names are
            // first-come-first-served, so a pre-existing proxy under this name is not necessarily
            // ours: whoever registered it chose its token address, protocol address and shares.
            // Silently adopting it is how a squatted, attacker-configured contract becomes "the
            // deployment" (security-audit-remediation.md 3.8). Require an explicit opt-in.
            require(
                vm.envOr("ALLOW_PROXY_REUSE", false),
                string.concat(
                    "REFUSING TO REUSE EXISTING PROXY: name '",
                    proxyName,
                    "' already resolves to ",
                    vm.toString(existingProxy),
                    ". Verify its provenance (token, protocolAddress, shares, role holders) and ",
                    "re-run with ALLOW_PROXY_REUSE=true, or deploy under a different name."
                )
            );

            console.log("\n=== Proxy already exists, reusing (ALLOW_PROXY_REUSE=true) ===");
            console.log("Proxy name:", proxyName);
            console.log("Existing proxy address:", existingProxy);
            console.log("Operator has accepted responsibility for this proxy's provenance.");
            proxy = existingProxy;
        } else {
            console.log("\n=== Deploying RecyReportproxy Proxy ===");

            vm.startBroadcast();

            proxy = factory.deployProxy(
                proxyName,
                "RECY",
                networkConfig.token,
                networkConfig.protocol,
                config.unlockDelay,
                config.shareRecycler,
                config.shareValidator,
                config.shareGenerator,
                config.shareProtocol
            );

            vm.stopBroadcast();

            console.log("Success! Proxy deployed at:", proxy);
        }

        // Test the deployed proxy
        RecyReport recyReport1 = RecyReport(proxy);
        console.log("Proxy label:", proxyName);
        console.log("Proxy reportName:", recyReport1.name());
        console.log("Proxy symbol:", recyReport1.symbol());
        console.log("Unlock delay:", recyReport1.unlockDelay(), "seconds");
        console.log("Recycler share:", recyReport1.shareRecycler(), "%");

        // Display final statistics
        console.log("\n=== Final Factory Statistics ===");
        console.log("Total deployed proxies:", factory.getDeployedProxiesCount());

        // Get all deployed proxies
        address[] memory allProxies = factory.getAllDeployedProxies();
        if (allProxies.length > 0) {
            console.log("\nAll deployed proxies:");
            for (uint256 i = 0; i < allProxies.length; i++) {
                console.log("  [%d] Proxy: %s ", i + 1, allProxies[i]);
            }
        }

        console.log("\n=== Completed ===");
    }

    /**
     * @notice Abort unless the factory's baked-in code addresses are the blessed ones from config
     * @dev `implementation` and `dataContract` are `immutable` on the factory
     *      (src/RecyReportFactory.sol:15,18) and are wired into every proxy it deploys — the data
     *      contract through the initializer payload (:107) and the implementation into the
     *      ERC1967Proxy itself (:117). Neither `setDataContract` on the live proxy nor a UUPS
     *      upgrade of the live proxy changes them, so a factory left holding pre-remediation
     *      addresses keeps minting proxies that are born with the malformed-`tokenURI` data
     *      contract and the unguarded implementation, with nothing at deploy time to say so.
     *      That is the silent regression of security-audit-remediation.md 5a; this turns it into
     *      a failed script.
     *
     *      `ALLOW_STALE_FACTORY=true` is the 5a-item-2 interim path only: deploy anyway, then
     *      immediately run the three remediation calls printed below, then re-verify the new proxy.
     *      The first of the three grants the operator `DEFAULT_ADMIN_ROLE` on the new proxy, which
     *      `deployProxy` does not do — `initialize` grants every role to the factory, not to the
     *      caller (src/RecyReport.sol:157-160).
     * @param factory The factory that would mint the proxy
     * @param networkConfig The network config carrying the blessed addresses
     */
    function _assertFactoryServesBlessedCode(RecyReportFactory factory, NetworkConfig memory networkConfig)
        internal
        view
    {
        address factoryImpl = factory.implementation();
        address factoryData = factory.dataContract();
        bool implOk = factoryImpl == networkConfig.reportImplementation;
        bool dataOk = factoryData == networkConfig.reportData;

        if (implOk && dataOk) {
            console.log("Blessed-code check: PASS (factory serves the config's implementation and data contract)");
            return;
        }

        console.log("\n=== BLESSED-CODE CHECK FAILED ===");
        if (!implOk) {
            console.log("  factory.implementation():   ", factoryImpl);
            console.log("  blessed reportImplementation:", networkConfig.reportImplementation);
        }
        if (!dataOk) {
            console.log("  factory.dataContract():     ", factoryData);
            console.log("  blessed reportData:         ", networkConfig.reportData);
        }
        console.log("  Any proxy deployed now is born with that code and none of the Phase 1/2 fixes.");
        console.log("  Proper fix: deploy the Phase 3 v2 factory carrying the blessed pair.");
        console.log("  Interim override: ALLOW_STALE_FACTORY=true, then IMMEDIATELY run all three,");
        console.log("  in this order (1 and 3 from the factory owner, 2 from <operator>):");
        console.log("    1. factory.grantAdminRole(<new proxy>, <operator>)");
        console.log("       Required: deployProxy grants the CALLER nothing. initialize gives all");
        console.log("       four roles to _msgSender(), which here is the factory");
        console.log("       (src/RecyReport.sol:157-160), and the factory has no setDataContract");
        console.log("       passthrough. Without this, step 2 reverts AccessControlUnauthorizedAccount.");
        console.log("    2. <new proxy>.setDataContract(", networkConfig.reportData, ")");
        console.log("    3. factory.upgradeProxy(<new proxy>,", networkConfig.reportImplementation, ")");

        require(
            vm.envOr("ALLOW_STALE_FACTORY", false),
            string.concat(
                "FACTORY SERVES STALE CODE: factory.implementation()/dataContract() do not match the ",
                "blessed addresses in config/contracts.json (security-audit-remediation.md 5a). Set ",
                "ALLOW_STALE_FACTORY=true to override and accept the mandatory post-deploy remediation."
            )
        );

        console.log("  ALLOW_STALE_FACTORY=true - proceeding. The three calls above are now MANDATORY.");
    }
}
