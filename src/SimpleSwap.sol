// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ISimpleSwap } from "./ISimpleSwap.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleSwap is ISimpleSwap {

    address private _tokenA;
    address private _tokenB;
    uint256 private _reserveA;
    uint256 private _reserveB;
    uint256 private _qA;
    uint256 private _qB;

    constructor(address tokenA, address tokenB) {
        require(tokenA != tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        require(tokenA.code.length > 0, "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(tokenB.code.length > 0, "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        (_tokenA, _tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        // avoid identical address
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        // avoid input token not A or B
        require(tokenIn == _tokenA || tokenIn == _tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        // avoid output token not A or B
        require(tokenOut == _tokenA || tokenOut == _tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        // check amount valid
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // get reserve storage into memory
        (uint256 reserveA, uint256 reserveB) = (_reserveA, _reserveB);

        // distinguish tokenA and tokenB
        if(tokenIn == _tokenA) {
            // calculate amount out
            amountOut = _amountOut(amountIn, 0);
            // update updated reserve by memory variable
            _reserveA = reserveA + amountIn;
            _reserveB = reserveB - amountOut;
        } else {
            amountOut = _amountOut(0, amountIn);
            _reserveB = reserveB + amountIn;
            _reserveA = reserveA - amountOut;
        }
        
        // transfer input token into this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // transfer output token with calculated amount for sender
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        // emit event
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external returns (uint256 amountA, uint256 amountB) {
        // check inputs amount valid
        require(amountAIn != 0 && amountBIn != 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        
        // get reserve storage into memory
        (uint256 reserveA, uint256 reserveB) = (_reserveA, _reserveB);

        amountA = amountAIn;
        amountB = amountBIn;

        // update reserve
        _reserveA = reserveA + amountA;
        _reserveB = reserveB + amountB;

        // transfer token into this contract
        IERC20(_tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(_tokenB).transferFrom(msg.sender, address(this), amountB);
        
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB){
        reserveA = _reserveA;
        reserveB = _reserveB;
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view returns (address tokenA){
        tokenA = _tokenA;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view returns (address tokenB){
        tokenB = _tokenB;
    }

    function setRatio(address token1, address token2, uint256 q1, uint256 q2) external {
        (uint256 qA, uint256 qB) = token1 < token2 ? (q1, q2) : (q2, q1);
        _qA = qA;
        _qB = qB;
    }

    function _amountOut(uint256 amountAIn, uint256 amountBIn) internal view returns (uint256 amountOut) {
        require((amountAIn != 0 || amountBIn != 0) && (amountAIn * amountBIn == 0), "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        if(amountAIn > 0) {
            amountOut = amountAIn * _qB / _qA;
        } else {
            amountOut = amountBIn * _qA / _qB;
        }
    }

}