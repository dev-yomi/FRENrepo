// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Sigils is ERC721URIStorage, Ownable {
    using Strings for uint256;
    
    uint256 public tokenCounter;
    uint256 public price = 0.1 ether;

    ERC20 public token;
    uint256 public tokenMintReward = 17250000 ether;

    mapping(address => bool) hasMinted;

    bool public WLmintOpen;
    bool public publicMintOpen;

    string public baseURI;
    bytes32 public merkleRoot;

    constructor (string memory _baseURI, bytes32 _merkleRoot, address _token) ERC721("Sigils", "SIGIL") {
        tokenCounter = 0;
        baseURI = _baseURI;
        merkleRoot = _merkleRoot;
        WLmintOpen = false;
        publicMintOpen = false;
        token = ERC20(_token);
    }

    function mint(bytes32[] calldata _merkleProof) public payable returns (uint256) {
        require(WLmintOpen, "Mint not open yet!");
        require(!hasMinted[msg.sender], "Wallet already minted.");
        require(tokenCounter < 399, "Minted out.");

        // Verify the Merkle proof if publicMint not open
        if(!publicMintOpen){
            require(msg.value == price, "Incorrect price given.");
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "Invalid Merkle proof");
        }else{
            require(msg.value == price * 2, "Incorrect price given.");
        }
        
        uint256 newItemId = tokenCounter;
        hasMinted[msg.sender] = true;
        _safeMint(msg.sender, newItemId);
        _setTokenURI(newItemId, string(abi.encodePacked(baseURI, newItemId.toString(), ".json")));
        tokenCounter = tokenCounter + 1;
        token.transfer(msg.sender, tokenMintReward);
        return newItemId;
    }
    
    function withdrawEther() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function updateMerkleRoot(bytes32 _newRoot) external onlyOwner {
        merkleRoot = _newRoot;
    }

    function updatePrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;
    }

    function toggleWLMintOpen() external onlyOwner {
        require(token.balanceOf(address(this)) >= 6900000000 ether, "Deposit tokens for minters first!");
        WLmintOpen = !WLmintOpen;
    }

    function togglePublicMintOpen() external onlyOwner {
        require(WLmintOpen, "Open WL Mint first!");
        publicMintOpen = !publicMintOpen;
    } 
}
