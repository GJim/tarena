// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SimpleSwap} from "src/SimpleSwap.sol";
import {ISimpleSwap} from "src/ISimpleSwap.sol";
import {SimplePriceOracle} from "src/SimplePriceOracle.sol";
import {Host} from "src/Host.sol";
import {IFund, Fund} from "src/Fund.sol";
import {IArena} from "src/Arena.sol";

contract Token is ERC20 {
   constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

   function mint(address account, uint256 value) public {
       _mint(account, value);
   }
}

contract ArenaTest is Test {
    address public owner;
    address public traderA;
    address public traderB;
    address public traderC;
    address public traderD;
    Token public chip;
    Token public target;
    SimpleSwap public dex;
    SimplePriceOracle public oracle;
    Host public host;

    function setUp() public {
        owner = makeAddr("owner");
        traderA = makeAddr("traderA");
        traderB = makeAddr("traderB");
        traderC = makeAddr("traderC");
        traderD = makeAddr("traderD");
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

        // setup host
        vm.startPrank(owner);
        host = new Host();
        host.initialize(address(chip), address(target), address(dex), address(oracle));
        vm.stopPrank();
    }

    function testRegister() public {
        // setup
        vm.startPrank(owner);
        chip.mint(owner, 1000e18);
        chip.transfer(address(host), 1000e18);
        address arena = host.createArena(1000e18);
        vm.stopPrank();

        // fail for fake fund
        address fund = address(new Fund());
        vm.startPrank(fund);
        vm.expectRevert(IArena.InvalidFund.selector);
        IArena(arena).register();
        vm.stopPrank();

        vm.startPrank(traderA);
        address fundAddressA = host.createFund(0);
        IFund fundA = IFund(fundAddressA);
        oracle.setPrice(address(chip), 10e18);
        chip.mint(traderA, 10e18);
        chip.approve(fundAddressA, 10e18);
        fundA.invest(10e18);
        oracle.setPrice(address(chip), 5e18);
        // fail for fund in loss
        vm.expectRevert(IArena.InvalidFund.selector);
        fundA.registerArena(arena);
        // fail for deadline exceeded
        vm.roll(block.number + 101);
        vm.expectRevert(IArena.ExceededDeadline.selector);
        fundA.registerArena(arena);
        vm.stopPrank();
    }

    function testScenario() public {
        /* setup scenario */
        // create an arena with 1000 chips as reward
        vm.startPrank(owner);
        chip.mint(owner, 1000e18);
        chip.transfer(address(host), 1000e18);
        address arena = host.createArena(1000e18);
        vm.stopPrank();
        // mint 50 chips for each trader
        chip.mint(traderA, 50e18);
        chip.mint(traderB, 50e18);
        chip.mint(traderC, 50e18);
        chip.mint(traderD, 50e18);

        /* Both chip and target are $10 and exchange rate is 1:1 */
        oracle.setPrice(address(chip), 10e18);
        oracle.setPrice(address(target), 10e18);
        dex.setRatio(address(chip), address(target), 1, 1);

        /* traders raise their funds with zero trader fee
         * and register the arena */
        vm.startPrank(traderA);
        address fundAddressA = host.createFund(0);
        IFund fundA = IFund(fundAddressA);
        chip.approve(address(fundA), 50e18);
        fundA.invest(50e18);
        // trader swap 80% of chip for 40 target
        fundA.swap(address(chip), 0.8e18);
        bool success = fundA.registerArena(arena);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderB);
        address fundAddressB = host.createFund(0);
        IFund fundB = IFund(fundAddressB);
        chip.approve(address(fundB), 50e18);
        fundB.invest(50e18);
        // trader swap 60% of chip for 30 target
        fundB.swap(address(chip), 0.6e18);
        success = fundB.registerArena(arena);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderC);
        address fundAddressC = host.createFund(0);
        IFund fundC = IFund(fundAddressC);
        chip.approve(address(fundC), 50e18);
        fundC.invest(50e18);
        // trader swap 40% of chip for 20 target
        fundC.swap(address(chip), 0.4e18);
        success = fundC.registerArena(arena);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderD);
        address fundAddressD = host.createFund(0);
        IFund fundD = IFund(fundAddressD);
        chip.approve(address(fundD), 50e18);
        fundD.invest(50e18);
        // trader swap 20% of chip for 10 target
        fundD.swap(address(chip), 0.2e18);
        success = fundD.registerArena(arena);
        assert(success);
        vm.stopPrank();

        // registration deadline has passed
        vm.roll(block.number + 101);

        /* Chip become $20, 
         * so exchange rate is become 1:2 */
        oracle.setPrice(address(chip), 20e18);
        dex.setRatio(address(chip), address(target), 1, 2);

        /* trader D, C and B successfully become the top 3
         * defenders in the arena rankings */
        vm.startPrank(traderD);
        success = fundD.challengeArena(arena, 1);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderC);
        success = fundC.challengeArena(arena, 2);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderB);
        success = fundB.challengeArena(arena, 3);
        assert(success);
        vm.stopPrank();

        /* Target become $40, 
         * so exchange rate is become 2:1 */
        oracle.setPrice(address(target), 40e18);
        dex.setRatio(address(chip), address(target), 2, 1);

        /* trader A, B and C successfully become new top 3 */
        vm.startPrank(traderA);
        success = fundA.challengeArena(arena, 1);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderB);
        success = fundB.challengeArena(arena, 2);
        assert(success);
        vm.stopPrank();
        vm.startPrank(traderC);
        success = fundC.challengeArena(arena, 3);
        assert(success);
        vm.stopPrank();

        // challenge deadline has passed
        vm.roll(block.number + 100);

        /* traders mint their NFT and apply their reward,
         * but trader C forget to apply reward */
        vm.startPrank(traderA);
        assertEq(chip.balanceOf(traderA), 0);
        success = fundA.mintArena(arena, 1);
        assert(success);
        // get 50% of reward
        assertEq(chip.balanceOf(traderA), 500e18);
        // get NFT
        assertEq(IArena(arena).ownerOf(1), fundAddressA);
        vm.stopPrank();
        vm.startPrank(traderB);
        assertEq(chip.balanceOf(traderB), 0);
        success = fundB.mintArena(arena, 2);
        assert(success);
        // get 30% of reward
        assertEq(chip.balanceOf(traderB), 300e18);
        // get NFT
        assertEq(IArena(arena).ownerOf(2), fundAddressB);
        vm.stopPrank();

        // mint deadline has passed
        vm.roll(block.number + 100);

        /* host forfeits the arena reward after mint deadline */
        vm.startPrank(owner);
        uint256 beforeBalance = chip.balanceOf(address(owner));
        host.forfeitReward(arena, owner);
        uint256 afterBalance = chip.balanceOf(address(owner));
        assertEq(afterBalance - beforeBalance, 200e18);
        vm.stopPrank();

        // check trader A transfer NFT from Fund A to Fund C
        vm.startPrank(traderA);
        fundA.transferNFT(arena, fundAddressC, 1);
        assertEq(IArena(arena).ownerOf(1), fundAddressC);
        vm.stopPrank();

        // check arena ranks
        assertEq(IArena(arena).ranks(1), fundAddressA);
        assertEq(IArena(arena).ranks(2), fundAddressB);
        assertEq(IArena(arena).ranks(3), fundAddressC);

        // check arena inRanks
        assertEq(IArena(arena).inRanks(address(fundA)), 0);
        assertEq(IArena(arena).inRanks(address(fundB)), 0);
        assertEq(IArena(arena).inRanks(address(fundC)), 3);
        assertEq(IArena(arena).inRanks(address(fundD)), 0);
    }
}