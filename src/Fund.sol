// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHost} from "./IHost.sol";
import {IFund} from "./IFund.sol";
import {IArena} from "./IArena.sol";
import {SimpleSwap} from "./SimpleSwap.sol";
import {SimplePriceOracle} from "./SimplePriceOracle.sol";

contract Fund is IFund, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant name = 'Trader Arena';
    string public constant symbol = 'TA';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    IHost public host;
    address public trader;
    IERC20 public chipToken;
    IERC20 public targetToken;
    // recording the balance of tokens avoid flashload attack
    uint256 public chipBalance;
    uint256 public targetBalance;
    SimpleSwap public dex;
    SimplePriceOracle public oracle;
    uint256 public traderFeeMantissa;
    uint256 public totalInvest;
    uint256 public accruedProfit;
    uint256 public accruedLoss;
    
    mapping(address => uint256) public balanceOf;
    mapping(address investor => mapping(address spender => uint256)) private _allowances;
    mapping(address => uint256) public investorSharePrice;

    // Constants
    uint256 constant DECIMAL = 1e18;
    uint256 constant PLATFROM_FEE = 1e16;

    struct DivestLocalVars {
        uint256 investorShareBalance;
        uint256 prevChipAmount;
        uint256 prevTargetAmount;
        uint256 investorSharePriceAtInvestment;
    }
    
    constructor() {
        host = IHost(msg.sender);
    }

    function initialize(address _trader, address _chipToken, address _targetToken, address _dex, address _oracle, uint256 _traderFeeMantissa) external {
        if(msg.sender != address(host)) {
            revert InvalidHost();
        }

        trader = _trader;
        chipToken = IERC20(_chipToken);
        targetToken = IERC20(_targetToken);
        dex = SimpleSwap(_dex);
        oracle = SimplePriceOracle(_oracle);
        traderFeeMantissa = _traderFeeMantissa;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address investor, address spender) external view returns (uint256) {
        return _allowances[investor][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    function _update(address from, address to, uint256 value) internal {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }
        unchecked {
            // Overflow not possible: value <= fromBalance <= totalSupply.
            balanceOf[from] = fromBalance - value;
        }

        unchecked {
            // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
            balanceOf[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _approve(address investor, address spender, uint256 value) internal {
        _approve(investor, spender, value, true);
    }

    function _approve(address investor, address spender, uint256 value, bool emitEvent) internal {
        if (investor == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[investor][spender] = value;
        if (emitEvent) {
            emit Approval(investor, spender, value);
        }
    }

    function _spendAllowance(address investor, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[investor][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(investor, spender, currentAllowance - value, false);
            }
        }
    }

    function _totalValue(uint256 chipPrice, uint256 chipAmount, uint256 targetAmount) internal view returns (uint256) {
        uint256 totalValue = chipAmount * chipPrice;
        if(targetAmount > 0) {
            uint256 targetPrice = oracle.getPrice(address(targetToken));
            totalValue += targetAmount * targetPrice;
        }
        return totalValue;
    }

    function _pricePerShare(uint256 chipPrice, uint256 chipAmount, uint256 targetAmount) internal view returns (uint256) {
        // Calculate total value
        uint256 totalValue = _totalValue(chipPrice, chipAmount, targetAmount);

        // Calculate share price
        uint256 sharePrice = totalValue == 0 ? chipPrice : totalValue / totalSupply;

        return sharePrice;
    }

    function performance() external view returns (uint256, uint256) {
        uint256 chipPrice = oracle.getPrice(address(chipToken));
        uint256 totalValue = _totalValue(chipPrice, chipBalance, targetBalance);
        uint positive = accruedProfit;
        uint negative = accruedLoss;
        if(totalValue > totalInvest) {
            positive = positive + totalValue - totalInvest;
        } else {
            negative = negative + totalInvest - totalValue;
        }

        if(positive > negative) {
            positive = positive - negative;
            return (positive, 0);
        } else {
            negative = negative - positive;
            return (0, negative);
        }
    }

    function invest(uint256 chipAmount) external nonReentrant {
        if(chipAmount == 0) {
            revert InvalidAmount();
        }

        // Calculate previous total value
        uint256 chipPrice = oracle.getPrice(address(chipToken));
        
        // Calculate share price
        uint256 sharePrice = _pricePerShare(chipPrice, chipBalance, targetBalance);
        
        // Calculate shares to mint
        uint256 investValue = chipAmount * chipPrice;
        uint256 sharesToMint = investValue / sharePrice;

        // Calculate average share price of investor
        uint256 prevSharePrice = investorSharePrice[msg.sender];
        uint256 prevShareAmount = balanceOf[msg.sender];
        uint256 avgSharePrice = prevSharePrice == 0 ? sharePrice : (prevSharePrice * prevShareAmount + sharePrice * sharesToMint) / (prevShareAmount + sharesToMint);

        // [effect part]

        // update total invest value
        totalInvest += investValue;

        // Update user's share price at investment
        investorSharePrice[msg.sender] = avgSharePrice;

        // Mint shares to user
        balanceOf[msg.sender] += sharesToMint;
        totalSupply += sharesToMint;

        // Update chip and target balance
        // need to handle meme coin in the future
        chipBalance += chipAmount;

        // [interactions part]

        // Transfer chips from user to contract
        chipToken.safeTransferFrom(msg.sender, address(this), chipAmount);

        emit Invested(msg.sender, chipAmount, sharesToMint);
        emit Transfer(address(0), msg.sender, sharesToMint);
    }

    function divest(uint256 shareAmount, address receiver) external nonReentrant {
        if(shareAmount == 0) {
            revert InvalidAmount();
        }

        DivestLocalVars memory vars;

        // sender shares must be greater than amount
        vars.investorShareBalance = balanceOf[msg.sender];
        if (vars.investorShareBalance < shareAmount) {
            revert ERC20InsufficientBalance(msg.sender, vars.investorShareBalance, shareAmount);
        }

        // Calculate previous total value
        vars.prevChipAmount = chipBalance;
        vars.prevTargetAmount = targetBalance;

        // Calculate share price
        uint256 sharePrice = _pricePerShare(oracle.getPrice(address(chipToken)), vars.prevChipAmount, vars.prevTargetAmount);

        // Calculate fee to charge
        uint256 platformFeeAmount = 0;
        uint256 traderFeeAmount = 0;
        uint256 totalProfit = 0;
        uint256 totalLoss = 0;
        vars.investorSharePriceAtInvestment = investorSharePrice[msg.sender];
        // host will not be charged any fee
        if(msg.sender == trader) {
            // charge platform fee to trader
            platformFeeAmount = shareAmount * PLATFROM_FEE / DECIMAL;
        } else if(msg.sender != address(host)) {
            // check trader fee only when fund is in profit
            if(sharePrice > vars.investorSharePriceAtInvestment) {
                // calculate profit
                totalProfit = (sharePrice - vars.investorSharePriceAtInvestment) * shareAmount;
                // charge trader fee
                traderFeeAmount = totalProfit * traderFeeMantissa / sharePrice / DECIMAL;
            } else {
                totalLoss = (vars.investorSharePriceAtInvestment - sharePrice) * shareAmount;
            }
        }
        
        // Calculate shares to burn
        uint256 totalFee = platformFeeAmount + traderFeeAmount;
        uint256 sharesToBurn = shareAmount - totalFee;
        // Calculate tokens to transfer
        uint256 chipToTransfer = vars.prevChipAmount * sharesToBurn / totalSupply;
        uint256 targetToTransfer = vars.prevTargetAmount * sharesToBurn / totalSupply;

        // [effect part]

        // update total invest value
        totalInvest = totalInvest - (vars.investorSharePriceAtInvestment * shareAmount);

        // update fund accumulated profit
        if(totalProfit > 0) {
            accruedProfit += totalProfit;
        }
        if(totalLoss > 0) {
            accruedLoss += totalLoss;
        }
        // update user's share balance
        balanceOf[msg.sender] -= shareAmount;
        // update total share supply
        totalSupply -= sharesToBurn;
        // taxed profit from platform or trader
        if(platformFeeAmount > 0) {
            balanceOf[address(host)] += platformFeeAmount;
        } else if(traderFeeAmount > 0) {
            balanceOf[trader] += traderFeeAmount;
        }
        // update token balances
        // need to handle meme coin in the future
        if(chipToTransfer > 0) {
            chipBalance -= chipToTransfer;
        }
        if(targetToTransfer > 0) {
            targetBalance -= targetToTransfer;
        }

        // [interactions part]
        chipToken.transfer(receiver, chipToTransfer);
        targetToken.transfer(receiver, targetToTransfer);

        if(platformFeeAmount > 0) {
            emit Transfer(msg.sender, address(host), platformFeeAmount);
        } else if(traderFeeAmount > 0) {
            emit Transfer(msg.sender, trader, traderFeeAmount);
        }

        emit Divested(msg.sender, shareAmount, totalFee, sharesToBurn);
        emit Transfer(msg.sender, address(0), sharesToBurn);
    }

    function swap(address tokenOut, uint256 ratio) external nonReentrant {
        // Check that tokenOut is either chip or target
        if(tokenOut != address(chipToken) && tokenOut != address(targetToken)) {
            revert InvalidToken();
        }
        if(trader != msg.sender) {
            revert InvalidTrader();
        }

        // Calculate amount to swap
        uint256 amountOut;
        address tokenIn;
        uint256 newChipBalance;
        uint256 newTargetBalance;
        if(tokenOut == address(chipToken)) {
            tokenIn = address(targetToken);
            amountOut = chipBalance * ratio / DECIMAL;
            newChipBalance = chipBalance - amountOut;
        } else {
            tokenIn = address(chipToken);
            amountOut = targetBalance * ratio / DECIMAL;
            newTargetBalance = targetBalance - amountOut;
        }
        
        IERC20(tokenOut).approve(address(dex), amountOut);
        uint256 amountIn = dex.swap(tokenOut, tokenIn, amountOut);

        // need to avoid reentrancy risk in the future
        if(tokenOut == address(chipToken)) {
            newTargetBalance = targetBalance + amountIn;
        } else {
            newChipBalance = chipBalance + amountIn;
        }
        // update token balances
        // need to handle meme coin in the future
        chipBalance = newChipBalance;
        targetBalance = newTargetBalance;

        emit Swapped(trader, tokenOut, amountIn, amountOut);
    }

    function registerArena(address arena) external nonReentrant {
        if(msg.sender != trader) {
            revert InvalidTrader();
        }
        
        if(!host.hasArena(arena)) {
            revert InvalidArena();
        }

        IArena(arena).register();
    }

    function challengeArena(address arena, uint8 _rank) external nonReentrant {
        if(msg.sender != trader) {
            revert InvalidTrader();
        }
        
        if(!host.hasArena(arena)) {
            revert InvalidArena();
        }

        IArena(arena).challenge(_rank);
    }

    function mintArena(address arena, uint8 _rank) external nonReentrant {
        if(msg.sender != trader) {
            revert InvalidTrader();
        }
        
        if(!host.hasArena(arena)) {
            revert InvalidArena();
        }

        IArena(arena).mint(_rank);
    }

    function transferNFT(address arena, address to, uint256 tokenId) external nonReentrant {
        if(msg.sender != trader) {
            revert InvalidTrader();
        }

        // transfer NFT
        // IERC721(arena).approve(to, tokenId);
        IERC721(arena).transferFrom(address(this), to, tokenId);
    }
}