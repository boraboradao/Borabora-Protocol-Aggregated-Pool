// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IBoraHelperStorage {
    /**
     * Liquidity Related Variables
     **/
    struct Stack {
        address user;
        uint64 startDate;
        bool isRemoveLiquidity;
        uint256 amount;
    }

    event SetBoraPVE(address newBoraPVE);
    
    event SetVault(address newVault);

    event SetUsdt(address newUsdt);

    event SetExecutor(address executor, bool isValid);
}
