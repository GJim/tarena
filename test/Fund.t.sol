// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SimpleSwap} from "src/SimpleSwap.sol";
import {ISimpleSwap} from "src/ISimpleSwap.sol";
import {SimplePriceOracle, IPriceOracle} from "src/SimplePriceOracle.sol";
import {Fund} from "src/Fund.sol";

contract Token is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}

contract FundTest is Test {
    address public owner;
    address public trader;
    address public userA;
    address public userB;
    Token public chip;
    Token public target;
    SimpleSwap public dex;
    SimplePriceOracle public oracle;
    Fund public fund;

    function setUp() public {
        owner = makeAddr("owner");
        trader = makeAddr("trader");
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        vm.startPrank(owner);
        // deploy chip and target tokens
        chip = new Token("chip token", "CP");
        target = new Token("target token", "TG");
        // deploy dex
        dex = new SimpleSwap(address(chip), address(target));
        // deploy price oracle
        oracle = new SimplePriceOracle();
        // deploy fund
        fund = new Fund(trader, address(chip), address(target), address(dex), address(oracle), 0);

        // setup dex
        chip.mint(owner, 10000e18);
        target.mint(owner, 10000e18);
        // approve chip and target to dex
        chip.approve(address(dex), type(uint256).max);
        target.approve(address(dex), type(uint256).max);
        dex.addLiquidity(1000e18, 1000e18);
        vm.stopPrank();
    }

    function testSwap() public {
        vm.startPrank(owner);
        dex.setRatio(1, 1);
        // swap 20 chip for 20 target
        uint amountOut = dex.swap(address(chip), address(target), 20e18);
        assertEq(amountOut, 20e18);
        dex.setRatio(1, 2);
        // swap 10 chip for 20 target
        amountOut = dex.swap(address(chip), address(target), 10e18);
        assertEq(amountOut, 20e18);
        vm.stopPrank();
    }

    function testScenario() public {
        // mint chip for investor A and B
        chip.mint(userA, 20e18);
        chip.mint(userB, 10e18);
        // The price of chip and target token are both 10 dollar
        oracle.setPrice(address(chip), 10e18);  // $10
        oracle.setPrice(address(target), 10e18); // $10

        // 1. Investor A deposit 10 chips. [Total: 100, chip: 10, target: 0]
        vm.startPrank(userA);
        chip.approve(address(fund), 10e18);
        fund.invest(10e18);
        vm.stopPrank();

        // 2. Investor B deposit 10 chips. [Total: 200, chip: 20, target: 0]
        vm.startPrank(userB);
        chip.approve(address(fund), 10e18);
        fund.invest(10e18);
        vm.stopPrank();

        // 3. Trader use 20 chips to swap 20 targets. [Total: 200, chip: 0, target: 20]
        vm.startPrank(trader);
        dex.setRatio(1, 1); // 1 chip for 1 target
        fund.swap(address(chip), 1e18); // swap 100% of chip balance
        vm.stopPrank();

        // 4. The target price become 5 dollar. [Total: 100, chip: 0, target: 20]
        oracle.setPrice(address(target), 5e18);

        // 5. Investor A deposit 10 chips again. [Total: 200, chip: 10, target: 20]
        vm.startPrank(userA);
        chip.approve(address(fund), 10e18);
        fund.invest(10e18);
        vm.stopPrank();

        // 6. Trader use 10 chips to swap 20 targets again. [Total: 200, chip: 0, target: 40]
        vm.startPrank(trader);
        dex.setRatio(1, 2); // 1 chip for 2 targets
        fund.swap(address(chip), 1e18); // swap 100% of chip balance
        vm.stopPrank();

        // 7. The target price become 10 dollar. [Total: 400, chip: 0, target: 40]
        oracle.setPrice(address(target), 10e18);

        // 8. check Investor A receive 30 targets after divest.
        vm.startPrank(userA);
        uint256 sharesA = fund.shares(userA);
        fund.divest(sharesA);
        uint256 targetBalanceA = target.balanceOf(userA);
        assertEq(targetBalanceA, 30e18); // Check Investor A receives 30 targets
        vm.stopPrank();

        // 9. check Investor B receive 10 targets after divest.
        vm.startPrank(userB);
        uint256 sharesB = fund.shares(userB);
        fund.divest(sharesB);
        uint256 targetBalanceB = target.balanceOf(userB);
        assertEq(targetBalanceB, 10e18); // Check Investor B receives 10 targets
        vm.stopPrank();
    }

}