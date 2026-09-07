// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyReport} from "../../src/RecyReport.sol";
import {RecyReportAttributes} from "../../src/RecyReportAttributes.sol";
import {RecyReportData} from "../../src/RecyReportData.sol";
import {RecyReportFactoryV2} from "../../src/RecyReportFactoryV2.sol";
import {RecyReportSvg} from "../../src/RecyReportSvg.sol";
import {RecyToken} from "../../src/RecyToken.sol";
import {RecyConstants} from "../../src/lib/RecyConstants.sol";
import {ManageRoles} from "../ManageRoles.s.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Deploys and verifies one complete, fresh report stack on the configured issuance chain.
/// @dev `proxy=<key>` selects the proxy configuration and defaults to `default`.
contract RecyReportDeploy is ManageRoles {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant DATA_SLOT = bytes32(uint256(0));
    uint256 private constant MAX_PROXY_NAME_LENGTH = 64;
    /// @dev Foundry's script sender when neither `--sender` nor an eagerly unlocked signer supplies one.
    address private constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    struct Stack {
        address attributes;
        address svg;
        address data;
        address implementation;
        address factoryAddress;
        address proxyAddress;
    }

    struct TokenSnapshot {
        uint256 totalIssued;
        uint256 totalSupply;
        uint256 ownerBalance;
        uint256 issuanceChainId;
        address owner;
        address endpoint;
    }

    /// @dev ManageRoles normally loads recorded addresses here. A fresh deployment assigns them after CREATE.
    // forge-lint: disable-next-line(empty-block)
    function setUp() public override {}

    /// @notice Simulates, broadcasts and records a complete fresh stack through one Foundry invocation.
    /// @dev Foundry predeploys the linked `RecyReward` library from the script sender (`msg.sender` here).
    /// When a signer is unlocked only during execution (interactive `--account`, hardware wallets), the
    /// first pass runs with Foundry's default sender: the library does not consume the broadcaster's
    /// nonce, so every simulated CREATE lands one nonce early. Foundry discards that pass and re-executes
    /// with the broadcaster as sender, so only the pass whose script sender is the broadcaster may record.
    function run() public {
        string memory proxyKey = _selectedProxyKey();
        NetworkConfig memory network = getNetworkConfig(block.chainid);
        ProxyConfig memory config = getProxyConfig(block.chainid, proxyKey);
        RecyToken token = _preflightFreshDeployment(network, config);

        address broadcaster = _broadcastSender();
        require(broadcaster == network.tokenOwner, "broadcaster is not the configured token owner");
        bool senderInferencePass = msg.sender != broadcaster;
        require(
            !senderInferencePass || msg.sender == FOUNDRY_DEFAULT_SENDER,
            "script sender differs from the broadcaster; pass --sender <token owner>"
        );
        TokenSnapshot memory tokenBefore = _snapshotToken(token, broadcaster);

        console2.log("=== Fresh RecyReport stack ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Network:", network.name);
        console2.log("Proxy config key:", proxyKey);
        console2.log("Broadcaster / owner:", broadcaster);

        vm.startBroadcast();
        (Stack memory stack, uint256 roleRevocations) = _deployAndConfigure(network, config);
        vm.stopBroadcast();

        require(roleRevocations == 2, "fresh proxy must revoke both factory operational roles");
        _assertStack(network, config, stack);
        _assertTokenUnchanged(token, broadcaster, tokenBefore);
        if (senderInferencePass) {
            console2.log(
                "Sender-inference pass: Foundry re-runs with the broadcaster as sender; registry left unchanged."
            );
            return;
        }
        _recordPlannedAddresses(stack, proxyKey);
        _logDeployment(stack, roleRevocations);
    }

    /// @notice Verifies the recorded live stack without requiring or opening a signing context.
    function check() public {
        string memory proxyKey = _selectedProxyKey();
        NetworkConfig memory network = getNetworkConfig(block.chainid);
        ProxyConfig memory config = getProxyConfig(block.chainid, proxyKey);
        _validateDeploymentInputs(network, config);

        Stack memory stack = Stack({
            attributes: network.reportAttributes,
            svg: network.reportSvg,
            data: network.reportData,
            implementation: network.reportImplementation,
            factoryAddress: network.factory,
            proxyAddress: config.proxy
        });
        _requireCompleteRecordedStack(stack);

        factory = RecyReportFactoryV2(stack.factoryAddress);
        proxy = RecyReport(stack.proxyAddress);
        _assertStack(network, config, stack);

        console2.log("Recorded RecyReport stack is valid.");
        _logAddresses(stack);
    }

    function _selectedProxyKey() private view returns (string memory proxyKey) {
        proxyKey = vm.envOr("proxy", string("default"));
        require(bytes(proxyKey).length != 0, "proxy config key is empty");
    }

    function _preflightFreshDeployment(NetworkConfig memory network, ProxyConfig memory config)
        private
        view
        returns (RecyToken token)
    {
        token = _validateDeploymentInputs(network, config);
        require(
            network.reportAttributes == address(0) && network.reportSvg == address(0)
                && network.reportData == address(0) && network.reportImplementation == address(0)
                && network.factory == address(0) && config.proxy == address(0),
            "report stack registry is not empty; never rerun a partial deployment, use Foundry --resume"
        );
    }

    function _validateDeploymentInputs(NetworkConfig memory network, ProxyConfig memory config)
        private
        view
        returns (RecyToken token)
    {
        require(network.issuanceChainId != 0, "issuance chain is not configured");
        require(block.chainid == network.issuanceChainId, "report stack must deploy on the configured issuance chain");
        require(network.tokenOwner != address(0), "token owner is not configured");
        require(network.protocol != address(0), "protocol recipient is not configured");
        require(network.token != address(0), "token is not configured");
        require(network.token.code.length != 0, "configured token has no code");
        require(
            network.lzEndpoint != address(0) && network.lzEndpoint.code.length != 0, "configured endpoint has no code"
        );

        require(bytes(config.name).length != 0, "report name is empty");
        require(bytes(config.name).length <= MAX_PROXY_NAME_LENGTH, "report name exceeds factory limit");
        require(bytes(config.symbol).length != 0, "report symbol is empty");
        require(
            config.unlockDelay >= RecyConstants.MIN_UNLOCK_DELAY
                && config.unlockDelay <= RecyConstants.MAX_UNLOCK_DELAY,
            "configured unlock delay is out of bounds"
        );
        require(
            uint256(config.shareRecycler) + uint256(config.shareValidator) + uint256(config.shareGenerator)
                    + uint256(config.shareProtocol) == RecyConstants.REWARD_TOTAL_PERCENTAGE,
            "configured reward shares do not total 100"
        );

        _assertConfigRoleSeparation(config);
        _assertRoleList(config.recyclers);
        _assertRoleList(config.auditors);
        _assertRoleList(config.admins);
        _assertRoleList(config.emergency);

        token = RecyToken(network.token);
        require(keccak256(bytes(token.name())) == keccak256(bytes("RecyToken")), "configured token name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes("cRECY")), "configured token symbol mismatch");
        require(token.issuanceChainId() == network.issuanceChainId, "token issuance chain mismatch");
        require(token.owner() == network.tokenOwner, "token owner mismatch");
        require(address(token.endpoint()) == network.lzEndpoint, "token endpoint mismatch");
    }

    // Invalid operator configuration must abort the entire plan before any broadcast.
    // forge-lint: disable-start(require-revert-in-loop)
    function _assertRoleList(address[] memory principals) private pure {
        for (uint256 i = 0; i < principals.length; ++i) {
            require(principals[i] != address(0), "role config contains the zero address");
            for (uint256 j = 0; j < i; ++j) {
                require(principals[j] != principals[i], "role config contains a duplicate address");
            }
        }
    }
    // forge-lint: disable-end(require-revert-in-loop)

    function _broadcastSender() private returns (address broadcaster) {
        vm.startBroadcast();
        // Foundry signer selection intentionally follows recurrent-broadcast msg.sender, as in RecyTokenDeploy.
        // forge-lint: disable-next-line(unused-return)
        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();
        vm.stopBroadcast();

        require(mode == VmSafe.CallerMode.RecurrentBroadcast, "Foundry broadcast signer is unavailable");
        return sender;
    }

    function _snapshotToken(RecyToken token, address tokenOwner) private view returns (TokenSnapshot memory snapshot) {
        snapshot.totalIssued = token.totalIssued();
        snapshot.totalSupply = token.totalSupply();
        snapshot.ownerBalance = token.balanceOf(tokenOwner);
        snapshot.issuanceChainId = token.issuanceChainId();
        snapshot.owner = token.owner();
        snapshot.endpoint = address(token.endpoint());
    }

    function _deployAndConfigure(NetworkConfig memory network, ProxyConfig memory config)
        private
        returns (Stack memory stack, uint256 roleRevocations)
    {
        RecyReportAttributes deployedAttributes = new RecyReportAttributes();
        RecyReportSvg deployedSvg = new RecyReportSvg();
        RecyReportData deployedData = new RecyReportData(address(deployedAttributes), address(deployedSvg));
        RecyReport deployedImplementation = new RecyReport();
        RecyReportFactoryV2 deployedFactory =
            new RecyReportFactoryV2(address(deployedImplementation), address(deployedData));
        address deployedProxy = deployedFactory.deployProxy(
            config.name,
            config.symbol,
            network.token,
            network.protocol,
            config.unlockDelay,
            config.shareRecycler,
            config.shareValidator,
            config.shareGenerator,
            config.shareProtocol
        );

        stack = Stack({
            attributes: address(deployedAttributes),
            svg: address(deployedSvg),
            data: address(deployedData),
            implementation: address(deployedImplementation),
            factoryAddress: address(deployedFactory),
            proxyAddress: deployedProxy
        });

        factory = deployedFactory;
        proxy = RecyReport(deployedProxy);
        _applyRolesFromConfig(config);
        roleRevocations = _revokeUnauthorizedOperationalRoles(config);
    }

    function _assertStack(NetworkConfig memory network, ProxyConfig memory config, Stack memory stack) private view {
        require(stack.attributes.code.length != 0, "registered attributes has no code");
        require(stack.svg.code.length != 0, "registered SVG has no code");
        require(stack.data.code.length != 0, "registered data contract has no code");
        require(stack.implementation.code.length != 0, "registered implementation has no code");
        require(stack.factoryAddress.code.length != 0, "registered factory has no code");
        require(stack.proxyAddress.code.length != 0, "registered proxy has no code");

        RecyReportAttributes deployedAttributes = RecyReportAttributes(stack.attributes);
        RecyReportSvg deployedSvg = RecyReportSvg(stack.svg);
        RecyReportData deployedData = RecyReportData(stack.data);
        RecyReportFactoryV2 deployedFactory = RecyReportFactoryV2(stack.factoryAddress);
        RecyReport deployedProxy = RecyReport(stack.proxyAddress);

        require(deployedAttributes.owner() == network.tokenOwner, "attributes owner mismatch");
        require(deployedSvg.owner() == network.tokenOwner, "SVG owner mismatch");
        require(bytes(deployedSvg.getTrashcan()).length != 0, "SVG renderer is empty");
        require(address(deployedData.attributes()) == stack.attributes, "data attributes wiring mismatch");
        require(address(deployedData.svg()) == stack.svg, "data SVG wiring mismatch");
        require(deployedData.materialsCount() == deployedAttributes.getMaterialsCount(), "metadata catalogue mismatch");

        require(deployedFactory.owner() == network.tokenOwner, "factory owner mismatch");
        require(deployedFactory.pendingOwner() == address(0), "factory has an unexpected pending owner");
        require(deployedFactory.implementation() == stack.implementation, "factory implementation mismatch");
        require(deployedFactory.dataContract() == stack.data, "factory data contract mismatch");
        require(deployedFactory.isDeployedProxy(stack.proxyAddress), "proxy is not a V2 factory member");
        require(deployedFactory.proxyByName(config.name) == stack.proxyAddress, "factory name lookup mismatch");
        require(
            keccak256(bytes(deployedFactory.nameByProxy(stack.proxyAddress))) == keccak256(bytes(config.name)),
            "factory reverse name lookup mismatch"
        );
        require(deployedFactory.getDeployedProxiesCount() == 1, "fresh factory proxy count mismatch");
        require(deployedFactory.getProxyNamesCount() == 1, "fresh factory name count mismatch");
        require(deployedFactory.deployedProxies(0) == stack.proxyAddress, "factory proxy enumeration mismatch");
        require(
            keccak256(bytes(deployedFactory.proxyNames(0))) == keccak256(bytes(config.name)),
            "factory name enumeration mismatch"
        );

        require(keccak256(bytes(deployedProxy.name())) == keccak256(bytes(config.name)), "report name mismatch");
        require(keccak256(bytes(deployedProxy.symbol())) == keccak256(bytes(config.symbol)), "report symbol mismatch");
        require(address(deployedProxy.token()) == network.token, "report token mismatch");
        require(deployedProxy.protocolAddress() == network.protocol, "report protocol mismatch");
        require(deployedProxy.unlockDelay() == config.unlockDelay, "report unlock delay mismatch");
        require(deployedProxy.shareRecycler() == config.shareRecycler, "report recycler share mismatch");
        require(deployedProxy.shareValidator() == config.shareValidator, "report validator share mismatch");
        require(deployedProxy.shareGenerator() == config.shareGenerator, "report generator share mismatch");
        require(deployedProxy.shareProtocol() == config.shareProtocol, "report protocol share mismatch");
        require(_addressAt(stack.proxyAddress, DATA_SLOT) == stack.data, "report data slot mismatch");
        require(
            _addressAt(stack.proxyAddress, IMPLEMENTATION_SLOT) == stack.implementation,
            "report implementation slot mismatch"
        );
        require(deployedProxy.trustedForwarder() == address(0), "fresh report forwarder must be disabled");

        _assertConfiguredRoles(config);
        _checkSeparationOnChain(config);
    }

    function _assertConfiguredRoles(ProxyConfig memory config) private view {
        address report = address(proxy);

        // Every configured principal is checked against the complete separation policy.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < config.admins.length; ++i) {
            address admin = config.admins[i];
            require(factory.hasAdminRole(report, admin), "configured admin role missing");
            require(!factory.hasRecyclerRole(report, admin), "configured admin has recycler role");
            require(!factory.hasAuditorRole(report, admin), "configured admin has auditor role");
        }
        for (uint256 i = 0; i < config.recyclers.length; ++i) {
            address recycler = config.recyclers[i];
            require(factory.hasRecyclerRole(report, recycler), "configured recycler role missing");
            require(!factory.hasAuditorRole(report, recycler), "configured recycler has auditor role");
            require(!factory.hasAdminRole(report, recycler), "configured recycler has admin role");
            require(!factory.hasEmergencyRole(report, recycler), "configured recycler has emergency role");
        }
        for (uint256 i = 0; i < config.auditors.length; ++i) {
            address auditor = config.auditors[i];
            require(factory.hasAuditorRole(report, auditor), "configured auditor role missing");
            require(!factory.hasRecyclerRole(report, auditor), "configured auditor has recycler role");
            require(!factory.hasAdminRole(report, auditor), "configured auditor has admin role");
            require(!factory.hasEmergencyRole(report, auditor), "configured auditor has emergency role");
        }
        for (uint256 i = 0; i < config.emergency.length; ++i) {
            address emergency = config.emergency[i];
            require(factory.hasEmergencyRole(report, emergency), "configured emergency role missing");
            require(!factory.hasRecyclerRole(report, emergency), "configured emergency has recycler role");
            require(!factory.hasAuditorRole(report, emergency), "configured emergency has auditor role");
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)

        require(factory.hasAdminRole(report, address(factory)), "factory admin role was removed");
        require(factory.hasEmergencyRole(report, address(factory)), "factory emergency role was removed");
        require(!factory.hasRecyclerRole(report, address(factory)), "factory still has recycler role");
        require(!factory.hasAuditorRole(report, address(factory)), "factory still has auditor role");
    }

    function _addressAt(address target, bytes32 slot) private view returns (address) {
        return address(uint160(uint256(vm.load(target, slot))));
    }

    function _assertTokenUnchanged(RecyToken token, address tokenOwner, TokenSnapshot memory before_) private view {
        require(token.totalIssued() == before_.totalIssued, "deployment changed token totalIssued");
        require(token.totalSupply() == before_.totalSupply, "deployment changed token totalSupply");
        // Exact equality proves non-interference within this single simulated execution, not a funding condition.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        require(token.balanceOf(tokenOwner) == before_.ownerBalance, "deployment changed token owner balance");
        require(token.issuanceChainId() == before_.issuanceChainId, "deployment changed token issuance chain");
        require(token.owner() == before_.owner, "deployment changed token owner");
        require(address(token.endpoint()) == before_.endpoint, "deployment changed token endpoint");
    }

    function _requireCompleteRecordedStack(Stack memory stack) private pure {
        require(
            stack.attributes != address(0) && stack.svg != address(0) && stack.data != address(0)
                && stack.implementation != address(0) && stack.factoryAddress != address(0)
                && stack.proxyAddress != address(0),
            "recorded report stack is incomplete"
        );
    }

    function _recordPlannedAddresses(Stack memory stack, string memory proxyKey) private {
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Dry run: config file left unchanged.");
            return;
        }

        string memory chainPath = string.concat(".", vm.toString(block.chainid));
        vm.writeJson(
            string.concat("\"", vm.toString(stack.attributes), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".contracts.reportAttributes")
        );
        vm.writeJson(
            string.concat("\"", vm.toString(stack.svg), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".contracts.reportSvg")
        );
        vm.writeJson(
            string.concat("\"", vm.toString(stack.data), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".contracts.reportData")
        );
        vm.writeJson(
            string.concat("\"", vm.toString(stack.implementation), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".contracts.reportImplementation")
        );
        vm.writeJson(
            string.concat("\"", vm.toString(stack.factoryAddress), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".contracts.factory")
        );
        vm.writeJson(
            string.concat("\"", vm.toString(stack.proxyAddress), "\""),
            CONFIG_PATH,
            string.concat(chainPath, ".proxies.", proxyKey, ".address")
        );
        // vm.writeJson drops the file's final newline; restore it so real deployments diff cleanly.
        vm.writeLine(CONFIG_PATH, "");

        console2.log("Recorded all six planned report-stack addresses.");
        console2.log("Recorded addresses are planned until every broadcast receipt succeeds.");
        console2.log("If sending is interrupted, keep the registry and resume Foundry's saved broadcast with --resume.");
    }

    function _logDeployment(Stack memory stack, uint256 roleRevocations) private pure {
        console2.log("Local simulation and all postchecks passed.");
        _logAddresses(stack);
        console2.log("Registry addresses produced: 6");
        console2.log("Direct stack CREATE calls: 5");
        console2.log("Factory deployProxy calls (proxy CREATE is internal): 1");
        console2.log("Factory operational-role revocation calls:", roleRevocations);
        console2.log("Token mint/transfer/ownership calls: 0");
        console2.log("Foundry's broadcast artifact is the transaction authority; linked libraries add deployments.");
    }

    function _logAddresses(Stack memory stack) private pure {
        console2.log("RecyReportAttributes:", stack.attributes);
        console2.log("RecyReportSvg:", stack.svg);
        console2.log("RecyReportData:", stack.data);
        console2.log("RecyReport implementation:", stack.implementation);
        console2.log("RecyReportFactoryV2:", stack.factoryAddress);
        console2.log("RecyReport proxy:", stack.proxyAddress);
    }
}
