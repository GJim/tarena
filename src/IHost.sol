// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHost {
    error TraderExist();
    error InvalidTraderFee();
    error InvalidOwner();
    
    function chipToken() external view returns (address);
    function targetToken() external view returns (address);
    function dex() external view returns (address);
    function oracle() external view returns (address);
    function traders(address trader) external view returns (bool);
    function hasFund(address fund) external view returns (bool);
    function hasArena(address arena) external view returns (bool);
}