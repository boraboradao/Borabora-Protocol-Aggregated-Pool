// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../PoolStructs.sol";

interface IPoolTradingPairHandler {
    event CreateTradingPair(address oracleAddr, bytes32 tradingPairId);

    event DeleteTradingPair(bytes32 tradingPairId);

    event UpdatedTradingPair(bytes32 tradingPairId, TradingPair newTradingPair);
}
