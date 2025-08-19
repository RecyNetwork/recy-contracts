// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

library RecyErrors {
    error AddressInvalid();
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
}
