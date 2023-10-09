// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IAirdrop {
    event Claim(
        address indexed user,
        uint256 indexed signatureId,
        address indexed tokenAddr,
        uint256 amount
    );

    event SetValidSigner(address signer, bool isValid);
}
