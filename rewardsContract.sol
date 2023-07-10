// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract SigilRewardsContract {

    IERC721 nft;
    ERC20 token;
    IUniswapV2Router02 uniswapRouter;
    address WETH;
    address tokenToBuy;

    uint256 public minWaitTime = 604800; //1 week in seconds

    uint256 public minBalanceThreshold = 0.0001 ether;

    mapping(uint256 => uint256) public lastClaimed;

    
    constructor(address _uniswapRouter, address _tokenToBuy, address _nft) {
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        WETH = uniswapRouter.WETH();
        tokenToBuy = _tokenToBuy;
        nft = IERC721(_nft);
        token = ERC20(_tokenToBuy);
    }

    receive() external payable {}

    function swapTokens() public {
        require(address(this).balance >= minBalanceThreshold, "Balance below threshold for swaps");

        uint deadline = block.timestamp + 300; // 5 minutes
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenToBuy;

        uint256 balance = address(this).balance - (address(this).balance / 10);

        uniswapRouter.swapExactETHForTokens{value: balance}(0, path, address(this), deadline);
    }

    function claimTokenOffering(uint256 tokenId) public {
        require(nft.ownerOf(tokenId) == msg.sender, "You don't own that sigil!");
        require(block.timestamp - lastClaimed[tokenId] > minWaitTime, "Sigil has already claimed this week!");
        require(token.balanceOf(address(this)) > 0, "No tokens in the contract!");
        lastClaimed[tokenId] = block.timestamp;
        if(address(this).balance >= minBalanceThreshold){
            swapTokens();
        }
        token.transfer(msg.sender, (token.balanceOf(address(this)) / 400));
    }

}
