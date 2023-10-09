// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IBoraAirdrop {
    event ClaimAirdrop(
        address indexed user,
        uint256 indexed signatureId,
        address indexed tokenAddr,
        uint256 amount
    );

    event SetAirdropSignatureLifetime(uint64 lifetime);
}
