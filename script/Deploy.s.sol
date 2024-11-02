// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

import {Token} from "../src/test/Token.sol";
import {SmartChefFactory} from "../src/SmartChefFactory.sol";

contract DeployScript is Script {
    bool public deployStakingToken;
    bool public deployRewardToken;

    function setUp() public {
        deployStakingToken = vm.envBool("DEPLOY_STAKING");
        deployRewardToken = vm.envBool("DEPLOY_REWARD");
    }

    function run() public {
        vm.startBroadcast();
        if (deployStakingToken) {
            Token stakingToken = new Token("Test LP", "TLP");
            console.log("Deployed staking token: ", address(stakingToken));
        }
        if (deployRewardToken) {
            Token rewardToken = new Token("Test Reward", "TRT");
            console.log("Deployed reward token: ", address(rewardToken));
        }

        SmartChefFactory factory = new SmartChefFactory();
        vm.stopBroadcast();

        console.log("Deployed SmartchefFactory: ", address(factory));
    }
}
