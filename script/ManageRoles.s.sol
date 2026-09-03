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
     * @dev Enforces the config role-separation invariant on every entry point that reads
     *      config/contracts.json or grants a role. Deliberately NOT applied in `setUp()`: forge
     *      reports a revert raised inside `setUp()` as "<empty revert data>" at default verbosity,
     *      which hides the reason from the operator.
     */
    modifier validatedConfig() {
        _assertConfigRoleSeparation(getProxyConfig(block.chainid, "default"));
        _;
    }

    /**
     * @notice Grant auditor role to an address on a specific proxy
     * @dev Aborts if the target already holds RECYCLER_ROLE on chain. Granting both to one key
     *      recreates the drain path of security-audit-remediation.md 3.1.
     * @param auditor The address to grant auditor role to
     */
    function grantAuditor(address auditor) public validatedConfig {
        require(
            !factory.hasRecyclerRole(address(proxy), auditor),
            string.concat(
                "ROLE SEPARATION VIOLATION: ",
                vm.toString(auditor),
                " already holds RECYCLER_ROLE. Revoke it before granting AUDITOR_ROLE."
            )
        );

        vm.startBroadcast();

        console.log("Granting auditor role to:", auditor);
        console.log("On proxy:", address(proxy));

        factory.grantAuditorRole(address(proxy), auditor);

        console.log("Auditor role granted successfully!");

        vm.stopBroadcast();
    }

    /**
     * @notice Grant recycler role to an address on a specific proxy
     * @dev Aborts if the target already holds AUDITOR_ROLE on chain. Granting both to one key
     *      recreates the drain path of security-audit-remediation.md 3.1.
     * @param recycler The address to grant recycler role to
     */
    function grantRecycler(address recycler) public validatedConfig {
        require(
            !factory.hasAuditorRole(address(proxy), recycler),
            string.concat(
                "ROLE SEPARATION VIOLATION: ",
                vm.toString(recycler),
                " already holds AUDITOR_ROLE. Revoke it before granting RECYCLER_ROLE."
            )
        );

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
     * @dev `getDeployedProxiesPaginated`'s first parameter is a starting index into
     *      `deployedProxies` (src/RecyReportFactory.sol:150,155), not a page number. This loop
     *      previously passed a page number, which returned overlapping windows past page 1 and
     *      made the `length < pageSize` termination guard unreliable. It now advances the offset
     *      by the number of entries actually returned and terminates against `total`.
     */
    function listProxies() public view {
        console.log("Listing deployed proxies...");

        uint256 pageSize = 10;
        uint256 offset = 0;

        while (true) {
            (address[] memory proxies, uint256 total) = factory.getDeployedProxiesPaginated(offset, pageSize);

            if (proxies.length == 0) break;

            console.log("Offset", offset, "- Total proxies:", total);

            for (uint256 i = 0; i < proxies.length; i++) {
                console.log("  Proxy", offset + i + 1, ":", proxies[i]);
            }

            offset += proxies.length;
            if (offset >= total) break;
        }
    }

    /**
     * @notice Apply all roles from the ConfigManager to the proxy
     * @dev Reads recyclers, auditors, admins and emergency arrays from config and grants roles.
     *      Aborts up front if the config assigns any address both RECYCLER_ROLE and AUDITOR_ROLE.
     *
     *      This function no longer sets fund wallets. `RecyReport.setFundsWallet` is self-service
     *      (`setFundsWallet(address)` writes `funds[_msgSender()]`), so no operator key can set a
     *      fund wallet on behalf of another account. `recyclerFunds` / `auditorFunds` in
     *      config/contracts.json are advisory records only; use `reportFundWalletDrift()` to see
     *      which principals still have to register their own wallet.
     */
    function applyAllRolesFromConfig() public validatedConfig {
        // Get the current chain ID and config
        uint256 chainId = block.chainid;
        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory config = getProxyConfig(chainId, "default");

        vm.startBroadcast();

        console.log("Applying all roles from config...");
        console.log("Network:", networkConfig.name);
        console.log("Proxy address:", address(proxy));

        // Apply admin roles
        console.log("Granting admin roles to", config.admins.length, "addresses:");
        for (uint256 i = 0; i < config.admins.length; i++) {
            address admin = config.admins[i];
            if (factory.hasAdminRole(address(proxy), admin)) {
                console.log("  Admin role already granted to:", admin);
            } else {
                console.log("  Granting admin role to:", admin);
                factory.grantAdminRole(address(proxy), admin);
            }
        }

        // Apply recycler roles
        console.log("Granting recycler roles to", config.recyclers.length, "addresses:");
        for (uint256 i = 0; i < config.recyclers.length; i++) {
            address recycler = config.recyclers[i];
            if (factory.hasRecyclerRole(address(proxy), recycler)) {
                console.log("  Recycler role already granted to:", recycler);
            } else {
                require(
                    !factory.hasAuditorRole(address(proxy), recycler),
                    string.concat(
                        "ROLE SEPARATION VIOLATION: ",
                        vm.toString(recycler),
                        " already holds AUDITOR_ROLE on chain. Revoke it before granting RECYCLER_ROLE."
                    )
                );
                console.log("  Granting recycler role to:", recycler);
                factory.grantRecyclerRole(address(proxy), recycler);
            }
        }

        // Apply auditor roles
        console.log("Granting auditor roles to", config.auditors.length, "addresses:");
        for (uint256 i = 0; i < config.auditors.length; i++) {
            address auditor = config.auditors[i];
            if (factory.hasAuditorRole(address(proxy), auditor)) {
                console.log("  Auditor role already granted to:", auditor);
            } else {
                require(
                    !factory.hasRecyclerRole(address(proxy), auditor),
                    string.concat(
                        "ROLE SEPARATION VIOLATION: ",
                        vm.toString(auditor),
                        " already holds RECYCLER_ROLE on chain. Revoke it before granting AUDITOR_ROLE."
                    )
                );
                console.log("  Granting auditor role to:", auditor);
                factory.grantAuditorRole(address(proxy), auditor);
            }
        }

        // Apply emergency roles
        console.log("Granting emergency roles to", config.emergency.length, "addresses:");
        for (uint256 i = 0; i < config.emergency.length; i++) {
            address emergencyAddr = config.emergency[i];
            if (factory.hasEmergencyRole(address(proxy), emergencyAddr)) {
                console.log("  Emergency role already granted to:", emergencyAddr);
            } else {
                console.log("  Granting emergency role to:", emergencyAddr);
                factory.grantEmergencyRole(address(proxy), emergencyAddr);
            }
        }

        console.log("All roles applied successfully!");

        vm.stopBroadcast();

        // Roles are only half the picture: fund wallets are now self-service.
        reportFundWalletDrift();
    }

    /**
     * @notice Audit the live proxy for the RECYCLER+AUDITOR overlap and revert if any exists
     * @dev Read-only. Covers every address named anywhere in the proxy's config (recyclers,
     *      auditors, admins, emergency) plus the factory itself, which is granted all four roles
     *      by `initialize` (src/RecyReport.sol:138-141) and whose operational grants are inert.
     *      Run this after Phase 0 revocations to prove the drain path of
     *      docs/plan/security-audit-remediation.md 3.1 is closed.
     */
    function checkSeparationOnChain() public view validatedConfig {
        ProxyConfig memory config = getProxyConfig(block.chainid, "default");
        address[] memory principals = _configuredPrincipals(config);

        console.log("=== On-chain RECYCLER/AUDITOR separation audit ===");
        console.log("Proxy:", address(proxy));
        console.log("Principals audited:", principals.length);

        uint256 violations = 0;
        for (uint256 i = 0; i < principals.length; i++) {
            address principal = principals[i];
            bool isRecycler = factory.hasRecyclerRole(address(proxy), principal);
            bool isAuditor = factory.hasAuditorRole(address(proxy), principal);

            if (isRecycler && isAuditor) {
                violations++;
                console.log("  VIOLATION: holds RECYCLER + AUDITOR:", principal);
            } else if (isRecycler) {
                console.log("  ok RECYCLER:", principal);
            } else if (isAuditor) {
                console.log("  ok AUDITOR :", principal);
            } else {
                console.log("  ok (no operational role):", principal);
            }
        }

        require(
            violations == 0,
            string.concat(
                "ROLE SEPARATION VIOLATION: ",
                vm.toString(violations),
                " address(es) hold both RECYCLER_ROLE and AUDITOR_ROLE on ",
                vm.toString(address(proxy)),
                ". Run revokeUnauthorizedOperationalRoles()."
            )
        );

        console.log("PASS: no audited address holds both RECYCLER_ROLE and AUDITOR_ROLE.");
    }

    /**
     * @notice Revoke every operational role the config does not authorise (Phase 0 remediation)
     * @dev Only ever REVOKES, and only RECYCLER_ROLE / AUDITOR_ROLE. Never grants, and never
     *      touches DEFAULT_ADMIN_ROLE or EMERGENCY_ROLE — `revokeAdminRole(proxy, factory)` is an
     *      irreversible footgun (src/RecyReportFactory.sol:313) and is deliberately out of scope.
     *      Must be broadcast from the factory owner key.
     */
    function revokeUnauthorizedOperationalRoles() public validatedConfig {
        ProxyConfig memory config = getProxyConfig(block.chainid, "default");

        address[] memory principals = _configuredPrincipals(config);

        console.log("=== Revoking unauthorized operational roles ===");
        console.log("Proxy:", address(proxy));

        vm.startBroadcast();

        uint256 revoked = 0;
        for (uint256 i = 0; i < principals.length; i++) {
            address principal = principals[i];
            bool wantRecycler = _contains(config.recyclers, principal);
            bool wantAuditor = _contains(config.auditors, principal);

            if (!wantRecycler && factory.hasRecyclerRole(address(proxy), principal)) {
                console.log("  Revoking RECYCLER_ROLE from:", principal);
                factory.revokeRecyclerRole(address(proxy), principal);
                revoked++;
            }
            if (!wantAuditor && factory.hasAuditorRole(address(proxy), principal)) {
                console.log("  Revoking AUDITOR_ROLE from:", principal);
                factory.revokeAuditorRole(address(proxy), principal);
                revoked++;
            }
        }

        vm.stopBroadcast();

        console.log("Roles revoked:", revoked);
        console.log("Re-run checkSeparationOnChain() to confirm.");
    }

    /**
     * @notice Report which principals still need to register their own fund wallet
     * @dev Read-only. Fund wallets cannot be set on behalf of another account: after the Phase 2
     *      upgrade `setFundsWallet(address)` writes `funds[_msgSender()]`, so each principal must
     *      send the transaction itself. This prints the exact call each one owes.
     */
    function reportFundWalletDrift() public view validatedConfig {
        ProxyConfig memory config = getProxyConfig(block.chainid, "default");

        console.log("=== Fund wallet drift (self-service; scripts cannot fix this) ===");
        console.log("Proxy:", address(proxy));

        uint256 pending = 0;
        pending += _reportFundWalletDriftFor("recycler", config.recyclers, config.recyclerFunds);
        pending += _reportFundWalletDriftFor("auditor", config.auditors, config.auditorFunds);

        if (pending == 0) {
            console.log("All declared fund wallets match on-chain state.");
        } else {
            console.log("Principals that must call setFundsWallet(address) themselves:", pending);
        }
    }

    /**
     * @notice Revert if the parsed config violates role separation
     * @dev Two rules. (1) No address may hold both RECYCLER_ROLE and AUDITOR_ROLE: that pair on
     *      one key is the complete-treasury-drain path of docs/plan/security-audit-remediation.md
     *      3.1 — the key mints its own report, validates it, and collects recycler + validator +
     *      generator = 90% of the payout. (2) No admin or emergency key may hold an operational
     *      role at all: a key that can grant roles, upgrade the implementation or pause claiming
     *      must not also produce or authorise a payout (Phase 0 outcome: "0 admin key with an
     *      operational role"). Enforced here so a future ops run cannot silently re-apply what
     *      Phase 0 removed.
     * @param config The proxy config to validate
     */
    function _assertConfigRoleSeparation(ProxyConfig memory config) internal pure {
        for (uint256 i = 0; i < config.recyclers.length; i++) {
            address recycler = config.recyclers[i];
            require(
                !_contains(config.auditors, recycler),
                string.concat(
                    "ROLE SEPARATION VIOLATION in config/contracts.json: ",
                    vm.toString(recycler),
                    " is listed as both a recycler and an auditor. One address must never hold ",
                    "RECYCLER_ROLE and AUDITOR_ROLE (security-audit-remediation.md 3.1)."
                )
            );
        }
        _assertNoOperationalRole(config, config.admins, "admins");
        _assertNoOperationalRole(config, config.emergency, "emergency");
    }

    /**
     * @notice Revert if any of `privileged` appears in the config's recycler or auditor lists
     * @param config The proxy config being validated
     * @param privileged The admin or emergency key list
     * @param listName Which list, for the error message
     */
    function _assertNoOperationalRole(ProxyConfig memory config, address[] memory privileged, string memory listName)
        internal
        pure
    {
        for (uint256 i = 0; i < privileged.length; i++) {
            address key = privileged[i];
            require(
                !_contains(config.recyclers, key) && !_contains(config.auditors, key),
                string.concat(
                    "ROLE SEPARATION VIOLATION in config/contracts.json: ",
                    vm.toString(key),
                    " is listed under `",
                    listName,
                    "` and in an operational list. Admin and emergency keys must not hold ",
                    "RECYCLER_ROLE or AUDITOR_ROLE (remediation-runbook.md, Phase 0)."
                )
            );
        }
    }

    /**
     * @notice Print the fund-wallet drift for one role group
     * @param role Human-readable role name used in the log lines
     * @param principals The addresses holding that role in config
     * @param declaredFunds The fund wallets declared for them, index-parallel to `principals`
     * @return pending The number of principals whose on-chain fund wallet does not match config
     */
    function _reportFundWalletDriftFor(
        string memory role,
        address[] memory principals,
        address[] memory declaredFunds
    ) internal view returns (uint256 pending) {
        for (uint256 i = 0; i < principals.length; i++) {
            if (i >= declaredFunds.length || declaredFunds[i] == address(0)) continue;

            address principal = principals[i];
            address declared = declaredFunds[i];
            address onChain = proxy.funds(principal);

            if (onChain == declared) continue;

            pending++;
            console.log(string.concat("  ", role, " must self-register:"), principal);
            console.log("    on-chain funds():", onChain);
            console.log("    declared in config:", declared);
            console.log(
                string.concat(
                    "    cast send ",
                    vm.toString(address(proxy)),
                    ' "setFundsWallet(address)" ',
                    vm.toString(declared),
                    "   # must be sent by ",
                    vm.toString(principal)
                )
            );
        }
    }

    /**
     * @notice Build the deduplicated set of addresses this script audits on chain
     * @dev The union of every address named in the proxy config plus the factory, whose own
     *      RECYCLER/AUDITOR grants come from `initialize` and are inert but still count as the
     *      overlap for least-privilege purposes.
     * @param config The proxy config to read
     * @return principals The deduplicated audit set
     */
    function _configuredPrincipals(ProxyConfig memory config) internal view returns (address[] memory principals) {
        uint256 capacity =
            config.recyclers.length + config.auditors.length + config.admins.length + config.emergency.length + 1;
        address[] memory buffer = new address[](capacity);
        uint256 count = 0;

        count = _appendUnique(buffer, count, config.recyclers);
        count = _appendUnique(buffer, count, config.auditors);
        count = _appendUnique(buffer, count, config.admins);
        count = _appendUnique(buffer, count, config.emergency);
        count = _appendUniqueOne(buffer, count, address(factory));

        principals = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            principals[i] = buffer[i];
        }
    }

    /// @dev Append every address of `extra` to `buffer[0:count]`, skipping duplicates and zeros.
    function _appendUnique(address[] memory buffer, uint256 count, address[] memory extra)
        private
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < extra.length; i++) {
            count = _appendUniqueOne(buffer, count, extra[i]);
        }
        return count;
    }

    /// @dev Append `candidate` to `buffer[0:count]` unless it is zero or already present.
    function _appendUniqueOne(address[] memory buffer, uint256 count, address candidate)
        private
        pure
        returns (uint256)
    {
        if (candidate == address(0)) return count;
        for (uint256 i = 0; i < count; i++) {
            if (buffer[i] == candidate) return count;
        }
        buffer[count] = candidate;
        return count + 1;
    }

    /// @dev Linear membership test; ops-scale arrays only.
    function _contains(address[] memory haystack, address needle) private pure returns (bool) {
        for (uint256 i = 0; i < haystack.length; i++) {
            if (haystack[i] == needle) return true;
        }
        return false;
    }
}
