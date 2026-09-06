// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {RecyToken} from "../../src/RecyToken.sol";
import {RecyTokenOFTWiring} from "../config/RecyTokenOFTWiring.s.sol";

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

        for (uint256 i; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            require(state.networks[i].token != address(0), "token is not configured");
            _validateToken(state.networks[i], state.oftConfigs[i]);
            _validateTokenIdentity(state.networks[i].token);
            state.tokenAddresses[i] = state.networks[i].token;
        }

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

        for (uint256 i; i < count; ++i) {
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

        // Open and verify every RPC before any broadcast scope is entered.
        for (uint256 i; i < count; ++i) {
            state.forkIds[i] = vm.createSelectFork(state.oftConfigs[i].rpcAlias);
            require(block.chainid == state.chainIds[i], "RPC alias resolves to the wrong chain");
            require(state.networks[i].lzEndpoint.code.length != 0, "endpoint has no code");
            require(
                ILayerZeroEndpointV2(state.networks[i].lzEndpoint).eid() == state.oftConfigs[i].eid,
                "endpoint EID mismatch"
            );
        }
    }

    function _preflightTokenPlan(DeploymentState memory state) private {
        for (uint256 i; i < state.chainIds.length; ++i) {
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
    }

    function _broadcastSender() private returns (address broadcaster) {
        vm.startBroadcast();
        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();
        vm.stopBroadcast();

        require(mode == VmSafe.CallerMode.RecurrentBroadcast, "Foundry broadcast signer is unavailable");
        return sender;
    }

    function _deployTokens(DeploymentState memory state) private {
        for (uint256 i; i < state.chainIds.length; ++i) {
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
    }

    function _configureRoutes(DeploymentState memory state) private {
        for (uint256 i; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            for (uint256 j; j < state.oftConfigs[i].peerChainIds.length; ++j) {
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
    }

    function _wireRoutes(DeploymentState memory state) private {
        for (uint256 i; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            for (uint256 j; j < state.oftConfigs[i].peerChainIds.length; ++j) {
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
    }

    function _checkRoutes(DeploymentState memory state) private {
        for (uint256 i; i < state.chainIds.length; ++i) {
            vm.selectFork(state.forkIds[i]);
            _validateToken(state.networks[i], state.oftConfigs[i]);
            _validateTokenIdentity(state.networks[i].token);

            for (uint256 j; j < state.oftConfigs[i].peerChainIds.length; ++j) {
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
    }

    function _recordPlannedAddresses(DeploymentState memory state) private {
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Dry run: config file left unchanged.");
            return;
        }

        bool recorded;
        for (uint256 i; i < state.chainIds.length; ++i) {
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

        if (recorded) {
            console2.log("Recorded addresses are planned until their broadcast receipts succeed.");
        } else {
            console2.log("No planned token address changes were needed.");
        }
    }

    function _validateTokenIdentity(address tokenAddress) private view {
        RecyToken token = RecyToken(tokenAddress);
        require(keccak256(bytes(token.name())) == keccak256(bytes(TOKEN_NAME)), "token name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes(TOKEN_SYMBOL)), "token symbol mismatch");
    }

    function _networkIndex(uint256[] memory chainIds, uint256 chainId) private pure returns (uint256 index) {
        for (uint256 i; i < chainIds.length; ++i) {
            if (chainIds[i] == chainId) return i;
        }
        revert("peer chain is not selected");
    }
}
