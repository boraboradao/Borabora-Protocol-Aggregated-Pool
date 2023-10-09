// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBoraNFT {
    event UpdateLevel(
        address owner,
        uint256 tokenId,
        uint256 newLevel,
        bytes data
    );

    event SetValidSigner(address signer, bool isValid);

    event SetBaseUri(string baseUri);

    function mint() external;

    function updateLevel(
        uint256 tokenId,
        uint256 nextLevel,
        uint256 signTimestamp,
        bytes memory data,
        bytes memory sign
    ) external;
}
