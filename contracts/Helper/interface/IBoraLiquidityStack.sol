// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IBoraHelperStorage.sol";

interface IBoraLiquidityStack is IBoraHelperStorage {
    event StackLiquidity(uint256 stackId, Stack stack);

    event UnstackLiquidity(uint256 stackId, uint256 unstackFee, Stack stack);

    event ClaimUsdt(uint256 stackId, uint256 receiveUsdtAmount);

    event SetUnstackingFeeRate(uint256 newRate);
}
