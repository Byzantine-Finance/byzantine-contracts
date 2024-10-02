// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {
    // External functions
    function registerNativeStaking(address _vaultAddr, bytes32 _clusterId) external;
    function withdrawPosRewards(address _vaultAddr) external;
    function updateUpkeepInterval(uint256 _upkeepInterval) external;
    function setForwarderAddress(address _forwarderAddress) external;

    // View functions
    function calculateRewards(
        address _vaultAddr,
        uint256 _numDVs
    ) external view returns (uint256);
    function getAllocatableRewards() external view returns (uint256);
    function getClusterData(
        bytes32 _clusterId
    ) external view returns (uint256, uint256, uint8);
    function getCheckpointData() external view returns (uint256, uint256);

    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();

    /// @notice Returned when the staker has claimed all the rewards or has no permission to claim rewards
    error NoRewardsToClaim();

    /// @dev Returned when unauthorized call to a function only callable by the StrategyModule owner
    error NotStratModOwner();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();

    /// @dev Error when performUpkeep() is not called by the Forwarder
    error NoPermissionToCallPerformUpkeep();

    /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
    error OnlyStrategyVaultManager();

    /// @dev Error when unauthorized call to a function callable only by a StratVaultETH.
    error OnlyStratVaultETH();

    /// @dev Error when the bid price cannot be sent back to the escrow
    error FailedToSendBackBidPrice();

    /// @dev Error when the staker tries to withdraw more than the staked amount
    error WithdrawMoreThanStaked();

    /// @dev Error when the timestamp is invalid
    error InvalidTimestamp();

    /// @dev Error when unauthorized call to a function callable only by a Strategy Vault.
    error OnlyStrategyVault();

    /// @dev Error when there are no active DVs
    error NoActiveDVs();

    /// @dev Error when the total VC cannot be zero
    error TotalVCsCannotBeZero();
}
