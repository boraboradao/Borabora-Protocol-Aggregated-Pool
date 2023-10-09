// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interface/IAirdrop.sol";

contract Airdrop is Ownable, IAirdrop {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    uint256 public sinatureLifetime; // 60 seconds = 1 minutes

    mapping(uint256 => bool) private _usedSignatures;
    mapping(address => bool) private _validSigners;

    receive() external payable {}

    function claim(
        uint256 signatureId,
        address tokenAddr,
        uint256 amount,
        uint256 timestamp,
        bytes memory signature
    ) external {
        require(!_usedSignatures[signatureId], "Signature Used");
        _usedSignatures[signatureId] = true;

        require(
            timestamp + sinatureLifetime > block.timestamp,
            "Signature Expired"
        );
        require(
            _validSignature(
                signatureId,
                tokenAddr,
                amount,
                timestamp,
                signature
            ),
            "Invalid Signature"
        );

        if (tokenAddr == address(0)) {
            bool isSuccess = payable(msg.sender).send(amount);
            require(isSuccess, "Failed to send Platform Token");
        } else {
            uint8 tokenDecimals = ERC20(tokenAddr).decimals();
            amount = _convertDecimals(amount, 18, tokenDecimals);
            SafeERC20.safeTransfer(IERC20(tokenAddr), msg.sender, amount);
        }

        emit Claim(msg.sender, signatureId, tokenAddr, amount);
    }

    function withdraw(
        address tokenAddr,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (tokenAddr == address(0)) {
            bool isSuccess = payable(to).send(amount);
            require(isSuccess, "Failed to send Platform Token");
        } else {
            SafeERC20.safeTransfer(IERC20(tokenAddr), to, amount);
        }
    }

    function _convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }

    function _validSignature(
        uint256 signatureId,
        address tokenAddr,
        uint256 amount,
        uint256 timestamp,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                "BORA_AIRDROP",
                msg.sender,
                signatureId,
                tokenAddr,
                amount,
                timestamp
            )
        );
        address signer = hash.toEthSignedMessageHash().recover(signature);

        return _validSigners[signer];
    }

    function setValidSigner(address signer, bool isValid) external onlyOwner {
        require(signer != address(0), "Invalid signer address");
        _validSigners[signer] = isValid;

        emit SetValidSigner(signer, isValid);
    }

    function setSignatureLifetime(uint256 lifetime) external onlyOwner {
        sinatureLifetime = lifetime;
    }

    function isSignatureBeenUsed(
        uint256 sinatureId
    ) public view returns (bool) {
        return _usedSignatures[sinatureId];
    }

    function isValidSigner(address signer) public view returns (bool) {
        return _validSigners[signer];
    }
}
