// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SmartChef} from "../src/SmartChef.sol";
import {Token} from "../src/test/Token.sol";

contract SmartChefTest is Test {
    SmartChef public chef;
    Token public stakingToken;
    Token public rewardToken;
    address public alice = address(0xa);
    address public bob = address(0xb);

    function setUp() public {
        stakingToken = new Token("Staking", "S");
        rewardToken = new Token("Reward", "R");

        chef = new SmartChef(stakingToken, rewardToken, 0.1 ether, 1000, 2000, 0);

        stakingToken.mint(alice, 5 ether);
        stakingToken.mint(bob, 5 ether);
        rewardToken.mint(address(chef), 1000 ether);
    }

    function testFullMining() public {
        vm.startPrank(alice);
        stakingToken.approve(address(chef), 1 ether);

        chef.deposit(1 ether);

        vm.warp(100);
        assertEq(chef.pendingReward(alice), 0);

        vm.warp(1001);
        assertEq(chef.pendingReward(alice), 0.1 ether);

        vm.warp(1100);
        chef.deposit(0 ether);
        assertEq(rewardToken.balanceOf(alice), 0.1 ether * 100);
        assertEq(rewardToken.balanceOf(address(chef)), 1000 ether - 0.1 ether * 100);
        vm.stopPrank();

        chef.updateRewardPerSecond(0.05 ether);

        vm.startPrank(alice);

        vm.warp(2000);
        chef.deposit(0 ether);
        assertEq(rewardToken.balanceOf(alice), 0.1 ether * 100 + 0.05 ether * 900);

        vm.warp(3000);
        chef.deposit(0 ether);
        assertEq(rewardToken.balanceOf(alice), 0.1 ether * 100 + 0.05 ether * 900);
        assertEq(chef.lastRewardTimestamp(), 3000);
        vm.stopPrank();

        vm.warp(4000);
        chef.updateRewardPerSecond(0.2 ether);
        assertEq(chef.lastRewardTimestamp(), 4000);
        assertEq(chef.pendingReward(alice), 0);
        assertEq(chef.pendingReward(bob), 0);

        vm.warp(5000);
        chef.updateEndTimestamp(6000);
        assertEq(chef.lastRewardTimestamp(), 5000);
        assertEq(chef.pendingReward(alice), 0);
        assertEq(chef.pendingReward(bob), 0);

        vm.warp(5500);
        assertEq(chef.lastRewardTimestamp(), 5000);
        assertEq(chef.pendingReward(alice), 0.2 ether * 500);
        assertEq(chef.pendingReward(bob), 0);

        uint256 originReward = rewardToken.balanceOf(alice);
        vm.prank(alice);
        chef.deposit(0 ether);
        assertEq(rewardToken.balanceOf(alice), originReward + 0.2 ether * 500);
    }

    function testMultiUsers() public {
        vm.startPrank(alice);
        stakingToken.approve(address(chef), 1 ether);
        chef.deposit(1 ether);
        vm.stopPrank();

        vm.warp(1001);
        vm.startPrank(bob);
        stakingToken.approve(address(chef), 3 ether);
        chef.deposit(3 ether);
        vm.stopPrank();

        vm.warp(1010);
        assertEq(chef.pendingReward(alice), 0.1 ether + 0.025 ether * 9);
        assertEq(chef.pendingReward(bob), 0.025 ether * 3 * 9);
        vm.prank(alice);
        chef.withdraw(0.5 ether);
        vm.prank(bob);
        chef.withdraw(1 ether);
        assertEq(rewardToken.balanceOf(alice), 0.1 ether + 0.025 ether * 9);
        assertEq(rewardToken.balanceOf(bob), 0.025 ether * 3 * 9);
    }
}
