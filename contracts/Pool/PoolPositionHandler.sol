// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "../library/BasicMaths.sol";
import "./interface/IPoolPositionHandler.sol";
import "./PoolTradingPairHandler.sol";

contract PoolPositionHandler is IPoolPositionHandler, PoolTradingPairHandler {
    using BasicMaths for uint256;
    using BasicMaths for bool;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    Counters.Counter private _positionIdCounter;

    mapping(uint256 => bool) private _signatures;
    mapping(uint256 => Position) private _positions;

    constructor(
        string memory name_,
        string memory symbol_,
        address poolToken_,
        address cryptocurrencyToPoolTokenOracle_,
        bool isCryptocurrencyToPoolTokenReverted_
    )
        PoolTradingPairHandler(
            name_,
            symbol_,
            poolToken_,
            cryptocurrencyToPoolTokenOracle_,
            isCryptocurrencyToPoolTokenReverted_
        )
    {}

    function openPosition(OpenPositionInput memory input) public {
        require(
            input.leverage >= minLeverage && input.leverage <= maxLeverage,
            "I-LVR" // Invalid leverage
        );
        require(input.margin >= minOpenAmount, "I-MGN"); // Invalid margin
        require(
            input.direction == uint8(Direction.Long) ||
                input.direction == uint8(Direction.Short),
            "I-DIR" // Invalid direction
        );

        _requireTradingPairActive(input.tradingPairId);

        _chargePoolToken(msg.sender, input.margin);

        Position memory newPosition = Position({
            tradingPairId: input.tradingPairId,
            openPrice: input.preBillPrice,
            initMargin: input.margin,
            extraMargin: 0,
            openRebase: 0,
            owner: msg.sender,
            openBlock: 0,
            leverage: uint16(input.leverage),
            direction: uint8(input.direction)
        });

        uint256 positionSize = 0;

        // if not PreBill
        if (input.signature.length != 0) {
            require(poolLiquidity > 0, "I-LQD"); // No Liquidity

            _requireValidCexPriceAndValidSignature(
                uint256(CexUsage.OpenPosition),
                input.tradingPairId,
                input.cexPrice,
                input.signTimestamp,
                input.signature
            );

            (uint256 openPrice, uint256 openRebase) = _openPosition(
                input.tradingPairId,
                input.margin,
                input.cexPrice,
                input.leverage,
                input.direction
            );

            newPosition.openPrice = openPrice;
            newPosition.openRebase = openRebase;
            newPosition.openBlock = uint64(block.number);

            positionSize = getPositionSize(
                input.margin * input.leverage,
                openPrice
            );
        }

        _positionIdCounter.increment();
        uint256 positionId = _positionIdCounter.current();
        _positions[positionId] = newPosition;

        emit OpenPosition(positionId, newPosition, positionSize);
    }

    function _openPosition(
        bytes32 tradingPairId,
        uint256 margin,
        uint256 cexPrice,
        uint256 leverage,
        uint256 direction
    ) internal returns (uint256 openPrice, uint256 openRebase) {
        _rebase();

        uint256 positionAmount = margin * leverage;
        bool isLong = isDirectionLong(direction);
        {
            uint256 poolLongAmount = poolLongAmount;
            uint256 poolShortAmount = poolShortAmount;

            if (isLong) {
                poolLongAmount += positionAmount;
            } else {
                poolShortAmount += positionAmount;
            }

            require(
                poolLongAmount.diff(poolShortAmount) <=
                    Price.mulE4(poolLiquidity, prohibitOpenDelta),
                "I-NPOS" // Invalid Nacked position
            );

            uint16 lpDiffDeviation = getLpDiffDivation(
                isLong,
                poolLongAmount,
                poolShortAmount
            );

            uint16 ladderDevition = getLadderDivation(positionAmount);

            uint256 finalDevition = ladderDevition > lpDiffDeviation
                ? ladderDevition
                : lpDiffDeviation;

            openPrice = isLong
                ? cexPrice + Price.mulE4(cexPrice, finalDevition)
                : cexPrice - Price.mulE4(cexPrice, finalDevition);
        }

        uint256 positionSize = Price.divE18(positionAmount, openPrice);

        TradingPair memory tradingPair = tradingPairOf(tradingPairId); // Need to be optimized

        if (isLong) {
            tradingPair.totalLongSize += positionSize;
            _updatePoolLongAmount(positionAmount, 0);
            openRebase = accumulatedPoolRebaseLong;
        } else {
            tradingPair.totalShortSize += positionSize;
            _updatePoolShortAmount(positionAmount, 0);
            openRebase = accumulatedPoolRebaseShort;
        }

        _updateTradingPair(tradingPairId, tradingPair);
    }

    function addMargin(uint256 positionId, uint256 margin) external {
        Position memory position = _positions[positionId];
        _requirePositionOpened(position.openBlock);

        require(msg.sender == position.owner, "O-O"); // Only Owner
        _requireTradingPairActive(position.tradingPairId);
        _chargePoolToken(msg.sender, margin);

        _positions[positionId].extraMargin += margin;

        uint256 totalMargin = position.initMargin +
            _positions[positionId].extraMargin;
        emit AddMargin(positionId, margin, totalMargin);
    }

    function closePosition(ClosePositionInput memory input) external {
        Position memory position = _positions[input.positionId];
        _requirePositionOpened(position.openBlock);

        _requireCallerIsOwnerOrValidExecutor(position.owner);

        _requireTradingPairActive(position.tradingPairId);

        _requireValidCexPriceAndValidSignature(
            uint256(CexUsage.ClosePosition),
            position.tradingPairId,
            input.cexPrice,
            input.signTimestamp,
            input.signature
        );

        _rebase();

        TradingPair memory tradingPair = tradingPairOf(position.tradingPairId);

        bool isClosedByExecutor = msg.sender != position.owner;
        PositionCloseInfo memory positionCloseInfo = getPositionValue(
            isClosedByExecutor,
            input.cexPrice,
            position,
            tradingPair
        );

        _updateTradingPair(position.tradingPairId, tradingPair);

        delete _positions[input.positionId];

        uint256 totalMargin = position.initMargin + position.extraMargin;
        if (positionCloseInfo.transferOut > (poolLiquidity + totalMargin)) {
            positionCloseInfo.transferOut = poolLiquidity + totalMargin;
        }

        if (positionCloseInfo.transferOut > 0 && input.closeType != 3) {
            _sendPoolToken(position.owner, positionCloseInfo.transferOut);
        }

        _sendPoolToken(vault, positionCloseInfo.serviceFee);

        uint256 protocolFee = Price.mulE4(
            (positionCloseInfo.closeFee + positionCloseInfo.fundingFee),
            protocolFeeRate
        );
        _mintLpByPoolToken(protocolFee);

        uint256 serviceAndExecutorFee = positionCloseInfo.serviceFee +
            positionCloseInfo.executorFee;

        if (input.closeType == 3) {
            _editPoolLiquidity(
                totalMargin + positionCloseInfo.transferOut,
                serviceAndExecutorFee
            );
        } else {
            _editPoolLiquidity(
                totalMargin,
                positionCloseInfo.transferOut + serviceAndExecutorFee
            );
        }

        positionCloseInfo.closeType = input.closeType;
        positionCloseInfo.positionId = input.positionId;
        positionCloseInfo.closePrice = input.cexPrice;
        positionCloseInfo.executor = isClosedByExecutor
            ? msg.sender
            : address(0);

        emit ClosePosition(positionCloseInfo);
        emit LiquidityChange(
            poolLiquidity,
            totalSupply(),
            Price.lpTokenPrice(totalSupply(), poolLiquidity)
        );
    }

    function exit(uint256 positionId) external {
        _rebase();
        Position memory position = _positions[positionId];
        _requirePositionOpened(position.openBlock);

        _requireCallerIsOwnerOrValidExecutor(position.owner);
        _requireTradingPairNotActive(position.tradingPairId);

        bool isClosedByExecutor = msg.sender != position.owner;
        uint256 executorFee;
        if (isClosedByExecutor) {
            executorFee = _chargeExecutorFee(closePositionGasUsage);
        }

        uint256 positionAmount = position.initMargin * position.leverage;
        if (isDirectionLong(position.direction)) {
            _updatePoolLongAmount(0, positionAmount);
        } else {
            _updatePoolShortAmount(0, positionAmount);
        }

        _sendPoolToken(
            position.owner,
            position.initMargin + position.extraMargin - executorFee
        );

        delete _positions[positionId];
        emit Exit(positionId, msg.sender);
    }

    function execPreBill(ExecPreBillInput memory input) external {
        Position memory position = _positions[input.positionId];
        _requirePositionNotOpened(position.openBlock);

        _requireTradingPairActive(position.tradingPairId);
        _requireCallerIsOwnerOrValidExecutor(position.owner);

        _requireValidCexPriceAndValidSignature(
            uint256(CexUsage.OpenPosition),
            position.tradingPairId,
            input.cexPrice,
            input.signTimestamp,
            input.signature
        );

        uint256 executorFee;
        bool isClosedByExecutor = msg.sender != position.owner;

        if (isClosedByExecutor) {
            executorFee = _chargeExecutorFee(execPreBillGasUsage);
        }

        uint256 initMarginWithoutExecutorFee = position.initMargin -
            executorFee;
        (uint256 openPrice, uint256 openRebase) = _openPosition(
            position.tradingPairId,
            initMarginWithoutExecutorFee,
            input.cexPrice,
            position.leverage,
            position.direction
        );

        position.openPrice = openPrice;
        position.openRebase = openRebase;
        position.openBlock = uint64(block.number);
        position.initMargin = initMarginWithoutExecutorFee;

        _positions[input.positionId].openPrice = openPrice;
        _positions[input.positionId].openRebase = openRebase;
        _positions[input.positionId].openBlock = uint64(block.number);
        _positions[input.positionId].initMargin = initMarginWithoutExecutorFee;

        address executor = isClosedByExecutor ? msg.sender : address(0);

        uint256 positionSize = getPositionSize(
            initMarginWithoutExecutorFee * position.leverage,
            openPrice
        );
        emit ExecPreBill(
            input.positionId,
            position,
            executor,
            executorFee,
            positionSize
        );
    }

    function cancelPreBill(uint256 positionId) public {
        Position memory position = _positions[positionId];

        _requirePositionNotOpened(position.openBlock);
        _requireCallerIsOwnerOrValidExecutor(position.owner);
        _sendPoolToken(position.owner, position.initMargin);

        delete _positions[positionId];
        emit CancelPrebill(positionId);
    }

    function _chargeExecutorFee(
        uint256 baseGasUsage
    ) internal returns (uint256) {
        // Step 1: Get charged gas
        uint256 usedGasAmount = baseGasUsage +
            Price.mulE4(baseGasUsage, executorFeeRate);

        // Step 2: Gas mainCrypto/poolToken price
        uint256 mainCryptoPriceToPoolToken = uint256(
            AggregatorV2V3Interface(bnbUsdtPriceFeed).latestAnswer()
        );

        // Step 3: Calculate executor fee in gas amount and pool token
        uint256 finalExecutorFeeInGasAmount = usedGasAmount * tx.gasprice;
        uint256 finalExecutorFeeInPoolToken;
        if (18 >= poolTokenDecimals) {
            finalExecutorFeeInPoolToken = isCryptocurrencyToPoolTokenReverted
                ? (finalExecutorFeeInGasAmount *
                    (10 ** bnbUsdtPriceFeedDecimals)) /
                    mainCryptoPriceToPoolToken
                : (finalExecutorFeeInGasAmount * mainCryptoPriceToPoolToken) /
                    (10 ** bnbUsdtPriceFeedDecimals);
        }

        // Step 4: Send BNB to executor
        payable(msg.sender).transfer(finalExecutorFeeInGasAmount);

        return finalExecutorFeeInPoolToken;
    }

    function _requireValidCexPriceAndValidSignature(
        uint256 cexUsage,
        bytes32 tradingPairId,
        uint256 cexPrice,
        uint256 signTimestamp,
        bytes memory signature
    ) internal {
        require(!_signatures[signTimestamp], "Used SIG"); // Used SIG
        _signatures[signTimestamp] = true;

        // Verify CexPrice
        uint256 dexPrice = uint256(
            AggregatorV2V3Interface(_getTradingPairOracle(tradingPairId))
                .latestAnswer()
        );

        dexPrice = Price.convertDecimal(
            dexPrice,
            _getTradingPairOracleDecimals(tradingPairId),
            18
        );

        uint256 priceDelta = dexPrice.diff(cexPrice);

        require(
            ((priceDelta * 100) / dexPrice) < cexPriceToleranceDeviation,
            "I-CP" //Invalid CexPrice
        );

        // Verify SIG
        uint256 blockTimestamp = block.timestamp * 1000;
        require(
            signTimestamp <= blockTimestamp &&
                blockTimestamp - signTimestamp <= cexPriceLatency * 1000,
            "I-SIGTS" //Invalid SIG Timestamp
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                "CexPrice",
                msg.sender,
                cexUsage,
                tradingPairId,
                cexPrice,
                uint64(signTimestamp)
            )
        );

        address signer = hash.toEthSignedMessageHash().recover(signature);
        require(isValidExecutor(signer), "I-SIG"); //Invalid SIG
    }

    function _requireCallerIsOwnerOrValidExecutor(address owner) internal view {
        require(
            msg.sender == owner || isValidExecutor(msg.sender),
            "O-O/E" // Only Oner or Executor
        );
    }

    function _requirePositionOpened(uint256 openBlock) internal pure {
        require(openBlock > 0, "I-NOP"); // Not Opened
    }

    function _requirePositionNotOpened(uint256 openBlock) internal pure {
        require(openBlock == 0, "I-OP"); // Opened
    }

    function isDirectionLong(uint256 direction) public pure returns (bool) {
        return direction == uint256(Direction.Long);
    }

    function getPositionSize(
        uint256 positionAmount,
        uint256 openPrice
    ) public pure returns (uint256) {
        return Price.divE18(positionAmount, openPrice);
    }

    function getPositionValue(
        bool isClosedByExecutor,
        uint256 cexPrice,
        Position memory position,
        TradingPair memory tradingPair
    ) public returns (PositionCloseInfo memory positionCloseInfo) {
        uint256 positionAmount = position.initMargin * position.leverage;
        uint256 positionSize = getPositionSize(
            positionAmount,
            position.openPrice
        );

        positionCloseInfo.pnl = Price.mulE18(
            positionSize,
            cexPrice.diff(position.openPrice)
        );

        {
            uint256 serviceFeeRate = ((block.number - position.openBlock) <=
                minHoldingBlocks)
                ? minHoldingBlocksFeeRate
                : serviceFeeRate;

            positionCloseInfo.serviceFee = Price.mulE4(
                positionAmount,
                serviceFeeRate
            );

            positionCloseInfo.closeFee = Price.mulE4(
                positionAmount,
                closeFeeRate
            );
        }

        if (isClosedByExecutor) {
            positionCloseInfo.executorFee = _chargeExecutorFee(
                closePositionGasUsage
            );
        }

        bool isLong = isDirectionLong(position.direction);

        if (isLong) {
            positionCloseInfo.fundingFee = Price.calFundingFee(
                positionAmount,
                (accumulatedPoolRebaseLong - position.openRebase)
            );

            tradingPair.totalLongSize -= positionSize;
            _updatePoolLongAmount(0, positionAmount);
        } else {
            positionCloseInfo.fundingFee = Price.calFundingFee(
                positionAmount,
                (accumulatedPoolRebaseShort - position.openRebase)
            );

            tradingPair.totalShortSize -= positionSize;
            _updatePoolShortAmount(0, positionAmount);
        }

        positionCloseInfo.isProfit = (cexPrice >= position.openPrice) == isLong;

        positionCloseInfo.transferOut = positionCloseInfo
            .isProfit
            .addOrSub2Zero(
                position.initMargin + position.extraMargin,
                positionCloseInfo.pnl
            )
            .sub2Zero(positionCloseInfo.closeFee)
            .sub2Zero(positionCloseInfo.fundingFee)
            .sub2Zero(positionCloseInfo.serviceFee)
            .sub2Zero(positionCloseInfo.executorFee);
    }

    function getLpDiffDivation(
        bool isLong,
        uint256 poolLongAmount,
        uint256 poolShortAmount
    ) public view returns (uint16 devitaion) {
        if (
            (poolLongAmount > poolShortAmount) == (isLong) ||
            (poolLongAmount < poolShortAmount) == (!isLong)
        ) {
            uint256 lpDiffRatio = Price.divE18(
                poolLongAmount.diff(poolShortAmount),
                poolLiquidity
            );

            LadderDeviation memory deviationInfo = lpDiffDeviation(0);
            while (deviationInfo.next < lpDiffRatio) {
                deviationInfo = lpDiffDeviation(deviationInfo.next);
            }
            devitaion = deviationInfo.deviationRate;
        }
    }

    function getLadderDivation(
        uint256 positionAmount
    ) public view returns (uint16) {
        LadderDeviation memory deviationInfo = ladderDeviation(0);

        while (deviationInfo.next < positionAmount) {
            deviationInfo = ladderDeviation(deviationInfo.next);
        }

        return deviationInfo.deviationRate;
    }

    function getPosition(
        uint256 positionId
    ) external view returns (Position memory) {
        return _positions[positionId];
    }
}
