// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {

    /* ============== STATE VARIABLES ============== */

    /// @notice Checkpoint updated at every new event
    struct Checkpoint {
        uint256 updateTime;
        uint256 totalPendingRewards;
        uint256 dailyRewardsPer32ETH; // Daily rewards distributed for every 32ETH staked
        uint64 totalVCs;
    }

    /// @notice Record every cluster at dvCreationCheckpoint
    struct ClusterData {
        uint256 activeTime; // Timestamp of the activation of the cluster, becomes a validator
        uint256 exitTimestamp; // = activeTime + smallestVC * _ONE_DAY
        uint32 smallestVC; // Smallest number of VCs among the nodeOp of a cluster
        uint8 clusterSize;
    }

    /// @notice Record every StratVaultETH at dvActivationCheckpoint
    struct VaultData {
        uint256 lastUpdate;
        uint16 numValidatorsInVault;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Function called by StratVaultETH when a DV is activated to add a new checkpoint and update variables
     * @param _vaultAddr The address of the vault
     * @param _clusterId The ID of the cluster
     */
    function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external; 

    /** 
     * @notice Function called by StratVaultETH when a staker exits the validator (unstake)
     * @param _vaultAddr The address of the vault
     */
    function withdrawCheckpoint(address _vaultAddr) external;

    /**
     * @notice Function to update the upkeep interval
     * @param _upkeepInterval The new upkeep interval
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external;

    /**
     * @notice Function to set the forwarder address
     * @param _forwarderAddress The address of the forwarder
     */
    function setForwarderAddress(address _forwarderAddress) external;

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Calculate the pending rewards since last update
     * @param _vaultAddr Address of the StratVaultETH
     * @param _numDVs Number of validators in the vault
     * @dev Revert if the last update timestamp is 0
     */
    function calculateRewards(address _vaultAddr, uint256 _numDVs) external view returns (uint256);

    /**
     * @notice Calculate the allocatable amount of ETH in the StakerRewards contract 
     * @dev The calculation of the dailyRewardsPer32ETH cannot take into account the rewards that were already distributed to the stakers.
     */
    function getAllocatableRewards() external view returns (uint256);

    /**
     * @notice Returns the cluster data of a given clusterId
     * @param _clusterId The ID of the cluster
     */
    function getClusterData(bytes32 _clusterId) external view returns (ClusterData memory);

    /**
     * @notice Function to get the checkpoint data
     * @return The checkpoint data
     */
    function getCheckpointData() external view returns (Checkpoint memory);
    
    /**
     * @notice Function to get the vault data for a given vault address
     * @param _vaultAddr Address of the StratVaultETH
     */
    function getVaultData(address _vaultAddr) external view returns (VaultData memory);

    /* ============== ERRORS ============== */

    /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
    error OnlyStrategyVaultManager();

    /// @dev Error when unauthorized call to a function callable only by a StratVaultETH.
    error OnlyStratVaultETH();

    /// @dev Returned when the transfer of the rewards to the StratVaultETH failed
    error FailedToSendRewards();

    /// @dev Error when the bid price cannot be sent back to the escrow
    error FailedToSendBidsToEscrow();

    /// @dev Error when the timestamp is invalid
    error InvalidTimestamp();

    /// @dev Error when there are no active cluster in the StakerRewards contract
    error NoCreatedClusters();

    /// @dev Error when the total VC cannot be zero
    error TotalVCsCannotBeZero();

    /// @dev Error when the total VC is less than the consumed VC
    error TotalVCsLessThanConsumedVCs();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();

    /// @dev Error when performUpkeep() is not called by the Forwarder
    error NoPermissionToCallPerformUpkeep();
}
