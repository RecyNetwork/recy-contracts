// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../src/RecyReport.sol";
import "../../src/RecyReportData.sol";
import {RecyTypes} from "../../src/lib/RecyTypes.sol";
import "../config/ConfigManager.s.sol";
import "forge-std/Script.sol";

/**
 * @title RecyReportDataRedeploy
 * @notice Phase 1 of the security remediation: deploy the repaired RecyReportData and print the
 *         exact `setDataContract` call the proxy admin must then make.
 * @dev Distinct from RecyReportDataDeploy, which deploys RecyReportAttributes / RecyReportSvg when
 *      they are missing from config. That behaviour is unsafe for a live proxy: a fresh attributes
 *      contract would renumber the material catalogue, and 64 live reports store raw material
 *      indices (security-audit-remediation.md 3.8). This script therefore REQUIRES both addresses
 *      to already exist in config and reuses them verbatim.
 *
 *      Phase 1 needs no proxy upgrade — `setDataContract` (src/RecyReport.sol:477) is a plain
 *      DEFAULT_ADMIN_ROLE call on the existing proxy.
 *
 *      Environment flags:
 *      - `proxy`           name of the proxy config to target (default: "default")
 *      - `CONFIRM_DEPLOY`  must be `true` to enter `vm.startBroadcast()`. Without it the script is
 *                          a dry run even when `--broadcast` is passed: it simulates the
 *                          deployment, runs every verification below, and sends nothing.
 *
 *      Dry run:
 *        forge script script/deploy/RecyReportDataRedeploy.s.sol:RecyReportDataRedeploy --rpc-url sepolia
 *      Real deployment:
 *        CONFIRM_DEPLOY=true forge script script/deploy/RecyReportDataRedeploy.s.sol:RecyReportDataRedeploy \
 *          --rpc-url sepolia --account deployer --broadcast
 */
contract RecyReportDataRedeploy is Script, ConfigManager {
    /// @dev Deliberately out of catalogue range: proves the new contract's read-time tolerance.
    uint32 private constant POISON_MATERIAL_ID = type(uint32).max;

    function run() public {
        uint256 chainId = block.chainid;
        string memory proxyName = vm.envOr("proxy", string("default"));

        NetworkConfig memory networkConfig = getNetworkConfig(chainId);
        ProxyConfig memory proxyConfig = getProxyConfig(chainId, proxyName);

        _preflight(chainId, proxyName, networkConfig, proxyConfig);

        bool confirmed = vm.envOr("CONFIRM_DEPLOY", false);

        if (confirmed) {
            vm.startBroadcast();
        }

        RecyReportData newData = new RecyReportData(networkConfig.reportAttributes, networkConfig.reportSvg);

        if (confirmed) {
            vm.stopBroadcast();
        }

        _verify(newData, networkConfig);
        _printHandover(newData, proxyConfig, confirmed);
    }

    /**
     * @notice Echo the pre-flight checklist and abort on anything that would produce a bad deploy
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
        console.log("=== Phase 1: RecyReportData redeploy ===");
        console.log("Chain ID:", chainId);
        console.log("Network:", networkConfig.name);
        console.log("Target proxy config:", proxyName);
        console.log("Target proxy address:", proxyConfig.proxy);

        console.log("\n--- Pre-flight checklist ---");
        console.log("[ ] 1. This deploys metadata code only. No proxy upgrade, no state migration.");
        console.log("[ ] 2. RecyReportAttributes and RecyReportSvg are REUSED, never redeployed:");
        console.log("       attributes:", networkConfig.reportAttributes);
        console.log("       svg:       ", networkConfig.reportSvg);
        console.log("       Deploying fresh attributes would renumber material ids that 64 live");
        console.log("       reports already store. If the catalogue must change, that is a");
        console.log("       separate migration (security-audit-remediation.md 3.8).");
        console.log("[ ] 3. Phase 1 MUST land before the Phase 2 implementation upgrade: Phase 2's");
        console.log("       write-time material validation calls data.materialsCount(), which the");
        console.log("       currently deployed RecyReportData does not have.");
        console.log("[ ] 4. After deployment an admin must call setDataContract on the proxy.");
        console.log("       Until then the proxy keeps serving the old, malformed tokenURI.");
        console.log("[ ] 5. Verify tokenURI(1) parses as JSON after setDataContract.");

        require(
            networkConfig.reportAttributes != address(0),
            "reportAttributes missing from config. Refusing to deploy a data contract wired to a fresh catalogue."
        );
        require(
            networkConfig.reportSvg != address(0),
            "reportSvg missing from config. Refusing to deploy a data contract wired to a fresh SVG contract."
        );
        require(networkConfig.reportAttributes.code.length > 0, "reportAttributes in config has no code on this chain");
        require(networkConfig.reportSvg.code.length > 0, "reportSvg in config has no code on this chain");
        require(proxyConfig.proxy != address(0), "Proxy address not found in config for the requested proxy name");
    }

    /**
     * @notice Prove the freshly built data contract fixes what Phase 1 is supposed to fix
     * @dev Exercises the two remediation targets directly: the malformed `tokenURI` JSON
     *      (security-audit-remediation.md 3.4) and read-time tolerance of an out-of-range material
     *      id (3.3 part 2). Both run against the just-built instance, in dry run and for real.
     * @param newData The freshly deployed data contract
     * @param networkConfig The network config, for the reward token used in metadata
     */
    function _verify(RecyReportData newData, NetworkConfig memory networkConfig) internal view {
        console.log("\n--- Verification ---");
        require(address(newData.attributes()) == networkConfig.reportAttributes, "attributes wiring mismatch");
        require(address(newData.svg()) == networkConfig.reportSvg, "svg wiring mismatch");
        console.log("attributes()/svg() wiring: OK");

        uint256 materialsCount = newData.materialsCount();
        console.log("materialsCount():", materialsCount);
        require(materialsCount > 0, "materialsCount() returned 0");

        RecyTypes.RecyReward memory reward = RecyTypes.RecyReward({rewardAmount: 1e18, rewardUnlockDate: 1});
        RecyTypes.RecyInfo memory info = RecyTypes.RecyInfo({
            validator: address(0xA11CE), recycler: address(0xB0B), recycleDate: 1, auditDate: 2, wasteAmount: 10_000_000
        });

        // One in-range material and one deliberately out of range: the old data contract reverts
        // on the second, permanently bricking that token's metadata.
        RecyTypes.RecyMaterials[] memory materials = new RecyTypes.RecyMaterials[](2);
        materials[0] = RecyTypes.RecyMaterials({
            material: 0, recycleType: 0, recycleShape: 0, disposalMethod: 0, amountRecycled: 5_000_000
        });
        materials[1] = RecyTypes.RecyMaterials({
            material: POISON_MATERIAL_ID, recycleType: 0, recycleShape: 0, disposalMethod: 0, amountRecycled: 5_000_000
        });

        // RECYCLE_REWARDED: the status every live token that matters is in.
        string memory json = newData.tokenJson(1, 4, ERC20(networkConfig.token), reward, info, materials);
        console.log("tokenJson with an out-of-range material id did not revert. Output:");
        console.log(json);

        // The 3.4 proof must be programmatic, not eyeballed: the OLD data contract also returned
        // successfully here - malformed JSON, not a revert, was the defect. vm.parseJson reverts
        // on anything a strict parser rejects, so a wrong-artifact deploy fails right here.
        // The returned bytes are deliberately discarded; successful strict parsing is the validation.
        // forge-lint: disable-next-line(unused-return)
        vm.parseJson(json);
        console.log("\ntokenJson parses as strict JSON: PASS");

        string memory uri = newData.tokenUriAttributes(1, 4, ERC20(networkConfig.token), reward, info, materials);
        console.log("\ntokenUriAttributes did not revert. Base64 payload:");
        console.log(uri);

        bytes memory uriBytes = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        require(uriBytes.length > prefix.length, "tokenUriAttributes: payload too short");
        // The script must compare each prefix byte because Solidity has no memory-bytes startsWith operation.
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i = 0; i < prefix.length; i++) {
            require(uriBytes[i] == prefix[i], "tokenUriAttributes: missing data-URI prefix");
        }
        // forge-lint: disable-end(require-revert-in-loop)
        console.log("\ntokenUriAttributes carries the data:application/json;base64, prefix: PASS");
        console.log("(Its payload is built from the same attribute fragments tokenJson just");
        console.log(" strict-parsed; the decoded-payload parse is pinned in the unit suite.)");
        console.log("\nDecode and validate the payload above yourself if desired, e.g.:");
        console.log(
            "  cast call <proxy> 'tokenURI(uint256)(string)' 1 | sed 's#^\"data:application/json;base64,##; s#\"$##'"
            " | base64 -d | jq -e ."
        );
    }

    /**
     * @notice Print the exact admin call required to activate the new data contract
     * @param newData The freshly deployed data contract
     * @param proxyConfig The proxy config identifying the live proxy
     * @param confirmed Whether this run actually broadcast
     */
    function _printHandover(RecyReportData newData, ProxyConfig memory proxyConfig, bool confirmed) internal pure {
        console.log("\n=== Handover ===");

        if (!confirmed) {
            console.log("DRY RUN. Nothing was deployed and nothing was sent.");
            console.log("The address below is a SIMULATED address and will differ on a real run.");
            console.log("Re-run with CONFIRM_DEPLOY=true --broadcast to deploy for real.");
        }

        console.log("New RecyReportData:", address(newData));
        console.log("\n1. Update config/contracts.json -> contracts.reportData:", address(newData));
        console.log("\n2. Activate it on the live proxy (DEFAULT_ADMIN_ROLE, one transaction):");
        console.log("   cast send", proxyConfig.proxy, string.concat('"setDataContract(address)" ', "<new data>"));
        console.log("\n3. Verify. `data` is a PRIVATE variable (src/RecyReport.sol:29) so there is");
        console.log("   no getter; read storage slot 0 instead:");
        console.log("   cast storage", proxyConfig.proxy, "0");
        console.log("\n4. Re-check tokenURI(1) decodes as valid JSON before starting Phase 2.");
    }
}
