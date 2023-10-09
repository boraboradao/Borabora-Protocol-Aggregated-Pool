// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interface/ISagesNFT.sol";

contract SagesNFT is ISagesNFT, Ownable, ERC721 {
    using Strings for uint256;
    using ECDSA for bytes32;
    using Counters for Counters.Counter;

    Counters.Counter public tokenIdCounter;
    string private constant MINT_SIGNATURE_PREFIX = "SAGES_NFT";
    string public baseUri;

    uint256 public mintPrice;
    uint256 public supplyLimit;
    bool public isMintLimited;

    address public vault;
    address public feeToken;
    mapping(address => bool) private _validSigners;
    mapping(bytes32 => bool) private _usedSignaturesHash;

    constructor(
        address singer_,
        address vault_,
        address feeToken_,
        string memory uri_,
        uint256 supplyLimit_
    ) ERC721("Sages NFT", "SaNFT") {
        setValidSigner(singer_, true);
        setVault(vault_);
        setBaseUri(uri_);
        setMintPrice(0);
        setFeeToken(feeToken_);
        setSupplyLimit(supplyLimit_);
        setIsMintLimited(true);
    }

    function mint(
        uint256 timestamp,
        bytes memory data,
        bytes memory signature
    ) external payable override {
        require(balanceOf(msg.sender) == 0, "SagesNFT - Already minted");
        require(
            tokenIdCounter.current() < supplyLimit,
            "SagesNFT - Supply limit reached"
        );

        if (isMintLimited) {
            require(
                timestamp + 30 seconds >= block.timestamp,
                "SagesNFT - Expired timestamp"
            );

            bytes32 msgHash = keccak256(
                abi.encodePacked(
                    MINT_SIGNATURE_PREFIX,
                    msg.sender,
                    timestamp,
                    data
                )
            );
            require(
                _usedSignaturesHash[msgHash] == false,
                "SagesNFT - Signature already used"
            );
            _usedSignaturesHash[msgHash] = true;

            address signer = msgHash.toEthSignedMessageHash().recover(
                signature
            );
            require(
                _validSigners[signer] == true,
                "SagesNFT - Invalid signer or signature"
            );
        }

        if (mintPrice > 0) {
            uint256 vaultBalanceBeforeCharging = IERC20(feeToken).balanceOf(
                vault
            );
            IERC20(feeToken).transferFrom(msg.sender, vault, mintPrice);
            require(
                IERC20(feeToken).balanceOf(vault) >=
                    vaultBalanceBeforeCharging + mintPrice,
                "SagesNFT - Does not charge enough balance"
            );
        }

        tokenIdCounter.increment();
        uint256 tokenId = tokenIdCounter.current();
        _mint(msg.sender, tokenId);

        emit Mint(msg.sender, tokenId, data, vault, feeToken, mintPrice);
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function _transfer(address, address, uint256) internal pure override {
        revert("SagesNFT: Can not be transferred");
    }

    function _approve(address, uint256) internal pure override {
        revert("SagesNFT: Can not be approved");
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

    function setMintPrice(uint256 newPrice) public onlyOwner {
        mintPrice = newPrice;
        emit SetMintPrice(newPrice);
    }

    function setVault(address newVault) public onlyOwner {
        vault = newVault;
        emit SetVault(newVault);
    }

    function setFeeToken(address newFeeToken) public onlyOwner {
        feeToken = newFeeToken;
        emit SetFeeToken(newFeeToken);
    }

    function setSupplyLimit(uint256 newSupplyLimit) public onlyOwner {
        require(
            newSupplyLimit >= tokenIdCounter.current(),
            "SagesNFT - Invalid supply limit"
        );

        supplyLimit = newSupplyLimit;
        emit SetSupplyLimit(newSupplyLimit);
    }

    function setIsMintLimited(bool isLimited) public onlyOwner {
        isMintLimited = isLimited;
        emit SetIsMintLimited(isLimited);
    }

    function isValidSigner(address signer) public view returns (bool) {
        return _validSigners[signer];
    }

    function withdraw(address tokenAddr) public onlyOwner {
        uint256 amount;
        if (tokenAddr == address(0)) {
            amount = address(this).balance;
            payable(owner()).transfer(amount);
        } else {
            amount = IERC20(tokenAddr).balanceOf(address(this));
            IERC20(tokenAddr).transfer(owner(), amount);
        }

        emit Withdraw(tokenAddr, amount);
    }
}
