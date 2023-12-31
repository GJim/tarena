// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFund {

    // Event declarations
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event Invested(address investor, uint256 amount, uint256 sharesMinted);
    event Divested(address investor, uint256 amount, uint256 fee, uint256 sharesBurned);
    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    error InvalidHost();
    error InvalidToken();
    error InvalidTrader();
    error InvalidArena();
    error InvalidAmount();

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address investor, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function trader() external view returns (address);
    function initialize(address _trader, address _chipToken, address _targetToken, address _dex, address _oracle, uint256 _traderFeeMantissa) external;
    function invest(uint256 chipAmount) external;
    function divest(uint256 shareAmount, address receiver) external;
    function swap(address tokenOut, uint256 ratio) external;
    function performance() external view returns (uint256, uint256);
}