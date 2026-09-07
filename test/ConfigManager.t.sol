// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ConfigManager} from "../script/config/ConfigManager.s.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract ConfigManagerHarness is ConfigManager {
    function parseProxySettings(string memory json) external pure {
        ProxyConfig memory config;
        _readProxySettings(json, "1", "report", config);
    }

    function parseLegacyDecisionLists(string memory json) external view returns (LegacyProxyConfig memory config) {
        _readLegacyDecisionLists(json, ".1.proxies.report.legacy", config);
    }
}

contract ConfigManagerTest is Test {
    // These values previously wrapped to 3,600 and 25, producing plausible settings with shares totaling 100.
    uint256 private constant OVERSIZED_UNLOCK_DELAY = 18_446_744_073_709_555_216;
    uint256 private constant OVERSIZED_RECYCLER_SHARE = 281;

    string private constant OVERSIZED_UNLOCK_DELAY_CONFIG =
        '{"1":{"proxies":{"report":{"settings":{"unlockDelay":18446744073709555216,"shareRecycler":25,"shareValidator":25,"shareGenerator":25,"shareProtocol":25}}}}}';
    string private constant OVERSIZED_RECYCLER_SHARE_CONFIG =
        '{"1":{"proxies":{"report":{"settings":{"unlockDelay":3600,"shareRecycler":281,"shareValidator":25,"shareGenerator":25,"shareProtocol":25}}}}}';
    address private constant EXCLUDED_HOLDER = address(0xBEEF);

    string private constant LEGACY_WITHOUT_DECISION_LISTS_CONFIG = '{"1":{"proxies":{"report":{"legacy":{}}}}}';
    string private constant LEGACY_WITH_EXPLICIT_EXCLUSION_CONFIG =
        '{"1":{"proxies":{"report":{"legacy":{"exclude":["0x000000000000000000000000000000000000beef"]}}}}}';
    string private constant LEGACY_WITH_MALFORMED_KEEP_RECYCLER_CONFIG =
        '{"1":{"proxies":{"report":{"legacy":{"keepRecycler":["not-an-address"]}}}}}';
    string private constant LEGACY_WITH_MALFORMED_KEEP_AUDITOR_CONFIG =
        '{"1":{"proxies":{"report":{"legacy":{"keepAuditor":["not-an-address"]}}}}}';
    string private constant LEGACY_WITH_MALFORMED_EXCLUSION_CONFIG =
        '{"1":{"proxies":{"report":{"legacy":{"exclude":["0x000000000000000000000000000000000000beef","not-an-address"]}}}}}';

    ConfigManagerHarness private configManager;

    function setUp() public {
        configManager = new ConfigManagerHarness();
    }

    function test_parseProxySettingsRejectsOversizedUnlockDelay() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 64, OVERSIZED_UNLOCK_DELAY)
        );
        configManager.parseProxySettings(OVERSIZED_UNLOCK_DELAY_CONFIG);
    }

    function test_parseProxySettingsRejectsOversizedRecyclerShare() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 8, OVERSIZED_RECYCLER_SHARE)
        );
        configManager.parseProxySettings(OVERSIZED_RECYCLER_SHARE_CONFIG);
    }

    function test_parseLegacyDecisionListsSupportsMissingOptionalFields() public view {
        ConfigManager.LegacyProxyConfig memory config =
            configManager.parseLegacyDecisionLists(LEGACY_WITHOUT_DECISION_LISTS_CONFIG);

        assertEq(config.keepRecycler.length, 0);
        assertEq(config.keepAuditor.length, 0);
        assertEq(config.exclude.length, 0);
    }

    function test_parseLegacyDecisionListsPreservesExplicitExclusion() public view {
        ConfigManager.LegacyProxyConfig memory config =
            configManager.parseLegacyDecisionLists(LEGACY_WITH_EXPLICIT_EXCLUSION_CONFIG);

        assertEq(config.exclude.length, 1);
        assertEq(config.exclude[0], EXCLUDED_HOLDER);
    }

    function test_parseLegacyDecisionListsRejectsMalformedKeepLists() public {
        _expectMalformedLegacyDecisionList(LEGACY_WITH_MALFORMED_KEEP_RECYCLER_CONFIG);
        _expectMalformedLegacyDecisionList(LEGACY_WITH_MALFORMED_KEEP_AUDITOR_CONFIG);
    }

    function test_malformedExclusionCannotEraseExplicitlyExcludedHolder() public {
        _expectMalformedLegacyDecisionList(LEGACY_WITH_MALFORMED_EXCLUSION_CONFIG);
    }

    function _expectMalformedLegacyDecisionList(string memory json) internal {
        vm.expectRevert();
        // forge-lint: disable-next-line(unused-return)
        configManager.parseLegacyDecisionLists(json);
    }
}
