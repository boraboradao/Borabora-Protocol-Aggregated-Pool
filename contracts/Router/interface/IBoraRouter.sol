// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBoraRouter {
    event ClosePosition(
        address operator,
        address positionOwner,
        uint256 positionId,
        uint256 bnbAmountFromPool,
        uint256 poolTokenAmountToUser,
        uint256 exBoraAmountExcavated
    );

    event SetBoraPVE(address newBoraPVE);

    event SetUsdt(address newUsdt);

    event SetExBora(address newExBora);

    event SetBoraHelper(address newBoraHelper);

    event SetBnbUsdtPriceFeed(address newPriceFeed, uint8 decimals);

    event SetVolumeLimit(uint256 newVolumeLimit);

    event SetExecutor(address executor, bool isExecutor);

    event SetFeeRateForSwap(uint16 newRate);

    event Excavated(
        address owner,
        uint256 blockNumberExcavated,
        uint256 nowBlockNumber,
        uint256 excavatedExBoraAmount
    );

    event SetTotalUnexcavatedExBora(
        uint128 startBlockNumber,
        uint256 newTotalUnexcavatedExBora
    );

    event SetExcavateExboraParams(
        uint128 newUnexcavatedBlockExBoraAmount,
        uint128 newExcavatedBlockExBoraAmount,
        uint128 newBlockAmountLimit
    );
}
