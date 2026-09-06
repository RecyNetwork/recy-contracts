// SPDX-License-Identifier: MIT

pragma solidity 0.8.36;

library RecyReward {
    uint128 private constant ONE_E18 = 10 ** 18;

    uint256 public constant FIRST_EPOCH = 2_138_428 * ONE_E18;
    uint256 public constant SECOND_EPOCH = 3_528_409 * ONE_E18;
    uint256 public constant THIRD_EPOCH = 9_882_748 * ONE_E18;
    uint256 public constant FOURTH_EPOCH = 12_775_428 * ONE_E18;
    uint256 public constant FIFTH_EPOCH = 12_775_429 * ONE_E18;
    uint256 public constant LAST_EPOCH = 15_895_115 * ONE_E18;

    uint128 public constant FIRST_EPOCH_REWARD = 1_000_000;
    uint128 public constant SECOND_EPOCH_REWARD = 2_000_000;
    uint128 public constant THIRD_EPOCH_REWARD = 10_000_000;
    uint128 public constant FOURTH_EPOCH_REWARD = 100_000_000;
    uint128 public constant FIFTH_EPOCH_REWARD = 10_000_000_000;
    uint128 public constant LAST_EPOCH_REWARD = 35_519_829_280;
    uint128 public constant FALLBACK_REWARD = 100_000_000_000;

    function calculateReward(uint128 amount, uint256 supply) public pure returns (uint128) {
        if (supply <= FIRST_EPOCH) {
            return (amount * ONE_E18) / FIRST_EPOCH_REWARD;
        } else if (supply <= SECOND_EPOCH) {
            return (amount * ONE_E18) / SECOND_EPOCH_REWARD;
        } else if (supply <= THIRD_EPOCH) {
            return (amount * ONE_E18) / THIRD_EPOCH_REWARD;
        } else if (supply <= FOURTH_EPOCH) {
            return (amount * ONE_E18) / FOURTH_EPOCH_REWARD;
        } else if (supply <= FIFTH_EPOCH) {
            return (amount * ONE_E18) / FIFTH_EPOCH_REWARD;
        } else if (supply <= LAST_EPOCH) {
            return (amount * ONE_E18) / LAST_EPOCH_REWARD;
        } else {
            return (amount * ONE_E18) / FALLBACK_REWARD;
        }
    }
}
