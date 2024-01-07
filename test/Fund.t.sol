// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SimpleSwap} from "src/SimpleSwap.sol";
import {ISimpleSwap} from "src/ISimpleSwap.sol";
import {SimplePriceOracle} from "src/SimplePriceOracle.sol";
import {Host} from "src/Host.sol";
import {IFund, Fund} from "src/Fund.sol";

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

    function setUp() public {
        owner = makeAddr("owner");
        trader = makeAddr("trader");
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        // deploy chip and target tokens
        chip = new Token("chip token", "CP");
        target = new Token("target token", "TG");
        // deploy dex
        dex = new SimpleSwap(address(chip), address(target));
        // deploy price oracle
        oracle = new SimplePriceOracle();

        // setup dex
        chip.mint(address(this), 10000e18);
        target.mint(address(this), 10000e18);
        // approve chip and target to dex
        chip.approve(address(dex), type(uint256).max);
        target.approve(address(dex), type(uint256).max);
        dex.addLiquidity(1000e18, 1000e18);
    }

    function testERC20() public {
        vm.startPrank(owner);
        Host host = new Host();
        host.initialize(address(chip), address(target), address(dex), address(oracle));
        address fundAddress = host.createFund(0);
        IFund fund = IFund(fundAddress);
        chip.mint(owner, 20e18);
        oracle.setPrice(address(chip), 10e18);  // $10
        chip.approve(address(fund), 20e18);
        fund.invest(20e18);
        // test total supply
        assertEq(fund.totalSupply(), 20e18);
        // test transfer
        fund.transfer(userA, 10e18);
        vm.stopPrank();
        vm.startPrank(userA);
        fund.approve(owner, 10e18);
        vm.stopPrank();
        vm.startPrank(owner);
        fund.transferFrom(userA, userB, 5e18);
        vm.stopPrank();
        assertEq(fund.balanceOf(owner), 10e18);
        assertEq(fund.balanceOf(userA), 5e18);
        assertEq(fund.balanceOf(userB), 5e18);
        assertEq(fund.allowance(userA, owner), 5e18);
    }

    function testScenario() public {
        vm.startPrank(owner);
        // deploy host
        Host host = new Host();
        host.initialize(address(chip), address(target), address(dex), address(oracle));
        // mint chip for investor A and B
        chip.mint(userA, 20e18);
        chip.mint(userB, 10e18);
        // The price of chip and target token are both 10 dollar
        oracle.setPrice(address(chip), 10e18);  // $10
        oracle.setPrice(address(target), 10e18); // $10
        vm.stopPrank();

        vm.startPrank(trader);
        uint256 traderFeeMantissa = 0.1e18;
        address fundAddress = host.createFund(traderFeeMantissa);
        IFund fund = IFund(fundAddress);
        vm.stopPrank();

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
        dex.setRatio(address(chip), address(target), 1, 1); // 1 chip for 1 target
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
        dex.setRatio(address(chip), address(target), 1, 2); // 1 chip for 2 targets
        fund.swap(address(chip), 1e18); // swap 100% of chip balance
        vm.stopPrank();

        // 7. The target price become 10 dollar. [Total: 400, chip: 0, target: 40]
        oracle.setPrice(address(target), 10e18);

        // 8. check Investor A receive 29 targets after divest.
        vm.startPrank(userA);
        uint256 sharesA = fund.balanceOf(userA);
        fund.divest(sharesA, userA);
        uint256 targetBalanceA = target.balanceOf(userA);
        assertEq(targetBalanceA, 29e18); // Check Investor A receives 30 targets
        vm.stopPrank();

        // 9. check Investor B receive 10 targets after divest.
        vm.startPrank(userB);
        uint256 sharesB = fund.balanceOf(userB);
        fund.divest(sharesB, userB);
        uint256 targetBalanceB = target.balanceOf(userB);
        assertEq(targetBalanceB, 10e18); // Check Investor B receives 10 targets
        vm.stopPrank();

        // 10. check trader receive 0.99 targets after divest.
        vm.startPrank(trader);
        uint256 sharesTrader = fund.balanceOf(trader);
        fund.divest(sharesTrader, trader);
        uint256 targetBalanceTrader = target.balanceOf(trader);
        assertEq(targetBalanceTrader, 0.99e18);
        vm.stopPrank();

        // 10. check owner receive 0.01 targets after divest.
        vm.startPrank(owner);
        host.divestFund(address(fund), owner);
        uint256 targetBalanceOwner = target.balanceOf(owner);
        assertEq(targetBalanceOwner, 0.01e18);
        vm.stopPrank();

        // 11. check all asset are 0 after divest.
        assertEq(fund.balanceOf(address(this)), 0);
        assertEq(chip.balanceOf(address(fund)), 0);
        assertEq(target.balanceOf(address(fund)), 0);
    }

}