// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library RecyTypes {
    struct RecyInfo {
        address validator;
        address recycler;
        uint64 recycleDate;
        uint64 auditDate;
        uint128 wasteAmount; // in miligrams
    }

    struct RecyReward {
        uint128 rewardAmount;
        uint64 rewardUnlockDate;
    }

    struct RecyMaterials {
        uint32 material;
        uint32 recycleType;
        uint32 recycleShape;
        uint32 disposalMethod;
        uint128 amountRecycled; // in miligrams
    }
}
