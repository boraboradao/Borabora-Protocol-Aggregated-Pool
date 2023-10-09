// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../Pool/interface/IPoolPositionHandler.sol";
import "../Pool/PoolStructs.sol";
import "../Helper/interface/IBoraSwap.sol";

import "../library/Price.sol";
import "./interface/IBoraRouter.sol";

contract BoraRouter is
    IBoraRouter,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    uint8 public bnbUsdtPriceFeedDecimals;
    uint16 public feeRateForSwap;

    address public usdt;
    address public exBora;
    address public boraPVE;
    address public boraHelper;
    address public bnbUsdtPriceFeed;

    uint128 public unexcavatedBlockExBoraAmount;
    uint128 public excavatedBlockExBoraAmount;
    uint128 public blockAmountLimit;
    uint128 public latestExcavatedBlockNumber;

    uint256 public totalUnexcavatedExBora;
    uint256 public volumeLimit;

    mapping(address => bool) private _executors;

    function initialize(
        uint16 feeRateForSwap_,
        uint128 unexcavatedBlockExBoraAmount_,
        uint128 excavatedBlockExBoraAmount_,
        uint128 blockAmountLimit_,
        uint256 newVolumeLimit_,
        address usdt_,
        address exBora_,
        address priceFeed_,
        address boraPVE_,
        address boraHelper_
    ) public initializer {
        __Ownable_init();

        setUsdt(usdt_);
        setExBora(exBora_);
        setBoraPVE(boraPVE_);
        setBoraHelper(boraHelper_);
        setBnbUsdtPriceFeed(priceFeed_);
        setFeeRateForSwap(feeRateForSwap_);
        setExcavateExboraParams(
            unexcavatedBlockExBoraAmount_,
            excavatedBlockExBoraAmount_,
            blockAmountLimit_
        );
        setVolumeLimit(newVolumeLimit_);
    }

    receive() external payable {}

    function closePosition(ClosePositionInput calldata input) external {
        address operator = _msgSender();
        Position memory position = IPoolPositionHandler(boraPVE).getPosition(
            input.positionId
        );

        require(
            position.owner == operator || isExecutor(operator),
            "Router: Not position owner or executor"
        );

        // Step 1. Close position and check the BNB receive
        uint256 balanceBeforeClosed = address(this).balance;
        uint256 helperPoolTokenBalanceBeforeClosed = 
            IERC20(usdt).balanceOf(boraHelper);

        IPoolPositionHandler(boraPVE).closePosition(input);
        uint256 bnbAmountFromPool = address(this).balance -
            balanceBeforeClosed;

        // Step 2. Edit Helper's swap (injectUsdtFromFee)
        uint256 usdtAmountToSwap = Price.mulE4(
            (IERC20(usdt).balanceOf(boraHelper) - helperPoolTokenBalanceBeforeClosed),
            feeRateForSwap
        );

        IBoraSwap(boraHelper).increaseUsdtBalance(usdtAmountToSwap);

        // Step 3. excavate
        uint256 remainingExBora = totalUnexcavatedExBora;
        uint256 exBoraAmountExcavated;
        uint256 positionVolume = position.initMargin * position.leverage;
        if (positionVolume >= volumeLimit && remainingExBora > 0) {
            exBoraAmountExcavated = _excavate(
                remainingExBora,
                position.owner
            );
        }

        // Step 4. Calculate executor fee & final return amount
        uint256 poolTokenAmountToUser;
        if (bnbAmountFromPool > 0) {
            if (isExecutor(operator)) {
                payable(operator).transfer(bnbAmountFromPool);
            } else {
                (
                    /* uint80 roundID */,
                    int answer,
                    /*uint startedAt*/,
                    /*uint timeStamp*/,
                    /*uint80 answeredInRound*/
                ) =   
                    AggregatorV3Interface(bnbUsdtPriceFeed).latestRoundData();

                poolTokenAmountToUser =
                    (bnbAmountFromPool * uint(answer)) /
                    (10 ** bnbUsdtPriceFeedDecimals);

                SafeERC20.safeTransfer(
                    IERC20(usdt),
                    position.owner,
                    poolTokenAmountToUser
                );
            }
        }

        emit ClosePosition(
            operator,
            position.owner,
            input.positionId,
            bnbAmountFromPool,
            poolTokenAmountToUser,
            exBoraAmountExcavated
        );
    }

    function _excavate(
        uint256 remainingExBora,
        address owner
    ) private returns (uint256 excavatedExBoraAmount) {
        // step 1: get block number
        uint256 nowBlockNumber = block.number;
        uint256 blockNumberExcavated = latestExcavatedBlockNumber;

        // step 2: check unexcavated block amount
        if (nowBlockNumber > blockNumberExcavated) {
            excavatedExBoraAmount = excavatedBlockExBoraAmount;
            uint256 blockAmount = nowBlockNumber - blockNumberExcavated;
            uint256 blockLimit = blockAmountLimit;
            if (blockAmount > blockLimit) {
                excavatedExBoraAmount +=
                    blockLimit *
                    unexcavatedBlockExBoraAmount;
            } else if (blockAmount > 1) {
                excavatedExBoraAmount +=
                    unexcavatedBlockExBoraAmount *
                    (blockAmount - 1);
            }

            if (excavatedExBoraAmount > remainingExBora) {
                excavatedExBoraAmount = remainingExBora;
            }

            latestExcavatedBlockNumber = uint128(nowBlockNumber);
            totalUnexcavatedExBora -= excavatedExBoraAmount;

            SafeERC20.safeTransfer(
                IERC20(exBora),
                owner,
                excavatedExBoraAmount
            );

            emit Excavated(
                owner,
                blockNumberExcavated,
                nowBlockNumber,
                excavatedExBoraAmount
            );
            return excavatedExBoraAmount;
        }
    }

    function setBoraPVE(address newBoraPVE) public onlyOwner {
        boraPVE = newBoraPVE;
        emit SetBoraPVE(newBoraPVE);
    }

    function setUsdt(address newUsdt) public onlyOwner {
        usdt = newUsdt;
        emit SetUsdt(newUsdt);
    }

    function setBoraHelper(address newHelper) public onlyOwner {
        boraHelper = newHelper;
        emit SetBoraHelper(newHelper);
    }

    function setBnbUsdtPriceFeed(address newPriceFeed) public onlyOwner {
        bnbUsdtPriceFeed = newPriceFeed;
        bnbUsdtPriceFeedDecimals = AggregatorV3Interface(newPriceFeed).decimals();

        emit SetBnbUsdtPriceFeed(newPriceFeed, bnbUsdtPriceFeedDecimals);
    }

    function setFeeRateForSwap(uint16 newRate) public onlyOwner {
        require(newRate <= 10000, "ExBoraLock: feeRate error");
        feeRateForSwap = newRate;
        emit SetFeeRateForSwap(newRate);
    }

    function setExBora(address newExBora) public onlyOwner {
        exBora = newExBora;
        emit SetExBora(newExBora);
    }

    function setVolumeLimit(uint256 newVolumeLimit) public onlyOwner {
        volumeLimit = newVolumeLimit;
        emit SetVolumeLimit(newVolumeLimit);
    }
    
    function setTotalUnexcavatedExBora(
        uint256 newTotalUnexcavatedExBora
    ) public onlyOwner {
        require(
            IERC20(exBora).balanceOf(address(this)) >= newTotalUnexcavatedExBora,
            "BoraRouter: Insufficient Balance"
        );
        totalUnexcavatedExBora = newTotalUnexcavatedExBora;
        latestExcavatedBlockNumber = uint128(block.number);
        
        emit SetTotalUnexcavatedExBora(
            latestExcavatedBlockNumber,
            newTotalUnexcavatedExBora
        );
    }

    function setExecutors(
        address[] memory executors,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < executors.length; ++i) {
            _executors[executors[i]] = isValid;
            emit SetExecutor(executors[i], isValid);
        }
    }

    function setExcavateExboraParams(
        uint128 newUnexcavatedBlockExBoraAmount,
        uint128 newExcavatedBlockExBoraAmount,
        uint128 newBlockAmountLimit
    ) public onlyOwner {
        unexcavatedBlockExBoraAmount = newUnexcavatedBlockExBoraAmount;
        excavatedBlockExBoraAmount = newExcavatedBlockExBoraAmount;
        blockAmountLimit = newBlockAmountLimit;
        emit SetExcavateExboraParams(
            newUnexcavatedBlockExBoraAmount,
            newExcavatedBlockExBoraAmount,
            newBlockAmountLimit
        );
    }

    function isExecutor(address executor) public view returns (bool) {
        return _executors[executor];
    }

    function withdraw(
        address tokenAddr,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (tokenAddr == address(0)) {
            payable(to).transfer(amount);
        } else {
            SafeERC20.safeTransfer(IERC20(tokenAddr), to, amount);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
