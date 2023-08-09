// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../PoolStructs.sol";

interface IPoolStorageHandler {
  event SetPoolParams(SetPoolParamsInput params);

  event SetLadderDeviations(SetLadderDeviationInput[] deviationInfos);

  event SetLpDiffDeviations(SetLadderDeviationInput[] deviationInfos);

  event SetIsValidExecutor(address addr, bool isValid);

  event SetisValidLiquidityProvider(address addr, bool isValid);

  event UpdatePoolLongShortAmount(uint256 longAmount, uint256 shortAmount);

  event UpdatePoolRebaseLongShort(
    uint256 rebaseLong,
    uint256 rebaseShort,
    uint256 blockNumber
  );
}
