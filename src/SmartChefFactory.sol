// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SmartChef} from "./SmartChef.sol";

contract SmartChefFactory is Ownable {
    event NewSmartChefContract(address indexed smartChef);

    function deployPool(
        IERC20Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _poolLimitPerUser,
        address _admin
    ) external onlyOwner returns (address) {
        SmartChef smartChef = new SmartChef(
            _stakedToken, _rewardToken, _rewardPerSecond, _startTimestamp, _endTimestamp, _poolLimitPerUser
        );
        smartChef.transferOwnership(_admin);

        emit NewSmartChefContract(address(smartChef));
        return address(smartChef);
    }
}
