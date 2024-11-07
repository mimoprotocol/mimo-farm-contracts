// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {Token} from "../src/test/Token.sol";
import {UniswapV3Staker, IUniswapV3Factory, INonfungiblePositionManager} from "../src/UniswapV3Staker.sol";

contract DeployScript is Script {
    address public factory;
    address public nonfungiblePositionManager;
    uint256 public maxIncentiveStartLeadTime;
    uint256 public maxIncentiveDuration;

    function setUp() public {
        factory = vm.envAddress("FACTORY");
        nonfungiblePositionManager = vm.envAddress("POSITION_MANAGER");
        maxIncentiveStartLeadTime = 7 days;
        maxIncentiveDuration = 365 days;
    }

    function run() public {
        vm.startBroadcast();
        UniswapV3Staker staker = new UniswapV3Staker(
            IUniswapV3Factory(factory),
            INonfungiblePositionManager(nonfungiblePositionManager),
            maxIncentiveStartLeadTime,
            maxIncentiveDuration
        );
        vm.stopBroadcast();

        console.log("Deployed UniswapV3Staker: ", address(staker));
    }
}
