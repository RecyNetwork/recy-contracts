// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyConstants} from "../src/lib/RecyConstants.sol";
import {ManageRoles} from "./ManageRoles.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Carries the RECYCLER_ROLE / AUDITOR_ROLE holders of a retired RecyReport proxy over to the configured one.
/// @dev RecyReport uses plain AccessControlUpgradeable (not enumerable), so holders are discovered from the legacy
///      proxy's RoleGranted logs and confirmed with hasRole. config/contracts.json stays the source of truth: its
///      role lists decide contested wallets, its `legacy` object settles dual-role wallets, and a broadcast merges
///      the restored wallets into `recyclers` / `auditors`. Nothing here ever grants DEFAULT_ADMIN_ROLE or
///      EMERGENCY_ROLE, and no wallet ends up holding both operational roles (security-audit-remediation.md 3.1).
contract RestoreLegacyRoles is ManageRoles {
    /// @dev Infura serves at most 10,000 blocks per eth_getLogs request and rate-limits bursts.
    uint256 private constant LOG_CHUNK_BLOCKS = 10_000;
    uint256 private constant LOG_CHUNK_PAUSE_MS = 250;
    bytes32 private constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @dev Current role holders of the legacy proxy. `factory` is the account RecyReport.initialize granted
    ///      DEFAULT_ADMIN_ROLE first, i.e. the factory that created the proxy.
    struct LegacySets {
        address[] recyclers;
        address[] auditors;
        address[] admins;
        address[] emergency;
        address factory;
    }

    /// @dev Outcome of `_plan`: the wallets to hold each operational role on the new proxy, dual-role wallets
    ///      awaiting a config decision, wallets deliberately left without an operational role, and privileged
    ///      legacy holders the config does not list (manual decisions, never granted here).
    struct Plan {
        address[] recyclers;
        address[] auditors;
        address[] unresolved;
        address[] excluded;
        address[] adminDifferences;
        address[] emergencyDifferences;
    }

    enum WalletStatus {
        Ok,
        Missing,
        Conflict
    }

    /// @notice Grants every missing planned role through the factory and records the plan in config.
    /// @dev Must be broadcast from the factory owner. Unresolved dual-role wallets do not block the settled
    ///      ones; they are reported until the config decides them. The config merge happens only in a real
    ///      broadcast, so a dry run never writes.
    function run() public {
        (ProxyConfig memory config, LegacyProxyConfig memory settings) = _loadInputs();
        LegacySets memory legacy = _discoverLegacyHolders(settings);
        Plan memory plan = _plan(legacy, config, settings, address(factory));
        (uint256 missing, uint256 conflicts) = _report(legacy, plan, config, settings);
        require(
            conflicts == 0,
            "ROLE SEPARATION VIOLATION: revoke each reported wallet's opposite role with its ManageRoles --sig command, then rerun."
        );

        vm.startBroadcast();
        // Only the signer's identity matters here; the transaction origin is irrelevant.
        // forge-lint: disable-next-line(unused-return)
        (VmSafe.CallerMode mode, address broadcaster,) = vm.readCallers();
        require(mode == VmSafe.CallerMode.RecurrentBroadcast, "Foundry broadcast signer is unavailable");
        require(broadcaster == factory.owner(), "broadcaster is not the factory owner");

        console2.log("=== Granting missing legacy roles ===");
        console2.log("Broadcaster / factory owner:", broadcaster);
        console2.log("Roles to grant:", missing);
        // The shared config-driven path re-checks the opposite role before every grant and skips held roles.
        ProxyConfig memory grants;
        grants.recyclers = plan.recyclers;
        grants.auditors = plan.auditors;
        _applyRolesFromConfig(grants);
        vm.stopBroadcast();

        _assertPlanHeld(plan);
        console2.log("Postcheck: every planned wallet holds its role on", address(proxy));

        _recordPlan(config, plan);
        _logUnresolved(plan);
    }

    /// @notice Signerless status check.
    /// @dev Reverts until every planned wallet holds exactly its planned role on the new proxy and no
    ///      dual-role wallet is left unresolved.
    function check() public {
        (ProxyConfig memory config, LegacyProxyConfig memory settings) = _loadInputs();
        LegacySets memory legacy = _discoverLegacyHolders(settings);
        Plan memory plan = _plan(legacy, config, settings, address(factory));
        (uint256 missing, uint256 conflicts) = _report(legacy, plan, config, settings);
        _logUnresolved(plan);

        require(missing == 0 && conflicts == 0 && plan.unresolved.length == 0, "legacy role restoration incomplete");
        console2.log("PASS: every legacy operational role is restored and no dual-role wallet is unresolved.");
    }

    /// @dev Loads and validates both config objects this script depends on.
    function _loadInputs() internal view returns (ProxyConfig memory config, LegacyProxyConfig memory settings) {
        settings = getLegacyProxyConfig(block.chainid, "default");
        require(settings.proxy != address(0), "legacy proxy is not configured");
        require(settings.fromBlock != 0, "legacy.fromBlock is not configured");
        require(settings.proxy != address(proxy), "legacy proxy is the configured proxy");
        require(settings.proxy.code.length != 0, "legacy proxy has no code");

        config = getProxyConfig(block.chainid, "default");
        _assertConfigRoleSeparation(config);
    }

    /// @dev Scans RoleGranted logs from `settings.fromBlock` to the chain head and keeps the accounts whose role
    ///      is still held. Confirming with hasRole makes RoleRevoked logs irrelevant.
    function _discoverLegacyHolders(LegacyProxyConfig memory settings) internal returns (LegacySets memory legacy) {
        uint256 head = block.number;
        require(settings.fromBlock <= head, "legacy fromBlock is beyond the chain head");

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IAccessControl.RoleGranted.selector;
        uint256 chunkCount = (head - settings.fromBlock) / LOG_CHUNK_BLOCKS + 1;
        VmSafe.EthGetLogs[][] memory chunks = new VmSafe.EthGetLogs[][](chunkCount);
        uint256 total = 0;

        console2.log("=== Discovering legacy role holders ===");
        console2.log("Legacy proxy:", settings.proxy);
        console2.log("Scanning RoleGranted logs from block", settings.fromBlock, "to", head);
        console2.log("eth_getLogs chunks:", chunkCount);

        // One sequential eth_getLogs request per 10,000-block chunk, paced for the provider's rate limit.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < chunkCount; i++) {
            uint256 from = settings.fromBlock + i * LOG_CHUNK_BLOCKS;
            uint256 to = from + LOG_CHUNK_BLOCKS - 1;
            if (to > head) to = head;
            if (i != 0) vm.sleep(LOG_CHUNK_PAUSE_MS);
            chunks[i] = vm.eth_getLogs(from, to, settings.proxy, topics);
            total += chunks[i].length;
        }
        // forge-lint: disable-end(calls-loop)
        console2.log("RoleGranted logs found:", total);

        address[] memory recyclers = new address[](total);
        address[] memory auditors = new address[](total);
        address[] memory admins = new address[](total);
        address[] memory emergency = new address[](total);
        uint256 recyclerCount = 0;
        uint256 auditorCount = 0;
        uint256 adminCount = 0;
        uint256 emergencyCount = 0;

        for (uint256 c = 0; c < chunkCount; c++) {
            VmSafe.EthGetLogs[] memory logs = chunks[c];
            for (uint256 i = 0; i < logs.length; i++) {
                // RoleGranted indexes role, account and sender: four topics including the signature.
                if (logs[i].topics.length != 4) continue;
                bytes32 role = logs[i].topics[1];
                address account = address(uint160(uint256(logs[i].topics[2])));
                if (role == RecyConstants.RECYCLER_ROLE) {
                    recyclerCount = _appendUniqueOne(recyclers, recyclerCount, account);
                } else if (role == RecyConstants.AUDITOR_ROLE) {
                    auditorCount = _appendUniqueOne(auditors, auditorCount, account);
                } else if (role == DEFAULT_ADMIN_ROLE) {
                    if (legacy.factory == address(0)) legacy.factory = account;
                    adminCount = _appendUniqueOne(admins, adminCount, account);
                } else if (role == RecyConstants.EMERGENCY_ROLE) {
                    emergencyCount = _appendUniqueOne(emergency, emergencyCount, account);
                }
            }
        }
        require(
            legacy.factory != address(0),
            "no DEFAULT_ADMIN_ROLE grant found; legacy.fromBlock must not be later than the proxy creation block"
        );

        legacy.recyclers = _confirmedHolders(settings.proxy, RecyConstants.RECYCLER_ROLE, recyclers, recyclerCount);
        legacy.auditors = _confirmedHolders(settings.proxy, RecyConstants.AUDITOR_ROLE, auditors, auditorCount);
        legacy.admins = _confirmedHolders(settings.proxy, DEFAULT_ADMIN_ROLE, admins, adminCount);
        legacy.emergency = _confirmedHolders(settings.proxy, RecyConstants.EMERGENCY_ROLE, emergency, emergencyCount);
    }

    /// @dev Keeps the candidates that still hold `role` on the legacy proxy, in first-granted order.
    function _confirmedHolders(address legacyProxy, bytes32 role, address[] memory candidates, uint256 count)
        internal
        view
        returns (address[] memory holders)
    {
        address[] memory buffer = new address[](count);
        uint256 kept = 0;
        // Every candidate needs one live hasRole read; the candidate set is bounded by the log scan.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < count; i++) {
            if (IAccessControl(legacyProxy).hasRole(role, candidates[i])) {
                buffer[kept] = candidates[i];
                kept++;
            }
        }
        // forge-lint: disable-end(calls-loop)
        holders = _truncated(buffer, kept);
    }

    /// @notice Decides which legacy holders receive which operational role on the new proxy.
    /// @dev Pure so the rules can be unit-tested. Per candidate (legacy recyclers and auditors), in order:
    ///      1. privileged keys (legacy DEFAULT_ADMIN/EMERGENCY holders, config admins/emergency, either factory)
    ///         and `legacy.exclude` entries receive nothing and are reported as excluded;
    ///      2. a wallet listed in config `recyclers` / `auditors` receives exactly that role (config decides);
    ///      3. a single legacy role is copied as is;
    ///      4. a dual legacy role follows `legacy.keepRecycler` / `legacy.keepAuditor`, otherwise it is unresolved.
    ///      Legacy admin/emergency holders missing from the config lists are reported as differences only.
    /// @param legacy Confirmed role holders of the legacy proxy
    /// @param config The new proxy's configuration
    /// @param settings The `legacy` object of that configuration
    /// @param newFactory The factory managing the new proxy
    /// @return plan The resulting plan
    function _plan(
        LegacySets memory legacy,
        ProxyConfig memory config,
        LegacyProxyConfig memory settings,
        address newFactory
    ) internal pure returns (Plan memory plan) {
        _assertKeepListsDisjoint(settings);

        address[] memory candidates = _union(legacy.recyclers, legacy.auditors);
        address[] memory recyclers = new address[](candidates.length);
        address[] memory auditors = new address[](candidates.length);
        address[] memory unresolved = new address[](candidates.length);
        address[] memory excluded = new address[](candidates.length);
        uint256 recyclerCount = 0;
        uint256 auditorCount = 0;
        uint256 unresolvedCount = 0;
        uint256 excludedCount = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            address candidate = candidates[i];
            if (bytes(_exclusionReason(candidate, legacy, config, settings, newFactory)).length != 0) {
                excluded[excludedCount] = candidate;
                excludedCount++;
            } else if (_contains(config.recyclers, candidate)) {
                recyclers[recyclerCount] = candidate;
                recyclerCount++;
            } else if (_contains(config.auditors, candidate)) {
                auditors[auditorCount] = candidate;
                auditorCount++;
            } else {
                bool legacyRecycler = _contains(legacy.recyclers, candidate);
                bool legacyAuditor = _contains(legacy.auditors, candidate);
                // Every candidate holds at least one legacy role, so unequal flags mean exactly one.
                if (legacyRecycler != legacyAuditor) {
                    if (legacyRecycler) {
                        recyclers[recyclerCount] = candidate;
                        recyclerCount++;
                    } else {
                        auditors[auditorCount] = candidate;
                        auditorCount++;
                    }
                } else if (_contains(settings.keepRecycler, candidate)) {
                    recyclers[recyclerCount] = candidate;
                    recyclerCount++;
                } else if (_contains(settings.keepAuditor, candidate)) {
                    auditors[auditorCount] = candidate;
                    auditorCount++;
                } else {
                    unresolved[unresolvedCount] = candidate;
                    unresolvedCount++;
                }
            }
        }

        plan.recyclers = _truncated(recyclers, recyclerCount);
        plan.auditors = _truncated(auditors, auditorCount);
        plan.unresolved = _truncated(unresolved, unresolvedCount);
        plan.excluded = _truncated(excluded, excludedCount);
        plan.adminDifferences = _difference(legacy.admins, config.admins, legacy.factory);
        plan.emergencyDifferences = _difference(legacy.emergency, config.emergency, legacy.factory);
    }

    /// @dev Non-empty when `account` must never receive an operational role on the new proxy.
    function _exclusionReason(
        address account,
        LegacySets memory legacy,
        ProxyConfig memory config,
        LegacyProxyConfig memory settings,
        address newFactory
    ) internal pure returns (string memory) {
        if (account == legacy.factory) return "legacy factory";
        if (account == newFactory) return "new factory";
        if (_contains(legacy.admins, account)) return "holds DEFAULT_ADMIN_ROLE on the legacy proxy";
        if (_contains(legacy.emergency, account)) return "holds EMERGENCY_ROLE on the legacy proxy";
        if (_contains(config.admins, account)) return "listed under config admins";
        if (_contains(config.emergency, account)) return "listed under config emergency";
        if (_contains(settings.exclude, account)) return "listed under legacy.exclude";
        return "";
    }

    /// @dev A wallet in both keep lists has no single answer; refuse rather than let list order decide.
    function _assertKeepListsDisjoint(LegacyProxyConfig memory settings) internal pure {
        // Each keepRecycler entry keeps its own check; vm.toString only identifies the offending config entry.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < settings.keepRecycler.length; i++) {
            require(
                !_contains(settings.keepAuditor, settings.keepRecycler[i]),
                string.concat(
                    "legacy.keepRecycler and legacy.keepAuditor both list ", vm.toString(settings.keepRecycler[i])
                )
            );
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)
    }

    /// @dev Prints the discovered holders, the plan and each planned wallet's state on the new proxy.
    /// @return missing Planned wallets that do not hold their role on the new proxy yet
    /// @return conflicts Planned wallets holding the opposite operational role on the new proxy
    function _report(
        LegacySets memory legacy,
        Plan memory plan,
        ProxyConfig memory config,
        LegacyProxyConfig memory settings
    ) internal view returns (uint256 missing, uint256 conflicts) {
        console2.log("=== Legacy role holders (confirmed with hasRole) ===");
        console2.log("Legacy proxy:", settings.proxy);
        console2.log("Legacy factory:", legacy.factory);
        console2.log("RECYCLER_ROLE holders:", legacy.recyclers.length);
        console2.log("AUDITOR_ROLE holders:", legacy.auditors.length);
        console2.log("DEFAULT_ADMIN_ROLE holders:", legacy.admins.length);
        console2.log("EMERGENCY_ROLE holders:", legacy.emergency.length);

        console2.log("=== Restoration plan for proxy", address(proxy), "===");
        (missing, conflicts) = _reportPlannedRole("RECYCLER_ROLE", plan.recyclers, true);
        (uint256 auditorMissing, uint256 auditorConflict) = _reportPlannedRole("AUDITOR_ROLE", plan.auditors, false);
        missing += auditorMissing;
        conflicts += auditorConflict;

        console2.log("Unresolved dual-role wallets:", plan.unresolved.length);
        _reportList("  UNRESOLVED", plan.unresolved);

        console2.log("Excluded from operational roles:", plan.excluded.length);
        for (uint256 i = 0; i < plan.excluded.length; i++) {
            address excluded = plan.excluded[i];
            console2.log(
                string.concat("  ", _exclusionReason(excluded, legacy, config, settings, address(factory)), ":"),
                excluded
            );
        }

        console2.log("Legacy admins not in config admins (manual decision):", plan.adminDifferences.length);
        _reportList("  admin on legacy only", plan.adminDifferences);
        console2.log("Legacy emergency not in config emergency (manual decision):", plan.emergencyDifferences.length);
        _reportList("  emergency on legacy only", plan.emergencyDifferences);

        console2.log("Summary: missing", missing, "conflicts", conflicts);
    }

    /// @dev Prints one line per planned wallet with its state on the new proxy and a per-wallet recovery command.
    function _reportPlannedRole(string memory role, address[] memory wallets, bool recyclerRole)
        internal
        view
        returns (uint256 missing, uint256 conflicts)
    {
        console2.log(string.concat("Planned ", role, " holders:"), wallets.length);
        // Each planned wallet needs two live role reads on the new proxy; the set is bounded by the legacy scan.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < wallets.length; i++) {
            WalletStatus status = _walletStatus(wallets[i], recyclerRole);
            if (status == WalletStatus.Ok) {
                console2.log("  ok       ", wallets[i]);
            } else if (status == WalletStatus.Missing) {
                missing++;
                console2.log("  MISSING  ", wallets[i]);
            } else {
                conflicts++;
                string memory oppositeRole = recyclerRole ? "AUDITOR_ROLE" : "RECYCLER_ROLE";
                string memory revokeSig = recyclerRole ? "revokeAuditor(address)" : "revokeRecycler(address)";
                console2.log(
                    string.concat("  CONFLICT (planned ", role, "; holds ", oppositeRole, " on the new proxy):"),
                    wallets[i]
                );
                console2.log(
                    string.concat(
                        "    Recovery: forge script script/ManageRoles.s.sol:ManageRoles --sig '",
                        revokeSig,
                        "' ",
                        vm.toString(wallets[i]),
                        " --rpc-url <RPC_URL> --account <FACTORY_OWNER_ACCOUNT> --sender ",
                        vm.toString(factory.owner()),
                        " --broadcast"
                    )
                );
            }
        }
        // forge-lint: disable-end(calls-loop)
    }

    /// @dev Prints `label: wallet` for every entry.
    function _reportList(string memory label, address[] memory wallets) internal pure {
        for (uint256 i = 0; i < wallets.length; i++) {
            console2.log(string.concat(label, ":"), wallets[i]);
        }
    }

    /// @dev Live state of one planned wallet on the new proxy.
    function _walletStatus(address wallet, bool recyclerRole) internal view returns (WalletStatus) {
        // Called once per planned wallet from the report and postcheck loops; both reads are required per wallet.
        // forge-lint: disable-start(calls-loop)
        bool isRecycler = factory.hasRecyclerRole(address(proxy), wallet);
        bool isAuditor = factory.hasAuditorRole(address(proxy), wallet);
        // forge-lint: disable-end(calls-loop)
        if (recyclerRole ? isAuditor : isRecycler) return WalletStatus.Conflict;
        return (recyclerRole ? isRecycler : isAuditor) ? WalletStatus.Ok : WalletStatus.Missing;
    }

    /// @dev Postcheck: every planned wallet must hold exactly its planned role after the grants.
    function _assertPlanHeld(Plan memory plan) internal view {
        // Each planned wallet is re-read after the grants; any wallet not in its planned state is a hard failure.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < plan.recyclers.length; i++) {
            require(_walletStatus(plan.recyclers[i], true) == WalletStatus.Ok, "legacy role restoration incomplete");
        }
        for (uint256 i = 0; i < plan.auditors.length; i++) {
            require(_walletStatus(plan.auditors[i], false) == WalletStatus.Ok, "legacy role restoration incomplete");
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)
    }

    /// @dev Appends the planned wallets the config lacks to its `recyclers` / `auditors` arrays. Only a real
    ///      broadcast writes; existing entries keep their order.
    function _recordPlan(ProxyConfig memory config, Plan memory plan) internal {
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Dry run: config file left unchanged.");
            return;
        }

        address[] memory recyclers = _merged(config.recyclers, plan.recyclers);
        address[] memory auditors = _merged(config.auditors, plan.auditors);
        bool recyclersChanged = recyclers.length != config.recyclers.length;
        bool auditorsChanged = auditors.length != config.auditors.length;
        if (!recyclersChanged && !auditorsChanged) {
            console2.log("config/contracts.json already lists every restored wallet.");
            return;
        }

        config.recyclers = recyclers;
        config.auditors = auditors;
        _assertConfigRoleSeparation(config);

        string memory basePath = string.concat(".", vm.toString(block.chainid), ".proxies.default");
        if (recyclersChanged) {
            vm.writeJson(_jsonAddressArray(recyclers), CONFIG_PATH, string.concat(basePath, ".recyclers"));
        }
        if (auditorsChanged) {
            vm.writeJson(_jsonAddressArray(auditors), CONFIG_PATH, string.concat(basePath, ".auditors"));
        }
        // vm.writeJson drops the file's final newline; restore it so the change diffs cleanly.
        vm.writeLine(CONFIG_PATH, "");

        console2.log("Recorded the restored wallets in config/contracts.json:");
        console2.log("  recyclers:", recyclers.length);
        console2.log("  auditors:", auditors.length);
        console2.log("Live once every broadcast receipt succeeds; rerun run() to grant anything still missing.");
    }

    /// @dev Tells the operator exactly which config keys settle the wallets that received nothing.
    function _logUnresolved(Plan memory plan) internal view {
        if (plan.unresolved.length == 0) return;
        console2.log("!!! UNRESOLVED dual-role wallets:", plan.unresolved.length);
        console2.log("    Each holds RECYCLER_ROLE and AUDITOR_ROLE on the legacy proxy and received nothing.");
        console2.log(
            "    Decide each one in config/contracts.json under",
            string.concat(".", vm.toString(block.chainid), ".proxies.default.legacy:")
        );
        console2.log("      keepRecycler -> RECYCLER_ROLE only");
        console2.log("      keepAuditor  -> AUDITOR_ROLE only");
        console2.log("      exclude      -> no operational role");
        console2.log("    then rerun this script; check() fails until every one is decided.");
    }

    /// @dev Serialises `wallets` as a JSON array of checksummed address strings for vm.writeJson.
    function _jsonAddressArray(address[] memory wallets) internal pure returns (string memory json) {
        json = "[";
        // Each entry needs one vm.toString call; the array is ops-scale.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < wallets.length; i++) {
            json = string.concat(json, i == 0 ? "\"" : ",\"", vm.toString(wallets[i]), "\"");
        }
        // forge-lint: disable-end(calls-loop)
        json = string.concat(json, "]");
    }

    /// @dev `first` followed by the members of `second` it lacks, zeros and duplicates dropped.
    function _union(address[] memory first, address[] memory second) internal pure returns (address[] memory) {
        address[] memory buffer = new address[](first.length + second.length);
        uint256 count = _appendUnique(buffer, 0, first);
        count = _appendUnique(buffer, count, second);
        return _truncated(buffer, count);
    }

    /// @dev `base` in its original order followed by the members of `extra` it lacks.
    function _merged(address[] memory base, address[] memory extra) internal pure returns (address[] memory) {
        address[] memory buffer = new address[](base.length + extra.length);
        for (uint256 i = 0; i < base.length; i++) {
            buffer[i] = base[i];
        }
        uint256 count = _appendUnique(buffer, base.length, extra);
        return _truncated(buffer, count);
    }

    /// @dev Members of `set` absent from `other`, except `omitted`.
    function _difference(address[] memory set, address[] memory other, address omitted)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory buffer = new address[](set.length);
        uint256 count = 0;
        for (uint256 i = 0; i < set.length; i++) {
            if (set[i] != omitted && !_contains(other, set[i])) {
                buffer[count] = set[i];
                count++;
            }
        }
        return _truncated(buffer, count);
    }

    /// @dev Copies `buffer[0:count]` into an exactly sized array.
    function _truncated(address[] memory buffer, uint256 count) internal pure returns (address[] memory out) {
        out = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = buffer[i];
        }
    }
}
