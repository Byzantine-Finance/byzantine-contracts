// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {

    function updateCheckpoint(uint256 _newVCs, uint256 _numDVsPreCreated) external;

    function stakerJoined(address _staker, uint256 _maxRewardDays) external;

    function claimRewards() external;

    function getAllocatableRewards() external view returns(uint256);

    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();
}