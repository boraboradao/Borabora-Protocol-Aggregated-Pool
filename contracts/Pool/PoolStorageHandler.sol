// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "./interface/IPoolStorageHandler.sol";
import "./library/TradingHelper.sol";
import "./PoolStructs.sol";

contract PoolStorageHandler is IPoolStorageHandler, Context, Ownable {
    uint256 public poolLiquidity;
    uint256 public poolLongAmount;
    uint256 public poolShortAmount;
    uint256 public accumulatedPoolRebaseLong;
    uint256 public accumulatedPoolRebaseShort;
    uint64 public lastRebaseBlock;

    uint240 public minOpenAmount;
    uint16 public executorFeeRate;

    address public poolToken;
    uint8 public poolTokenDecimals;
    uint88 public closePositionGasUsage;

    address public official;
    bool public isLiquidityProviderLimited;
    uint88 public execPreBillGasUsage;

    uint16 public removeLiquidityFeeRate;
    uint16 public cexPriceToleranceDeviation;
    uint16 public prohibitOpenDelta;
    uint16 public protocolFeeRate;
    uint16 public serviceFeeRate;
    uint16 public closeFeeRate;
    uint8 public minLeverage;
    uint16 public maxLeverage;
    uint16 public imbalanceThreshold;
    uint32 public rebasecCoefficient;
    uint64 public cexPriceLatency;

    address public bnbUsdtPriceFeed;
    uint8 public bnbUsdtPriceFeedDecimals;
    bool public isCryptocurrencyToPoolTokenReverted;
    uint16 public minHoldingBlocks;
    uint16 public minHoldingBlocksFeeRate;

    address public vault;

    mapping(uint240 => LadderDeviation) private _ladderDeviations;
    mapping(uint240 => LadderDeviation) private _lpDiffDeviations;
    mapping(address => bool) private _validExecutors;
    mapping(address => bool) private _validLiquidityProviders;

    constructor(
        address poolToken_,
        address cryptocurrencyToPoolTokenOracle_,
        bool isCryptocurrencyToPoolTokenReverted_
    ) {
        poolToken = poolToken_;
        poolTokenDecimals = ERC20(poolToken_).decimals();

        bnbUsdtPriceFeed = cryptocurrencyToPoolTokenOracle_;
        bnbUsdtPriceFeedDecimals = AggregatorV2V3Interface(
            cryptocurrencyToPoolTokenOracle_
        ).decimals();
        isCryptocurrencyToPoolTokenReverted = isCryptocurrencyToPoolTokenReverted_;
    }

    function ladderDeviation(
        uint240 key
    ) public view returns (LadderDeviation memory) {
        return _ladderDeviations[key];
    }

    function lpDiffDeviation(
        uint240 key
    ) public view returns (LadderDeviation memory) {
        return _lpDiffDeviations[key];
    }

    function isValidExecutor(address addr) public view returns (bool) {
        return _validExecutors[addr];
    }

    function isValidLiquidityProvider(address addr) public view returns (bool) {
        return _validLiquidityProviders[addr];
    }

    function setPoolParams(
        SetPoolParamsInput calldata input
    ) external onlyOwner {
        executorFeeRate = uint16(input.executorFeeRate);
        closePositionGasUsage = uint88(input.closePositionGasUsage);
        execPreBillGasUsage = uint88(input.execPreBillGasUsage);
        minOpenAmount = uint128(input.minOpenAmount);
        official = input.official;
        vault = input.vault;
        removeLiquidityFeeRate = uint16(input.removeLiquidityFeeRate);
        isLiquidityProviderLimited = input.isLiquidityProviderLimited;
        cexPriceToleranceDeviation = uint16(input.cexPriceToleranceDeviation);
        prohibitOpenDelta = uint16(input.prohibitOpenDelta);
        protocolFeeRate = uint16(input.protocolFeeRate);
        serviceFeeRate = uint16(input.serviceFeeRate);
        closeFeeRate = uint16(input.closeFeeRate);
        minLeverage = uint8(input.minLeverage);
        maxLeverage = uint16(input.maxLeverage);
        imbalanceThreshold = uint16(input.imbalanceThreshold);
        cexPriceLatency = uint64(input.cexPriceLatency);
        rebasecCoefficient = uint32(input.rebasecCoefficient);
        minHoldingBlocks = uint16(input.minHoldingBlocks);
        minHoldingBlocksFeeRate = uint16(input.minHoldingBlocksFeeRate);

        emit SetPoolParams(input);
    }

    function _rebase() internal {
        CalRebaseDeltaInput memory calRebaseDeltaInput = CalRebaseDeltaInput({
            poolLongAmount: poolLongAmount,
            poolShortAmount: poolShortAmount,
            poolLiquidity: poolLiquidity,
            imbalanceThreshold: imbalanceThreshold,
            lastRebaseBlock: lastRebaseBlock,
            rebasecCoefficient: rebasecCoefficient
        });

        (uint256 rebaseLongDelta, uint256 rebaseShortDelta) = TradingHelper
            .calRebaseDelta(calRebaseDeltaInput);

        accumulatedPoolRebaseLong = accumulatedPoolRebaseLong + rebaseLongDelta;
        accumulatedPoolRebaseShort =
            accumulatedPoolRebaseShort +
            rebaseShortDelta;

        lastRebaseBlock = uint64(block.number);

        emit UpdatePoolRebaseLongShort(
            accumulatedPoolRebaseLong,
            accumulatedPoolRebaseShort,
            block.number
        );
    }

    function _editPoolLiquidity(
        uint256 addAmount,
        uint256 removeAmount
    ) internal {
        poolLiquidity = poolLiquidity + addAmount - removeAmount;
    }

    function _updatePoolLongAmount(
        uint256 addAmount,
        uint256 removeAmount
    ) internal {
        poolLongAmount = poolLongAmount + addAmount - removeAmount;
        emit UpdatePoolLongShortAmount(poolLongAmount, poolShortAmount);
    }

    function _updatePoolShortAmount(
        uint256 addAmount,
        uint256 removeAmount
    ) internal {
        poolShortAmount = poolShortAmount + addAmount - removeAmount;
        emit UpdatePoolLongShortAmount(poolLongAmount, poolShortAmount);
    }

    function setLadderDeviations(
        SetLadderDeviationInput[] memory inputs
    ) public onlyOwner {
        SetLadderDeviationInput memory input;

        for (uint256 i; i < inputs.length; ++i) {
            input = inputs[i];
            require(input.next > input.amount, "I-NXT"); // Invalid Next

            LadderDeviation memory deviationInfo = LadderDeviation({
                deviationRate: uint16(input.deviationRate),
                next: uint240(input.next)
            });

            _ladderDeviations[uint240(input.amount)] = deviationInfo;
        }

        emit SetLadderDeviations(inputs);
    }

    function setLpDiffDeviations(
        SetLadderDeviationInput[] memory inputs
    ) public onlyOwner {
        SetLadderDeviationInput memory input;

        for (uint256 i; i < inputs.length; ++i) {
            input = inputs[i];
            require(input.next > input.amount, "I-NXT"); // Invalid Next

            LadderDeviation memory deviationInfo = LadderDeviation({
                deviationRate: uint16(input.deviationRate),
                next: uint240(input.next)
            });
            _lpDiffDeviations[uint240(input.amount)] = deviationInfo;
        }

        emit SetLpDiffDeviations(inputs);
    }

    function setValidExecutors(
        address[] calldata addrs,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < addrs.length; ++i) {
            _validExecutors[addrs[i]] = isValid;
            emit SetIsValidExecutor(addrs[i], isValid);
        }
    }

    function setValidLiquidityProvier(
        address addr,
        bool isValid
    ) public onlyOwner {
        _validLiquidityProviders[addr] = isValid;
        emit SetisValidLiquidityProvider(addr, isValid);
    }
}
