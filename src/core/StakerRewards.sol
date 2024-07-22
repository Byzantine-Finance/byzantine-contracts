// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IAuction.sol";


contract StakerRewards is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IStakerRewards {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    IStrategyModuleManager public immutable stratModManager;

    /// @notice StrategyModule contract
    IStrategyModule public immutable strategyModule;

    /// @notice Auction contract
    IAuction public immutable auction;

    uint256 internal constant _ONE_DAY = 1 days; 

    /* ============== STATE VARIABLES ============== */

    /// @notice Check if there is at least one staker
    bool _hasStakers;
    /// @notice Total of non consumed VCs in circulation 
    uint256 public totalVCs; 
    /// @notice Sum of all the strategy module rewards distributed at current timestamp but not yet claimed by the stakers
    uint256 public totalNotYetClaimedRewards; 

    /// @notice Data related to each staker
    struct StakerData {
        uint256 lastUpdateTime; // staking time or last claim time
        uint256 maxRewardDays; 
        uint256 claimedRewards;
    }
    /// @notice Staker address to its data
    mapping(address => StakerData) public stakers;

    /// @notice Global struct recording the last checkpoint details
    /// @dev Formula: dailyRewardsPerDV = allocableRewardsInContract / total_number_of_VCs_in_circulation
    struct RewardCheckpoint {
        uint256 startAt; 
        uint256 dailyRewardsPerDV; // latest average VC price per validator = stakers' daily rewards  
        uint256 clusterSize; 
    }
    RewardCheckpoint public rewardCheckpoint;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyModuleManager _stratModManager,
        IStrategyModule _strategyModule,
        IAuction _auction
    ) {
        stratModManager = _stratModManager;
        strategyModule = _strategyModule;
        auction = _auction;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives funds from the Escrow contract when the node operator wins the auction
     * @dev The funds are locked in the StakerRewards contract and are distributed to the stakers on a daily basis
     */
    receive() external payable {}

    /**
     * @notice Update the global reward checkpoint details
     * @param _newVCs Total VCs brought by the new DV
     * @dev Function triggered in 4 scenarios: precreation of DVs, creation of new DV by a staker, arrival of a new staker, rewards claimed by a staker.
     * If the checkpoint is updated due to the preCreateDVs function, the precreated DVs are batched and are considered as one checkpoint.
    */ 
    function updateCheckpoint(uint256 _newVCs, uint256 _numDVsPreCreated) public onlyOwner nonReentrant {   
        // Increase totalVCs
        totalVCs += _newVCs; 

        // If this is not the first checkpoint in the contract
        if (rewardCheckpoint.startAt != 0) {
            // Decreasing totalVCs by the number of VCs burnt from the previous checkpoint
            uint256 vcToBurn = _getElapsedDays(rewardCheckpoint.startAt) * rewardCheckpoint.clusterSize * _numDVsPreCreated;
            totalVCs -= vcToBurn;

            // If there are already stakers, update totalNotYetClaimedRewards by adding the rewards generated from the previous checkpoint
            if (_hasStakers) {
                _increaseTotalNotClaimedRewards();
            }
        }

        // Update the reward checkpoint
        rewardCheckpoint.dailyRewardsPerDV = getAllocatableRewards() / totalVCs * auction.clusterSize(); // rewards per validator (4 nodeOp, 4 VCs burnt/day)
        rewardCheckpoint.clusterSize = auction.clusterSize();
        rewardCheckpoint.startAt = block.timestamp;
    }

    /**
     * @notice Update the staker's data when a staker has staked 32 ETH
     * @param _staker Address of the staker
     * @param _maxRewardDays Maximum number of days the staker can claim rewards, which is also the smallest number of VC in the strategy module
    */ 
    /// TODO solve the problem where the staker has more than one strategy module
    function stakerJoined(address _staker, uint256 _maxRewardDays) public {
        // If this is the first staker in the contract, only update the timestamp of the checkpoint
        if (!_hasStakers) {
            _hasStakers = true;
            rewardCheckpoint.startAt = block.timestamp;
        } else {
            // If this is not the first staker in the contract, update the checkpoint. 1 = 1 DV
            updateCheckpoint(0, 1);
        }

        // Update the staker data
        StakerData storage staker = stakers[_staker];
        staker.lastUpdateTime = block.timestamp;
        staker.maxRewardDays = _maxRewardDays;
    }

    /**
     * @notice Staker claims rewards and receive rewards
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send the rewards to the staker
     * 2. Update totalNotYetClaimedRewards by decreasing the claimed rewards
     * 3. Update the node operators' reward counter
     * 4. Update the checkpoint data including updating totalVCs by burning the used VCs and upding AGAIN totalNotYetClaimedRewards by increasing by the        distributed rewards from the last checkpoint
     * 5. Update the staker data
    */ 
    function claimRewards() external {
        // Calculate the rewards and send them to the staker
        (uint256 rewards, uint256 elapsedDays) = _calculateRewards(msg.sender);
        (bool success,) = payable(msg.sender).call{value: rewards}("");
        if (!success) revert FailedToSendRewards();

        // Update totalNotYetClaimedRewards by subtracting the claimed rewards
        totalNotYetClaimedRewards -= rewards;

        // Update each node operator's reward counter
        _updateStratModVcCounter(msg.sender, rewardCheckpoint.clusterSize, elapsedDays);

        // Update the checkpoint data TODO: check again
        updateCheckpoint(0, rewardCheckpoint.numDVs);

        // Update the staker data
        StakerData storage staker = stakers[msg.sender];
        staker.lastUpdateTime = block.timestamp;
        staker.claimedRewards += rewards;

        // TODO: consider the situation where one of the staker has consumed all the VCs, and where 2/4 have consumed all the VCs
    }

    /**
    * @notice Calculate the locked rewards of the StakerRewards contract which can be distributed to stakers
    * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards 
    * This is used to calculate the correct total rewards in the contract that can be distributed to the stakers
    * The rewards related to the days that have elapsed between the last checkpoint and the current checkpoint cannot be distributed again to stakers
    */
    function getAllocatableRewards() public view returns(uint256) {
        return address(this).balance - totalNotYetClaimedRewards;
    }


    /* ============== INTERNAL FUNCTIONS ============== */

    /**
    * @notice Calculate the rewards for a staker
    * @param _staker The address of the staker
    * @dev Staker cannot claim rewards for more than maxRewardDays
    * @return The rewards for the staker and the number of days that the staker has claime rewards for
    */
    function _calculateRewards(address _staker) internal view returns(uint256, uint256) {
        StakerData storage staker = stakers[_staker];
        uint256 elapsedDays = _getElapsedDays(staker.lastUpdateTime);

        if (elapsedDays <= staker.maxRewardDays) {
            return (rewardCheckpoint.dailyRewardsPerDV * elapsedDays, elapsedDays);
        }
        // If the staker has claimed rewards for more than maxRewardDays, return the maximum rewards
        return (rewardCheckpoint.dailyRewardsPerDV * staker.maxRewardDays, staker.maxRewardDays);
    }

    /**
    * @notice Get the number of days that have elapsed between the last checkpoint and the current one
    * @param _lastTimestamp The timestamp of the last checkpoint or the last update time of the staker
    */
    function _getElapsedDays(uint256 _lastTimestamp) internal view returns(uint256) {
        return (block.timestamp - _lastTimestamp) / _ONE_DAY;
    }

    /**
    * @notice Increase the total not yet claimed rewards by adding the rewards between the last checkpoint and the current one
    * @dev The totalNotYetClaimedRewards should be updated when a staker claims rewards by substracting the rewards from it
    */
    function _increaseTotalNotClaimedRewards() internal {
        uint256 elapsedDays = _getElapsedDays(rewardCheckpoint.startAt);
        uint256 rewardsBetweenTwoPoints = rewardCheckpoint.dailyRewardsPerDV * elapsedDays;
        // Update the total distributed but not yet claimed rewards
        totalNotYetClaimedRewards += rewardsBetweenTwoPoints;
    }

    /**
    * @notice Update the VC counter of each node operator of all the strategy modules owned by a staker
    * @param _staker The address of the staker
    * @dev The function iterates through all the strategy modules owned by the staker and update the VC counter of each node operator
    */
    function _updateStratModVcCounter(address _staker, uint256 _clusterSize, uint256 _vcToBurn) internal {
        address[] memory stratMods = stratModManager.getStratMods(_staker);

        for (uint8 i; i < stratMods.length;) {
            IStrategyModule.Node[_clusterSize] memory nodes = IStrategyModule(stratMods[i]).getDVNodesDetails();

            for (uint8 j; j < _clusterSize;) {
                if (_vcToBurn > nodes[j].vcNumber) {
                    nodes[j].vcNumber = 0;
                    // TODO: kick the node operator out of the DV
                }
                nodes[j].vcNumber -= _vcToBurn; 

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}
