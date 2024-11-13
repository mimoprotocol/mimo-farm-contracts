// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SmartChef is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The timestamp when mining ends.
    uint256 public endTimestamp;

    // The timestamp when mining starts.
    uint256 public startTimestamp;

    // The  of the last pool update
    uint256 public lastRewardTimestamp;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // Tokens created per second.
    uint256 public rewardPerSecond;

    // The precision factor
    uint256 public immutable PRECISION_FACTOR;

    // The reward token
    IERC20Metadata public immutable rewardToken;

    // The staked token
    IERC20Metadata public immutable stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewRewardPerSecond(uint256 rewardPerSecond);
    event NewStartTimestamp(uint256 startTimestamp);
    event NewEndTimestamp(uint256 endTimestamp);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount);

    /*
     * @notice constructor
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerSecond: reward per second (in rewardToken)
     * @param _startTimestamp: start timestamp
     * @param _endTimestamp: end timestamp
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     */
    constructor(
        IERC20Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _poolLimitPerUser
    ) {
        require(_startTimestamp > block.timestamp && _endTimestamp > _startTimestamp, "invalid timestamp");

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10 ** (30 - decimalsRewardToken));

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }

        if (_amount > 0) {
            user.amount = user.amount + _amount;
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    /*
     * @notice Emergency reward withdraw
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

        IERC20Metadata(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        require(endTimestamp < block.timestamp, "Cannot stop ended cycle");
        endTimestamp = block.timestamp;

        emit RewardsStop(block.timestamp);
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per second
     * @dev Only callable by owner.
     * @param _rewardPerSecond: the reward per second
     */
    function updateRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        _updatePool();
        rewardPerSecond = _rewardPerSecond;
        emit NewRewardPerSecond(_rewardPerSecond);
    }

    /*
     * @notice Update start timestamp
     * @dev Only callable by owner.
     * @param _startTimestamp: the start timestamp
     */
    function updateStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        require(startTimestamp > block.timestamp, "Mining has started");
        require(_startTimestamp > block.timestamp && _startTimestamp < endTimestamp, "Invalid timestamp");

        startTimestamp = _startTimestamp;
        lastRewardTimestamp = _startTimestamp;
        emit NewStartTimestamp(_startTimestamp);
    }

    function updateEndTimestamp(uint256 _endTimestamp) external onlyOwner {
        require(_endTimestamp > block.timestamp, "Invalid timestamp");

        _updatePool();
        endTimestamp = _endTimestamp;
        emit NewEndTimestamp(_endTimestamp);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        if (block.timestamp > lastRewardTimestamp && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 reward = multiplier * rewardPerSecond;
            uint256 adjustedTokenPerShare = accTokenPerShare + reward * PRECISION_FACTOR / stakedTokenSupply;
            return user.amount * adjustedTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        } else {
            return user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
        uint256 reward = multiplier * rewardPerSecond;
        accTokenPerShare = accTokenPerShare + reward * PRECISION_FACTOR / stakedTokenSupply;
        lastRewardTimestamp = block.timestamp;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= endTimestamp) {
            return _to - _from;
        } else if (_from >= endTimestamp) {
            return 0;
        } else {
            return endTimestamp - _from;
        }
    }
}
