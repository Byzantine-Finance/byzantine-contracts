// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// TODO: need to import Chainlink functions here? 
interface IStakerRewards {

    /**
     * @notice Update the Checkpoint struct when new DVs are pre-created or a strategy module is deployed (= new staker)
     * @param _newVCs Total VCs brought by the new DV
     * @param _clusterSize Number of nodeOps in the cluster
     * @dev If the checkpoint is updated due to `preCreateDVs`, the DVs are batched and are considered as one checkpoint.
     * @dev The function does the following actions:
     * 1. Increase totalVCs by the number of VCs brought by the new DVs
     * 2. Update totalVCs and totalNotYetClaimedRewards variables if necessary
     * 3. Update the checkpoint data
    */ 
    function updateCheckpoint(uint256 _newVCs, uint256 _clusterSize) external;

    /**
     * @notice Update the Checkpoint and StratModData structs when a strategy module is deployed (becomes an active DV)
     * @param _stratModAddr Address of the strategy module
     * @param _smallestVCNumber Maximum number of days the owner of the stratMod can claim rewards 
     * @param _newVCs Number of VCs brought by the new DV precreated by the new staker if any, otherwise 0
     * @param _clusterSize Number of nodeOps in the cluster
     * @dev Revert if the strategy module has already been deployed
    */ 
    function strategyModuleDeployed(address _stratModAddr, uint256 _smallestVCNumber, uint256 _newVCs, uint256 _clusterSize) external;

    /**
     * @notice Function that allows the staker to claim rewards
     * @param _stratModAddr Address of the strategy module
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send them to the staker
     * 2. Update totalNotYetClaimedRewards 
     * 3. Update the checkpoint data and totalVCs if necessary
     * 4. Update the strategy module data
     * @dev Revert if last claim was within the last 4 days or the strategy module was deployed less than 4 days ago
    */ 
    function claimRewards(address _stratModAddr) external;

    /**
     * @notice Function that allows the staker to claim rewards
     * @param _stratModAddr Address of the strategy module
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send them to the staker
     * 2. Update totalNotYetClaimedRewards 
     * 3. Update the checkpoint data and totalVCs if necessary
     * 4. Update the strategy module data
     * @dev Revert if last claim was within the last 4 days or the strategy module was deployed less than 4 days ago
    */ 
    function calculateRewards(address _stratModAddr) external view returns(uint256);

    /**
    * @notice Update the claim interval 
    * @param _claimInterval New claim interval
    */
    function updateClaimInterval(uint256 _claimInterval) external;

    /**
    * @notice Calculate the amount of ETH in the contract that can be allocated to the stakers
    * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards 
    * @dev The calculation of the dailyRewardsPerDV cannot take into account the rewards that were already distributed to the stakers.
    */
    function getAllocatableRewards() external view returns(uint256);

    /**
     * @notice Returns the strategy module data of a given strategy module address
     */
    function getStratModData(address _stratModAddr) external view  returns(uint256, uint256, uint256, uint256, uint256);

    /**
    * @notice Returns the current checkpoint data
    */
    function getCheckpointData() external view returns(uint256, uint256, uint256);

     /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StrategyModuleManager
     */
    function setForwarderAddress(address _forwarderAddress) external;

     /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StrategyModuleManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external;



    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();

    /// @notice Returned when the staker has claimed all the rewards
    error AllRewardsHaveBeenClaimed();

    /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager or the StakerRewards contract.
    error OnlyStratModManagerOrStakerRewards();

    /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
    error OnlyStrategyModuleManager();

    /// @dev Returned when unauthorized call to a function only callable by the StrategyModule owner
    error NotStratModOwner();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();

    /// @dev Error when performUpkeep() is not called by the Forwarder
    error NoPermissionToCallPerformUpkeep();
}