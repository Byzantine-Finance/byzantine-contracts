// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
// import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IAuction.sol";

contract StakerRewards is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IStakerRewards {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    IStrategyModuleManager public immutable stratModManager;

    /// @notice StrategyModule contract
    // IStrategyModule public immutable strategyModule;

    /// @notice Auction contract
    IAuction public immutable auction;

    uint256 internal constant _ONE_DAY = 1 days; 

    /* ============== STATE VARIABLES ============== */

    /// @notice Check if there is at least one staker
    bool _hasStakers;
    /// @notice Total of non consumed VCs in circulation: 1 VC consumed per day per NO 
    uint256 public totalVCs; 
    /// @notice Sum of all the strategy module rewards distributed at current timestamp but not yet claimed by the stakers
    uint256 public totalNotYetClaimedRewards; 
    /// @notice Locked amount related to the unused DVs
    uint256 public lockedAmount;
    /// @notice Number of stakers
    /// TODO: decreasing by 1 if the staker unstake or one of the nodeOp of the DV has consumed all the VCs
    uint256 public totalStakers;

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
        // IStrategyModule _strategyModule,
        IAuction _auction
    ) {
        stratModManager = _stratModManager;
        // strategyModule = _strategyModule;
        auction = _auction;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        address _initialOwner
    ) external initializer {
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives funds from the Escrow contract when the node operator wins the auction
     * @dev The funds are locked in the StakerRewards contract and are distributed to the stakers on a daily basis
     */
    receive() external payable {}

    /**
     * @notice Update the global reward checkpoint details when new DVs are pre-created or when a staker staked 32ETH
     * @param _newVCs Total VCs brought by the new DV
     * @param _numDVsPreCreated Number of DVs pre-created: can be 0 if no DV is pre-created
     * @dev Function triggered in 3 scenarios: precreation of DVs, creation of new DV by a staker, arrival of a new staker.
     * If the checkpoint is updated due to the preCreateDVs function, the precreated DVs are batched and are considered as one checkpoint.
     * The function does the following actions:
     * 1. Increase totalVCs by the number of VCs brought by the new DV
     * 2. If there is at least one staker has staked 32ETH, decrease totalVCs by the number of VCs consumed by all the stakers from the previous checkpoint
     * 3. If there is at least one staker has staked 32ETH, update totalNotYetClaimedRewards by adding the rewards distributed from the previous checkpoint
     * 4. Update dailyRewardsPerDV, clusterSize, timestamp
    */ 
    function updateCheckpoint(uint256 _newVCs, uint256 _numDVsPreCreated) public nonReentrant {   
        // Increase totalVCs
        totalVCs += _newVCs; 

        // If there is at least one staker has staked 32ETH 
        if (_hasStakers) {
            // Decreasing totalVCs by the number of VCs consumed by all the stakers from the previous checkpoint
            uint256 consumedVCs = _getElapsedDays(rewardCheckpoint.startAt) * rewardCheckpoint.clusterSize * _numDVsPreCreated * totalStakers;
            totalVCs -= consumedVCs;

            // Update totalNotYetClaimedRewards by adding the rewards generated from the previous checkpoint
            _increaseTotalNotClaimedRewards();
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
            rewardCheckpoint.startAt = block.timestamp;
        } else {
            // If this is not the first staker in the contract, update the checkpoint. 1 = 1 DV
            updateCheckpoint(0, 1);
        }

        // Update the staker data
        StakerData storage staker = stakers[_staker];
        staker.lastUpdateTime = block.timestamp;
        staker.maxRewardDays = _maxRewardDays;
        _hasStakers = true;
        totalStakers++;
    }

    /**
     * @notice Staker claims rewards and receive rewards
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send the rewards to the staker
     * 2. Update the node operators' reward counter
     * 3. Update the checkpoint data 
     * 4. Update the staker data
    */ 
    function claimRewards() public {
        // Calculate the rewards and send them to the staker
        (uint256 rewards, uint256 elapsedDays) = _calculateRewards(msg.sender);
        (bool success,) = payable(msg.sender).call{value: rewards}("");
        if (!success) revert FailedToSendRewards();

        // Update each node operator's reward counter
        _updateStratModVcCounter(msg.sender, elapsedDays);

        // Update the checkpoint data
        _updateCheckpointWhenClaim(rewards);

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
    * @notice Update the checkpoint data when a staker claims rewards
    * @param _rewardsClaimed Amount of rewards claimed by the staker
    * @dev The function does the following actions:
    * 1. Decreasing totalVCs by the number of VCs consumed by all the stakers from the previous checkpoint
    * 2. Update totalNotYetClaimedRewards by adding the rewards generated from the previous checkpoint
    * 3. Update totalNotYetClaimedRewards by subtracting the claimed rewards
    * 4. Update the new dailyRewardsPerDV and timestamp
    */
    function _updateCheckpointWhenClaim(uint256 _rewardsClaimed) internal {
        // Decreasing totalVCs by the number of VCs consumed by all the stakers from the previous checkpoint
        uint256 consumedVCs = _getElapsedDays(rewardCheckpoint.startAt) * rewardCheckpoint.clusterSize * totalStakers;
        totalVCs -= consumedVCs;

        // Update totalNotYetClaimedRewards by adding the rewards generated from the previous checkpoint
        _increaseTotalNotClaimedRewards();

        // Update totalNotYetClaimedRewards by subtracting the claimed rewards
        totalNotYetClaimedRewards -= _rewardsClaimed;

        // Update the reward checkpoint
        rewardCheckpoint.dailyRewardsPerDV = getAllocatableRewards() / totalVCs * rewardCheckpoint.clusterSize; // rewards per validator (4 nodeOp, 4 VCs burnt/day)
        rewardCheckpoint.startAt = block.timestamp;
    }

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
    * @notice Increase the total not yet claimed rewards by adding the rewards ditributed to all stakers between the last checkpoint and the current one
    * @dev The totalNotYetClaimedRewards should be updated when a staker claims rewards by substracting the rewards from it
    */
    function _increaseTotalNotClaimedRewards() internal {
        uint256 elapsedDays = _getElapsedDays(rewardCheckpoint.startAt);
        uint256 rewardsDistributed = rewardCheckpoint.dailyRewardsPerDV * elapsedDays * totalStakers;
        // Update the total distributed but not yet claimed rewards
        totalNotYetClaimedRewards += rewardsDistributed;
    }

    /**
    * @notice Update the VC counter of each node operator of all the strategy modules owned by a staker
    * @param _staker The address of the staker
    * @dev The function iterates through all the strategy modules owned by the staker and update the VC counter of each node operator
    */
    function _updateStratModVcCounter(address _staker, uint256 _consumedVCs) internal view {
        address[] memory stratMods = stratModManager.getStratMods(_staker);

        for (uint8 i; i < stratMods.length;) {
            IStrategyModule.Node[4] memory nodes = IStrategyModule(stratMods[i]).getDVNodesDetails();

            for (uint8 j; j < nodes.length;) {
                if (_consumedVCs > nodes[j].vcNumber) {
                    nodes[j].vcNumber = 0;
                    // TODO: kick the node operator out of the DV
                }
                nodes[j].vcNumber -= _consumedVCs; 

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function _calculateLockDvAmount() internal view returns(uint256) {
    }
}
