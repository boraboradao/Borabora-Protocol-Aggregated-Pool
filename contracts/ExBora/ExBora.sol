// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interface/IExBora.sol";

// This token can not transfer
contract ExBora is IExBora, Ownable, ERC20 {
    mapping(address => bool) private _managers;

    modifier onlyManager() {
        require(_managers[msg.sender], "ExBora: caller is not the manager");
        _;
    }

    constructor(uint256 amount_) ERC20("ExBora", "EXB") {
        _mint(msg.sender, amount_ * (10 ** decimals()));
    }

    function setManagers(
        address[] memory managers,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < managers.length; i++) {
            _managers[managers[i]] = isValid;
            emit SetManager(managers[i], isValid);
        }
    }

    function mint(
        address to,
        uint256 amount
    ) public onlyManager returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) public onlyManager returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function isManager(address manager) public view returns (bool) {
        return _managers[manager];
    }
}
