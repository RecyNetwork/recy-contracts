// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/lib/RecyReward.sol";

contract RecyRewardTest is Test {
    uint128 private constant ONE_E18 = 10 ** 18;

    function test_calculateRewardFirstEpoch() public pure {
        // Test supply at the beginning of first epoch
        uint256 supply = 1000 * ONE_E18;
        uint128 amount = 1000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FIRST_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFirstEpochBoundary() public pure {
        // Test supply exactly at first epoch boundary
        uint256 supply = RecyReward.FIRST_EPOCH;
        uint128 amount = 1000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FIRST_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardSecondEpoch() public pure {
        // Test supply in second epoch
        uint256 supply = RecyReward.FIRST_EPOCH + 1;
        uint128 amount = 2000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.SECOND_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardSecondEpochBoundary() public pure {
        // Test supply exactly at second epoch boundary
        uint256 supply = RecyReward.SECOND_EPOCH;
        uint128 amount = 1500;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.SECOND_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardThirdEpoch() public pure {
        // Test supply in third epoch
        uint256 supply = RecyReward.SECOND_EPOCH + 1;
        uint128 amount = 5000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.THIRD_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardThirdEpochBoundary() public pure {
        // Test supply exactly at third epoch boundary
        uint256 supply = RecyReward.THIRD_EPOCH;
        uint128 amount = 3000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.THIRD_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFourthEpoch() public pure {
        // Test supply in fourth epoch
        uint256 supply = RecyReward.THIRD_EPOCH + 1;
        uint128 amount = 10000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FOURTH_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFourthEpochBoundary() public pure {
        // Test supply exactly at fourth epoch boundary
        uint256 supply = RecyReward.FOURTH_EPOCH;
        uint128 amount = 7500;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FOURTH_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFifthEpoch() public pure {
        // Test supply in fifth epoch
        uint256 supply = RecyReward.FOURTH_EPOCH + 1;
        uint128 amount = 25000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FIFTH_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFifthEpochBoundary() public pure {
        // Test supply exactly at fifth epoch boundary
        uint256 supply = RecyReward.FIFTH_EPOCH;
        uint128 amount = 15000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FIFTH_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardLastEpoch() public pure {
        // Test supply in last epoch
        uint256 supply = RecyReward.FIFTH_EPOCH + 1;
        uint128 amount = 50000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.LAST_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardLastEpochBoundary() public pure {
        // Test supply exactly at last epoch boundary
        uint256 supply = RecyReward.LAST_EPOCH;
        uint128 amount = 30000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.LAST_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardFallback() public pure {
        // Test supply beyond last epoch (fallback case)
        uint256 supply = RecyReward.LAST_EPOCH + 1;
        uint128 amount = 100000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FALLBACK_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardWithZeroAmount() public pure {
        // Test zero amount in each epoch
        uint128 amount = 0;

        // First epoch
        uint256 supply1 = RecyReward.FIRST_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply1), 0);

        // Second epoch
        uint256 supply2 = RecyReward.SECOND_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply2), 0);

        // Third epoch
        uint256 supply3 = RecyReward.THIRD_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply3), 0);

        // Fourth epoch
        uint256 supply4 = RecyReward.FOURTH_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply4), 0);

        // Fifth epoch
        uint256 supply5 = RecyReward.FIFTH_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply5), 0);

        // Last epoch
        uint256 supply6 = RecyReward.LAST_EPOCH / 2;
        assertEq(RecyReward.calculateReward(amount, supply6), 0);

        // Fallback
        uint256 supply7 = RecyReward.LAST_EPOCH + 1000;
        assertEq(RecyReward.calculateReward(amount, supply7), 0);
    }

    function test_calculateRewardWithMaxAmount() public pure {
        // Test with large but safe amounts to avoid overflow
        uint128 largeAmount = type(uint64).max; // Use smaller amount to avoid overflow

        // First epoch - should not overflow
        uint256 supply1 = RecyReward.FIRST_EPOCH / 2;
        uint128 reward1 = RecyReward.calculateReward(largeAmount, supply1);
        assertGt(reward1, 0);

        // Fallback epoch - test with a reasonable amount
        uint256 supply7 = RecyReward.LAST_EPOCH + 1;
        uint128 reasonableAmount = 1000000; // 1M units
        uint128 reward7 = RecyReward.calculateReward(reasonableAmount, supply7);
        assertGt(reward7, 0);
    }

    function test_calculateRewardWithZeroSupply() public pure {
        // Test edge case with zero supply - should use first epoch
        uint256 supply = 0;
        uint128 amount = 1000;

        uint128 expectedReward = (amount * ONE_E18) /
            RecyReward.FIRST_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(amount, supply);

        assertEq(actualReward, expectedReward);
    }

    function test_calculateRewardConsistency() public pure {
        // Test that rewards are consistent for same inputs
        uint128 amount = 5000;
        uint256 supply = RecyReward.THIRD_EPOCH / 2;

        uint128 reward1 = RecyReward.calculateReward(amount, supply);
        uint128 reward2 = RecyReward.calculateReward(amount, supply);

        assertEq(reward1, reward2);
    }

    function test_calculateRewardDifferentEpochs() public pure {
        // Test that different epochs produce different or equal rewards based on their divisors
        uint128 amount = 10000;

        uint128 firstEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.FIRST_EPOCH / 2
        );
        uint128 secondEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.SECOND_EPOCH / 2
        );
        uint128 thirdEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.THIRD_EPOCH / 2
        );
        uint128 fourthEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.FOURTH_EPOCH / 2
        );
        uint128 fifthEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.FIFTH_EPOCH / 2
        );
        uint128 lastEpochReward = RecyReward.calculateReward(
            amount,
            RecyReward.LAST_EPOCH / 2
        );
        uint128 fallbackReward = RecyReward.calculateReward(
            amount,
            RecyReward.LAST_EPOCH + 1
        );

        // All rewards should be positive
        assertGt(firstEpochReward, 0);
        assertGt(secondEpochReward, 0);
        assertGt(thirdEpochReward, 0);
        assertGt(fourthEpochReward, 0);
        assertGt(fifthEpochReward, 0);
        assertGt(lastEpochReward, 0);
        assertGt(fallbackReward, 0);

        // Test a clear relationship: third epoch should have less reward than second
        // (10M divisor vs 2M divisor)
        assertGt(secondEpochReward, thirdEpochReward);

        // Test fallback has smallest reward (100B is largest divisor)
        assertGe(firstEpochReward, fallbackReward);
        assertGe(secondEpochReward, fallbackReward);
        assertGe(thirdEpochReward, fallbackReward);
        assertGe(fourthEpochReward, fallbackReward);
        assertGe(fifthEpochReward, fallbackReward);
        assertGe(lastEpochReward, fallbackReward);
    }

    function test_calculateRewardPrecision() public pure {
        // Test precision with small amounts
        uint128 smallAmount = 1;

        // Test in first epoch where division should give a reasonable result
        uint256 supply = 1000 * ONE_E18;
        uint128 reward = RecyReward.calculateReward(smallAmount, supply);

        // Should be: (1 * 10^18) / 1000000 = 10^12
        uint128 expectedReward = ONE_E18 / RecyReward.FIRST_EPOCH_REWARD;
        assertEq(reward, expectedReward);
    }

    function test_calculateRewardLargeNumbers() public pure {
        // Test with large but realistic numbers
        uint128 largeAmount = 1000000; // 1 million units
        uint256 largeSupply = RecyReward.THIRD_EPOCH;

        uint128 expectedReward = (largeAmount * ONE_E18) /
            RecyReward.THIRD_EPOCH_REWARD;
        uint128 actualReward = RecyReward.calculateReward(
            largeAmount,
            largeSupply
        );

        assertEq(actualReward, expectedReward);
    }

    function test_epochConstants() public pure {
        // Test that epoch constants are properly defined and ordered
        assertLt(RecyReward.FIRST_EPOCH, RecyReward.SECOND_EPOCH);
        assertLt(RecyReward.SECOND_EPOCH, RecyReward.THIRD_EPOCH);
        assertLt(RecyReward.THIRD_EPOCH, RecyReward.FOURTH_EPOCH);
        assertLt(RecyReward.FOURTH_EPOCH, RecyReward.FIFTH_EPOCH);
        assertLt(RecyReward.FIFTH_EPOCH, RecyReward.LAST_EPOCH);

        // Test reward constants are defined
        assertGt(RecyReward.FIRST_EPOCH_REWARD, 0);
        assertGt(RecyReward.SECOND_EPOCH_REWARD, 0);
        assertGt(RecyReward.THIRD_EPOCH_REWARD, 0);
        assertGt(RecyReward.FOURTH_EPOCH_REWARD, 0);
        assertGt(RecyReward.FIFTH_EPOCH_REWARD, 0);
        assertGt(RecyReward.LAST_EPOCH_REWARD, 0);
        assertGt(RecyReward.FALLBACK_REWARD, 0);
    }

    function test_rewardConstantsIncrease() public pure {
        // Test that reward divisors generally increase (meaning rewards decrease)
        // Note: The actual constants don't strictly increase due to tokenomics design
        assertLt(RecyReward.FIRST_EPOCH_REWARD, RecyReward.SECOND_EPOCH_REWARD);
        assertLt(RecyReward.SECOND_EPOCH_REWARD, RecyReward.THIRD_EPOCH_REWARD);
        assertLt(RecyReward.THIRD_EPOCH_REWARD, RecyReward.FOURTH_EPOCH_REWARD);
        assertLt(RecyReward.FOURTH_EPOCH_REWARD, RecyReward.FIFTH_EPOCH_REWARD);
        // Note: FIFTH_EPOCH_REWARD (10B) < LAST_EPOCH_REWARD (35.5B)
        assertLt(RecyReward.FIFTH_EPOCH_REWARD, RecyReward.LAST_EPOCH_REWARD);
        assertLt(RecyReward.LAST_EPOCH_REWARD, RecyReward.FALLBACK_REWARD);
    }

    function test_calculateRewardFuzz(
        uint128 amount,
        uint256 supply
    ) public pure {
        // Fuzz test to ensure no reverts with random inputs
        vm.assume(amount > 0);
        vm.assume(supply > 0);
        // Limit amount to avoid overflow in multiplication with ONE_E18
        vm.assume(amount <= type(uint128).max / ONE_E18);

        // This should not revert for any valid inputs
        uint128 reward = RecyReward.calculateReward(amount, supply);

        // Reward should be proportional to amount (larger amount = larger reward, assuming same supply)
        if (amount > 1) {
            uint128 smallerReward = RecyReward.calculateReward(
                amount - 1,
                supply
            );
            assertGe(reward, smallerReward);
        }
    }

    function test_calculateRewardEdgeCaseSupplyValues() public pure {
        uint128 amount = 1000;

        // Test supply values right around epoch boundaries
        uint256[] memory testSupplies = new uint256[](14);
        testSupplies[0] = RecyReward.FIRST_EPOCH - 1;
        testSupplies[1] = RecyReward.FIRST_EPOCH;
        testSupplies[2] = RecyReward.FIRST_EPOCH + 1;
        testSupplies[3] = RecyReward.SECOND_EPOCH - 1;
        testSupplies[4] = RecyReward.SECOND_EPOCH;
        testSupplies[5] = RecyReward.SECOND_EPOCH + 1;
        testSupplies[6] = RecyReward.THIRD_EPOCH - 1;
        testSupplies[7] = RecyReward.THIRD_EPOCH;
        testSupplies[8] = RecyReward.THIRD_EPOCH + 1;
        testSupplies[9] = RecyReward.FOURTH_EPOCH - 1;
        testSupplies[10] = RecyReward.FOURTH_EPOCH;
        testSupplies[11] = RecyReward.FOURTH_EPOCH + 1;
        testSupplies[12] = RecyReward.FIFTH_EPOCH - 1;
        testSupplies[13] = RecyReward.FIFTH_EPOCH;

        // All of these should execute without reverting
        for (uint256 i = 0; i < testSupplies.length; i++) {
            uint128 reward = RecyReward.calculateReward(
                amount,
                testSupplies[i]
            );
            assertGt(reward, 0); // Should always return a positive reward for positive amount
        }
    }
}
