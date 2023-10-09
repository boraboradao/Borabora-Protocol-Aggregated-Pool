// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interface/IBoraNFT.sol";

contract BoraNFT is IBoraNFT, Ownable, ERC721 {
    using Strings for uint256;

    mapping(uint256 => uint256) private levelOf;
    mapping(address => bool) public isMinted;
    mapping(address => bool) private _validSigners;

    string public baseUri;
    uint256 public sinatureLifetime = 180;

    using ECDSA for bytes32;
    using Counters for Counters.Counter;
    Counters.Counter public tokenIdCounter;

    constructor(address singer_, string memory uri_) ERC721("Bora", "Bora") {
        setValidSigner(singer_, true);
        setBaseUri(uri_);
    }

    function mint() external {
        require(isMinted[msg.sender] == false, "Bora: Already minted");
        isMinted[msg.sender] = true;

        tokenIdCounter.increment();
        uint256 tokenId = tokenIdCounter.current();
        _mint(msg.sender, tokenId);
    }

    function updateLevel(
        uint256 tokenId,
        uint256 nextLevel,
        uint256 signTimestamp,
        bytes memory data,
        bytes memory sign
    ) external override {
        require(ownerOf(tokenId) == msg.sender, "Bora: Not NFT owner");
        require(levelOf[tokenId] == nextLevel - 1, " Bora: Invalid level");
        require(
            signTimestamp + sinatureLifetime > block.timestamp,
            "Bora: Signature expired"
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                "BORA_UPDATE_LEVEL",
                msg.sender,
                tokenId,
                nextLevel,
                signTimestamp,
                data
            )
        );
        address signerOfMsg = hash.toEthSignedMessageHash().recover(sign);
        require(
            _validSigners[signerOfMsg] == true,
            "Bora_updateLevel: invalid signature."
        );

        levelOf[tokenId] += 1;

        emit UpdateLevel(msg.sender, tokenId, nextLevel, data);
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        uint256 level = levelOf[tokenId];
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, level.toString()))
                : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function isValidSigner(address signer) public view returns (bool) {
        return _validSigners[signer];
    }

    function setValidSigner(address signer, bool isValid) public onlyOwner {
        require(signer != address(0), "Invalid signer address");
        _validSigners[signer] = isValid;

        emit SetValidSigner(signer, isValid);
    }

    function setBaseUri(string memory newUri) public onlyOwner {
        baseUri = newUri;

        emit SetBaseUri(newUri);
    }

    function setSignatureLifetime(uint256 newLifetime) external onlyOwner {
        sinatureLifetime = newLifetime;
    }
}
