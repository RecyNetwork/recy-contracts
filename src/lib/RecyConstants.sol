// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/**
 * @title RecyConstants
 * @notice Library containing all constants used throughout the Recy ecosystem
 * @dev Centralizes magic numbers and commonly used values for maintainability
 */
library RecyConstants {
    /// @notice Role identifier for auditors who can validate recycling reports
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    /// @notice Role identifier for recyclers who can create and populate recycling reports
    bytes32 public constant RECYCLER_ROLE = keccak256("RECYCLER_ROLE");

    /// @notice Role identifier for reward distributors (future use)
    bytes32 public constant REWARD_ROLE = keccak256("REWARD_ROLE");

    /// @notice Role identifier for emergency controllers who can pause reward claiming
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Standard 18 decimal precision multiplier for token calculations
    uint256 public constant ONE_E18 = 10 ** 18;

    /// @notice Total percentage value used for reward distribution calculations (100%)
    uint8 public constant REWARD_TOTAL_PERCENTAGE = 100;

    /// @notice Status indicating a recycling report has been created but not yet completed
    uint8 public constant RECYCLE_CREATED = 1;

    /// @notice Status indicating a recycling report has been completed with all materials data
    uint8 public constant RECYCLE_COMPLETED = 2;

    /// @notice Status indicating a recycling report has been validated and rewards calculated
    uint8 public constant RECYCLE_VALIDATED = 3;

    /// @notice Status indicating rewards have been claimed and distributed
    uint8 public constant RECYCLE_REWARDED = 4;

    /// @notice ERC4906 interface ID for metadata update events
    bytes4 public constant ERC4906_INTERFACE_ID = 0x49064906;

    /// @notice Increment value for NFT ID generation
    uint128 public constant NFT_ID_INCREMENT = 1;
}
