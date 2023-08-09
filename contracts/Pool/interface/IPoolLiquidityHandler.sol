// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../PoolStructs.sol";

interface IPoolLiquidityHandler {
  event RequestLiquidityChange(
    uint256 requestId,
    LiquidityChangeRequest request
  );

  event ClaimLiquidityChange(
    uint256 requestId,
    uint256 sendAmount,
    LiquidityChangeRequest request
  );

  event TakeSnapshot(
    uint256 date,
    uint256 totalLPTokenSupply,
    uint256 poolLiquidity,
    uint256 totalAdd,
    uint256 totalRemove,
    uint256 liquidityFee
  );

  event LiquidityChange(
    uint256 poolLiquidity,
    uint256 totalLPTokenSupply,
    uint256 lpTokenPrice
  );

  function requestLiquidityChange(uint256 amount, bool isAdd) external;

  function claimLiquidityChange(uint256 requestId) external;

  function getLiquidityChangeRequest(
    uint256 requestId
  ) external returns (LiquidityChangeRequest memory);
}
