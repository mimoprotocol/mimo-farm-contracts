// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {SmartChef, SmartChefFactory, IERC20Metadata} from "../src/SmartChefFactory.sol";
import {Token} from "../src/test/Token.sol";

contract SmartChefFactoryTest is Test {
    SmartChefFactory public factory;
    address public owner = address(0xa);

    function setUp() public {
        factory = new SmartChefFactory();
    }

    function testAdmin() public {
        Token stakingToken = new Token("Staking", "S");
        Token rewardToken = new Token("Reward", "R");
        address smartchef = factory.deployPool(stakingToken, rewardToken, 0.1 ether, 1000, 2000, 0, owner);

        assertEq(SmartChef(smartchef).owner(), owner);
    }
}
