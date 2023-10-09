// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../../library/BasicMaths.sol";
import "../../library/Price.sol";

import "../PoolStructs.sol";

library TradingHelper {
    using BasicMaths for uint256;
    uint256 private constant E18 = 1e18;

    function calRebaseDelta(
        CalRebaseDeltaInput memory input
    )
        internal
        view
        returns (uint256 rebaseLongDelta, uint256 rebaseShortDelta)
    {
        if (input.lastRebaseBlock >= block.number || input.poolLiquidity == 0) {
            return (rebaseLongDelta, rebaseShortDelta);
        }

        uint256 adjustPosition = Price.mulE4(
            input.poolLiquidity,
            input.imbalanceThreshold
        );

        uint256 nakedPosition = input.poolLongAmount.diff(
            input.poolShortAmount
        );

        if (nakedPosition < adjustPosition) {
            return (rebaseLongDelta, rebaseShortDelta);
        }

        uint256 rebasePosition = nakedPosition - adjustPosition;
        uint256 validBlockDiff = block.number - input.lastRebaseBlock;
        uint256 tmpRebaseDelta;

        tmpRebaseDelta =
            (rebasePosition * validBlockDiff * E18) /
            (input.rebasecCoefficient);

        if (input.poolLongAmount > input.poolShortAmount) {
            rebaseLongDelta = tmpRebaseDelta / input.poolLongAmount;
        } else {
            rebaseShortDelta = tmpRebaseDelta / input.poolShortAmount;
        }
    }
}
