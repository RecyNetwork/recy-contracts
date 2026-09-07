// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RestoreLegacyRoles} from "../script/RestoreLegacyRoles.s.sol";
import {ConfigManager} from "../script/config/ConfigManager.s.sol";
import {Test} from "forge-std/Test.sol";

contract RestoreLegacyRolesHarness is RestoreLegacyRoles {
    function planRoles(
        LegacySets memory legacy,
        ProxyConfig memory config,
        LegacyProxyConfig memory settings,
        address newFactory
    ) external pure returns (Plan memory) {
        return _plan(legacy, config, settings, newFactory);
    }
}

/// @dev Exercises the pure planner with inline fixtures. Every case defends the rule that no wallet may end up
///      holding both RECYCLER_ROLE and AUDITOR_ROLE and that privileged keys never receive an operational role.
contract RestoreLegacyRolesTest is Test {
    address private constant DUAL = address(0xD0A1);
    address private constant SINGLE_AUDITOR = address(0xA0D1);
    address private constant SINGLE_RECYCLER = address(0x0EC1);
    address private constant LEGACY_ADMIN = address(0xAD01);
    address private constant LEGACY_EMERGENCY = address(0xE001);
    address private constant CONFIG_ADMIN = address(0xAD02);
    address private constant CONFIG_EMERGENCY = address(0xE002);
    address private constant LEGACY_FACTORY = address(0xFAC1);
    address private constant NEW_FACTORY = address(0xFAC2);

    RestoreLegacyRolesHarness private harness;

    function setUp() public {
        harness = new RestoreLegacyRolesHarness();
    }

    function test_dualRoleWalletListedAsConfigRecyclerGetsRecyclerOnly() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.recyclers = _list(DUAL);
        legacy.auditors = _list(DUAL);
        ConfigManager.ProxyConfig memory config;
        config.recyclers = _list(DUAL);
        ConfigManager.LegacyProxyConfig memory settings;

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.recyclers.length, 1);
        assertEq(plan.recyclers[0], DUAL);
        assertEq(plan.auditors.length, 0);
        assertEq(plan.unresolved.length, 0);
    }

    function test_dualRoleWalletInKeepAuditorGetsAuditorOnly() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.recyclers = _list(DUAL);
        legacy.auditors = _list(DUAL);
        ConfigManager.ProxyConfig memory config;
        ConfigManager.LegacyProxyConfig memory settings;
        settings.keepAuditor = _list(DUAL);

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.auditors.length, 1);
        assertEq(plan.auditors[0], DUAL);
        assertEq(plan.recyclers.length, 0);
        assertEq(plan.unresolved.length, 0);
    }

    function test_dualRoleWalletWithoutDecisionIsUnresolved() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.recyclers = _list(DUAL, SINGLE_RECYCLER);
        legacy.auditors = _list(DUAL, SINGLE_AUDITOR);
        ConfigManager.ProxyConfig memory config;
        ConfigManager.LegacyProxyConfig memory settings;

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.unresolved.length, 1);
        assertEq(plan.unresolved[0], DUAL);
        assertFalse(_has(plan.recyclers, DUAL));
        assertFalse(_has(plan.auditors, DUAL));
        // The undecided wallet does not hold back the settled ones.
        assertEq(plan.recyclers.length, 1);
        assertEq(plan.recyclers[0], SINGLE_RECYCLER);
        assertEq(plan.auditors.length, 1);
        assertEq(plan.auditors[0], SINGLE_AUDITOR);
    }

    function test_privilegedKeysAndFactoriesAreNeverPlanned() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.recyclers = _list(LEGACY_ADMIN, LEGACY_EMERGENCY, LEGACY_FACTORY, NEW_FACTORY);
        legacy.auditors = _list(LEGACY_ADMIN, CONFIG_ADMIN, CONFIG_EMERGENCY, LEGACY_FACTORY);
        legacy.admins = _list(LEGACY_FACTORY, LEGACY_ADMIN);
        legacy.emergency = _list(LEGACY_FACTORY, LEGACY_EMERGENCY);
        legacy.factory = LEGACY_FACTORY;
        ConfigManager.ProxyConfig memory config;
        config.admins = _list(CONFIG_ADMIN);
        config.emergency = _list(CONFIG_EMERGENCY);
        ConfigManager.LegacyProxyConfig memory settings;
        // Even an explicit keep decision must not override the privilege rule.
        settings.keepRecycler = _list(LEGACY_ADMIN, LEGACY_FACTORY);

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.recyclers.length, 0);
        assertEq(plan.auditors.length, 0);
        assertEq(plan.unresolved.length, 0);
        assertEq(plan.excluded.length, 6);
        assertTrue(_has(plan.excluded, LEGACY_ADMIN));
        assertTrue(_has(plan.excluded, LEGACY_EMERGENCY));
        assertTrue(_has(plan.excluded, CONFIG_ADMIN));
        assertTrue(_has(plan.excluded, CONFIG_EMERGENCY));
        assertTrue(_has(plan.excluded, LEGACY_FACTORY));
        assertTrue(_has(plan.excluded, NEW_FACTORY));
        // Privileged differences are surfaced for a manual decision, without the legacy factory.
        assertEq(plan.adminDifferences.length, 1);
        assertEq(plan.adminDifferences[0], LEGACY_ADMIN);
        assertEq(plan.emergencyDifferences.length, 1);
        assertEq(plan.emergencyDifferences[0], LEGACY_EMERGENCY);
    }

    function test_excludeRemovesWallet() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.recyclers = _list(SINGLE_RECYCLER, DUAL);
        legacy.auditors = _list(DUAL);
        ConfigManager.ProxyConfig memory config;
        ConfigManager.LegacyProxyConfig memory settings;
        settings.exclude = _list(SINGLE_RECYCLER, DUAL);

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.recyclers.length, 0);
        assertEq(plan.auditors.length, 0);
        assertEq(plan.unresolved.length, 0);
        assertEq(plan.excluded.length, 2);
        assertTrue(_has(plan.excluded, SINGLE_RECYCLER));
        assertTrue(_has(plan.excluded, DUAL));
    }

    function test_legacyAuditorListedAsConfigRecyclerIsPlannedAsRecycler() public view {
        RestoreLegacyRoles.LegacySets memory legacy;
        legacy.auditors = _list(SINGLE_AUDITOR);
        ConfigManager.ProxyConfig memory config;
        config.recyclers = _list(SINGLE_AUDITOR);
        ConfigManager.LegacyProxyConfig memory settings;

        RestoreLegacyRoles.Plan memory plan = harness.planRoles(legacy, config, settings, NEW_FACTORY);

        assertEq(plan.recyclers.length, 1);
        assertEq(plan.recyclers[0], SINGLE_AUDITOR);
        assertEq(plan.auditors.length, 0);
    }

    function _has(address[] memory list, address wallet) private pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == wallet) return true;
        }
        return false;
    }

    function _list(address a) private pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = a;
    }

    function _list(address a, address b) private pure returns (address[] memory list) {
        list = new address[](2);
        list[0] = a;
        list[1] = b;
    }

    function _list(address a, address b, address c, address d) private pure returns (address[] memory list) {
        list = new address[](4);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        list[3] = d;
    }
}
