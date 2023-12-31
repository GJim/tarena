// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IArena {

    error InvalidHost();
    error InvalidFund();
    error InvalidRank();
    error InvalidWinner();
    error ExceededDeadline();
    error InvalidChallenge();
    error AlreadyMinted();
    
    function initialize(uint256 _registrationDeadline, uint256 _challengeDeadline, uint256 _mintDeadline, address _rewardToken) external;
    function register() external returns(bool);
    function challenge(uint8 _rank) external;
    function mint(uint8 _rank) external;
    function clear(address _token) external;
}