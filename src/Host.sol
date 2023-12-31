// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IHost} from './IHost.sol';
import {Fund, IFund} from './Fund.sol';
import {Arena, IArena} from './Arena.sol';

contract Host is IHost, ReentrancyGuard {
    uint256 constant DECIMAL = 1e18;

    address public owner;
    address public chipToken;
    address public targetToken;
    address public dex;
    address public oracle;

    mapping (address => bool) public traders;
    mapping (address => bool) public hasFund;
    mapping (address => bool) public hasArena;

    constructor() {
        owner = msg.sender;
    }

    function initialize(address _chipToken, address _targetToken, address _dex, address _oracle) external {
        if(msg.sender != owner) {
            revert InvalidOwner();
        }

        chipToken = _chipToken;
        targetToken = _targetToken;
        dex = _dex;
        oracle = _oracle;
    }

    function createFund(uint256 _traderFeeMantissa) external returns (address fund) {
        if(_traderFeeMantissa >= DECIMAL) {
            revert InvalidTraderFee();
        }

        if(traders[msg.sender]) {
            revert TraderExist();
        }

        bytes memory bytecode = type(Fund).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, _traderFeeMantissa));
        assembly {
            fund := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IFund(fund).initialize(msg.sender, chipToken, targetToken, dex, oracle, _traderFeeMantissa);
        traders[msg.sender] = true;
        hasFund[fund] = true;
        // emit fund
    }

    function divestFund(address fund, address receiver) external {
        if(msg.sender != owner) {
            revert InvalidOwner();
        }
        IFund iFund = IFund(fund);
        iFund.divest(iFund.balanceOf(address(this)), receiver);
    }

    function createArena() external returns (address arena) {
        if(msg.sender != owner) {
            revert InvalidOwner();
        }

        bytes memory bytecode = type(Arena).creationCode;
        uint256 currentBlock = block.number;
        bytes32 salt = keccak256(abi.encodePacked(currentBlock));
        assembly {
            arena := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IArena(arena).initialize(currentBlock+100, currentBlock+200, currentBlock+300, chipToken);
        hasArena[arena] = true;
        // emit Arena;
    }

    function setOwner(address _owner) external {
        if(msg.sender != owner) {
            revert InvalidOwner();
        }
        owner = _owner;
    }
}