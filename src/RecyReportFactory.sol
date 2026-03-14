// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RecyReport} from "./RecyReport.sol";

/**
 * @title RecyReportFactory
 * @notice Factory contract for deploying RecyReport proxy instances
 * @dev Each deployment creates a new RecyReport proxy with a specified recycler
 */
contract RecyReportFactory is Ownable {
    /// @notice The RecyReport implementation contract
    address public immutable implementation;

    /// @notice The RecyReportData contract address
    address public immutable dataContract;

    /// @notice Array of all deployed proxy addresses
    address[] public deployedProxies;

    /// @notice Mapping from proxy name to proxy address
    mapping(string => address) public proxyByName;

    /// @notice Mapping from proxy address to proxy name
    mapping(address => string) public nameByProxy;

    /// @notice Array of all proxy names for enumeration
    string[] public proxyNames;

    /// @notice Events
    event ProxyDeployed(address indexed proxy, address indexed deployer, string indexed proxyName);

    event AuditorRoleGranted(address indexed proxy, address indexed auditor, address indexed grantedBy);

    event AuditorRoleRevoked(address indexed proxy, address indexed auditor, address indexed revokedBy);

    event RecyclerRoleGranted(address indexed proxy, address indexed recycler, address indexed grantedBy);

    event RecyclerRoleRevoked(address indexed proxy, address indexed recycler, address indexed revokedBy);

    event AdminRoleGranted(address indexed proxy, address indexed admin, address indexed grantedBy);

    event AdminRoleRevoked(address indexed proxy, address indexed admin, address indexed revokedBy);

    event EmergencyRoleGranted(address indexed proxy, address indexed emergency, address indexed grantedBy);

    event EmergencyRoleRevoked(address indexed proxy, address indexed emergency, address indexed revokedBy);

    /// @notice Errors
    error RecyclerAlreadyHasProxy();
    error InvalidRecyclerAddress();
    error InvalidImplementation();
    error InvalidDataContract();
    error ProxyNameAlreadyExists();
    error InvalidProxyName();
    error ProxyNotFound();

    /**
     * @notice Constructor
     * @param _implementation Address of the RecyReport implementation contract
     * @param _dataContract Address of the RecyReportData contract
     */
    constructor(address _implementation, address _dataContract) Ownable(msg.sender) {
        if (_implementation == address(0)) revert InvalidImplementation();
        if (_dataContract == address(0)) revert InvalidDataContract();

        implementation = _implementation;
        dataContract = _dataContract;
    }

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
    ) public returns (address proxy) {
        // Validate proxy name
        if (bytes(name).length == 0) revert InvalidProxyName();
        if (proxyByName[name] != address(0)) revert ProxyNameAlreadyExists();

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

        // Store the mappings
        deployedProxies.push(proxy);
        proxyByName[name] = proxy;
        nameByProxy[proxy] = name;
        proxyNames.push(name);

        emit ProxyDeployed(proxy, msg.sender, name);

        return proxy;
    }

    /**
     * @notice Get the total number of deployed proxies
     * @return count The number of deployed proxies
     */
    function getDeployedProxiesCount() external view returns (uint256 count) {
        return deployedProxies.length;
    }

    /**
     * @notice Get all deployed proxy addresses
     * @return proxies Array of all deployed proxy addresses
     */
    function getAllDeployedProxies() external view returns (address[] memory proxies) {
        return deployedProxies;
    }

    /**
     * @notice Get a paginated list of deployed proxies
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return proxies Array of proxy addresses
     * @return total Total number of deployed proxies
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

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 length = end - offset;
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
     * @notice Get all deployed proxy names
     * @return names Array of all deployed proxy names
     */
    function getAllProxyNames() external view returns (string[] memory names) {
        return proxyNames;
    }

    /**
     * @notice Get the total number of deployed proxy names
     * @return count The number of deployed proxy names
     */
    function getProxyNamesCount() external view returns (uint256 count) {
        return proxyNames.length;
    }

    /**
     * @notice Grant AUDITOR_ROLE to an address on a specific proxy
     * @param proxy The proxy address to grant the role on
     * @param auditor The address to grant the AUDITOR_ROLE to
     */
    function grantAuditorRole(address proxy, address auditor) external onlyOwner {
        require(proxy != address(0), "Invalid proxy address");
        require(auditor != address(0), "Invalid auditor address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(auditor != address(0), "Invalid auditor address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(recycler != address(0), "Invalid recycler address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(recycler != address(0), "Invalid recycler address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(admin != address(0), "Invalid admin address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

        RecyReport recyReport = RecyReport(proxy);
        recyReport.grantRole(recyReport.DEFAULT_ADMIN_ROLE(), admin);

        emit AdminRoleGranted(proxy, admin, msg.sender);
    }

    /**
     * @notice Revoke DEFAULT_ADMIN_ROLE from an address on a specific proxy
     * @param proxy The proxy address to revoke the role from
     * @param admin The address to revoke the DEFAULT_ADMIN_ROLE from
     */
    function revokeAdminRole(address proxy, address admin) external onlyOwner {
        require(proxy != address(0), "Invalid proxy address");
        require(admin != address(0), "Invalid admin address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(emergency != address(0), "Invalid emergency address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(emergency != address(0), "Invalid emergency address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

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
        require(proxy != address(0), "Invalid proxy address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

        RecyReport recyReport = RecyReport(proxy);
        return recyReport.hasRole(recyReport.EMERGENCY_ROLE(), emergency);
    }

    /**
     * @notice Upgrade a deployed proxy to a new implementation
     * @param proxy The proxy contract address to upgrade
     * @param newImplementation The new implementation contract address
     * @dev Only the factory owner can upgrade proxies
     */
    function upgradeProxy(address proxy, address newImplementation) external onlyOwner {
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");
        require(newImplementation != address(0), "Invalid implementation address");

        // Call upgradeToAndCall on the proxy - factory has DEFAULT_ADMIN_ROLE
        RecyReport(proxy).upgradeToAndCall(newImplementation, "");

        emit ProxyUpgraded(proxy, newImplementation, msg.sender);
    }

    /// @notice Event emitted when a proxy is upgraded
    event ProxyUpgraded(address indexed proxy, address indexed newImplementation, address indexed upgradedBy);

    /**
     * @notice Internal function to check if a proxy was deployed by this factory
     * @param proxy The proxy address to check
     * @return isDeployed True if the proxy was deployed by this factory
     */
    function _isDeployedProxy(address proxy) internal view returns (bool isDeployed) {
        for (uint256 i = 0; i < deployedProxies.length; i++) {
            if (deployedProxies[i] == proxy) {
                return true;
            }
        }
        return false;
    }

    // ===== FUND WALLET MANAGEMENT FUNCTIONS =====

    /**
     * @notice Set fund wallet for a recycler on a deployed proxy
     * @param proxy The proxy address
     * @param recycler The recycler address
     * @param fundWallet The fund wallet address (can be zero to clear)
     */
    function setRecyclerFund(address proxy, address recycler, address fundWallet) external onlyOwner {
        require(proxy != address(0), "Invalid proxy address");
        require(recycler != address(0), "Invalid recycler address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

        RecyReport(proxy).setFundsWallet(recycler, fundWallet);
    }

    /**
     * @notice Set fund wallet for an auditor on a deployed proxy
     * @param proxy The proxy address
     * @param auditor The auditor address
     * @param fundWallet The fund wallet address (can be zero to clear)
     */
    function setAuditorFund(address proxy, address auditor, address fundWallet) external onlyOwner {
        require(proxy != address(0), "Invalid proxy address");
        require(auditor != address(0), "Invalid auditor address");
        require(_isDeployedProxy(proxy), "Proxy not deployed by factory");

        RecyReport(proxy).setFundsWallet(auditor, fundWallet);
    }
}
