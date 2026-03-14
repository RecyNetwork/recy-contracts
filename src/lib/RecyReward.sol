// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

library RecyReward {
    uint128 private constant ONE_E18 = 10 ** 18;

    uint256 public constant FIRST_EPOCH = 2138428 * ONE_E18;
    uint256 public constant SECOND_EPOCH = 3528409 * ONE_E18;
    uint256 public constant THIRD_EPOCH = 9882748 * ONE_E18;
    uint256 public constant FOURTH_EPOCH = 12775428 * ONE_E18;
    uint256 public constant FIFTH_EPOCH = 12775429 * ONE_E18;
    uint256 public constant LAST_EPOCH = 15895115 * ONE_E18;

    uint128 public constant FIRST_EPOCH_REWARD = 1000000;
    uint128 public constant SECOND_EPOCH_REWARD = 2000000;
    uint128 public constant THIRD_EPOCH_REWARD = 10000000;
    uint128 public constant FOURTH_EPOCH_REWARD = 100000000;
    uint128 public constant FIFTH_EPOCH_REWARD = 10000000000;
    uint128 public constant LAST_EPOCH_REWARD = 35519829280;
    uint128 public constant FALLBACK_REWARD = 100000000000;

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
