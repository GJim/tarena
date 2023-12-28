// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleSwap.sol";
import "./SimplePriceOracle.sol";

contract Fund is IERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant name = 'Trader Arena';
    string public constant symbol = 'TA';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    address public owner;
    address public trader;
    IERC20 public chipToken;
    IERC20 public targetToken;
    SimpleSwap public dex;
    SimplePriceOracle public oracle;
    uint256 public traderFeeMantissa;
    
    mapping(address => uint256) public balanceOf;
    mapping(address investor => mapping(address spender => uint256)) private _allowances;
    mapping(address => uint256) public investorSharePrice;

    // Constants
    uint256 constant DECIMAL = 1e18;
    uint256 constant PLATFROM_FEE = 1e16;

    // Event declarations
    event Invested(address investor, uint256 amount, uint256 sharesMinted);
    event Divested(address investor, uint256 amount, uint256 fee, uint256 sharesBurned);
    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
    error TAZeroAmount();
    error TAInsufficientBalance();
    error TAInvalidToken();
    error TAInvalidTrader();

    constructor(address _trader, address _chipToken, address _targetToken, address _dex, address _oracle, uint256 _traderFeeMantissa) {
        owner = msg.sender;
        trader = _trader;
        chipToken = IERC20(_chipToken);
        targetToken = IERC20(_targetToken);
        dex = SimpleSwap(_dex);
        oracle = SimplePriceOracle(_oracle);
        traderFeeMantissa = _traderFeeMantissa;
    }

    function transfer(address to, uint256 value) public virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address investor, address spender) public view virtual returns (uint256) {
        return _allowances[investor][spender];
    }

    function approve(address spender, uint256 value) public virtual returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
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

    function _update(address from, address to, uint256 value) internal virtual {
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

    function _approve(address investor, address spender, uint256 value, bool emitEvent) internal virtual {
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

    function _spendAllowance(address investor, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(investor, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(investor, spender, currentAllowance - value, false);
            }
        }
    }

    function invest(uint256 chipAmount) external nonReentrant {
        if(chipAmount == 0) {
            revert TAZeroAmount();
        }

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
        uint256 sharePrice = prevTotalValue == 0 ? chipPrice : prevTotalValue / totalSupply;
        
        // Calculate shares to mint
        uint256 sharesToMint = (chipAmount * chipPrice) / sharePrice;

        // Calculate average share price of investor
        uint256 prevSharePrice = investorSharePrice[msg.sender];
        uint256 prevShareAmount = balanceOf[msg.sender];
        uint256 avgSharePrice = prevSharePrice == 0 ? sharePrice : (prevSharePrice * prevShareAmount + sharePrice * sharesToMint) / (prevShareAmount + sharesToMint);

        // [effect part]

        // Update user's share price at investment
        investorSharePrice[msg.sender] = avgSharePrice;

        // Mint shares to user
        balanceOf[msg.sender] += sharesToMint;
        totalSupply += sharesToMint;

        // [interactions part]

        // Transfer chips from user to contract
        chipToken.safeTransferFrom(msg.sender, address(this), chipAmount);

        emit Invested(msg.sender, chipAmount, sharesToMint);
        emit Transfer(address(0), msg.sender, sharesToMint);
    }

    function divest(uint256 shareAmount) external nonReentrant {
        if(shareAmount == 0) {
            revert TAZeroAmount();
        }

        // sender shares must be greater than amount
        uint256 investorShareBalance = balanceOf[msg.sender];
        if (investorShareBalance < shareAmount) {
            revert ERC20InsufficientBalance(msg.sender, investorShareBalance, shareAmount);
        }

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
        uint256 sharePrice = prevTotalValue == 0 ? DECIMAL : prevTotalValue / totalSupply;

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
        uint256 chipToTransfer = prevChipAmount * sharesToBurn / totalSupply;
        uint256 targetToTransfer = targetAmount * sharesToBurn / totalSupply;

        // [effect part]
        balanceOf[msg.sender] -= shareAmount;
        totalSupply -= sharesToBurn;
        if(platformFeeAmount > 0) {
            balanceOf[owner] += platformFeeAmount;
        } else if(traderFeeAmount > 0) {
            balanceOf[trader] += traderFeeAmount;
        }

        // [interactions part]
        chipToken.transfer(msg.sender, chipToTransfer);
        targetToken.transfer(msg.sender, targetToTransfer);

        if(platformFeeAmount > 0) {
            emit Transfer(msg.sender, owner, platformFeeAmount);
        } else if(traderFeeAmount > 0) {
            emit Transfer(msg.sender, trader, traderFeeAmount);
        }

        emit Divested(msg.sender, shareAmount, totalFee, sharesToBurn);
        emit Transfer(msg.sender, address(0), sharesToBurn);
    }

    function swap(address tokenOut, uint256 ratio) external nonReentrant {
        // Check that tokenOut is either chip or target
        if(tokenOut != address(chipToken) && tokenOut != address(targetToken)) {
            revert TAInvalidToken();
        }
        if(trader != msg.sender) {
            revert TAInvalidTrader();
        }

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