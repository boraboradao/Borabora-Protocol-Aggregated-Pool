// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISagesNFT {
    event SetValidSigner(address signer, bool isValid);

    event SetBaseUri(string baseUri);

    event SetMintPrice(uint256 mintPrice);

    event SetVault(address vault);

    event SetFeeToken(address feeToken);

    event SetSupplyLimit(uint256 supplyLimit);

    event SetIsMintLimited(bool isMintLimited);

    event Mint(
        address owner,
        uint256 tokenId,
        bytes data,
        address vault,
        address feeToken,
        uint256 feeAmount
    );

    event Withdraw(address tokenAddr, uint256 amount);

    function mint(
        uint256 timestamp,
        bytes memory data,
        bytes memory signature
    ) external payable;
}
