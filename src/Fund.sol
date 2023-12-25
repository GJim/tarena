// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleSwap.sol";
import "./SimplePriceOracle.sol";

contract Fund is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public owner;
    address public trader;
    IERC20 public chipToken;
    IERC20 public targetToken;
    SimpleSwap public dex;
    SimplePriceOracle public oracle;
    uint256 public traderFeeMantissa;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public investorSharePrice;

    // Constants
    uint256 constant DECIMAL = 1e18;
    uint256 constant PLATFROM_FEE = 1e16;

    // Event declarations
    event Invested(address investor, uint256 amount, uint256 sharesMinted);
    event Divested(address investor, uint256 amount, uint256 fee, uint256 sharesBurned);
    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _trader, address _chipToken, address _targetToken, address _dex, address _oracle, uint256 _traderFeeMantissa) {
        owner = msg.sender;
        trader = _trader;
        chipToken = IERC20(_chipToken);
        targetToken = IERC20(_targetToken);
        dex = SimpleSwap(_dex);
        oracle = SimplePriceOracle(_oracle);
        traderFeeMantissa = _traderFeeMantissa;
    }

    function invest(uint256 chipAmount) external nonReentrant {
        require(chipAmount > 0, "Amount must be greater than 0");

        // Calculate previous total value
        uint256 chipPrice = oracle.getPrice(address(chipToken));
        uint256 prevChipAmount = chipToken.balanceOf(address(this));
        uint256 prevTotalValue = prevChipAmount * chipPrice;
        uint256 targetAmount = targetToken.balanceOf(address(this));
        if(targetAmount > 0) {
            uint256 targetPrice = oracle.getPrice(address(targetToken));
            prevTotalValue += targetAmount * targetPrice;
        }

        // Calculate share price
        uint256 sharePrice = prevTotalValue == 0 ? chipPrice : prevTotalValue / totalShares;
        
        // Calculate shares to mint
        uint256 sharesToMint = (chipAmount * chipPrice) / sharePrice;

        // Calculate average share price of investor
        uint256 prevSharePrice = investorSharePrice[msg.sender];
        uint256 prevShareAmount = shares[msg.sender];
        uint256 avgSharePrice = prevSharePrice == 0 ? sharePrice : (prevSharePrice * prevShareAmount + sharePrice * sharesToMint) / (prevShareAmount + sharesToMint);

        // [effect part]

        // Update user's share price at investment
        investorSharePrice[msg.sender] = avgSharePrice;

        // Mint shares to user
        shares[msg.sender] += sharesToMint;
        totalShares += sharesToMint;

        // [interactions part]

        // Transfer chips from user to contract
        chipToken.safeTransferFrom(msg.sender, address(this), chipAmount);

        emit Invested(msg.sender, chipAmount, sharesToMint);
    }

    function divest(uint256 shareAmount) external nonReentrant {
        require(shareAmount > 0, "Amount must be greater than 0");
        // sender shares must be greater than amount
        require(shareAmount <= shares[msg.sender], "Insufficient shares");
        // Calculate previous total value
        uint256 chipPrice = oracle.getPrice(address(chipToken));
        uint256 prevChipAmount = chipToken.balanceOf(address(this));
        uint256 prevTotalValue = prevChipAmount * chipPrice;
        uint256 targetAmount = targetToken.balanceOf(address(this));
        if(targetAmount > 0) {
            uint256 targetPrice = oracle.getPrice(address(targetToken));
            prevTotalValue += targetAmount * targetPrice;
        }

        // Calculate share price
        uint256 sharePrice = prevTotalValue == 0 ? DECIMAL : prevTotalValue / totalShares;

        // Calculate fee to charge
        uint256 platformFeeAmount = 0;
        uint256 traderFeeAmount = 0;
        // owner will not be charged any fee
        if(msg.sender == trader) {
            // charge platform fee to trader
            platformFeeAmount = shareAmount * PLATFROM_FEE / DECIMAL;
        } else if(msg.sender != owner) {
            // check trader fee only when fund is in profit
            uint256 investorSharePriceAtInvestment = investorSharePrice[msg.sender];
            if(sharePrice > investorSharePriceAtInvestment) {
                // calculate profit
                uint256 profit = sharePrice - investorSharePriceAtInvestment;
                // charge trader fee
                traderFeeAmount = shareAmount * profit * traderFeeMantissa / sharePrice / DECIMAL;
            }
        }
        
        // Calculate shares to burn
        uint256 totalFee = platformFeeAmount + traderFeeAmount;
        uint256 sharesToBurn = shareAmount - totalFee;
        // Calculate tokens to transfer
        uint256 chipToTransfer = prevChipAmount * sharesToBurn / totalShares;
        uint256 targetToTransfer = targetAmount * sharesToBurn / totalShares;

        // [effect part]
        shares[msg.sender] -= shareAmount;
        totalShares -= sharesToBurn;
        if(platformFeeAmount > 0) {
            shares[owner] += platformFeeAmount;
        } else if(traderFeeAmount > 0) {
            shares[trader] += traderFeeAmount;
        }

        // [interactions part]
        chipToken.transfer(msg.sender, chipToTransfer);
        targetToken.transfer(msg.sender, targetToTransfer);

        emit Divested(msg.sender, shareAmount, totalFee, sharesToBurn);
    }

    function swap(address tokenOut, uint256 ratio) external nonReentrant {
        // Check that tokenOut is either chip or target
        require(tokenOut == address(chipToken) || tokenOut == address(targetToken), "Invalid token");
        require(trader == msg.sender, "Only trader can swap");

        // Calculate amount to swap
        uint256 amountOut;
        address tokenIn;
        if(tokenOut == address(chipToken)) {
            tokenIn = address(targetToken);
            amountOut = chipToken.balanceOf(address(this)) * ratio / DECIMAL;
        } else {
            tokenIn = address(chipToken);
            amountOut = targetToken.balanceOf(address(this)) * ratio / DECIMAL;
        }
        
        IERC20(tokenOut).approve(address(dex), amountOut);
        uint256 amountIn = dex.swap(tokenOut, tokenIn, amountOut);

        emit Swapped(trader, tokenOut, amountIn, amountOut);
    }

}
