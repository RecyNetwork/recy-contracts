// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RecyReport} from "./RecyReport.sol";

/**
 * @title RecyReportFactoryV2
 * @notice Factory contract for deploying and managing RecyReport proxy instances
 * @dev Replacement for the non-upgradeable `RecyReportFactory`. The V1 factory bakes
 *      `implementation` and `dataContract` into `immutable` storage, so every proxy it
 *      deploys is permanently born with whatever code those two addresses pointed at when
 *      the factory itself was deployed. V2 holds both in owner-settable storage instead, so
 *      future fixes propagate to new proxies without another factory migration.
 *
 *      V2 can also adopt proxies it did not deploy via {registerExistingProxy}; without that
 *      path a replacement factory could never manage the already-live proxy, because every
 *      privileged function gates on registry membership.
 *
 *      Migration sequence for an existing proxy (all steps signed by the V1 factory owner,
 *      who must also be the V2 owner or coordinate with them):
 *        0. Transfer V2 ownership to the governance address (multisig / TimelockController)
 *           and complete `acceptOwnership` BEFORE adopting the live proxy. V2 upgrades are
 *           immediate and single-key; the delay half of the plan's "Ownable2Step + timelock"
 *           is deliberately operational, so it exists only if the owner IS the timelock.
 *        1. Deploy V2 with the current blessed implementation + data contract.
 *        2. `v2.registerExistingProxy(proxy, name)`  — V2 owner. ⚠ PERMANENT: there is no
 *           unregister or rename; a wrong address burns the name forever and pollutes
 *           enumeration forever. Triple-check against config/contracts.json before signing.
 *        3. `v1.grantAdminRole(proxy, address(v2))`  — V1 owner; hands DEFAULT_ADMIN_ROLE to V2.
 *        4. `v2.hasAdminRole(proxy, address(v2))`    — verify the grant landed before step 5.
 *        5. `v1.revokeAdminRole(proxy, address(v1))` — V1 owner; drops the old factory.
 *      Step 5 must come last and must never be run before step 4 succeeds.
 *
 *      INITIALIZE-SELECTOR FREEZE. {deployProxy} encodes `RecyReport.initialize.selector`
 *      fixed at THIS contract's compile time (0x54de02e5, 10 params). Any implementation set
 *      via {setImplementation} MUST keep that exact initialize signature; otherwise every
 *      subsequent {deployProxy} reverts in the proxy constructor until the implementation is
 *      corrected or a successor factory ships.
 */
contract RecyReportFactoryV2 is Ownable2Step {
    /// @notice Maximum byte length of a proxy name
    /// @dev Names are attacker-supplied strings persisted three times and returned wholesale
    ///      by `getAllProxyNames()`; an unbounded name is a permanent storage/return-size cost.
    uint256 public constant MAX_PROXY_NAME_LENGTH = 64;

    /// @notice The RecyReport implementation contract used for new proxies
    /// @dev Mutable (unlike V1) so implementation fixes reach subsequently deployed proxies
    address public implementation;

    /// @notice The RecyReportData contract wired into new proxies at initialization
    /// @dev Mutable (unlike V1) so data-contract fixes reach subsequently deployed proxies
    address public dataContract;

    /// @notice Array of all proxy addresses managed by this factory, for enumeration
    address[] public deployedProxies;

    /// @notice O(1) membership check for every privileged path
    /// @dev True for proxies deployed by this factory *and* for proxies adopted via
    ///      {registerExistingProxy}. Replaces V1's unbounded linear scan.
    mapping(address => bool) public isDeployedProxy;

    /// @notice Mapping from proxy name to proxy address
    mapping(string => address) public proxyByName;

    /// @notice Mapping from proxy address to proxy name
    mapping(address => string) public nameByProxy;

    /// @notice Array of all proxy names for enumeration
    string[] public proxyNames;

    /// @notice Events
    /// @dev `proxyName` is deliberately NOT indexed: an indexed string is stored as
    ///      `keccak256(name)`, which makes the name unrecoverable from logs.
    event ProxyDeployed(address indexed proxy, address indexed deployer, string proxyName);

    event ProxyRegistered(address indexed proxy, address indexed registeredBy, string proxyName);

    event ProxyUpgraded(address indexed proxy, address indexed newImplementation, address indexed upgradedBy);

    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    event DataContractUpdated(address indexed oldDataContract, address indexed newDataContract);

    event AuditorRoleGranted(address indexed proxy, address indexed auditor, address indexed grantedBy);

    event AuditorRoleRevoked(address indexed proxy, address indexed auditor, address indexed revokedBy);

    event RecyclerRoleGranted(address indexed proxy, address indexed recycler, address indexed grantedBy);

    event RecyclerRoleRevoked(address indexed proxy, address indexed recycler, address indexed revokedBy);

    event AdminRoleGranted(address indexed proxy, address indexed admin, address indexed grantedBy);

    event AdminRoleRevoked(address indexed proxy, address indexed admin, address indexed revokedBy);

    event EmergencyRoleGranted(address indexed proxy, address indexed emergency, address indexed grantedBy);

    event EmergencyRoleRevoked(address indexed proxy, address indexed emergency, address indexed revokedBy);

    /// @notice Errors
    error InvalidImplementation();
    error InvalidDataContract();
    error InvalidProtocolAddress();
    error InvalidProxyAddress();
    error ProxyNameAlreadyExists();
    error InvalidProxyName();
    error ProxyNameTooLong();
    error ProxyNotFound();
    error ProxyAlreadyRegistered();
    error ProxyNotAContract();
    error CannotRevokeFactoryAdmin();
    error RenounceOwnershipDisabled();

    /// @notice A role passthrough was called against an address that is not in the registry
    /// @dev The registry contains factory-deployed AND adopted proxies, so "not registered",
    ///      not "not deployed by factory", is the accurate failure description
    error ProxyNotRegistered();

    /// @notice A role grant/revoke passthrough was given the zero address as its target account
    error InvalidAccount();

    /**
     * @notice Constructor
     * @param _implementation Address of the RecyReport implementation contract
     * @param _dataContract Address of the RecyReportData contract
     * @dev Both must be deployed contracts. A code-less `dataContract` would be worse than a
     *      loud failure: `RecyReport.initialize` only stores it, so {deployProxy} would SUCCEED
     *      and the proxy would be born with every tokenURI/tokenJson call reverting.
     */
    constructor(address _implementation, address _dataContract) Ownable(msg.sender) {
        if (_implementation.code.length == 0) revert InvalidImplementation();
        if (_dataContract.code.length == 0) revert InvalidDataContract();

        implementation = _implementation;
        dataContract = _dataContract;
    }

    // ===== CONFIGURATION =====

    /**
     * @notice Set the implementation used for proxies deployed from here on
     * @param _implementation Address of the new RecyReport implementation contract
     * @dev Does not touch already-deployed proxies; use {upgradeProxy} for those. Must be a
     *      deployed contract whose `initialize` keeps selector 0x54de02e5 (see the
     *      INITIALIZE-SELECTOR FREEZE note on the contract): {deployProxy} encodes the selector
     *      from THIS contract's compile time, so a signature-incompatible implementation makes
     *      every subsequent deployment revert
     */
    function setImplementation(address _implementation) external onlyOwner {
        if (_implementation.code.length == 0) revert InvalidImplementation();

        address oldImplementation = implementation;
        implementation = _implementation;

        emit ImplementationUpdated(oldImplementation, _implementation);
    }

    /**
     * @notice Set the data contract wired into proxies deployed from here on
     * @param _dataContract Address of the new RecyReportData contract
     * @dev Does not touch already-deployed proxies; call `setDataContract` on those directly.
     *      Must be a deployed contract: `RecyReport.initialize` only stores the address, so a
     *      code-less value here would let {deployProxy} succeed and produce a proxy whose
     *      metadata reads all revert - the silent "born broken" class this mutable design
     *      exists to prevent
     */
    function setDataContract(address _dataContract) external onlyOwner {
        if (_dataContract.code.length == 0) revert InvalidDataContract();

        address oldDataContract = dataContract;
        dataContract = _dataContract;

        emit DataContractUpdated(oldDataContract, _dataContract);
    }

    /**
     * @notice Renouncing ownership is permanently disabled
     * @dev The factory holds DEFAULT_ADMIN_ROLE on every proxy it manages. A single
     *      `renounceOwnership()` would irreversibly sever control of all of them.
     */
    function renounceOwnership() public pure override {
        revert RenounceOwnershipDisabled();
    }

    // ===== DEPLOYMENT & REGISTRATION =====

    /**
     * @notice Deploy a new RecyReport proxy with custom configuration
     * @param name The name for the NFT collection
     * @param symbol The symbol for the NFT collection
     * @param tokenAddress The address of the token used for rewards
     * @param protocolAddress The address that receives protocol fees
     * @param unlockDelay The delay in seconds before rewards can be claimed
     * @param shareRecycler The percentage share for recyclers (0-100)
     * @param shareValidator The percentage share for validators (0-100)
     * @param shareGenerator The percentage share for generators (0-100)
     * @param shareProtocol The percentage share for protocol (0-100)
     * @return proxy The address of the deployed proxy
     * @dev Owner-gated (unlike V1): permissionless deployment allowed permanent name squatting,
     *      since names are first-come-first-served with no removal path.
     */
    function deployProxy(
        string memory name,
        string memory symbol,
        address tokenAddress,
        address protocolAddress,
        uint64 unlockDelay,
        uint8 shareRecycler,
        uint8 shareValidator,
        uint8 shareGenerator,
        uint8 shareProtocol
    ) public onlyOwner returns (address proxy) {
        _validateProxyName(name);

        // `initialize` only checks token + data. A zero protocol address bricks every
        // `claimRecyReportReward` forever, because ERC20 rejects a zero recipient.
        if (protocolAddress == address(0)) revert InvalidProtocolAddress();

        // Encode the initialize function call
        bytes memory initializeCall = abi.encodeWithSelector(
            RecyReport.initialize.selector,
            name,
            symbol,
            tokenAddress,
            dataContract,
            protocolAddress,
            unlockDelay,
            shareRecycler,
            shareValidator,
            shareGenerator,
            shareProtocol
        );

        // Deploy the proxy contract
        ERC1967Proxy newProxy = new ERC1967Proxy(implementation, initializeCall);

        proxy = address(newProxy);

        _registerProxy(proxy, name);

        emit ProxyDeployed(proxy, msg.sender, name);

        return proxy;
    }

    /**
     * @notice Adopt a RecyReport proxy this factory did not deploy
     * @param proxy The proxy address to bring under this factory's management
     * @param name The registry name to record for that proxy
     * @dev Registration alone grants no on-chain power. The proxy's current
     *      DEFAULT_ADMIN_ROLE holder must additionally grant that role to this factory
     *      before any of the role or upgrade passthroughs will succeed.
     */
    function registerExistingProxy(address proxy, string calldata name) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (proxy.code.length == 0) revert ProxyNotAContract();
        if (isDeployedProxy[proxy]) revert ProxyAlreadyRegistered();

        _validateProxyName(name);
        _registerProxy(proxy, name);

        emit ProxyRegistered(proxy, msg.sender, name);
    }

    // ===== VIEWS =====

    /**
     * @notice Get the total number of managed proxies
     * @return count The number of managed proxies
     */
    function getDeployedProxiesCount() external view returns (uint256 count) {
        return deployedProxies.length;
    }

    /**
     * @notice Get all managed proxy addresses
     * @return proxies Array of all managed proxy addresses
     */
    function getAllDeployedProxies() external view returns (address[] memory proxies) {
        return deployedProxies;
    }

    /**
     * @notice Get a paginated list of managed proxies
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return proxies Array of proxy addresses
     * @return total Total number of managed proxies
     */
    function getDeployedProxiesPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory proxies, uint256 total)
    {
        total = deployedProxies.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 length = _pageLength(total, offset, limit);
        proxies = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            proxies[i] = deployedProxies[offset + i];
        }

        return (proxies, total);
    }

    /**
     * @notice Get proxy address by name
     * @param proxyName The name of the proxy
     * @return proxy The address of the proxy with the given name
     */
    function getProxyByName(string memory proxyName) external view returns (address proxy) {
        proxy = proxyByName[proxyName];
        if (proxy == address(0)) revert ProxyNotFound();
        return proxy;
    }

    /**
     * @notice Get proxy name by address
     * @param proxy The address of the proxy
     * @return proxyName The name of the proxy at the given address
     */
    function getNameByProxy(address proxy) external view returns (string memory proxyName) {
        proxyName = nameByProxy[proxy];
        if (bytes(proxyName).length == 0) revert ProxyNotFound();
        return proxyName;
    }

    /**
     * @notice Check if a proxy name exists
     * @param proxyName The name to check
     * @return exists True if the proxy name exists
     */
    function proxyNameExists(string memory proxyName) external view returns (bool exists) {
        return proxyByName[proxyName] != address(0);
    }

    /**
     * @notice Get all managed proxy names
     * @return names Array of all managed proxy names
     */
    function getAllProxyNames() external view returns (string[] memory names) {
        return proxyNames;
    }

    /**
     * @notice Get the total number of managed proxy names
     * @return count The number of managed proxy names
     */
    function getProxyNamesCount() external view returns (uint256 count) {
        return proxyNames.length;
    }

    /**
     * @notice Get a paginated list of managed proxy names
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return names Array of proxy names
     * @return total Total number of managed proxy names
     * @dev Mirrors {getDeployedProxiesPaginated}; the unbounded {getAllProxyNames} should not
     *      be the only way a backend reads the registry.
     */
    function getProxyNamesPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (string[] memory names, uint256 total)
    {
        total = proxyNames.length;

        if (offset >= total) {
            return (new string[](0), total);
        }

        uint256 length = _pageLength(total, offset, limit);
        names = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            names[i] = proxyNames[offset + i];
        }

        return (names, total);
    }

    // ===== ROLE MANAGEMENT =====

    /**
     * @notice Grant AUDITOR_ROLE to an address on a specific proxy
     * @param proxy The proxy address to grant the role on
     * @param auditor The address to grant the AUDITOR_ROLE to
     */
    function grantAuditorRole(address proxy, address auditor) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (auditor == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.grantRole(recyReport.AUDITOR_ROLE(), auditor);

        emit AuditorRoleGranted(proxy, auditor, msg.sender);
    }

    /**
     * @notice Revoke AUDITOR_ROLE from an address on a specific proxy
     * @param proxy The proxy address to revoke the role from
     * @param auditor The address to revoke the AUDITOR_ROLE from
     */
    function revokeAuditorRole(address proxy, address auditor) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (auditor == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.revokeRole(recyReport.AUDITOR_ROLE(), auditor);

        emit AuditorRoleRevoked(proxy, auditor, msg.sender);
    }

    /**
     * @notice Grant RECYCLER_ROLE to an address on a specific proxy
     * @param proxy The proxy address to grant the role on
     * @param recycler The address to grant the RECYCLER_ROLE to
     */
    function grantRecyclerRole(address proxy, address recycler) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (recycler == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.grantRole(recyReport.RECYCLER_ROLE(), recycler);

        emit RecyclerRoleGranted(proxy, recycler, msg.sender);
    }

    /**
     * @notice Revoke RECYCLER_ROLE from an address on a specific proxy
     * @param proxy The proxy address to revoke the role from
     * @param recycler The address to revoke the RECYCLER_ROLE from
     */
    function revokeRecyclerRole(address proxy, address recycler) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (recycler == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.revokeRole(recyReport.RECYCLER_ROLE(), recycler);

        emit RecyclerRoleRevoked(proxy, recycler, msg.sender);
    }

    /**
     * @notice Grant DEFAULT_ADMIN_ROLE to an address on a specific proxy
     * @param proxy The proxy address to grant the role on
     * @param admin The address to grant the DEFAULT_ADMIN_ROLE to
     */
    function grantAdminRole(address proxy, address admin) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (admin == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.grantRole(recyReport.DEFAULT_ADMIN_ROLE(), admin);

        emit AdminRoleGranted(proxy, admin, msg.sender);
    }

    /**
     * @notice Revoke DEFAULT_ADMIN_ROLE from an address on a specific proxy
     * @param proxy The proxy address to revoke the role from
     * @param admin The address to revoke the DEFAULT_ADMIN_ROLE from
     * @dev The factory cannot revoke its own admin role. DEFAULT_ADMIN_ROLE is its own role
     *      admin in OZ AccessControl, so doing so would irreversibly brick every factory
     *      passthrough for that proxy with no way back.
     */
    function revokeAdminRole(address proxy, address admin) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (admin == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();
        if (admin == address(this)) revert CannotRevokeFactoryAdmin();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.revokeRole(recyReport.DEFAULT_ADMIN_ROLE(), admin);

        emit AdminRoleRevoked(proxy, admin, msg.sender);
    }

    /**
     * @notice Grant EMERGENCY_ROLE to an address on a specific proxy
     * @param proxy The proxy address to grant the role on
     * @param emergency The address to grant the EMERGENCY_ROLE to
     */
    function grantEmergencyRole(address proxy, address emergency) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (emergency == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.grantRole(recyReport.EMERGENCY_ROLE(), emergency);

        emit EmergencyRoleGranted(proxy, emergency, msg.sender);
    }

    /**
     * @notice Revoke EMERGENCY_ROLE from an address on a specific proxy
     * @param proxy The proxy address to revoke the role from
     * @param emergency The address to revoke the EMERGENCY_ROLE from
     */
    function revokeEmergencyRole(address proxy, address emergency) external onlyOwner {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (emergency == address(0)) revert InvalidAccount();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        recyReport.revokeRole(recyReport.EMERGENCY_ROLE(), emergency);

        emit EmergencyRoleRevoked(proxy, emergency, msg.sender);
    }

    /**
     * @notice Check if an address has AUDITOR_ROLE on a specific proxy
     * @param proxy The proxy address to check
     * @param auditor The address to check
     * @return hasRole True if the address has the AUDITOR_ROLE
     */
    function hasAuditorRole(address proxy, address auditor) external view returns (bool hasRole) {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        return recyReport.hasRole(recyReport.AUDITOR_ROLE(), auditor);
    }

    /**
     * @notice Check if an address has RECYCLER_ROLE on a specific proxy
     * @param proxy The proxy address to check
     * @param recycler The address to check
     * @return hasRole True if the address has the RECYCLER_ROLE
     */
    function hasRecyclerRole(address proxy, address recycler) external view returns (bool hasRole) {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        return recyReport.hasRole(recyReport.RECYCLER_ROLE(), recycler);
    }

    /**
     * @notice Check if an address has DEFAULT_ADMIN_ROLE on a specific proxy
     * @param proxy The proxy address to check
     * @param admin The address to check
     * @return hasRole True if the address has the DEFAULT_ADMIN_ROLE
     */
    function hasAdminRole(address proxy, address admin) external view returns (bool hasRole) {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        return recyReport.hasRole(recyReport.DEFAULT_ADMIN_ROLE(), admin);
    }

    /**
     * @notice Check if an address has EMERGENCY_ROLE on a specific proxy
     * @param proxy The proxy address to check
     * @param emergency The address to check
     * @return hasRole True if the address has the EMERGENCY_ROLE
     */
    function hasEmergencyRole(address proxy, address emergency) external view returns (bool hasRole) {
        if (proxy == address(0)) revert InvalidProxyAddress();
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();

        RecyReport recyReport = RecyReport(proxy);
        return recyReport.hasRole(recyReport.EMERGENCY_ROLE(), emergency);
    }

    // ===== UPGRADES =====

    /**
     * @notice Upgrade a managed proxy to a new implementation
     * @param proxy The proxy contract address to upgrade
     * @param newImplementation The new implementation contract address
     * @dev Only the factory owner can upgrade proxies. This does not change the factory's
     *      own {implementation} default for future deployments; use {setImplementation}.
     */
    function upgradeProxy(address proxy, address newImplementation) external onlyOwner {
        if (!isDeployedProxy[proxy]) revert ProxyNotRegistered();
        if (newImplementation == address(0)) revert InvalidImplementation();

        // Call upgradeToAndCall on the proxy - factory has DEFAULT_ADMIN_ROLE
        RecyReport(proxy).upgradeToAndCall(newImplementation, "");

        emit ProxyUpgraded(proxy, newImplementation, msg.sender);
    }

    // ===== INTERNAL =====

    /**
     * @notice Validate a not-yet-used proxy name
     * @param name The candidate name
     */
    function _validateProxyName(string memory name) internal view {
        uint256 nameLength = bytes(name).length;
        if (nameLength == 0) revert InvalidProxyName();
        if (nameLength > MAX_PROXY_NAME_LENGTH) revert ProxyNameTooLong();
        if (proxyByName[name] != address(0)) revert ProxyNameAlreadyExists();
    }

    /**
     * @notice Write a proxy into every registry structure
     * @param proxy The proxy address
     * @param name The already-validated proxy name
     */
    function _registerProxy(address proxy, string memory name) internal {
        deployedProxies.push(proxy);
        isDeployedProxy[proxy] = true;
        proxyByName[name] = proxy;
        nameByProxy[proxy] = name;
        proxyNames.push(name);
    }

    /**
     * @notice Compute the length of a page, clamped to the end of the collection
     * @param total Total number of items
     * @param offset Starting index, already known to be `< total`
     * @param limit Maximum number of results
     * @return length The number of items in the page
     * @dev Written as a subtraction so a `limit` near `type(uint256).max` clamps instead of
     *      overflowing on `offset + limit`.
     */
    function _pageLength(uint256 total, uint256 offset, uint256 limit) internal pure returns (uint256 length) {
        uint256 remaining = total - offset;
        return limit < remaining ? limit : remaining;
    }
}
