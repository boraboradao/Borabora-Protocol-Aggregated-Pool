// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

enum Direction {
    Long,
    Short
}

enum CexUsage {
    OpenPosition,
    ClosePosition
}

struct LiquidityChangeRequest {
    address user;
    uint64 dueDate;
    bool isAdd;
    uint256 amount;
}

struct DailyLiquidityRecord {
    bool isRecorded;
    uint256 accumAddAmount;
    uint256 accumRemoveAmount;
    uint256 poolLiquiditySnapshot;
    uint256 totalLPTokenSupplySnapshot;
    uint256 newLPTokenAmount;
    uint256 removePoolTokenAmount;
    uint256 removeLiquidityFee;
}

struct TradingPair {
    address oracleAddr;
    uint8 oracleDecimals;
    uint256 totalLongSize;
    uint256 totalShortSize;
}

struct Strategy {
    uint16 strategyType;
    uint240 value;
}

struct Position {
    bytes32 tradingPairId;
    uint256 openPrice;
    uint256 initMargin;
    uint256 extraMargin;
    uint256 openRebase;
    address owner;
    uint64 openBlock;
    uint16 leverage;
    uint8 direction;
}

struct PositionCloseInfo {
    uint256 positionId;
    uint256 closePrice;
    address executor;
    bool isProfit;
    uint256 closeType;
    uint256 transferOut;
    uint256 closeFee;
    uint256 serviceFee;
    uint256 fundingFee;
    uint256 executorFee;
    uint256 pnl;
}

struct LadderDeviation {
    uint16 deviationRate;
    uint240 next;
}

// Input Series
struct OpenPositionInput {
    bytes32 tradingPairId;
    uint256 margin;
    uint256 preBillPrice;
    uint256 cexPrice;
    uint256 signTimestamp;
    uint256 leverage;
    uint256 direction;
    bytes signature;
}

struct ClosePositionInput {
    uint256 positionId;
    uint256 cexPrice;
    uint256 signTimestamp;
    bytes signature;
    uint256 closeType;
}

struct ExecPreBillInput {
    uint256 positionId;
    uint256 cexPrice;
    uint256 signTimestamp;
    bytes signature;
}

struct CalRebaseDeltaInput {
    uint256 poolLongAmount;
    uint256 poolShortAmount;
    uint256 poolLiquidity;
    uint256 imbalanceThreshold;
    uint256 lastRebaseBlock;
    uint256 rebasecCoefficient;
}

struct SetPoolParamsInput {
    uint256 executorFeeRate;
    uint256 closePositionGasUsage;
    uint256 execPreBillGasUsage;
    uint256 minOpenAmount;
    address official;
    uint256 removeLiquidityFeeRate;
    bool isLiquidityProviderLimited;
    uint256 cexPriceToleranceDeviation;
    uint256 prohibitOpenDelta;
    uint256 protocolFeeRate;
    uint256 serviceFeeRate;
    uint256 closeFeeRate;
    uint256 minLeverage;
    uint256 maxLeverage;
    uint256 imbalanceThreshold;
    uint256 rebasecCoefficient;
    uint256 cexPriceLatency;
    uint256 minHoldingBlocks;
    uint256 minHoldingBlocksFeeRate;
    address vault;
}

struct SetLadderDeviationInput {
    uint256 amount;
    uint256 deviationRate;
    uint256 next;
}
