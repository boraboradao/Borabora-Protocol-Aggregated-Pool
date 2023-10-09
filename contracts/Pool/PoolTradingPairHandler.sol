// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "./interface/IPoolTradingPairHandler.sol";
import "./PoolLiquidityHandler.sol";

contract PoolTradingPairHandler is
    IPoolTradingPairHandler,
    PoolLiquidityHandler
{
    int32 private constant STANDARD_ERC20_DECIMALS = 18;

    mapping(bytes32 => TradingPair) private _tradingPairs;

    constructor(
        string memory name_,
        string memory symbol_,
        address poolToken_,
        address cryptocurrencyToPoolTokenOracle_,
        bool isCryptocurrencyToPoolTokenReverted_
    )
        PoolLiquidityHandler(
            name_,
            symbol_,
            poolToken_,
            cryptocurrencyToPoolTokenOracle_,
            isCryptocurrencyToPoolTokenReverted_
        )
    {}

    function createTradingPair(address oracleAddr) external onlyOwner {
        require(oracleAddr != address(0), "I-ORCL"); //Invalid Oracle

        bytes32 tradingPairId = getTradingPairId(oracleAddr);
        _requireTradingPairNotActive(tradingPairId);

        uint8 oracleDecimals = AggregatorV2V3Interface(oracleAddr).decimals();

        _tradingPairs[tradingPairId].oracleAddr = oracleAddr;
        _tradingPairs[tradingPairId].oracleDecimals = oracleDecimals;

        emit CreateTradingPair(oracleAddr, tradingPairId);
    }

    function _updateTradingPair(
        bytes32 tradingPairId,
        TradingPair memory tradingPair
    ) internal {
        _tradingPairs[tradingPairId].totalLongSize = tradingPair.totalLongSize;
        _tradingPairs[tradingPairId].totalShortSize = tradingPair
            .totalShortSize;

        emit UpdatedTradingPair(tradingPairId, tradingPair);
    }

    function deleteTradingPair(bytes32 tradingPairId) external onlyOwner {
        _requireTradingPairActive(tradingPairId);

        delete _tradingPairs[tradingPairId];
        emit DeleteTradingPair(tradingPairId);
    }

    function getTradingPairId(
        address oracleAddr
    ) public view returns (bytes32) {
        return keccak256(abi.encode(poolToken, oracleAddr));
    }

    function _requireTradingPairNotActive(bytes32 tradingPairId) internal view {
        require(
            _tradingPairs[tradingPairId].oracleAddr == address(0),
            "I-AP" // Already Active Pair
        );
    }

    function _requireTradingPairActive(bytes32 tradingPairId) internal view {
        require(
            _tradingPairs[tradingPairId].oracleAddr != address(0),
            "I-IAP" // Inactive Pair
        );
    }

    function _getTradingPairOracle(
        bytes32 tradingPairId
    ) internal view returns (address) {
        return _tradingPairs[tradingPairId].oracleAddr;
    }

    function _getTradingPairOracleDecimals(
        bytes32 tradingPairId
    ) internal view returns (uint8) {
        return _tradingPairs[tradingPairId].oracleDecimals;
    }

    function tradingPairOf(
        bytes32 tradingPairId
    ) public view returns (TradingPair memory) {
        return _tradingPairs[tradingPairId];
    }
}
