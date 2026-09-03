// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

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

    /// @notice Status indicating a recycling report has been invalidated; terminal - no reward is
    ///         recorded and rewardTotal is untouched (nothing was ever added for this report; see
    ///         the invariant note on RecyReport.rewardTotal)
    uint8 public constant RECYCLE_INVALIDATED = 5;

    /// @notice Status indicating a recycling report has been flagged for review due to suspected issues, pending further investigation
    uint8 public constant RECYCLE_FLAGGED = 6;

    /// @notice ERC4906 interface ID for metadata update events
    bytes4 public constant ERC4906_INTERFACE_ID = 0x49064906;

    /// @notice Increment value for NFT ID generation
    uint128 public constant NFT_ID_INCREMENT = 1;

    /// @notice Upper bound on a single report's total waste amount, in milligrams
    /// @dev Bounds the linear, uncapped reward computed by RecyReward.calculateReward so that one
    ///      report can never mint a claim large enough to drain the reward pool. Also keeps the
    ///      uint128 arithmetic in calculateReward far below its overflow bound.
    uint128 public constant MAX_WASTE_AMOUNT = 1e15;

    /// @notice Lower bound for RecyReport's unlock delay, in seconds (1 hour); enforced at
    ///         `initialize` and `setUnlockDelay`
    /// @dev The unlock delay is the protocol's only reaction window: the time EMERGENCY_ROLE has
    ///      to see a fraudulent validation and pause claiming before the payout opens. Zero or
    ///      near-zero would silently remove that control (security-audit-remediation.md 3.1 P0-c).
    uint64 public constant MIN_UNLOCK_DELAY = 1 hours;

    /// @notice Upper bound for RecyReport's unlock delay, in seconds (365 days); enforced at
    ///         `initialize` and `setUnlockDelay`
    /// @dev Also keeps `block.timestamp + unlockDelay` far below the uint64 truncation at
    ///      validation time, where a wrapping sum would store a PAST unlock date - maximum delay
    ///      silently behaving as no delay at all.
    uint64 public constant MAX_UNLOCK_DELAY = 365 days;
}
