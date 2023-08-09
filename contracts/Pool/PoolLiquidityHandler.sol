// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../library/Price.sol";
import "./interface/IPoolLiquidityHandler.sol";
import "./PoolStorageHandler.sol";

contract PoolLiquidityHandler is
  IPoolLiquidityHandler,
  PoolStorageHandler,
  ERC20
{
  using SafeERC20 for IERC20;
  using Counters for Counters.Counter;

  Counters.Counter private _liquidityRequestCounter;

  mapping(uint256 => LiquidityChangeRequest) private _liquidityChangeRequest;
  mapping(uint256 => DailyLiquidityRecord) private _dailyLiquidityRecord;

  modifier onlyValidExecutor() {
    require(isValidExecutor(msg.sender), "O-E"); //Only Executor
    _;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    address poolToken_,
    address cryptocurrencyToPoolTokenOracle_,
    bool isCryptocurrencyToPoolTokenReverted_
  )
    ERC20(name_, symbol_)
    PoolStorageHandler(
      poolToken_,
      cryptocurrencyToPoolTokenOracle_,
      isCryptocurrencyToPoolTokenReverted_
    )
  {}

  function editLiquidityForEmergency(
    uint256 amount,
    bool isAdd
  ) external onlyOwner {
    _rebase();

    uint256 curTotalSupply = totalSupply();
    uint256 resultAmount = 0;

    if (isAdd) {
      resultAmount = Price.lpTokenByPoolToken(
        curTotalSupply,
        poolLiquidity,
        amount
      );
      _chargePoolToken(msg.sender, amount);
      _mint(msg.sender, resultAmount);

      _editPoolLiquidity(amount, 0);
    } else {
      resultAmount = (amount == curTotalSupply)
        ? poolLiquidity
        : Price.poolTokenByLPToken(curTotalSupply, poolLiquidity, amount);

      _burn(msg.sender, amount);
      _sendPoolToken(msg.sender, resultAmount);
      _editPoolLiquidity(0, resultAmount);
    }

    emit LiquidityChange(
      poolLiquidity,
      totalSupply(),
      Price.lpTokenPrice(totalSupply(), poolLiquidity)
    );
  }

  function requestLiquidityChange(uint256 amount, bool isAdd) external {
    uint64 dueDate = uint64(block.timestamp / 1 days) + 2;

    LiquidityChangeRequest memory request = LiquidityChangeRequest({
      user: msg.sender,
      dueDate: dueDate,
      isAdd: isAdd,
      amount: amount
    });

    if (isAdd) {
      if (isLiquidityProviderLimited) {
        require(isValidLiquidityProvider(msg.sender), "I-AL"); // Invalid to add liquidity
      }

      _chargePoolToken(msg.sender, amount);

      _dailyLiquidityRecord[dueDate].accumAddAmount += amount;
    } else {
      _transfer(msg.sender, address(this), amount);

      _dailyLiquidityRecord[dueDate].accumRemoveAmount += amount;
    }

    _liquidityRequestCounter.increment();
    uint256 requestId = _liquidityRequestCounter.current();
    _liquidityChangeRequest[requestId] = request;

    emit RequestLiquidityChange(requestId, request);
  }

  function claimLiquidityChange(uint256 requestId) external {
    LiquidityChangeRequest memory request = _liquidityChangeRequest[requestId];
    require(request.user != address(0), "I-ReqId"); // Invalid RequestId

    require(
      _dailyLiquidityRecord[request.dueDate].isRecorded,
      "I-SS" // No Snapshot Yet
    );

    uint256 totalLPTokenSupplySnapshot = _dailyLiquidityRecord[request.dueDate]
      .totalLPTokenSupplySnapshot;
    uint256 poolLiquiditySnapshot = _dailyLiquidityRecord[request.dueDate]
      .poolLiquiditySnapshot;

    uint256 sendAmount;
    if (request.isAdd) {
      sendAmount = Price.lpTokenByPoolToken(
        totalLPTokenSupplySnapshot,
        poolLiquiditySnapshot,
        request.amount
      );

      _transfer(address(this), request.user, sendAmount);
    } else {
      uint256 feeAmount = Price.mulE4(request.amount, removeLiquidityFeeRate);
      sendAmount = Price.poolTokenByLPToken(
        totalLPTokenSupplySnapshot,
        poolLiquiditySnapshot,
        request.amount - feeAmount
      );
      _sendPoolToken(request.user, sendAmount);
    }

    delete _liquidityChangeRequest[requestId];
    emit ClaimLiquidityChange(requestId, sendAmount, request);
  }

  function takeSnapshot(
    uint256 dueDate,
    bool isHardFix,
    uint256 hardFixTotalLPSupply,
    uint256 hardFixPoolLiquidity
  ) external onlyValidExecutor {
    _rebase();
    // Step1: Check what totalSupply and poolLiquidity is
    uint256 fixedTotalLPTokenSupply;
    uint256 fixedPoolLiquidity;
    if (isHardFix) {
      fixedTotalLPTokenSupply = hardFixTotalLPSupply;
      fixedPoolLiquidity = hardFixPoolLiquidity;
    } else {
      require(!_dailyLiquidityRecord[dueDate].isRecorded, " I-AT"); // Alreadt Taken
      fixedTotalLPTokenSupply = totalSupply();
      fixedPoolLiquidity = poolLiquidity;
    }

    // Step2: Rollback if hardFix more than once
    uint256 dueDateAddAmount = _dailyLiquidityRecord[dueDate].accumAddAmount;
    uint256 dueDateRemoveAmount = _dailyLiquidityRecord[dueDate]
      .accumRemoveAmount;

    if (isHardFix && _dailyLiquidityRecord[dueDate].isRecorded) {
      _transfer(
        official,
        address(this),
        _dailyLiquidityRecord[dueDate].removeLiquidityFee
      );

      _editPoolLiquidity(
        _dailyLiquidityRecord[dueDate].removePoolTokenAmount,
        dueDateAddAmount
      );

      uint256 lastFinalLPRemoveAmount = dueDateRemoveAmount -
        _dailyLiquidityRecord[dueDate].removeLiquidityFee;

      if (
        _dailyLiquidityRecord[dueDate].newLPTokenAmount >=
        _dailyLiquidityRecord[dueDate].removePoolTokenAmount
      ) {
        _burn(
          address(this),
          _dailyLiquidityRecord[dueDate].newLPTokenAmount -
            lastFinalLPRemoveAmount
        );
      } else {
        _mint(
          address(this),
          lastFinalLPRemoveAmount -
            _dailyLiquidityRecord[dueDate].newLPTokenAmount
        );
      }
    }

    // Step3: Calculate and change Pool state
    // Step3-1: Calculate new LP-Token amount
    uint256 newLPTokenAmount = Price.lpTokenByPoolToken(
      fixedTotalLPTokenSupply,
      fixedPoolLiquidity,
      dueDateAddAmount
    );

    // Step3-2: Calculate remove Pool Liquidity Fee
    uint256 removeLiquidityFee = Price.mulE4(
      dueDateRemoveAmount,
      removeLiquidityFeeRate
    );

    uint256 finalLPRemoveAmount = dueDateRemoveAmount - removeLiquidityFee;

    // Step3-3: Calculate actual remove Pool Liquidity
    uint256 removePoolTokenAmount = Price.poolTokenByLPToken(
      fixedTotalLPTokenSupply,
      fixedPoolLiquidity,
      finalLPRemoveAmount
    );

    // Step3-4: Change Pool state
    _editPoolLiquidity(dueDateAddAmount, removePoolTokenAmount);
    if (newLPTokenAmount >= finalLPRemoveAmount) {
      _mint(address(this), newLPTokenAmount - finalLPRemoveAmount);
    } else {
      _burn(address(this), finalLPRemoveAmount - newLPTokenAmount);
    }

    // Step4: Record latest daily liquidity record
    _dailyLiquidityRecord[dueDate].isRecorded = true;
    _dailyLiquidityRecord[dueDate]
      .totalLPTokenSupplySnapshot = fixedTotalLPTokenSupply;
    _dailyLiquidityRecord[dueDate].poolLiquiditySnapshot = fixedPoolLiquidity;
    _dailyLiquidityRecord[dueDate].newLPTokenAmount = newLPTokenAmount;
    _dailyLiquidityRecord[dueDate]
      .removePoolTokenAmount = removePoolTokenAmount;
    _dailyLiquidityRecord[dueDate].removeLiquidityFee = removeLiquidityFee;

    // Step5: Emit events
    emit TakeSnapshot(
      dueDate,
      fixedTotalLPTokenSupply,
      fixedPoolLiquidity,
      dueDateAddAmount,
      finalLPRemoveAmount,
      removeLiquidityFee
    );
    emit LiquidityChange(
      poolLiquidity,
      totalSupply(),
      Price.lpTokenPrice(totalSupply(), poolLiquidity)
    );
  }

  function getLiquidityChangeRequest(
    uint256 requestId
  ) external view returns (LiquidityChangeRequest memory) {
    return _liquidityChangeRequest[requestId];
  }

  function getDailyLiquidityRecord(
    uint256 date
  ) external view returns (DailyLiquidityRecord memory) {
    return _dailyLiquidityRecord[date];
  }

  function _sendPoolToken(address to, uint256 amount) internal {
    uint256 sendAmount = Price.convertDecimal(amount, 18, poolTokenDecimals);

    IERC20(poolToken).safeTransfer(to, sendAmount);
  }

  function _chargePoolToken(address from, uint256 amount) internal {
    address poolToken = poolToken;
    uint256 balanceBefore = IERC20(poolToken).balanceOf(address(this));

    uint256 chargeAmount = Price.convertDecimal(amount, 18, poolTokenDecimals);

    IERC20(poolToken).safeTransferFrom(from, address(this), chargeAmount);

    require(
      IERC20(poolToken).balanceOf(address(this)) >=
        (balanceBefore + chargeAmount),
      "F-CPT" // Failed to charge PoolToken
    );
  }

  function _mintLpByPoolToken(uint256 amount) internal {
    uint256 newLpTokenAmount = Price.lpTokenByPoolToken(
      totalSupply(),
      poolLiquidity,
      amount
    );

    _mint(official, newLpTokenAmount);
  }
}
