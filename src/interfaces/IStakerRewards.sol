// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {

    function updateCheckpoint(uint256 _newVCs, uint256 _numDVsPreCreated) external;

    function stakerJoined(address _stratModAddr, uint256 _rewardDaysCap, uint256 _newVCs) external;

    function claimRewards(address _stratModAddr) external;

    function calculateRewards(address _stratModAddr) external view returns(uint256, uint256);

    function getAllocatableRewards() external view returns(uint256);

    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();
}