// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IStakerReward} from "../interfaces/IStakerReward.sol";
import "../interfaces/IStrategyModule.sol";


contract StakerReward is Initializable, OwnableUpgradeable, IStakerReward {

    uint256 internal constant _ONE_DAY = 1 days; 

    /// @notice The total amount of bid prices sent to this contract
    uint256 public totalBidPrices; 
    /// @notice The total amount of rewards claimed by stakers
    uint256 public totalRewardsClaimed;

    /// @notice Data related to each staker
    struct StakerData {
        uint256 lastUpdateTime; // staking time or last claim time
        uint256 arrivalCumulativeRewards; // the culative rewards of the checkpoint where the staker arrived + additional rewards from checkpoint to arrival day
        uint256 claimedRewards; 
    }
    /// @notice Staker address to its data
    mapping(address => StakerData) public stakers;

    /// @notice Global struct recording the last checkpoint details
    /// @dev Formula: dailyRewards = total_ETH_in_StakerRewards / total_number_of_VCs_in_circulation
    struct RewardCheckpoint {
        uint256 startAt; // timestamp of the DV created
        uint256 totalVCs;
        uint256 dailyRewards; // latest average VC price per node operator 
        uint256 clusterSize; 
    }
    RewardCheckpoint public rewardCheckpoint;

    /// @notice strategy module address to its rewards
    mapping(address => uint256) public rewardCounter;

    /**
     * @notice Fallback function which receives funds from the Escrow contract when the node operator wins the auction
     * @dev The funds are locked in the StakerReward contract and are distributed to the stakers
     */
    receive() external payable {}

    /**
     * @notice Update the reward checkpoint details 
     * @param _stratMod The address of the strategy module
     * @param _clusterSize The number of nodes in the cluster
     * @dev Function triggered every time a DV is created
     * @note /// @notice Staker to its owned StrategyModules 
    // mapping(address => address[]) public stakerToStratMods;
    */ 
    function updateCheckpoint(address _stratMod, uint256 _clusterSize) public onlyOwner {

        IStrategyModule.Node[_clusterSize] memory nodes = IStrategyModule(_stratMod).getDVNodesDetails();
        
        uint256 totalVCs = 0;
        for (uint256 i; i < _clusterSize;) {
            totalVCs += nodes[i].vcNumber;

            unchecked {
                ++i;
            }
        }

        // For the first checkpoint
        if (rewardCheckpoint.startAt == 0) {
            rewardCheckpoint.startAt = block.timestamp;
            rewardCheckpoint.dailyRewards = (address(this).balance + totalRewardsClaimed) / totalVCs * _clusterSize;
            rewardCheckpoint.totalVCs = totalVCs;
            rewardCheckpoint.clusterSize = _clusterSize;
            return; 
        }

        // For the subsequent checkpoints
        uint256 elapsedTime = (block.timestamp - rewardCheckpoint.startAt) / _ONE_DAY;
        rewardCheckpoint.dailyRewards = (address(this).balance + totalRewardsClaimed) / totalVCs * _clusterSize;
        rewardCheckpoint.totalVCs = totalVCs;
        rewardCheckpoint.clusterSize = _clusterSize;
        totalBidPrices += elapsedTime * rewardCheckpoint.dailyRewards * _clusterSize;
        rewardCheckpoint.startAt = block.timestamp;
    }

    function stakerJoined(address _staker) public {
        stakers[_staker].lastUpdateTime = block.timestamp;
        // cumulativ rewards of the latest checkpoint + additional rewards from checkpoint to arrival day
        stakers[_staker].arrivalCumulativeRewards = totalBidPrices + (rewardCheckpoint.dailyRewards * ((block.timestamp - rewarddCheckpoint.startAt) / _ONE_DAY));
    }

    function claimRewards() external {
        uint256 rewards = _calculateRewards(msg.sender);
        StakerData storage info = stakers[msg.sender];
        info.lastClaimTime = block.timestamp;
        info.claimedRewards += rewards;

        (bool success,) = payable(msg.sender).call{value: rewards}("");
        if (!success) revert FailedToSendRewards();
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _calculateRewards(address _staker) internal view returns(uint256) {
        StakerData storage info = stakers[_staker];

        uint256 rewardsBeforeLastCheckpoint = totalBidPrices - info.arrivalCumulativeRewards;
        uint256 rewardsAfterLastCheckpoint = rewardCheckpoint.dailyRewards * (block.timestamp - rewardCheckpoint.startAt);
        uint256 totalRewards = rewardsBeforeLastCheckpoint + rewardsAfterLastCheckpoint;
        uint256 availableRewards = totalRewards - info.claimedRewards;

        return availableRewards;
    }

}
