// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../library/Price.sol";

import "./interface/IBoraHelperStorage.sol";

abstract contract BoraHelperStorage is IBoraHelperStorage, OwnableUpgradeable {
    /**
     * Shared Variables & functions
     **/
    address public boraPVE;
    address public usdt;
    
    address public vault;

    mapping(address => bool) private _executors;

    uint256[50] private __gap;

    modifier onlyExecutor() {
        require(isExecutor(msg.sender), "BoraHelper: Caller is not Executor");
        _;
    }

    function _storageIntialize(
        address boraPVE_,
        address usdt_,
        address vault_
    ) internal {
        setBoraPVE(boraPVE_);
        setUsdt(usdt_);
        setVault(vault_);
    }

    function setBoraPVE(address newBoraPVE) public onlyOwner {
        boraPVE = newBoraPVE;
        emit SetBoraPVE(newBoraPVE);
    }

    function setVault(address newVault) public onlyOwner {
        vault = newVault;
        emit SetVault(newVault);
    }

    function setUsdt(address newUsdt) public onlyOwner {
        usdt = newUsdt;
        emit SetUsdt(newUsdt);
    }

    function setExecutors(
        address[] calldata executors,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < executors.length; i++) {
            _executors[executors[i]] = isValid;

            emit SetExecutor(executors[i], isValid);
        }
    }

    function isExecutor(address executor) public view returns (bool) {
        return _executors[executor];
    }
}
