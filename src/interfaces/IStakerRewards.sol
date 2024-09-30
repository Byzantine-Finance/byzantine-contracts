// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {


    // External functions
    function claimRewards(address _staker) external;
    function updateClaimInterval(uint256 _claimInterval) external;
    function updateUpkeepInterval(uint256 _upkeepInterval) external;
    function setForwarderAddress(address _forwarderAddress) external;

    // View functions
    function claimableRewards(address _staker) external view returns (uint256);
    function getAllocatableRewards() external view returns (uint256);
    function getClusterData(bytes32 _clusterId) external view returns (uint256, uint256, uint8);
    function getCheckpointData() external view returns (uint256, uint256);
    function getStakerData(address _staker) external view returns (uint256, uint256, uint256, uint256, bool);

    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();

    /// @notice Returned when the staker has claimed all the rewards or has no permission to claim rewards
    error RewardsClaimedOrNoPermission();

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

    /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
    error OnlyStrategyVaultManager();
}
