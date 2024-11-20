// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerRewards {

    /* ============== STATE VARIABLES ============== */

    /// @notice Checkpoint updated at every new event
    struct Checkpoint {
        uint256 updateTime;
        uint256 totalActivedBids; // Used to record the total bid prices of the activated DVs
        uint256 totalPendingRewards;
        uint256 daily32EthBaseRewards; // Amount of daily rewards distributed to every 32ETH staked
        uint64 totalVCs;
        uint64 totalDailyConsumedVCs; // Total number of VCs that is supposed to be consumed by the validators on a daily basis
        uint24 totalStakedBalanceRate; // The accrued staked balance rate that represents the total amount of ETH staked (the rate of 1 = 32 ETH)
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
        uint16 accruedStakedBalanceRate;
        uint256 pendingRewards;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Function called by StratVaultETH when activating a cluster to create a new checkpoint
     * 1. Create the cluster data * 2. Update the checkpoint data * 3. Create or update the vault data
     * 4. Update the validator counter * 5. Update daily32EthBaseRewards
     * @param _vaultAddr Address of the StratVaultETH
     * @param _clusterId The ID of the cluster
     * @dev Revert if called by non-StratVaultETH
     */
    function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external; 

    /** 
     * @notice Function called by StratVaultETH when a staker decides to withdraw the rewards
     * 1. Update the checkpoint data
     * 2. Send the pending rewards from the BidInvestment contract to the vault
     * 3. Update daily32EthBaseRewards
     * @param _vaultAddr Address of the StratVaultETH
     * @dev Revert if called by non-StratVaultETH
     */
    function withdrawalCheckpoint(address _vaultAddr) external;

    /**
     * @notice Update upkeepInterval
     * @dev Only callable by the byzantineAdmin address
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external;

    /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the byzantineAdmin address
     */
    function setForwarderAddress(address _forwarderAddress) external;

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Get the pending rewards of a given vault
     * @param _vaultAddr Address of the StratVaultETH
     */
    function getVaultRewards(address _vaultAddr) external view returns (uint256);

    /**
     * @notice Calculate the allocatable amount of ETH in the StakerRewards contract 
     * @dev The calculation of the daily32EthBaseRewards cannot take into account the rewards that were already distributed to the stakers.
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

    /// @dev Error when unauthorized call to a function callable only by a StratVaultETH.
    error OnlyStratVaultETH();

    /// @dev Returned when the transfer of the rewards to the StratVaultETH failed
    error FailedToSendRewards();

    /// @dev Error when the bid price cannot be sent back to the escrow
    error FailedToSendBidsToEscrow();

    /// @dev Error when the timestamp is invalid
    error InvalidTimestamp();

    /// @dev Error when the total VC cannot be zero
    error TotalVCsCannotBeZero();

    /// @dev Error when the total VC is less than the consumed VC
    error TotalVCsLessThanConsumedVCs();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();

    /// @dev Error when performUpkeep() is not called by the Forwarder
    error NoPermissionToCallPerformUpkeep();
}
