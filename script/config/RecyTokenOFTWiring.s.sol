// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {RecyToken} from "../../src/RecyToken.sol";
import {RecyTokenOFTConfig} from "./RecyTokenOFTConfig.s.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessageLib, MessageLibType} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ILayerZeroEndpointV2View is ILayerZeroEndpointV2 {
    function delegates(address oapp) external view returns (address);
}

interface IUln302ConfigView {
    function getAppUlnConfig(address oapp, uint32 remoteEid) external view returns (UlnConfig memory);
}

interface ISendUln302ConfigView is IUln302ConfigView {
    function executorConfigs(address oapp, uint32 remoteEid)
        external
        view
        returns (uint32 maxMessageSize, address executor);
}

abstract contract RecyTokenOFTWiring is RecyTokenOFTConfig {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    uint32 private constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 private constant CONFIG_TYPE_ULN = 2;
    uint8 private constant NIL_DVN_COUNT = type(uint8).max;
    uint16 private constant SEND = 1;
    uint16 private constant SEND_AND_CALL = 2;

    struct RouteSetup {
        address remoteToken;
        OFTConfig localOft;
        OFTConfig remoteOft;
        RecyToken token;
        ILayerZeroEndpointV2View endpoint;
    }

    struct RouteChanges {
        bool sendLibrary;
        bool receiveLibrary;
        bool executor;
        bool sendUln;
        bool receiveUln;
        bool sendOptions;
        bool sendAndCallOptions;
    }

    // Route scripts intentionally run these fail-fast on-chain checks for each finite configured chain.
    // forge-lint: disable-start(calls-loop, require-revert-in-loop)
    function _validateToken(NetworkConfig memory network, OFTConfig memory oft) internal view {
        require(network.token != address(0), "token is not configured");
        require(network.token.code.length != 0, "token has no code");
        require(network.lzEndpoint != address(0), "endpoint is not configured");
        require(network.lzEndpoint.code.length != 0, "endpoint has no code");
        require(network.tokenOwner != address(0), "token owner is not configured");
        require(network.issuanceChainId != 0, "issuance chain is not configured");
        require(oft.eid != 0, "OFT eid is zero");

        RecyToken token = RecyToken(network.token);
        ILayerZeroEndpointV2View endpoint = ILayerZeroEndpointV2View(network.lzEndpoint);

        require(address(token.endpoint()) == network.lzEndpoint, "token endpoint mismatch");
        require(endpoint.eid() == oft.eid, "endpoint EID mismatch");
        require(token.issuanceChainId() == network.issuanceChainId, "token issuance chain mismatch");
        require(token.owner() == network.tokenOwner, "token owner mismatch");
        require(endpoint.delegates(network.token) == network.tokenOwner, "endpoint delegate mismatch");

        (bytes4 interfaceId, uint64 version) = token.oftVersion();
        require(interfaceId == type(IOFT).interfaceId && version == 1, "token is not compatible OFT v1");
        require(token.token() == network.token, "token is not a native OFT");
        require(!token.approvalRequired(), "native OFT must not require approval");
    }

    // forge-lint: disable-end(calls-loop, require-revert-in-loop)

    // These route mutation entry points intentionally read and write each route in bounded script loops.
    // forge-lint: disable-start(calls-loop, require-revert-in-loop)
    function _configureRoute(
        NetworkConfig memory localNetwork,
        OFTConfig memory localOft,
        NetworkConfig memory remoteNetwork,
        OFTConfig memory remoteOft,
        uint256 remoteChainId
    ) internal {
        RouteSetup memory setup = _routeSetup(localNetwork, localOft, remoteNetwork, remoteOft, remoteChainId);
        RouteChanges memory changes = _configurationChanges(setup);
        bytes32 currentPeer = setup.token.peers(setup.remoteOft.eid);
        bytes32 expectedPeer = _addressToBytes32(setup.remoteToken);

        require(currentPeer == bytes32(0) || currentPeer == expectedPeer, "unrelated OFT peer already set");
        require(currentPeer == bytes32(0) || !_hasChanges(changes), "cannot alter security on a live peer");
        if (!changes.receiveLibrary) _assertNoReceiveTimeout(setup);

        if (_hasChanges(changes)) {
            vm.startBroadcast();
            _applyChanges(setup, changes);
            vm.stopBroadcast();
        }

        _assertConfigured(setup, false);
    }

    function _wireRoute(
        NetworkConfig memory localNetwork,
        OFTConfig memory localOft,
        NetworkConfig memory remoteNetwork,
        OFTConfig memory remoteOft,
        uint256 remoteChainId
    ) internal {
        RouteSetup memory setup = _routeSetup(localNetwork, localOft, remoteNetwork, remoteOft, remoteChainId);
        _assertConfigured(setup, false);

        bytes32 expectedPeer = _addressToBytes32(setup.remoteToken);
        bytes32 currentPeer = setup.token.peers(setup.remoteOft.eid);
        require(currentPeer == bytes32(0) || currentPeer == expectedPeer, "refusing to replace unrelated OFT peer");

        if (currentPeer == bytes32(0)) {
            vm.startBroadcast();
            setup.token.setPeer(setup.remoteOft.eid, expectedPeer);
            vm.stopBroadcast();
        }

        _assertConfigured(setup, true);
    }
    // forge-lint: disable-end(calls-loop, require-revert-in-loop)

    function _checkRoute(
        NetworkConfig memory localNetwork,
        OFTConfig memory localOft,
        NetworkConfig memory remoteNetwork,
        OFTConfig memory remoteOft,
        uint256 remoteChainId,
        bool requirePeer
    ) internal view {
        RouteSetup memory setup = _routeSetup(localNetwork, localOft, remoteNetwork, remoteOft, remoteChainId);
        _assertConfigured(setup, requirePeer);
    }

    // Bounded route setup performs every chain-specific fail-fast code and library check before any broadcast.
    // forge-lint: disable-start(calls-loop, require-revert-in-loop)
    function _routeSetup(
        NetworkConfig memory localNetwork,
        OFTConfig memory localOft,
        NetworkConfig memory remoteNetwork,
        OFTConfig memory remoteOft,
        uint256 remoteChainId
    ) private view returns (RouteSetup memory setup) {
        _validateOFTConfig(block.chainid, localOft);
        _validateOFTConfig(remoteChainId, remoteOft);
        require(remoteChainId != block.chainid, "local and remote chain IDs match");
        require(remoteOft.eid != localOft.eid, "local and remote EIDs match");
        require(_hasPeerChain(localOft, remoteChainId), "remote chain is not a local peer");
        require(_hasPeerChain(remoteOft, block.chainid), "peer chain IDs are not reciprocal");
        require(remoteNetwork.token != address(0), "remote token is not configured");
        require(remoteNetwork.lzEndpoint != address(0), "remote endpoint is not configured");
        require(localNetwork.tokenOwner == remoteNetwork.tokenOwner, "token owners differ");
        require(localNetwork.issuanceChainId == remoteNetwork.issuanceChainId, "issuance chain IDs differ");

        _validateToken(localNetwork, localOft);

        setup.remoteToken = remoteNetwork.token;
        setup.localOft = localOft;
        setup.remoteOft = remoteOft;
        setup.token = RecyToken(localNetwork.token);
        setup.endpoint = ILayerZeroEndpointV2View(localNetwork.lzEndpoint);

        _validateMessageLibrary(setup, localOft.sendLibrary, MessageLibType.Send);
        _validateMessageLibrary(setup, localOft.receiveLibrary, MessageLibType.Receive);
        require(localOft.executor.code.length != 0, "executor has no code");
        for (uint256 i = 0; i < localOft.requiredDVNs.length; ++i) {
            require(localOft.requiredDVNs[i].code.length != 0, "DVN has no code");
        }
    }

    function _hasPeerChain(OFTConfig memory oft, uint256 chainId) private pure returns (bool) {
        for (uint256 i = 0; i < oft.peerChainIds.length; ++i) {
            if (oft.peerChainIds[i] == chainId) return true;
        }
        return false;
    }

    function _validateMessageLibrary(RouteSetup memory setup, address libraryAddress, MessageLibType expectedType)
        private
        view
    {
        require(libraryAddress.code.length != 0, "message library has no code");
        require(setup.endpoint.isRegisteredLibrary(libraryAddress), "message library is not registered");
        IMessageLib messageLibrary = IMessageLib(libraryAddress);
        require(messageLibrary.messageLibType() == expectedType, "wrong message library type");
        require(messageLibrary.isSupportedEid(setup.remoteOft.eid), "message library does not support remote EID");
        (uint64 major, uint8 minor, uint8 endpointVersion) = messageLibrary.version();
        require(major == 3 && minor == 0 && endpointVersion == 2, "message library is not ULN 302");
    }

    // forge-lint: disable-end(calls-loop, require-revert-in-loop)

    // Each bounded route comparison must read current endpoint and token state before deciding its exact delta.
    // forge-lint: disable-start(calls-loop)
    function _configurationChanges(RouteSetup memory setup) private view returns (RouteChanges memory changes) {
        address tokenAddress = address(setup.token);
        uint32 remoteEid = setup.remoteOft.eid;

        changes.sendLibrary = setup.endpoint.getSendLibrary(tokenAddress, remoteEid) != setup.localOft.sendLibrary
            || setup.endpoint.isDefaultSendLibrary(tokenAddress, remoteEid);

        (address receiveLibrary, bool receiveIsDefault) = setup.endpoint.getReceiveLibrary(tokenAddress, remoteEid);
        changes.receiveLibrary = receiveLibrary != setup.localOft.receiveLibrary || receiveIsDefault;

        (uint32 maxMessageSize, address executor) =
            ISendUln302ConfigView(setup.localOft.sendLibrary).executorConfigs(tokenAddress, remoteEid);
        changes.executor = maxMessageSize != setup.localOft.maxMessageSize || executor != setup.localOft.executor;

        UlnConfig memory desiredSendUln = _rawUln(setup.localOft, setup.localOft.confirmations);
        UlnConfig memory desiredReceiveUln = _rawUln(setup.localOft, setup.remoteOft.confirmations);
        changes.sendUln = !_sameUln(
            IUln302ConfigView(setup.localOft.sendLibrary).getAppUlnConfig(tokenAddress, remoteEid), desiredSendUln
        );
        changes.receiveUln = !_sameUln(
            IUln302ConfigView(setup.localOft.receiveLibrary).getAppUlnConfig(tokenAddress, remoteEid), desiredReceiveUln
        );

        bytes memory desiredOptions = _receiveOptions(setup.remoteOft.lzReceiveGas);
        changes.sendOptions = !_sameBytes(setup.token.enforcedOptions(remoteEid, SEND), desiredOptions);
        changes.sendAndCallOptions = !_sameBytes(setup.token.enforcedOptions(remoteEid, SEND_AND_CALL), desiredOptions);
    }

    // forge-lint: disable-end(calls-loop)

    // Deployment scripts intentionally apply route-specific endpoint and OFT writes for each finite configured route.
    // forge-lint: disable-start(calls-loop)
    function _applyChanges(RouteSetup memory setup, RouteChanges memory changes) private {
        address tokenAddress = address(setup.token);
        uint32 remoteEid = setup.remoteOft.eid;

        if (changes.sendLibrary) {
            setup.endpoint.setSendLibrary(tokenAddress, remoteEid, setup.localOft.sendLibrary);
        }
        if (changes.receiveLibrary) {
            setup.endpoint.setReceiveLibrary(tokenAddress, remoteEid, setup.localOft.receiveLibrary, 0);
        }

        if (changes.executor || changes.sendUln) _setSendConfig(setup, changes);
        if (changes.receiveUln) _setReceiveConfig(setup);
        if (changes.sendOptions || changes.sendAndCallOptions) _setOptions(setup, changes);
    }

    function _setSendConfig(RouteSetup memory setup, RouteChanges memory changes) private {
        uint256 count = (changes.executor ? 1 : 0) + (changes.sendUln ? 1 : 0);
        SetConfigParam[] memory params = new SetConfigParam[](count);
        uint256 index = 0;

        if (changes.executor) {
            params[index++] = SetConfigParam({
                eid: setup.remoteOft.eid,
                configType: CONFIG_TYPE_EXECUTOR,
                config: abi.encode(
                    ExecutorConfig({maxMessageSize: setup.localOft.maxMessageSize, executor: setup.localOft.executor})
                )
            });
        }
        if (changes.sendUln) {
            params[index] = SetConfigParam({
                eid: setup.remoteOft.eid,
                configType: CONFIG_TYPE_ULN,
                config: abi.encode(_rawUln(setup.localOft, setup.localOft.confirmations))
            });
        }

        setup.endpoint.setConfig(address(setup.token), setup.localOft.sendLibrary, params);
    }

    function _setReceiveConfig(RouteSetup memory setup) private {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({
            eid: setup.remoteOft.eid,
            configType: CONFIG_TYPE_ULN,
            config: abi.encode(_rawUln(setup.localOft, setup.remoteOft.confirmations))
        });
        setup.endpoint.setConfig(address(setup.token), setup.localOft.receiveLibrary, params);
    }

    function _setOptions(RouteSetup memory setup, RouteChanges memory changes) private {
        uint256 count = (changes.sendOptions ? 1 : 0) + (changes.sendAndCallOptions ? 1 : 0);
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](count);
        bytes memory options = _receiveOptions(setup.remoteOft.lzReceiveGas);
        uint256 index = 0;

        if (changes.sendOptions) {
            params[index++] = EnforcedOptionParam({eid: setup.remoteOft.eid, msgType: SEND, options: options});
        }
        if (changes.sendAndCallOptions) {
            params[index] = EnforcedOptionParam({eid: setup.remoteOft.eid, msgType: SEND_AND_CALL, options: options});
        }

        setup.token.setEnforcedOptions(params);
    }

    // forge-lint: disable-end(calls-loop)

    // Route verification intentionally re-reads and fail-fast checks each finite route before advancing.
    // forge-lint: disable-start(calls-loop, require-revert-in-loop)
    function _assertConfigured(RouteSetup memory setup, bool requirePeer) private view {
        address tokenAddress = address(setup.token);
        uint32 remoteEid = setup.remoteOft.eid;

        require(
            setup.endpoint.getSendLibrary(tokenAddress, remoteEid) == setup.localOft.sendLibrary,
            "send library mismatch"
        );
        require(!setup.endpoint.isDefaultSendLibrary(tokenAddress, remoteEid), "send library is inherited");
        (address receiveLibrary, bool receiveIsDefault) = setup.endpoint.getReceiveLibrary(tokenAddress, remoteEid);
        require(receiveLibrary == setup.localOft.receiveLibrary, "receive library mismatch");
        require(!receiveIsDefault, "receive library is inherited");
        _assertNoReceiveTimeout(setup);

        (uint32 rawMaxMessageSize, address rawExecutor) =
            ISendUln302ConfigView(setup.localOft.sendLibrary).executorConfigs(tokenAddress, remoteEid);
        require(rawMaxMessageSize == setup.localOft.maxMessageSize, "raw max message size mismatch");
        require(rawExecutor == setup.localOft.executor, "raw executor mismatch");

        UlnConfig memory rawSendUln =
            IUln302ConfigView(setup.localOft.sendLibrary).getAppUlnConfig(tokenAddress, remoteEid);
        UlnConfig memory rawReceiveUln =
            IUln302ConfigView(setup.localOft.receiveLibrary).getAppUlnConfig(tokenAddress, remoteEid);
        require(_sameUln(rawSendUln, _rawUln(setup.localOft, setup.localOft.confirmations)), "raw send ULN mismatch");
        require(
            _sameUln(rawReceiveUln, _rawUln(setup.localOft, setup.remoteOft.confirmations)), "raw receive ULN mismatch"
        );

        ExecutorConfig memory effectiveExecutor = abi.decode(
            setup.endpoint.getConfig(tokenAddress, setup.localOft.sendLibrary, remoteEid, CONFIG_TYPE_EXECUTOR),
            (ExecutorConfig)
        );
        require(
            effectiveExecutor.maxMessageSize == setup.localOft.maxMessageSize, "effective max message size mismatch"
        );
        require(effectiveExecutor.executor == setup.localOft.executor, "effective executor mismatch");

        UlnConfig memory effectiveSendUln = abi.decode(
            setup.endpoint.getConfig(tokenAddress, setup.localOft.sendLibrary, remoteEid, CONFIG_TYPE_ULN), (UlnConfig)
        );
        UlnConfig memory effectiveReceiveUln = abi.decode(
            setup.endpoint.getConfig(tokenAddress, setup.localOft.receiveLibrary, remoteEid, CONFIG_TYPE_ULN),
            (UlnConfig)
        );
        require(
            _sameUln(effectiveSendUln, _effectiveUln(setup.localOft, setup.localOft.confirmations)),
            "effective send ULN mismatch"
        );
        require(
            _sameUln(effectiveReceiveUln, _effectiveUln(setup.localOft, setup.remoteOft.confirmations)),
            "effective receive ULN mismatch"
        );

        bytes memory options = _receiveOptions(setup.remoteOft.lzReceiveGas);
        require(_sameBytes(setup.token.enforcedOptions(remoteEid, SEND), options), "SEND options mismatch");
        require(
            _sameBytes(setup.token.enforcedOptions(remoteEid, SEND_AND_CALL), options), "SEND_AND_CALL options mismatch"
        );

        if (requirePeer) {
            require(setup.token.peers(remoteEid) == _addressToBytes32(setup.remoteToken), "OFT peer mismatch");
        }
    }

    function _assertNoReceiveTimeout(RouteSetup memory setup) private view {
        (address timeoutLibrary, uint256 expiry) =
            setup.endpoint.receiveLibraryTimeout(address(setup.token), setup.remoteOft.eid);
        require(timeoutLibrary == address(0) && expiry == 0, "receive library timeout must be empty");
    }

    // forge-lint: disable-end(calls-loop, require-revert-in-loop)

    // These route-local ULN builders allocate distinct empty optional-DVN arrays for each finite route.
    // forge-lint: disable-start(calls-loop)
    function _rawUln(OFTConfig memory localConfig, uint64 confirmations) private pure returns (UlnConfig memory) {
        return UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: localConfig.requiredDVNs.length.toUint8(),
            optionalDVNCount: NIL_DVN_COUNT,
            optionalDVNThreshold: 0,
            requiredDVNs: localConfig.requiredDVNs,
            optionalDVNs: new address[](0)
        });
    }

    function _effectiveUln(OFTConfig memory localConfig, uint64 confirmations) private pure returns (UlnConfig memory) {
        return UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: localConfig.requiredDVNs.length.toUint8(),
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: localConfig.requiredDVNs,
            optionalDVNs: new address[](0)
        });
    }
    // forge-lint: disable-end(calls-loop)

    function _receiveOptions(uint128 gasLimit) private pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
    }

    function _sameUln(UlnConfig memory left, UlnConfig memory right) private pure returns (bool) {
        return left.confirmations == right.confirmations && left.requiredDVNCount == right.requiredDVNCount
            && left.optionalDVNCount == right.optionalDVNCount
            && left.optionalDVNThreshold == right.optionalDVNThreshold
            && _sameAddresses(left.requiredDVNs, right.requiredDVNs)
            && _sameAddresses(left.optionalDVNs, right.optionalDVNs);
    }

    function _sameAddresses(address[] memory left, address[] memory right) private pure returns (bool) {
        if (left.length != right.length) return false;
        for (uint256 i = 0; i < left.length; ++i) {
            if (left[i] != right[i]) return false;
        }
        return true;
    }

    function _sameBytes(bytes memory left, bytes memory right) private pure returns (bool) {
        return keccak256(left) == keccak256(right);
    }

    function _hasChanges(RouteChanges memory changes) private pure returns (bool) {
        return changes.sendLibrary || changes.receiveLibrary || changes.executor || changes.sendUln
            || changes.receiveUln || changes.sendOptions || changes.sendAndCallOptions;
    }

    function _addressToBytes32(address value) private pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
