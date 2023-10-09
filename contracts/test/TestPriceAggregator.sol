// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract TestPriceAggregator {
    int256 answer = 100e8;

    function latestAnswer() public view returns (int256) {
        return answer;
    }

    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        price = answer;
    }

    function decimals() public pure returns (uint8) {
        return 8;
    }

    function setAnswer(int256 newAnswer) public {
        answer = newAnswer;
    }
}
