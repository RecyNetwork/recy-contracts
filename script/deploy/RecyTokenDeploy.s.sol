// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyToken} from "../../src/RecyToken.sol";
import {RecyTokenOFTWiring} from "../config/RecyTokenOFTWiring.s.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

contract RecyTokenDeploy is RecyTokenOFTWiring {
    string private constant TOKEN_NAME = "RecyToken";
    string private constant TOKEN_SYMBOL = "cRECY";

    struct DeploymentState {
        uint256[] chainIds;
        uint256[] forkIds;
        NetworkConfig[] networks;
        OFTConfig[] oftConfigs;
        address[] tokenAddresses;
        bool[] needsDeployment;
        bool[] needsRecording;
    }

    /// @notice Simulates the complete configured graph, recording broadcasts for one Foundry signer.
    function run() public returns (address[] memory tokenAddresses) {
        DeploymentState memory state = _loadState();
        _preflightTokenPlan(state);

        address broadcaster = _broadcastSender();
        require(broadcaster == state.networks[0].tokenOwner, "broadcaster is not the configured token owner");

        _deployTokens(state);
        _configureRoutes(state);
        _wireRoutes(state);
        _checkRoutes(state);
        _recordPlannedAddresses(state);

        console2.log("All configured routes passed local simulation and readback.");
        console2.log("Broadcast receipts must succeed before planned changes are treated as live.");
        return state.tokenAddresses;
    }

    /// @notice Checks every configured live route without opening a signing or write context.
    function check() public {
        DeploymentState memory state = _loadState();

        // The script must select and fail-fast validate every configured fork; this
        // bounded chain set comes from static deployment configuration, not user input.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            require(state.networks[i].token != address(0), "token is not configured");
            _validateToken(state.networks[i], state.oftConfigs[i]);
            _validateTokenIdentity(state.networks[i].token);
            state.tokenAddresses[i] = state.networks[i].token;
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)

        _checkRoutes(state);
        console2.log("All configured live OFT routes are valid.");
    }

    function _loadState() private returns (DeploymentState memory state) {
        // Discovery also validates numeric ordering, unique EIDs, shared ownership/issuance,
        // and a closed, reciprocal graph containing only selected OFT networks.
        state.chainIds = getOFTChainIds();
        uint256 count = state.chainIds.length;
        state.forkIds = new uint256[](count);
        state.networks = new NetworkConfig[](count);
        state.oftConfigs = new OFTConfig[](count);
        state.tokenAddresses = new address[](count);
        state.needsDeployment = new bool[](count);
        state.needsRecording = new bool[](count);

        // Cross-chain config is intentionally validated entry by entry before any
        // broadcast; one inconsistent network must abort the deployment plan.
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i = 0; i < count; ++i) {
            state.networks[i] = getNetworkConfig(state.chainIds[i]);
            state.oftConfigs[i] = getOFTConfig(state.chainIds[i]);
            require(state.networks[i].tokenOwner != address(0), "token owner is not configured");
            require(state.networks[i].issuanceChainId != 0, "issuance chain is not configured");
            require(state.networks[i].lzEndpoint != address(0), "endpoint is not configured");
            if (i != 0) {
                require(state.networks[i].tokenOwner == state.networks[0].tokenOwner, "configured token owners differ");
                require(
                    state.networks[i].issuanceChainId == state.networks[0].issuanceChainId,
                    "configured issuance chains differ"
                );
            }
        }
        // forge-lint: disable-end(require-revert-in-loop)

        // Preflight must open and validate every configured RPC before any broadcast;
        // bounded cheatcode and endpoint calls plus fail-fast checks are the safety boundary.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < count; ++i) {
            state.forkIds[i] = vm.createSelectFork(state.oftConfigs[i].rpcAlias);
            require(block.chainid == state.chainIds[i], "RPC alias resolves to the wrong chain");
            require(state.networks[i].lzEndpoint.code.length != 0, "endpoint has no code");
            require(
                ILayerZeroEndpointV2(state.networks[i].lzEndpoint).eid() == state.oftConfigs[i].eid,
                "endpoint EID mismatch"
            );
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)
    }

    function _preflightTokenPlan(DeploymentState memory state) private {
        // Address planning is per fork because nonce and code state are chain-local;
        // bounded cheatcode reads and CREATE-address mismatches must abort the plan.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            address configured = state.networks[i].token;

            if (configured != address(0) && configured.code.length != 0) {
                _validateToken(state.networks[i], state.oftConfigs[i]);
                _validateTokenIdentity(configured);
                state.tokenAddresses[i] = configured;
                console2.log("Reusing RPC-confirmed token on chain", state.chainIds[i]);
                console2.log("Token address", configured);
                continue;
            }

            address planned =
                vm.computeCreateAddress(state.networks[i].tokenOwner, vm.getNonce(state.networks[i].tokenOwner));
            if (configured != address(0)) {
                require(configured == planned, "configured code-less token is not the current CREATE address");
                console2.log("Retrying configured pending CREATE address on chain", state.chainIds[i]);
            } else {
                state.needsRecording[i] = true;
                console2.log("Planned new token CREATE address on chain", state.chainIds[i]);
            }

            state.tokenAddresses[i] = planned;
            state.needsDeployment[i] = true;
            console2.log("Token address", planned);
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)
    }

    function _broadcastSender() private returns (address broadcaster) {
        vm.startBroadcast();
        // readCallers also reports tx.origin, but signer selection intentionally uses
        // Foundry's recurrent mode and msg.sender rather than adding an origin policy.
        // forge-lint: disable-next-line(unused-return)
        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();
        vm.stopBroadcast();

        require(mode == VmSafe.CallerMode.RecurrentBroadcast, "Foundry broadcast signer is unavailable");
        return sender;
    }

    function _deployTokens(DeploymentState memory state) private {
        // Each selected chain needs its own fork and broadcast scope; deployment
        // readbacks and fail-fast postconditions prevent recording an invalid plan.
        // forge-lint: disable-start(calls-loop, require-revert-in-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            if (!state.needsDeployment[i]) continue;
            vm.selectFork(state.forkIds[i]);

            NetworkConfig memory network = state.networks[i];
            vm.startBroadcast();
            RecyToken token = new RecyToken(
                TOKEN_NAME, TOKEN_SYMBOL, 0, network.lzEndpoint, network.tokenOwner, network.issuanceChainId
            );
            vm.stopBroadcast();

            require(address(token) == state.tokenAddresses[i], "simulated CREATE address changed");
            state.networks[i].token = address(token);
            _validateToken(state.networks[i], state.oftConfigs[i]);
            _validateTokenIdentity(address(token));
            require(token.totalSupply() == 0 && token.totalIssued() == 0, "new token supply is not zero");
            console2.log("Locally simulated planned token on chain", state.chainIds[i]);
            console2.log("Token address", address(token));
        }
        // forge-lint: disable-end(calls-loop, require-revert-in-loop)
    }

    function _configureRoutes(DeploymentState memory state) private {
        // Route configuration runs once per configured chain and peer on its selected
        // fork; the closed deployment graph bounds this script-only batch.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            for (uint256 j = 0; j < state.oftConfigs[i].peerChainIds.length; ++j) {
                uint256 remoteChainId = state.oftConfigs[i].peerChainIds[j];
                uint256 remoteIndex = _networkIndex(state.chainIds, remoteChainId);
                _configureRoute(
                    state.networks[i],
                    state.oftConfigs[i],
                    state.networks[remoteIndex],
                    state.oftConfigs[remoteIndex],
                    remoteChainId
                );
            }
        }
        // forge-lint: disable-end(calls-loop)
    }

    function _wireRoutes(DeploymentState memory state) private {
        // Peer wiring runs once per configured chain and peer on its selected fork;
        // the closed deployment graph bounds this script-only batch.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            for (uint256 j = 0; j < state.oftConfigs[i].peerChainIds.length; ++j) {
                uint256 remoteChainId = state.oftConfigs[i].peerChainIds[j];
                uint256 remoteIndex = _networkIndex(state.chainIds, remoteChainId);
                _wireRoute(
                    state.networks[i],
                    state.oftConfigs[i],
                    state.networks[remoteIndex],
                    state.oftConfigs[remoteIndex],
                    remoteChainId
                );
            }
        }
        // forge-lint: disable-end(calls-loop)
    }

    function _checkRoutes(DeploymentState memory state) private {
        // Complete readback must visit every configured chain and peer; these bounded
        // calls are the cross-chain postcondition, not user-controlled iteration.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            _validateToken(state.networks[i], state.oftConfigs[i]);
            _validateTokenIdentity(state.networks[i].token);

            for (uint256 j = 0; j < state.oftConfigs[i].peerChainIds.length; ++j) {
                uint256 remoteChainId = state.oftConfigs[i].peerChainIds[j];
                uint256 remoteIndex = _networkIndex(state.chainIds, remoteChainId);
                _checkRoute(
                    state.networks[i],
                    state.oftConfigs[i],
                    state.networks[remoteIndex],
                    state.oftConfigs[remoteIndex],
                    remoteChainId,
                    true
                );
            }
        }
        // forge-lint: disable-end(calls-loop)
    }

    function _recordPlannedAddresses(DeploymentState memory state) private {
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Dry run: config file left unchanged.");
            return;
        }

        bool recorded = false;
        // Broadcast-mode persistence writes every newly planned chain address so the
        // bounded deployment config remains synchronized with broadcast output.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i = 0; i < state.chainIds.length; ++i) {
            if (!state.needsRecording[i]) continue;
            vm.writeJson(
                string.concat("\"", vm.toString(state.tokenAddresses[i]), "\""),
                CONFIG_PATH,
                string.concat(".", vm.toString(state.chainIds[i]), ".contracts.token")
            );
            recorded = true;
            console2.log("Recorded planned token address for chain", state.chainIds[i]);
            console2.log("Token address", state.tokenAddresses[i]);
        }
        // forge-lint: disable-end(calls-loop)

        if (recorded) {
            console2.log("Recorded addresses are planned until their broadcast receipts succeed.");
        } else {
            console2.log("No planned token address changes were needed.");
        }
    }

    // This validator is intentionally reached from each selected-chain loop; its
    // metadata reads and fail-fast mismatches protect token reuse and deployment.
    // forge-lint: disable-start(calls-loop, require-revert-in-loop)
    function _validateTokenIdentity(address tokenAddress) private view {
        RecyToken token = RecyToken(tokenAddress);
        require(keccak256(bytes(token.name())) == keccak256(bytes(TOKEN_NAME)), "token name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes(TOKEN_SYMBOL)), "token symbol mismatch");
    }

    // forge-lint: disable-end(calls-loop, require-revert-in-loop)

    // Route loops require a total lookup over the closed configured graph; a missing
    // peer is invalid deployment input and must stop the entire script immediately.
    // forge-lint: disable-start(require-revert-in-loop)
    function _networkIndex(uint256[] memory chainIds, uint256 chainId) private pure returns (uint256 index) {
        for (uint256 i = 0; i < chainIds.length; ++i) {
            if (chainIds[i] == chainId) return i;
        }
        revert("peer chain is not selected");
    }
    // forge-lint: disable-end(require-revert-in-loop)
}
