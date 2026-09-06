// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../../src/RecyReport.sol";
import "../../src/RecyReportFactory.sol";
import "../config/ConfigManager.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RecyReportImplementationUpgrade
 * @notice Phase 2 of the security remediation: deploy the hardened RecyReport implementation and
 *         print the exact upgrade call the operator must then make.
 * @dev This script deploys an implementation. It never upgrades anything: the upgrade is a
 *      separate, deliberate transaction so the OZ upgrade-safety validator and a human can sit
 *      between the two steps.
 *      WARNING: Historical testnet proxies use an incompatible storage layout. Do not run this
 *      upgrade flow for them; deploy a fresh stack instead.
 *
 *      HARD ORDERING CONSTRAINT. The Phase 1 RecyReportData must already be live on the proxy
 *      before this implementation is activated. The new implementation validates material ids at
 *      write time by calling `data.materialsCount()`, which does not exist on the previously
 *      deployed data contract — upgrading first makes both write paths revert. This script reads
 *      the proxy's installed data contract and aborts if it cannot answer `materialsCount()`.
 *
 *      Environment flags:
 *      - `proxy`           name of the proxy config to target (default: "default")
 *      - `CONFIRM_DEPLOY`  must be `true` to enter `vm.startBroadcast()`. Without it the script is
 *                          a dry run even when `--broadcast` is passed.
 *
 *      Dry run (also the ordering pre-check — safe to run any time):
 *        forge script script/deploy/RecyReportImplementationUpgrade.s.sol:RecyReportImplementationUpgrade \
 *          --rpc-url sepolia
 *      Real deployment:
 *        CONFIRM_DEPLOY=true forge script \
 *          script/deploy/RecyReportImplementationUpgrade.s.sol:RecyReportImplementationUpgrade \
 *          --rpc-url sepolia --account deployer --broadcast
 */
contract RecyReportImplementationUpgrade is Script, ConfigManager {
    /// @dev EIP-1967 implementation slot.
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev `RecyReport.data` is the first declared variable and is private (src/RecyReport.sol:29).
    bytes32 private constant DATA_SLOT = bytes32(uint256(0));

    /// @dev unlockDelay the live proxy should be retuned to once the upgrade ships setUnlockDelay.
    uint64 private constant TARGET_UNLOCK_DELAY = 86_400;

    function setUp() public {}

    function run() public {
        uint256 chainId = block.chainid;
        string memory proxyName = vm.envOr("proxy", string("default"));

        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, proxyName);

        _preflight(chainId, proxyName, networkConfig, proxyConfig);
        _assertPhaseOneLanded(proxyConfig.proxy);
        _assertPoolSolvent(proxyConfig.proxy, networkConfig.token);

        bool confirmed = vm.envOr("CONFIRM_DEPLOY", false);

        if (confirmed) {
            vm.startBroadcast();
        }

        RecyReport newImplementation = new RecyReport();

        if (confirmed) {
            vm.stopBroadcast();
        }

        _printHandover(address(newImplementation), networkConfig, proxyConfig, confirmed);
    }

    /**
     * @notice Echo the pre-flight checklist and abort on missing configuration
     * @param chainId The chain being targeted
     * @param proxyName The proxy config key being targeted
     * @param networkConfig The network config
     * @param proxyConfig The proxy config
     */
    function _preflight(
        uint256 chainId,
        string memory proxyName,
        NetworkConfig memory networkConfig,
        ProxyConfig memory proxyConfig
    ) internal view {
        console.log("=== Phase 2: RecyReport implementation upgrade ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", networkConfig.name);
        console.log("Target proxy config:", proxyName);
        console.log("Target proxy address:", proxyConfig.proxy);

        require(proxyConfig.proxy != address(0), "Proxy address not found in config for the requested proxy name");
        require(proxyConfig.proxy.code.length > 0, "Proxy in config has no code on this chain");
        require(networkConfig.factory != address(0), "Factory address not found in config");

        console.log("\n--- Pre-flight checklist ---");
        console.log("[ ] 1. Phase 1 RecyReportData is deployed AND setDataContract has been called.");
        console.log("       Checked automatically below; the script aborts if it has not.");
        console.log("[ ] 2. OZ upgrade-safety validator has been run against the deployed");
        console.log("       implementation and reports no storage-layout break:");
        console.log("         forge clean && forge build --build-info");
        console.log("         npx @openzeppelin/upgrades-core validate out/build-info \\");
        console.log("           --contract src/RecyReport.sol:RecyReport --requireReference \\");
        console.log("           --reference <previous build-info>:RecyReport");
        console.log("[ ] 3. RecyReport reserves NO __gap. New variables must be appended after");
        console.log("       `mapping(address => address) public funds` (src/RecyReport.sol:63) and");
        console.log("       `rewardMinted` (:55) must still occupy its slot.");
        console.log("[ ] 4. `initialize` still has 10 parameters and an unchanged selector: the");
        console.log("       factory is immutable and hardcodes it (src/RecyReportFactory.sol:107).");
        console.log("[ ] 5. Phase 0 role revocations are already applied:");
        console.log("         forge script script/ManageRoles.s.sol:ManageRoles \\");
        console.log("           --sig 'checkSeparationOnChain()' --rpc-url <rpc>");
        console.log("[ ] 6. Announced to participants: setFundsWallet becomes self-service and the");
        console.log("       two-argument admin form stops existing at this upgrade.");
        console.log("[ ] 7. Announced to recy-api: POST /set-result starts returning 409");
        console.log("       REPORT_INVALID_STATUS for non-CREATED tokens.");
        console.log("[ ] 8. Pool solvency: checked automatically below; the script aborts if the");
        console.log("       live accumulators would make the new validate-time check revert.");
    }

    /**
     * @notice Abort unless the proxy's installed data contract answers `materialsCount()`
     * @dev The Phase 2 implementation validates material ids at write time through
     *      `data.materialsCount()`. The pre-Phase-1 data contract has no such function, so
     *      activating this implementation before `setDataContract` would make `mintRecyReportResult`
     *      and `setRecyReportResult` revert for every caller. `data` is private, so the address is
     *      read straight out of storage slot 0 and probed with a low-level staticcall — the probe
     *      must not depend on the compiled ABI of whatever is deployed there.
     * @param proxy The live proxy to inspect
     */
    function _assertPhaseOneLanded(address proxy) internal view {
        address installedData = address(uint160(uint256(vm.load(proxy, DATA_SLOT))));

        console.log("\n--- Ordering check: Phase 1 before Phase 2 ---");
        console.log("Proxy data contract (slot 0):", installedData);

        require(installedData != address(0), "Proxy has no data contract installed");

        (bool ok, bytes memory returned) = installedData.staticcall(abi.encodeWithSignature("materialsCount()"));

        require(
            ok && returned.length == 32,
            string.concat(
                "ORDERING VIOLATION: the data contract installed on ",
                vm.toString(proxy),
                " (",
                vm.toString(installedData),
                ") does not answer materialsCount(). Deploy the Phase 1 RecyReportData and call ",
                "setDataContract BEFORE upgrading the implementation, or every write path reverts. ",
                "See script/deploy/RecyReportDataRedeploy.s.sol."
            )
        );

        console.log("materialsCount():", abi.decode(returned, (uint256)));
        console.log("Ordering check: PASS (Phase 1 data contract is live).");
    }

    /**
     * @notice Abort if the live proxy's accumulators violate the new solvency invariant
     * @dev The upgraded validateRecyReport enforces `rewardTotal <= balanceOf(proxy) + rewardClaimed`
     *      as a CONTRACT-WIDE invariant, but the live accumulators were built under the old rules
     *      (no status guard, nothing ever decremented) and were never checked against the balance.
     *      If the proxy arrives at the upgrade with `rewardTotal - rewardClaimed > balance`, every
     *      validateRecyReport reverts InsufficientRewardBalance from the moment the upgrade lands
     *      until the pool is topped up - a self-inflicted outage this pre-flight turns into a
     *      failed script with an exact top-up amount. Live values read 2026-08-11: rewardTotal
     *      ~10,368.08e18, rewardClaimed ~368.07e18, balance ~10,009,631.93e18 - outstanding
     *      ~10,000e18, roughly 1000x headroom. The check stays load-bearing anyway: validations
     *      before the upgrade still run under the unchecked old code and can move these numbers.
     * @param proxy The live proxy
     * @param token The reward token wired into that proxy
     */
    function _assertPoolSolvent(address proxy, address token) internal view {
        uint256 total = RecyReport(proxy).rewardTotal();
        uint256 claimed = RecyReport(proxy).rewardClaimed();
        uint256 balance = IERC20(token).balanceOf(proxy);
        uint256 outstanding = total > claimed ? total - claimed : 0;

        console.log("\n--- Solvency check: outstanding obligations vs pool balance ---");
        console.log("rewardTotal:  ", total);
        console.log("rewardClaimed:", claimed);
        console.log("balance:      ", balance);
        console.log("outstanding:  ", outstanding);

        require(
            outstanding <= balance,
            string.concat(
                "SOLVENCY VIOLATION: outstanding obligations (rewardTotal - rewardClaimed = ",
                vm.toString(outstanding),
                ") exceed the pool balance (",
                vm.toString(balance),
                "). The upgraded validateRecyReport enforces outstanding <= balance as an invariant, ",
                "so upgrading now halts ALL validation until the pool is topped up. Transfer at least ",
                vm.toString(outstanding - balance),
                " wei of the reward token to the proxy, then re-run."
            )
        );

        console.log("Solvency check: PASS (the upgrade cannot strand validation).");
    }

    /**
     * @notice Print the exact upgrade call and the follow-up admin calls
     * @param newImplementation The freshly deployed implementation
     * @param networkConfig The network config, for the factory address
     * @param proxyConfig The proxy config identifying the live proxy
     * @param confirmed Whether this run actually broadcast
     */
    function _printHandover(
        address newImplementation,
        NetworkConfig memory networkConfig,
        ProxyConfig memory proxyConfig,
        bool confirmed
    ) internal view {
        address currentImplementation = address(uint160(uint256(vm.load(proxyConfig.proxy, IMPLEMENTATION_SLOT))));

        console.log("\n=== Handover ===");

        if (!confirmed) {
            console.log("DRY RUN. Nothing was deployed and nothing was sent.");
            console.log("The address below is a SIMULATED address and will differ on a real run.");
            console.log("Re-run with CONFIRM_DEPLOY=true --broadcast to deploy for real.");
        }

        console.log("Current implementation:", currentImplementation);
        console.log("New implementation:    ", newImplementation);

        console.log("\n1. Update config/contracts.json -> contracts.reportImplementation.");
        console.log("\n2. Upgrade the proxy. Preferred route, from the factory owner key:");
        console.log("   forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade \\");
        console.log("     --sig 'upgradeProxy(address,address)'", proxyConfig.proxy, "<new implementation> \\");
        console.log("     --rpc-url <rpc> --account <factory owner> --broadcast");
        console.log("   Factory:", networkConfig.factory);
        console.log("   Direct route, from a DEFAULT_ADMIN_ROLE key on the proxy:");
        console.log("     cast send", proxyConfig.proxy, '"upgradeToAndCall(address,bytes)" <new implementation> 0x');

        console.log("\n3. Immediately after the upgrade, from a DEFAULT_ADMIN_ROLE key:");
        console.log("   cast send", proxyConfig.proxy, '"setUnlockDelay(uint64)" 86400');
        console.log("   Target unlockDelay (seconds):", TARGET_UNLOCK_DELAY);
        console.log("   Until this lands the live proxy keeps its 60 second delay.");

        console.log("\n4. Verify (read-only) before declaring the upgrade done:");
        console.log(
            "   cast storage", proxyConfig.proxy, "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
        );
        console.log("   cast call", proxyConfig.proxy, '"unlockDelay()(uint64)"');
        console.log("   Then run the status-guard and dual-control revert checks in");
        console.log("   docs/plan/remediation-runbook.md.");

        console.log("\n5. Note: RecyReportFactory.setRecyclerFund / setAuditorFund are DEAD after");
        console.log("   this upgrade. They call the deleted two-argument setFundsWallet and will");
        console.log("   revert. Fund wallets are self-service from now on.");
    }
}
