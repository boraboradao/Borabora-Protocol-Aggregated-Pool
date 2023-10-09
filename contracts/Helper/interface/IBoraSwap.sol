// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IBoraSwap {
    event SwapExBoraToUsdt(
        address indexed swaper,
        uint256 exBoraAmount,
        uint256 usdtAmount,
        uint256 swapFee,
        uint256 usdtBalanceAfterSwaped
    );

    event IncreasedUsdtBalance(
        bool isTransfer,
        address sender,
        uint256 usdtAmount,
        uint256 usdtBalanceAfterIncreased
    );

    event SetSwapRate(uint256 newRate);

    event SetSwapFeeRate(uint16 newRate);

    event SetExBora(address newExbora);
    
    event SetBoraRouter(address newRouter);

    event SetIncreaser(address increaser, bool isValid);

    function increaseUsdtBalance(
        uint256 usdtAmount
    ) external returns (uint256);
}
