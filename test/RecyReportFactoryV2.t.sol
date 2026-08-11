// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../src/RecyReportFactory.sol";
import "../src/RecyReportFactoryV2.sol";
import "../src/RecyReport.sol";
import "../src/RecyReportData.sol";
import "../src/RecyReportAttributes.sol";
import "../src/RecyReportSvg.sol";
import "../src/RecyToken.sol";
import "../src/lib/RecyErrors.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./helpers/TestHelpers.sol";

contract RecyReportFactoryV2Test is Test, TestHelpers {
    /// @dev ERC-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev `RecyReportData private data` is slot 0 of RecyReport (src/RecyReport.sol:29). It has
    ///      no public getter, so reading the slot is the only way to observe which data contract a
    ///      freshly deployed proxy was initialized with.
    bytes32 private constant DATA_CONTRACT_SLOT = bytes32(uint256(0));

    RecyReportFactoryV2 factory;
    RecyReport implementation;
    RecyReportData dataContract;
    RecyReportAttributes attributes;
    RecyReportSvg svg;
    RecyToken token;

    address owner = address(this);
    address stranger = address(0xBEEF);
    address protocolAddress = address(0x3);

    uint256 private proxyCounter;

    function setUp() public {
        attributes = new RecyReportAttributes();
        svg = new RecyReportSvg();
        dataContract = new RecyReportData(address(attributes), address(svg));
        MockLZEndpointForHelpers mockEndpoint = new MockLZEndpointForHelpers();
        token = new RecyToken("Test Token", "TEST", 1000000, address(mockEndpoint), owner);

        implementation = new RecyReport();

        factory = new RecyReportFactoryV2(address(implementation), address(dataContract));
    }

    // ===== HELPERS =====

    function deployTestProxy() internal returns (address) {
        proxyCounter++;
        string memory proxyName = string(abi.encodePacked("v2-proxy-", vm.toString(proxyCounter)));
        return factory.deployProxy(proxyName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function _initCall(string memory name, address data) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            RecyReport.initialize.selector,
            name,
            "RECY",
            address(token),
            data,
            protocolAddress,
            uint64(3600),
            uint8(25),
            uint8(25),
            uint8(25),
            uint8(25)
        );
    }

    /// @dev A proxy V2 never deployed, whose DEFAULT_ADMIN_ROLE is held by this test contract.
    function _deployStandaloneProxy(string memory name) internal returns (address) {
        return address(new ERC1967Proxy(address(implementation), _initCall(name, address(dataContract))));
    }

    /// @dev A proxy deployed by the legacy V1 factory, which therefore holds DEFAULT_ADMIN_ROLE.
    function _deployLegacyFactoryAndProxy(string memory name)
        internal
        returns (RecyReportFactory legacy, address proxy)
    {
        legacy = new RecyReportFactory(address(implementation), address(dataContract));
        proxy = legacy.deployProxy(name, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function _proxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    function _proxyDataContract(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, DATA_CONTRACT_SLOT))));
    }

    function _repeat(bytes1 char, uint256 count) internal pure returns (string memory) {
        bytes memory buffer = new bytes(count);
        for (uint256 i = 0; i < count; i++) {
            buffer[i] = char;
        }
        return string(buffer);
    }

    function _assertRegistered(address proxy, string memory name, uint256 expectedIndex, uint256 expectedTotal)
        internal
        view
    {
        assertTrue(factory.isDeployedProxy(proxy), "isDeployedProxy");
        assertEq(factory.deployedProxies(expectedIndex), proxy, "deployedProxies[i]");
        assertEq(factory.proxyByName(name), proxy, "proxyByName");
        assertEq(factory.nameByProxy(proxy), name, "nameByProxy");
        assertEq(factory.proxyNames(expectedIndex), name, "proxyNames[i]");
        assertEq(factory.getProxyByName(name), proxy, "getProxyByName");
        assertEq(factory.getNameByProxy(proxy), name, "getNameByProxy");
        assertTrue(factory.proxyNameExists(name), "proxyNameExists");
        assertEq(factory.getDeployedProxiesCount(), expectedTotal, "proxy count");
        assertEq(factory.getProxyNamesCount(), expectedTotal, "name count");
    }

    // ===== REGISTRATION OF EXISTING PROXIES (migration-critical) =====

    function test_registerExistingProxyPopulatesEveryRegistryStructure() public {
        address proxy = _deployStandaloneProxy("adopted");

        assertFalse(factory.isDeployedProxy(proxy));
        assertEq(factory.getDeployedProxiesCount(), 0);

        vm.expectEmit(true, true, false, true);
        emit RecyReportFactoryV2.ProxyRegistered(proxy, address(this), "adopted");
        factory.registerExistingProxy(proxy, "adopted");

        _assertRegistered(proxy, "adopted", 0, 1);

        address[] memory all = factory.getAllDeployedProxies();
        assertEq(all.length, 1);
        assertEq(all[0], proxy);

        string[] memory names = factory.getAllProxyNames();
        assertEq(names.length, 1);
        assertEq(names[0], "adopted");
    }

    /// @notice The full V1 -> V2 handover runbook, end to end.
    function test_migrateLiveProxyFromLegacyFactoryToV2() public {
        (RecyReportFactory legacy, address proxy) = _deployLegacyFactoryAndProxy("live-plant");
        RecyReport report = RecyReport(proxy);

        // Legacy factory is the sole DEFAULT_ADMIN_ROLE holder after initialize.
        assertTrue(report.hasRole(report.DEFAULT_ADMIN_ROLE(), address(legacy)));
        assertFalse(report.hasRole(report.DEFAULT_ADMIN_ROLE(), address(factory)));

        // Step 1: adopt into V2's registry.
        factory.registerExistingProxy(proxy, "live-plant");
        _assertRegistered(proxy, "live-plant", 0, 1);

        // Registration alone conveys no on-chain power.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(factory), bytes32(0)
            )
        );
        factory.grantAuditorRole(proxy, stranger);

        // Step 2: legacy factory hands DEFAULT_ADMIN_ROLE to V2.
        legacy.grantAdminRole(proxy, address(factory));
        assertTrue(factory.hasAdminRole(proxy, address(factory)));

        // Step 3: legacy factory drops itself (V1 has no self-revocation guard, which is the
        // very footgun V2 closes -- here it is used deliberately, as the last step).
        legacy.revokeAdminRole(proxy, address(legacy));
        assertFalse(report.hasRole(report.DEFAULT_ADMIN_ROLE(), address(legacy)));

        // V2 now drives the adopted proxy through every privileged path.
        factory.grantAuditorRole(proxy, stranger);
        assertTrue(factory.hasAuditorRole(proxy, stranger));
        factory.revokeAuditorRole(proxy, stranger);
        assertFalse(factory.hasAuditorRole(proxy, stranger));

        factory.grantRecyclerRole(proxy, stranger);
        assertTrue(factory.hasRecyclerRole(proxy, stranger));
        factory.revokeRecyclerRole(proxy, stranger);
        assertFalse(factory.hasRecyclerRole(proxy, stranger));

        factory.grantEmergencyRole(proxy, stranger);
        assertTrue(factory.hasEmergencyRole(proxy, stranger));
        factory.revokeEmergencyRole(proxy, stranger);
        assertFalse(factory.hasEmergencyRole(proxy, stranger));

        factory.grantAdminRole(proxy, stranger);
        assertTrue(factory.hasAdminRole(proxy, stranger));
        factory.revokeAdminRole(proxy, stranger);
        assertFalse(factory.hasAdminRole(proxy, stranger));

        RecyReport newImplementation = new RecyReport();
        factory.upgradeProxy(proxy, address(newImplementation));
        assertEq(_proxyImplementation(proxy), address(newImplementation));

        // Proxy state survived the whole migration.
        assertEq(report.name(), "live-plant");
        assertEq(report.unlockDelay(), 3600);
    }

    function test_registerExistingProxyOnlyOwner() public {
        address proxy = _deployStandaloneProxy("adopted");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.registerExistingProxy(proxy, "adopted");
    }

    function test_registerExistingProxyRejectsZeroAddress() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidProxyAddress.selector);
        factory.registerExistingProxy(address(0), "adopted");
    }

    function test_registerExistingProxyRejectsNonContract() public {
        vm.expectRevert(RecyReportFactoryV2.ProxyNotAContract.selector);
        factory.registerExistingProxy(address(0xDEAD), "adopted");
    }

    function test_registerExistingProxyRejectsAlreadyRegistered() public {
        address proxy = _deployStandaloneProxy("adopted");
        factory.registerExistingProxy(proxy, "adopted");

        vm.expectRevert(RecyReportFactoryV2.ProxyAlreadyRegistered.selector);
        factory.registerExistingProxy(proxy, "adopted-again");
    }

    function test_registerExistingProxyRejectsProxyDeployedByV2() public {
        address proxy = deployTestProxy();

        vm.expectRevert(RecyReportFactoryV2.ProxyAlreadyRegistered.selector);
        factory.registerExistingProxy(proxy, "some-other-name");
    }

    function test_registerExistingProxyRejectsDuplicateName() public {
        address first = _deployStandaloneProxy("shared");
        address second = _deployStandaloneProxy("shared-2");

        factory.registerExistingProxy(first, "shared");

        vm.expectRevert(RecyReportFactoryV2.ProxyNameAlreadyExists.selector);
        factory.registerExistingProxy(second, "shared");
    }

    function test_registerExistingProxyRejectsNameCollidingWithDeployedProxy() public {
        factory.deployProxy("taken", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        address adopted = _deployStandaloneProxy("other");

        vm.expectRevert(RecyReportFactoryV2.ProxyNameAlreadyExists.selector);
        factory.registerExistingProxy(adopted, "taken");
    }

    function test_registerExistingProxyRejectsEmptyName() public {
        address proxy = _deployStandaloneProxy("adopted");

        vm.expectRevert(RecyReportFactoryV2.InvalidProxyName.selector);
        factory.registerExistingProxy(proxy, "");
    }

    function test_registerExistingProxyRejectsNameTooLong() public {
        address proxy = _deployStandaloneProxy("adopted");
        string memory tooLong = _repeat("a", factory.MAX_PROXY_NAME_LENGTH() + 1);

        vm.expectRevert(RecyReportFactoryV2.ProxyNameTooLong.selector);
        factory.registerExistingProxy(proxy, tooLong);
    }

    function test_registerExistingProxyAcceptsMaxLengthName() public {
        address proxy = _deployStandaloneProxy("adopted");
        string memory maxName = _repeat("a", factory.MAX_PROXY_NAME_LENGTH());

        factory.registerExistingProxy(proxy, maxName);
        _assertRegistered(proxy, maxName, 0, 1);
    }

    function test_registeredAndDeployedProxiesShareOneRegistry() public {
        address deployed = factory.deployProxy("deployed", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        address adopted = _deployStandaloneProxy("adopted");
        factory.registerExistingProxy(adopted, "adopted");

        _assertRegistered(deployed, "deployed", 0, 2);
        _assertRegistered(adopted, "adopted", 1, 2);
    }

    // ===== UNREGISTERED PROXIES ARE REJECTED EVERYWHERE =====

    function test_unregisteredProxyRejectedOnEveryPrivilegedPath() public {
        address unregistered = _deployStandaloneProxy("not-adopted");
        RecyReport newImplementation = new RecyReport();

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.grantAuditorRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.revokeAuditorRole(unregistered, stranger);

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.grantRecyclerRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.revokeRecyclerRole(unregistered, stranger);

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.grantAdminRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.revokeAdminRole(unregistered, stranger);

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.grantEmergencyRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.revokeEmergencyRole(unregistered, stranger);

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.hasAuditorRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.hasRecyclerRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.hasAdminRole(unregistered, stranger);
        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.hasEmergencyRole(unregistered, stranger);

        vm.expectRevert(RecyReportFactoryV2.ProxyNotRegistered.selector);
        factory.upgradeProxy(unregistered, address(newImplementation));
    }

    function test_isDeployedProxyIsExactMembership() public {
        address deployed = deployTestProxy();
        address adopted = _deployStandaloneProxy("adopted");
        factory.registerExistingProxy(adopted, "adopted");

        assertTrue(factory.isDeployedProxy(deployed));
        assertTrue(factory.isDeployedProxy(adopted));
        assertFalse(factory.isDeployedProxy(address(0xCAFE)));
        assertFalse(factory.isDeployedProxy(address(0)));
        assertFalse(factory.isDeployedProxy(address(implementation)));
        assertFalse(factory.isDeployedProxy(_deployStandaloneProxy("never-adopted")));
    }

    /// @dev Membership must be a constant-cost lookup, not V1's linear scan over `deployedProxies`.
    function test_isDeployedProxyCostDoesNotGrowWithRegistrySize() public {
        address first = deployTestProxy();

        uint256 gasBefore = gasleft();
        factory.isDeployedProxy(first);
        uint256 earlyCost = gasBefore - gasleft();

        for (uint256 i = 0; i < 20; i++) {
            deployTestProxy();
        }
        address last = deployTestProxy();

        gasBefore = gasleft();
        factory.isDeployedProxy(last);
        uint256 lateCost = gasBefore - gasleft();

        // A linear scan would make the 22nd entry cost ~22 SLOADs more than the 1st.
        assertApproxEqAbs(lateCost, earlyCost, 200);
    }

    // ===== deployProxy GATING AND VALIDATION =====

    function test_deployProxyRevertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.deployProxy("squatted", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_deployProxyRevertsOnZeroProtocolAddress() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidProtocolAddress.selector);
        factory.deployProxy("zero-protocol", "RECY", address(token), address(0), 3600, 25, 25, 25, 25);
    }

    function test_deployProxyRevertsOnEmptyName() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidProxyName.selector);
        factory.deployProxy("", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_deployProxyRevertsOnNameTooLong() public {
        string memory tooLong = _repeat("b", factory.MAX_PROXY_NAME_LENGTH() + 1);

        vm.expectRevert(RecyReportFactoryV2.ProxyNameTooLong.selector);
        factory.deployProxy(tooLong, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_deployProxyAcceptsMaxLengthName() public {
        string memory maxName = _repeat("b", factory.MAX_PROXY_NAME_LENGTH());

        address proxy = factory.deployProxy(maxName, "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        _assertRegistered(proxy, maxName, 0, 1);
    }

    function test_deployProxyRevertsOnDuplicateName() public {
        factory.deployProxy("dupe", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        vm.expectRevert(RecyReportFactoryV2.ProxyNameAlreadyExists.selector);
        factory.deployProxy("dupe", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_deployProxyStillUsesTheInitializeSelector() public {
        address proxy = factory.deployProxy("selector", "cSEL", address(token), protocolAddress, 7200, 70, 10, 15, 5);

        RecyReport report = RecyReport(proxy);
        assertEq(report.name(), "selector");
        assertEq(report.symbol(), "cSEL");
        assertEq(report.unlockDelay(), 7200);
        assertEq(report.shareRecycler(), 70);
        assertEq(report.shareValidator(), 10);
        assertEq(report.shareGenerator(), 15);
        assertEq(report.shareProtocol(), 5);
        assertEq(report.protocolAddress(), protocolAddress);
        assertEq(address(report.token()), address(token));
        assertTrue(report.hasRole(report.DEFAULT_ADMIN_ROLE(), address(factory)));
    }

    /// @dev The event's `proxyName` must be readable from log data; V1 indexed it, which stored
    ///      only `keccak256(name)` as a topic and made names unrecoverable for indexers.
    function test_proxyDeployedEventCarriesRecoverableName() public {
        vm.recordLogs();
        address proxy =
            factory.deployProxy("recoverable-name", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 signature = keccak256("ProxyDeployed(address,address,string)");
        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != signature) continue;
            found = true;

            // Signature + proxy + deployer only: the name is NOT a topic.
            assertEq(logs[i].topics.length, 3);
            assertEq(address(uint160(uint256(logs[i].topics[1]))), proxy);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), address(this));
            assertEq(abi.decode(logs[i].data, (string)), "recoverable-name");
        }

        assertTrue(found, "ProxyDeployed not emitted");
    }

    // ===== MUTABLE implementation / dataContract =====

    function test_setImplementationChangesWhatNewProxiesRun() public {
        address before = factory.deployProxy("before", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(_proxyImplementation(before), address(implementation));

        RecyReport newImplementation = new RecyReport();

        vm.expectEmit(true, true, false, false);
        emit RecyReportFactoryV2.ImplementationUpdated(address(implementation), address(newImplementation));
        factory.setImplementation(address(newImplementation));

        assertEq(factory.implementation(), address(newImplementation));

        address afterProxy =
            factory.deployProxy("after", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(_proxyImplementation(afterProxy), address(newImplementation));

        // Already-deployed proxies are untouched by the setter.
        assertEq(_proxyImplementation(before), address(implementation));
    }

    function test_setDataContractChangesWhatNewProxiesReceive() public {
        address before = factory.deployProxy("before", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(_proxyDataContract(before), address(dataContract));

        RecyReportData newData = new RecyReportData(address(attributes), address(svg));

        vm.expectEmit(true, true, false, false);
        emit RecyReportFactoryV2.DataContractUpdated(address(dataContract), address(newData));
        factory.setDataContract(address(newData));

        assertEq(factory.dataContract(), address(newData));

        address afterProxy =
            factory.deployProxy("after", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(_proxyDataContract(afterProxy), address(newData));

        // Already-deployed proxies keep their original wiring.
        assertEq(_proxyDataContract(before), address(dataContract));
    }

    function test_setImplementationOnlyOwner() public {
        RecyReport newImplementation = new RecyReport();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.setImplementation(address(newImplementation));
    }

    function test_setDataContractOnlyOwner() public {
        RecyReportData newData = new RecyReportData(address(attributes), address(svg));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.setDataContract(address(newData));
    }

    function test_setImplementationRejectsZero() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidImplementation.selector);
        factory.setImplementation(address(0));
    }

    function test_setDataContractRejectsZero() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidDataContract.selector);
        factory.setDataContract(address(0));
    }

    function test_constructorRejectsZeroImplementation() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidImplementation.selector);
        new RecyReportFactoryV2(address(0), address(dataContract));
    }

    function test_constructorRejectsZeroDataContract() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidDataContract.selector);
        new RecyReportFactoryV2(address(implementation), address(0));
    }

    function test_setImplementationRejectsCodelessAddress() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidImplementation.selector);
        factory.setImplementation(address(0xDEAD)); // EOA-shaped: no code
    }

    function test_setDataContractRejectsCodelessAddress() public {
        // A code-less data contract is the silent "born broken" class: RecyReport.initialize
        // only stores the address, so deployProxy would SUCCEED and the new proxy's metadata
        // reads would all revert until an admin re-pointed it.
        vm.expectRevert(RecyReportFactoryV2.InvalidDataContract.selector);
        factory.setDataContract(address(0xDEAD));
    }

    function test_constructorRejectsCodelessAddresses() public {
        vm.expectRevert(RecyReportFactoryV2.InvalidImplementation.selector);
        new RecyReportFactoryV2(address(0xDEAD), address(dataContract));

        vm.expectRevert(RecyReportFactoryV2.InvalidDataContract.selector);
        new RecyReportFactoryV2(address(implementation), address(0xDEAD));
    }

    function test_initializeSelectorIsFrozen() public pure {
        // Both factories hardcode this selector: V1 in immutable deployed bytecode, V2 at its
        // own compile time. Every behavioural test computes the selector FROM SOURCE, so an
        // initialize signature change would recompile consistently and keep the whole suite
        // green while permanently bricking deployProxy on the deployed factories. This literal
        // pin is what turns that silent live-compat break into a test failure.
        assertEq(RecyReport.initialize.selector, bytes4(0x54de02e5));
        assertEq(
            RecyReport.initialize.selector,
            bytes4(keccak256("initialize(string,string,address,address,address,uint64,uint8,uint8,uint8,uint8)"))
        );
    }

    function test_deployProxyRevertsWhenImplementationInitializeIncompatible() public {
        // Executable documentation of the INITIALIZE-SELECTOR FREEZE note: point the factory at
        // a contract that has code but no initialize with the frozen selector - the deployment
        // fails loudly in the proxy constructor instead of minting a mis-initialized proxy.
        factory.setImplementation(address(dataContract));

        vm.expectRevert();
        factory.deployProxy("doomed", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
    }

    function test_upgradeProxyEmitsAndRejectsZeroImplementation() public {
        address proxy = deployTestProxy();
        RecyReport newImplementation = new RecyReport();

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactoryV2.ProxyUpgraded(proxy, address(newImplementation), owner);
        factory.upgradeProxy(proxy, address(newImplementation));
        assertEq(_proxyImplementation(proxy), address(newImplementation));

        vm.expectRevert(RecyReportFactoryV2.InvalidImplementation.selector);
        factory.upgradeProxy(proxy, address(0));
    }

    function test_registrationConveysNoPowerOverArbitraryContracts() public {
        // Adopting an arbitrary contract (here: the token) registers it and nothing more: the
        // factory holds no role on it and the passthrough cannot even resolve AUDITOR_ROLE() on
        // it, so every privileged action reverts. Registration is bookkeeping, not authority.
        factory.registerExistingProxy(address(token), "not-a-report");
        assertTrue(factory.isDeployedProxy(address(token)));

        vm.expectRevert();
        factory.grantAuditorRole(address(token), stranger);
    }

    // ===== OWNERSHIP =====

    function test_renounceOwnershipRevertsForOwner() public {
        vm.expectRevert(RecyReportFactoryV2.RenounceOwnershipDisabled.selector);
        factory.renounceOwnership();

        assertEq(factory.owner(), owner);
    }

    function test_renounceOwnershipRevertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(RecyReportFactoryV2.RenounceOwnershipDisabled.selector);
        factory.renounceOwnership();

        assertEq(factory.owner(), owner);
    }

    function test_twoStepOwnershipTransfer() public {
        address newOwner = address(0xA11CE);

        factory.transferOwnership(newOwner);

        // Ownership has NOT moved yet.
        assertEq(factory.owner(), owner);
        assertEq(factory.pendingOwner(), newOwner);

        // A non-pending account cannot accept.
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.acceptOwnership();

        // The pending owner has no powers before accepting.
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        factory.deployProxy("premature", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        vm.prank(newOwner);
        factory.acceptOwnership();

        assertEq(factory.owner(), newOwner);
        assertEq(factory.pendingOwner(), address(0));

        // The old owner is out.
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        factory.deployProxy("stale", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);

        vm.prank(newOwner);
        factory.deployProxy("fresh", "RECY", address(token), protocolAddress, 3600, 25, 25, 25, 25);
        assertEq(factory.getDeployedProxiesCount(), 1);
    }

    function test_ownershipTransferCanBeCancelled() public {
        address newOwner = address(0xA11CE);

        factory.transferOwnership(newOwner);
        assertEq(factory.pendingOwner(), newOwner);

        factory.transferOwnership(address(0));
        assertEq(factory.pendingOwner(), address(0));

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        factory.acceptOwnership();

        assertEq(factory.owner(), owner);
    }

    // ===== SELF-REVOCATION GUARD =====

    function test_revokeAdminRoleCannotTargetTheFactory() public {
        address proxy = deployTestProxy();
        assertTrue(factory.hasAdminRole(proxy, address(factory)));

        vm.expectRevert(RecyReportFactoryV2.CannotRevokeFactoryAdmin.selector);
        factory.revokeAdminRole(proxy, address(factory));

        // Factory control is intact.
        assertTrue(factory.hasAdminRole(proxy, address(factory)));
        factory.grantAuditorRole(proxy, stranger);
        assertTrue(factory.hasAuditorRole(proxy, stranger));
    }

    function test_revokeAdminRoleCannotTargetTheFactoryOnAdoptedProxy() public {
        address proxy = _deployStandaloneProxy("adopted");
        factory.registerExistingProxy(proxy, "adopted");
        RecyReport(proxy).grantRole(RecyReport(proxy).DEFAULT_ADMIN_ROLE(), address(factory));

        vm.expectRevert(RecyReportFactoryV2.CannotRevokeFactoryAdmin.selector);
        factory.revokeAdminRole(proxy, address(factory));

        assertTrue(factory.hasAdminRole(proxy, address(factory)));
    }

    function test_revokeAdminRoleStillWorksForOtherAdmins() public {
        address proxy = deployTestProxy();

        factory.grantAdminRole(proxy, stranger);
        assertTrue(factory.hasAdminRole(proxy, stranger));

        vm.expectEmit(true, true, true, false);
        emit RecyReportFactoryV2.AdminRoleRevoked(proxy, stranger, address(this));
        factory.revokeAdminRole(proxy, stranger);

        assertFalse(factory.hasAdminRole(proxy, stranger));
        assertTrue(factory.hasAdminRole(proxy, address(factory)));
    }

    // ===== NAME PAGINATION =====

    function test_getProxyNamesPaginatedOnEmptyRegistry() public view {
        (string[] memory names, uint256 total) = factory.getProxyNamesPaginated(0, 10);

        assertEq(total, 0);
        assertEq(names.length, 0);
    }

    function test_getProxyNamesPaginatedReturnsNamesInOrder() public {
        for (uint256 i = 0; i < 5; i++) {
            deployTestProxy();
        }

        (string[] memory page, uint256 total) = factory.getProxyNamesPaginated(0, 3);
        assertEq(total, 5);
        assertEq(page.length, 3);
        assertEq(page[0], "v2-proxy-1");
        assertEq(page[1], "v2-proxy-2");
        assertEq(page[2], "v2-proxy-3");
    }

    function test_getProxyNamesPaginatedPartialLastPage() public {
        for (uint256 i = 0; i < 5; i++) {
            deployTestProxy();
        }

        (string[] memory page, uint256 total) = factory.getProxyNamesPaginated(3, 3);
        assertEq(total, 5);
        assertEq(page.length, 2);
        assertEq(page[0], "v2-proxy-4");
        assertEq(page[1], "v2-proxy-5");
    }

    function test_getProxyNamesPaginatedOffsetBeyondEnd() public {
        for (uint256 i = 0; i < 3; i++) {
            deployTestProxy();
        }

        (string[] memory atEnd, uint256 total) = factory.getProxyNamesPaginated(3, 3);
        assertEq(total, 3);
        assertEq(atEnd.length, 0);

        (string[] memory past, uint256 total2) = factory.getProxyNamesPaginated(10, 3);
        assertEq(total2, 3);
        assertEq(past.length, 0);

        (string[] memory extreme, uint256 total3) = factory.getProxyNamesPaginated(type(uint256).max, 1);
        assertEq(total3, 3);
        assertEq(extreme.length, 0);
    }

    function test_getProxyNamesPaginatedZeroLimit() public {
        deployTestProxy();

        (string[] memory page, uint256 total) = factory.getProxyNamesPaginated(0, 0);
        assertEq(total, 1);
        assertEq(page.length, 0);
    }

    function test_paginatorsClampInsteadOfOverflowing() public {
        for (uint256 i = 0; i < 3; i++) {
            deployTestProxy();
        }

        (string[] memory names, uint256 nameTotal) = factory.getProxyNamesPaginated(1, type(uint256).max);
        assertEq(nameTotal, 3);
        assertEq(names.length, 2);
        assertEq(names[0], "v2-proxy-2");

        (address[] memory proxies, uint256 proxyTotal) = factory.getDeployedProxiesPaginated(1, type(uint256).max);
        assertEq(proxyTotal, 3);
        assertEq(proxies.length, 2);
    }

    function test_getDeployedProxiesPaginatedBoundaries() public {
        address[] memory deployed = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            deployed[i] = deployTestProxy();
        }

        (address[] memory first, uint256 total) = factory.getDeployedProxiesPaginated(0, 3);
        assertEq(total, 5);
        assertEq(first.length, 3);
        assertEq(first[0], deployed[0]);

        (address[] memory last,) = factory.getDeployedProxiesPaginated(3, 3);
        assertEq(last.length, 2);
        assertEq(last[1], deployed[4]);

        (address[] memory beyond,) = factory.getDeployedProxiesPaginated(5, 1);
        assertEq(beyond.length, 0);
    }

    function test_getProxyNamesPaginatedIncludesAdoptedProxies() public {
        deployTestProxy();
        address adopted = _deployStandaloneProxy("adopted");
        factory.registerExistingProxy(adopted, "adopted");

        (string[] memory names, uint256 total) = factory.getProxyNamesPaginated(0, 10);
        assertEq(total, 2);
        assertEq(names.length, 2);
        assertEq(names[0], "v2-proxy-1");
        assertEq(names[1], "adopted");
    }

    // ===== LOOKUP FAILURES =====

    function test_getProxyByNameRevertsForUnknownName() public {
        vm.expectRevert(RecyReportFactoryV2.ProxyNotFound.selector);
        factory.getProxyByName("nope");
    }

    function test_getNameByProxyRevertsForUnknownProxy() public {
        vm.expectRevert(RecyReportFactoryV2.ProxyNotFound.selector);
        factory.getNameByProxy(address(0xCAFE));
    }
}
