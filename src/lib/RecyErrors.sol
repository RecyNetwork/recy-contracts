// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

library RecyErrors {
    error AddressInvalid();
    error RewardsUnavailableOnThisChain();
    error ArrayLengthMismatch();
    error NotReportOwner();
    error RewardAlreadyClaimed();
    error RecyReportNotValidated();
    error RecyReportNotCompleted();
    error NftNotExists();

    error RecyReportNotInitialized();
    error RecyReportAlreadyInitialized();
    error RecyReportNotAuditor();
    error RecyReportNotRecycler();
    error RecyReportNotRewarder();
    error RewardNotUnlocked();
    error InsufficientRewardBalance();

    error RecyReportInvalidStatus();
    error RecyReportInvalidShareDistribution();

    /// @notice Thrown when a report's total waste amount exceeds RecyConstants.MAX_WASTE_AMOUNT
    error WasteAmountExceedsCap();

    /// @notice Thrown when the account validating a report is the same account that recorded it
    error ValidatorCannotBeRecycler();

    /// @notice Thrown when a material id is outside the catalogue exposed by the data contract
    error MaterialIdOutOfRange();

    /// @notice Thrown when a report is written with no materials at all
    error EmptyMaterialsArray();

    /// @notice Thrown when a new unlock delay is outside [MIN_UNLOCK_DELAY, MAX_UNLOCK_DELAY]
    error UnlockDelayOutOfBounds();
}
