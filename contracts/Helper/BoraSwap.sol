// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BoraHelperStorage.sol";
import "./interface/IBoraSwap.sol";

abstract contract BoraSwap is IBoraSwap, BoraHelperStorage {
    /**
     * BoraSwap Related Variables & Functions
     **/

    uint16 public swapFeeRate;
    address public exBora;
    address public boraRouter;

    uint256 public swapRate;
    uint256 public swapUsdtBalance;
    uint256 public swapExBoraBalance;

    uint256[50] private __gap;

    function _swapIntialize(
        address exbora_,
        uint16 swapFeeRate_,
        uint256 swapRate_
    ) internal {
        setExBora(exbora_);
        setSwapRate(swapRate_);
        setSwapFeeRate(swapFeeRate_);
    }

    function swapExBoraToUsdt(uint256 exboraAmount) external returns (uint256) {
        address swaper = _msgSender();
        SafeERC20.safeTransferFrom(
            IERC20(exBora),
            swaper,
            vault,
            exboraAmount
        );
        swapExBoraBalance += exboraAmount;

        uint256 usdtAmount = Price.mulE4(exboraAmount, swapRate);
        uint256 swapFee = Price.mulE4(usdtAmount, swapFeeRate);
        usdtAmount -= swapFee;

        uint256 swapUsdtBalance_stack = swapUsdtBalance;
        require(
            swapUsdtBalance_stack >= usdtAmount,
            "BoraSwap: Not enough to swap"
        );
        uint256 usdtBalanceAfterSwaped = swapUsdtBalance_stack - usdtAmount;

        swapUsdtBalance = usdtBalanceAfterSwaped;

        // transfer USDT to user
        SafeERC20.safeTransfer(IERC20(usdt), swaper, usdtAmount);

        emit SwapExBoraToUsdt(
            swaper,
            exboraAmount,
            usdtAmount,
            swapFee,
            usdtBalanceAfterSwaped
        );

        return usdtAmount;
    }

    function increaseUsdtBalance(
        uint256 usdtAmount
    ) external returns (uint256) {
        bool isTransfer;
        address sender = _msgSender();
        if(sender != boraRouter){
            SafeERC20.safeTransferFrom(
                IERC20(usdt),
                sender,
                address(this),
                usdtAmount
            );
            isTransfer = true;
        }
        
        uint256 usdtBalanceAfterIncreased = swapUsdtBalance + usdtAmount;
        swapUsdtBalance = usdtBalanceAfterIncreased;

        emit IncreasedUsdtBalance(
            isTransfer,
            sender,
            usdtAmount,
            usdtBalanceAfterIncreased
        );
        return usdtBalanceAfterIncreased;
    }

   
    function setExBora(address newExbora) public onlyOwner {
        exBora = newExbora;
        emit SetExBora(newExbora);
    }

    function setBoraRouter(address newRouter) public onlyOwner {
        boraRouter = newRouter;
        emit SetBoraRouter(newRouter);
    }

    function setSwapRate(uint256 newRate) public onlyOwner {
        swapRate = newRate;
        emit SetSwapRate(newRate);
    }

    function setSwapFeeRate(uint16 newRate) public onlyOwner {
        swapFeeRate = newRate;
        emit SetSwapFeeRate(newRate);
    }

}
