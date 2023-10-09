// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./BoraHelperStorage.sol";
import "./BoraAirdrop.sol";
import "./BoraSwap.sol";
import "./BoraLiquidityStack.sol";

contract BoraHelper is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    BoraHelperStorage,
    BoraAirdrop,
    BoraSwap,
    BoraLiquidityStack
{
    receive() external payable {}

    function initialize(
        uint16 unstackingFeeRate_,
        uint16 swapFeeRate_,
        uint64 lifetime_,
        uint256 swapRate_,
        address exbora_,
        address boraPVE_,
        address usdt_,
        address vault_
    ) public initializer {
        __Ownable_init();
        _storageIntialize(boraPVE_, usdt_, vault_);
        _airdropIntialize(lifetime_);
        _liquidityStackIntialize(unstackingFeeRate_);
        _swapIntialize(exbora_, swapFeeRate_, swapRate_);
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
