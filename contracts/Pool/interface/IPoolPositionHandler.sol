// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../PoolStructs.sol";

interface IPoolPositionHandler {
  event OpenPosition(
    uint256 positionId,
    Position position,
    uint256 positionSize
  );

  event AddMargin(uint256 positionId, uint256 addMargin, uint256 totalMargin);

  event ClosePosition(PositionCloseInfo closeInfo);

  event Exit(uint256 positionId, address executor);

  event ExecPreBill(
    uint256 positionId,
    Position position,
    address executor,
    uint256 executorFee,
    uint256 positionSize
  );

  event CancelPrebill(uint256 positionId);

  function getPosition(uint256 positionId) external returns (Position memory);

  function closePosition(ClosePositionInput memory input) external;
}
