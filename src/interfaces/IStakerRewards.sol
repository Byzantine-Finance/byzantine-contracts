// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// TODO: need to import Chainlink functions here? 
interface IStakerRewards {

    function updateCheckpoint(uint256 _newVCs, uint256 _clusterSize) external;

    function stakerJoined(address _stratModAddr, uint256 _smallestVCNumber, uint256 _newVCs, uint256 _clusterSize) external;

    function claimRewards(address _stratModAddr) external;

    function calculateRewards(address _stratModAddr) external view returns(uint256);

    function getAllocatableRewards() external view returns(uint256);

    function getStratModData(address _stratModAddr) external view  returns(uint256, uint256, uint256, uint256);

    function getCheckpointData() external view returns(uint256, uint256, uint256);
    
    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();

    /// @notice Returned when failed to send Ether to the bid price receiver or to bidder
    error FailedToSendEther();

    /// @notice Returned when the staker has claimed all the rewards
    error AllRewardsHaveBeenClaimed();

    /// @notice Returned when the claimer has no strategy modules
    error NotEligibleToClaim();

    /// @notice Returned when the strategy module has already deployed 
    error StratModAlreadyExists();

    /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
    error OnlyStrategyModuleManager();

    /// @dev Returned when unauthorized call to a function only callable by the StrategyModule owner
    error NotStratModOwner();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();
}