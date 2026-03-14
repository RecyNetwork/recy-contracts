// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RecyTypes} from "./lib/RecyTypes.sol";
import {RecyErrors} from "./lib/RecyErrors.sol";
import {RecyReport} from "./RecyReport.sol";
import {RecyToken} from "./RecyToken.sol";

contract RecyDistribution is Ownable {
    RecyToken public token;

    /// @notice Array to track all report contracts
    address[] public reportContracts;

    /// @notice Mapping to track total tokens minted to each report contract
    mapping(address => uint256) public totalMintedToReport;

    /// @notice Mapping to track blacklisted report contracts
    mapping(address => bool) public blacklistedReports;

    /// @notice Events
    event TokensMinted(address indexed reportContract, uint256 amount);
    event ReportContractAdded(address indexed reportContract);
    event ReportContractBlacklisted(address indexed reportContract);
    event ReportContractWhitelisted(address indexed reportContract);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Zero address not allowed");

        token = RecyToken(_token);
    }

    /**
     * @notice Add a RecyReport contract or remove it from the blacklist
     * @param _reportContract The address of the RecyReport contract to whitelist
     * @dev Only owner can call this function
     */
    function whitelistReportContract(address _reportContract) external onlyOwner {
        require(_reportContract != address(0), "Zero address not allowed");

        bool exists = false;
        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (reportContracts[i] == _reportContract) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            reportContracts.push(_reportContract);
        } else {
            blacklistedReports[_reportContract] = false;
        }

        emit ReportContractWhitelisted(_reportContract);
    }

    /**
     * @notice Blacklist a RecyReport contract temporarily
     * @param _reportContract The address of the RecyReport contract to blacklist
     * @dev Only owner can call this function. Blacklisted contracts cannot receive minted tokens
     */
    function blacklistReportContract(address _reportContract) external onlyOwner {
        require(_reportContract != address(0), "Zero address not allowed");

        // Check if contract exists in the array
        bool exists = false;
        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (reportContracts[i] == _reportContract) {
                exists = true;
                break;
            }
        }
        require(exists, "Report contract not found");
        require(!blacklistedReports[_reportContract], "Report contract already blacklisted");

        blacklistedReports[_reportContract] = true;

        emit ReportContractBlacklisted(_reportContract);
    }

    /**
     * @notice Calculate the amount of tokens needed to be minted to a specific RecyReport contract
     * @param _reportContract The address of the RecyReport contract
     * @return tokensToMint The amount of tokens that need to be minted
     */
    function calculateTokensToMint(address _reportContract) public view returns (uint256 tokensToMint) {
        // Check if contract exists in the array
        bool exists = false;
        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (reportContracts[i] == _reportContract) {
                exists = true;
                break;
            }
        }
        require(exists, "Report contract not found");
        require(!blacklistedReports[_reportContract], "Report contract is blacklisted");

        RecyReport report = RecyReport(_reportContract);

        // Get total rewards that should be available across all reports
        uint256 totalRewards = report.rewardTotal();

        // Get total claimed rewards across all reports
        uint256 claimedRewards = report.rewardClaimed();

        // Get current token balance of the RecyReport contract
        uint256 contractBalance = token.balanceOf(_reportContract);

        // Calculate how much should be available (total - claimed)
        uint256 shouldHave = totalRewards - claimedRewards;

        // If contract doesn't have enough tokens, calculate how much to mint
        if (shouldHave > contractBalance) {
            tokensToMint = shouldHave - contractBalance;
        } else {
            tokensToMint = 0;
        }
    }

    /**
     * @notice Mint tokens to a specific RecyReport contract to cover reward shortfall
     * @param _reportContract The address of the RecyReport contract
     * @dev Only owner can call this function
     */
    function mintTokensToReport(address _reportContract) external onlyOwner {
        require(!blacklistedReports[_reportContract], "Report contract is blacklisted");

        uint256 tokensToMint = calculateTokensToMint(_reportContract);

        require(tokensToMint > 0, "No tokens need to be minted");

        // Mint tokens directly to the RecyReport contract
        token.mint(_reportContract, tokensToMint);

        // Update the tracking mapping
        totalMintedToReport[_reportContract] += tokensToMint;

        emit TokensMinted(_reportContract, tokensToMint);
    }

    /**
     * @notice Mint tokens to all approved RecyReport contracts that need them
     * @dev Only owner can call this function
     */
    function mintTokensToAllReports() external onlyOwner {
        uint256 totalMinted = 0;

        for (uint256 i = 0; i < reportContracts.length; i++) {
            address reportContract = reportContracts[i];

            // Skip blacklisted contracts
            if (blacklistedReports[reportContract]) {
                continue;
            }

            uint256 tokensToMint = calculateTokensToMint(reportContract);

            if (tokensToMint > 0) {
                token.mint(reportContract, tokensToMint);
                totalMintedToReport[reportContract] += tokensToMint;
                emit TokensMinted(reportContract, tokensToMint);
                totalMinted += tokensToMint;
            }
        }

        require(totalMinted > 0, "No tokens needed to be minted");
    }

    /**
     * @notice Get all report contracts (including blacklisted ones)
     * @return Array of all report contract addresses
     */
    function getAllReportContracts() external view returns (address[] memory) {
        return reportContracts;
    }

    /**
     * @notice Get all active (non-blacklisted) report contracts
     * @return Array of active report contract addresses
     */
    function getActiveReportContracts() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active contracts
        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeCount++;
            }
        }

        // Create array of active contracts
        address[] memory activeContracts = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeContracts[index] = reportContracts[i];
                index++;
            }
        }

        return activeContracts;
    }

    /**
     * @notice Get the number of report contracts
     * @return The count of all report contracts (including blacklisted)
     */
    function getReportContractCount() external view returns (uint256) {
        return reportContracts.length;
    }

    /**
     * @notice Get the number of active (non-blacklisted) report contracts
     * @return The count of active report contracts
     */
    function getActiveReportContractCount() external view returns (uint256) {
        uint256 activeCount = 0;

        for (uint256 i = 0; i < reportContracts.length; i++) {
            if (!blacklistedReports[reportContracts[i]]) {
                activeCount++;
            }
        }

        return activeCount;
    }
}
