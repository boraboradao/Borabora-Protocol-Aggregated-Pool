// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PoolPositionHandler.sol";

contract Pool is PoolPositionHandler {
    using SafeERC20 for IERC20;

    receive() external payable {}

    constructor(
        string memory name_,
        string memory symbol_,
        address poolToken_,
        address cryptocurrencyToPoolTokenOracle_,
        bool isCryptocurrencyToPoolTokenReverted_
    )
        PoolPositionHandler(
            name_,
            symbol_,
            poolToken_,
            cryptocurrencyToPoolTokenOracle_,
            isCryptocurrencyToPoolTokenReverted_
        )
    {}

    function withdraw(
        address tokenAddr,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (tokenAddr == address(0)) {
            payable(to).transfer(amount);
        } else {
            if (tokenAddr == poolToken) {
                require(
                    poolLiquidity <=
                        ERC20(poolToken).balanceOf(address(this)) - amount,
                    "I-Amt"
                );
            }
            IERC20(tokenAddr).safeTransfer(to, amount);
        }
    }
}
