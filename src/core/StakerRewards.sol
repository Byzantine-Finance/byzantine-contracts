// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

import {AutomationCompatibleInterface} from "chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {OwnerIsCreator} from "chainlink/v0.8/shared/access/OwnerIsCreator.sol";

import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IStrategyVaultManager.sol";
import "../interfaces/IStrategyVaultETH.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import {console} from "forge-std/console.sol";

// TODO: check nonReentrant modifier 

contract StakerRewards is
    Initializable,
    ReentrancyGuardUpgradeable,
    AutomationCompatibleInterface,
    OwnerIsCreator,
    IStakerRewards
{
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StratVaultManager contract
    IStrategyVaultManager public immutable stratVaultManager;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice Auction contract
    IAuction public immutable auction;

    uint32 internal constant _ONE_DAY = 1 days;
    uint256 private constant _WAD = 1e18;

    /* ============== STATE VARIABLES ============== */

    /// @notice Total of non consumed VCs at Checkpoint's `updateTime`, 1 VC consumed per day per nodeOp
    uint256 public totalVCs = 0;
    /// @notice Number of active DVs of size 4
    uint256 public numberDV4 = 0;
    /// @notice Number of active DVs of size 7
    uint256 public numberDV7 = 0;
    /// @notice Rewards distributed to stakers but not yet sent to StratVaultETH
    uint256 public totalPendingRewards = 0;

    /// @notice Address deployed by Chainlink at each registration of upkeep, it is the address that calls `performUpkeep`
    address public forwarderAddress;
    /// @notice Interval of time between two upkeeps
    uint256 public upkeepInterval;
    /// @notice Tracks the last upkeep performed
    uint256 public lastPerformUpkeep;

    /// @notice Checkpoint updated at every new event
    /// @dev dailyRewardsPer32ETH = `getAllocatableRewards` / totalVCs * totalDVs
    struct Checkpoint {
        uint256 updateTime;
        uint256 dailyRewardsPer32ETH; // Daily rewards distributed for every 32ETH staked
    }
    Checkpoint public checkpoint;

    /// @notice Cluster data
    struct ClusterData {
        uint32 smallestVC; // Smallest number of VCs among the nodeOp of a cluster
        uint256 exitTimestamp; // = block.timestamp + smallestVC * _ONE_DAY
        uint8 clusterSize;
    }
    /// @notice ClusterId => ClusterData
    mapping(bytes32 => ClusterData) public clusters;

    struct VaultData {
        uint256 lastUpdate;
        uint256 numActiveDVs;
    }
    /// @notice StratVaultETH address => VaultData
    mapping(address => VaultData) public vaults;

    /* ============== MODIFIERS ============== */

    modifier onlyStratVaultETH() {
        if (!stratVaultManager.isStratVaultETH(msg.sender)) revert OnlyStratVaultETH();
        _;
    }

    modifier onlyStratVaultManager() {
        if (msg.sender != address(stratVaultManager)) revert OnlyStrategyVaultManager();
        _;
    }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyVaultManager _stratVaultManager,
        IEscrow _escrow,
        IAuction _auction
    ) {
        stratVaultManager = _stratVaultManager;
        escrow = _escrow;
        auction = _auction;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(uint256 _upkeepInterval) external initializer {
        __ReentrancyGuard_init();
        upkeepInterval = _upkeepInterval;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives the paid bid prices from the Escrow contract 
     */
    receive() external payable {}

    /**
     * @notice Function called by StratVaultETH when a DV is created to add a new checkpoint and update variables
     * @param _clusterId The ID of the cluster
     */
    function dvCreationCheckpoint(bytes32 _clusterId) external onlyStratVaultETH {
        // Get the total new VCs, the smallest VC and the cluster size
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(_clusterId);
        IAuction.NodeDetails[] memory nodes = clusterDetails.nodes;
        (uint256 totalClusterVCs, uint32 smallestVC, uint8 clusterSize) = _getTotalAndSmallestVCs(nodes);

        // Update ClusterData
        ClusterData storage cluster = clusters[_clusterId];
        cluster.smallestVC = smallestVC;
        cluster.exitTimestamp = block.timestamp + smallestVC * _ONE_DAY;
        cluster.clusterSize = clusterSize;

        // Update variables and checkpoint
        totalVCs += totalClusterVCs;
        if (numberDV4 + numberDV7 > 0 && block.timestamp - checkpoint.updateTime > _ONE_DAY) {
            _removeConsumedVCs();
            _updatePendingRewards(0);
        }

        clusterSize == 4 ? ++numberDV4 : ++numberDV7;
        _updateCheckpoint();
    }

    /**
     * @notice Function called by StratVaultETH when a DV is activated to add a new checkpoint and update variables
     * @param _vaultAddr Address of the StratVaultETH
     */
    function dvActivationCheckpoint(address _vaultAddr) external onlyStratVaultETH {
        VaultData storage vault = vaults[_vaultAddr];

        if (vault.lastUpdate != 0) {
            uint256 pendingRewards = calculateRewards(_vaultAddr, vault.numActiveDVs);

            if (pendingRewards > 0) {
                (bool success, ) = payable(_vaultAddr).call{value: pendingRewards}("");
                if (!success) revert FailedToSendRewards();

                // Remove the rewards sent to StratVaultETH from totalPendingRewards
                _updatePendingRewards(pendingRewards);
                // Remove the consumed VCs if the checkpoint is not updated for a day
                if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
                    _removeConsumedVCs();
                }
                // Update the checkpoint
                _updateCheckpoint();
            }
        }

        vault.lastUpdate = block.timestamp;
        ++vault.numActiveDVs;
    }

    /** 
     * @notice Function called by StratVaultETH when a staker withdraws its rewards
     * @dev The function does the following actions:
     * 1. Calculate the last set of pending rewards and send them to the StratVaultETH
     * 2. Update variables and checkpoint if necessary
     */
    function withdrawPosRewards(address _vaultAddr) external onlyStratVaultETH {
        // Calculate the rewards and send them to the StratVaultETH
        VaultData storage vault = vaults[_vaultAddr];
        uint256 numActiveDVsInVault = vault.numActiveDVs;
        uint256 pendingRewards = calculateRewards(_vaultAddr, numActiveDVsInVault);

        if (pendingRewards > 0) {
            (bool success, ) = payable(_vaultAddr).call{value: pendingRewards}("");
            if (!success) revert FailedToSendRewards();

            // Remove the rewards sent to the StratVaultETH from totalPendingRewards
            _updatePendingRewards(pendingRewards);
            // Remove the consumed VCs and update Checkpoint
            if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
                _removeConsumedVCs();
            }
            // Update the checkpoint
            _updateCheckpoint();
            // Update the last update timestamp of the StratVaultETH
            vault.lastUpdate = block.timestamp;
        }
    }


    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Calculate the pending rewards since last update
     * @param _vaultAddr Address of the StratVaultETH
     * @dev Revert if the last update timestamp is 0
     */
    function calculateRewards(address _vaultAddr, uint256 _numDVs) public view returns (uint256) {
        VaultData storage vault = vaults[_vaultAddr];
        uint256 elapsedDays = _getElapsedDays(vault.lastUpdate);
        return checkpoint.dailyRewardsPer32ETH * elapsedDays * _numDVs;
    }

    /**
     * @notice Calculate the allocatable amount of ETH in the StakerRewards contract 
     * @dev The calculation of the dailyRewardsPer32ETH cannot take into account the rewards that were already distributed to the stakers.
     */
    function getAllocatableRewards() public view returns (uint256) {
        return address(this).balance - totalPendingRewards;
    }

    /**
     * @notice Returns the cluster data of a given clusterId
     */
    function getClusterData(bytes32 _clusterId) public view returns (uint256, uint256, uint8) {
        ClusterData memory cluster = clusters[_clusterId];
        return (
            cluster.smallestVC,
            cluster.exitTimestamp,
            cluster.clusterSize
        );
    }

    /**
     * @notice Returns the current checkpoint data
     */
    function getCheckpointData() public view returns (uint256, uint256) {
        return (checkpoint.updateTime, checkpoint.dailyRewardsPer32ETH);
    }

    /**
     * @notice Returns the last update timestamp and the number of active DVs of a given StratVaultETH
     */
    function getVaultData(address _vaultAddr) public view returns (uint256, uint256) {
        VaultData memory vault = vaults[_vaultAddr];
        return (vault.lastUpdate, vault.numActiveDVs);
    }

    /* ============== CHAINLINK AUTOMATION FUNCTIONS ============== */

    /**
     * @notice Function called at every block time by the Chainlink Automation Nodes to check if an active DV should exit
     * @return upkeepNeeded is true if the block timestamp is bigger than exitTimestamp of any strategy module
     * @return performData is not used to pass the encoded data from `checkData` to `performUpkeep`
     * @dev If `upkeepNeeded` returns `true`,  `performUpkeep` is called.
     * @dev This function doe not consume any gas and is simulated offchain.
     * @dev `checkData` is not used in our case.
     * @dev Revert if there is no DV
     * @dev Revert if the time interval since the last upkeep is less than the upkeep interval
     */
    function checkUpkeep(bytes memory /*checkData*/) public view override returns (bool upkeepNeeded, bytes memory performData) {
        if (numberDV4 == 0 && numberDV7 == 0) revert UpkeepNotNeeded();
        if (block.timestamp - lastPerformUpkeep < upkeepInterval)
            revert UpkeepNotNeeded();

        // Get the number of clusters requiring update
        address[] memory stratVaults = stratVaultManager.getAllStratVaultETHs();
        uint256 counter = 0;

        // Iterate over all the clusters that are registered in the StakerRewards contract so are active
        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();
            if (clusterIds.length == 0) continue;

            for (uint256 j; j < clusterIds.length; ) {  
                if (clusters[clusterIds[j]].exitTimestamp == 0) continue;
                ClusterData memory cluster = clusters[clusterIds[j]];

                if (cluster.exitTimestamp < block.timestamp) {
                    ++counter;
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Skip the second loop if counter is 0, skip the the next loop and no upkeep needed
        if (counter == 0) {
            return (false, "");
        }

        // Array of cluster IDs at the size of counter
        bytes32[] memory listClusterIds = new bytes32[](counter);
        // Total remaining VCs to remove
        uint256 remainingVCsToRemove;
        // Total bid prices to send back to Escrow contract
        uint256 totalBidsToEscrow;

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over the clusters again to set upkeepNeeded to true and prepare the performData
        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();

            for (uint256 j; j < clusterIds.length; ) {
                if (clusters[clusterIds[j]].exitTimestamp == 0) continue; 
                ClusterData memory cluster = clusters[clusterIds[j]];

                // Check if the current block timestamp becomes bigger than the exitTimestamp
                if (cluster.exitTimestamp < block.timestamp) {
                    // Set the upkeepNeeded to true
                    upkeepNeeded = true;
                    // Store the clusterId to the array
                    listClusterIds[indexCounter] = clusterIds[j];
                    // Get the total number of VCs and the smallest VC number of the cluster
                    IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(clusterIds[j]).nodes;
                    (uint256 totalClusterVCs, uint32 smallestVC, ) = _getTotalAndSmallestVCs(nodes);
                    // Add up the remaining VC number of each cluster
                    remainingVCsToRemove += (totalClusterVCs - smallestVC * cluster.clusterSize);
                    // Calculate the total remaining bid prices of each node
                    for (uint8 k; k < nodes.length; ) {
                        IAuction.BidDetails memory bidDetails = auction.getBidDetails(nodes[k].bidId);
                        uint256 dailyVcPrice = _getDailyVcPrice(bidDetails.bidPrice, bidDetails.vcNumber);
                        uint256 leftVCs = bidDetails.vcNumber - smallestVC;
                        totalBidsToEscrow += (dailyVcPrice * leftVCs);

                        unchecked {
                            ++k;
                        }
                    }

                    ++indexCounter;
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (!upkeepNeeded) {
            performData = ""; 
        } else {
            performData = abi.encode(listClusterIds, remainingVCsToRemove, totalBidsToEscrow);
        }

        return (upkeepNeeded, performData);
    }

    /**
     * @notice Function triggered by `checkUpkeep` to perform the upkeep onchain if `checkUpkeep` returns `true`
     * @param performData is the encoded data returned by `checkUpkeep` 
     * @dev This function does the following:
       1. Update lastPerformUpkeep to the current block timestamp
       2. Iterate over all the clusters and update the VC number of each node
       3. Update totalVCs and totalPendingRewards variables
       4. Add up the remaining VCs of all relevant clusters to be subtracted from totalVCs
       5. Send back the bid prices of the exited DVs to the Escrow contract
       6. Update the checkpoint data
     * @dev Revert if it is called by a non-forwarder address
    */
    function performUpkeep(bytes calldata performData) external override {
        // Double check that the upkeep is needed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) revert UpkeepNotNeeded();
        if (msg.sender != forwarderAddress)
            revert NoPermissionToCallPerformUpkeep();

        lastPerformUpkeep = block.timestamp;

        // Decode `performData` 
        (bytes32[] memory clusterIds, uint256 remainingVCsToRemove, uint256 totalBidsToEscrow) = abi.decode(performData, (bytes32[], uint256, uint256));

        uint256 numberDV4ToExit;
        uint256 numberDV7ToExit;
        
        for (uint256 i; i < clusterIds.length; ) {
            ClusterData storage cluster = clusters[clusterIds[i]];
            uint32 consumedVCs = cluster.smallestVC;

            // Subtract the consumed VC number for each node
            auction.updateNodeVCNumber(clusterIds[i], consumedVCs);
            // Add up the number of active DVs to exit
            cluster.clusterSize == 4 ? ++numberDV4ToExit : ++numberDV7ToExit;

            unchecked {
                ++i;
            }
        }
         
        (bool success, ) = payable(address(escrow)).call{value: totalBidsToEscrow}("");
        if (!success) revert FailedToSendBackBidPrice();

        // Update totalVCs and totalPendingRewards variables
        if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
            _removeConsumedVCs();
            _updatePendingRewards(0);
        }

        // Subtract the remaining VCs of the exited DVs from totalVCs
        totalVCs -= remainingVCsToRemove;
        // Decrease the number of DVs
        numberDV4 -= numberDV4ToExit;
        numberDV7 -= numberDV7ToExit;

        // Update the checkpoint data
        _updateCheckpoint();
    }

    /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StrategyModuleManager
     */
    function setForwarderAddress(address _forwarderAddress) external onlyStratVaultManager {
        forwarderAddress = _forwarderAddress;
    }

    /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StrategyModuleManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external onlyStratVaultManager {
        upkeepInterval = _upkeepInterval;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @notice Get the total number of VCs and the smallest VC number of a cluster
     * @param nodes The nodes of the cluster
     */
    function _getTotalAndSmallestVCs(IAuction.NodeDetails[] memory nodes) internal pure returns (uint256 totalClusterVCs, uint32 smallestVcNumber, uint8 clusterSize) {
        clusterSize = uint8(nodes.length);
        smallestVcNumber = nodes[0].currentVCNumber; 
        for (uint8 i; i < clusterSize;) {
            totalClusterVCs += nodes[i].currentVCNumber; 
            if (nodes[i].currentVCNumber < smallestVcNumber) {
                smallestVcNumber = nodes[i].currentVCNumber;
            }
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @notice Decrease totalVCs by the number of VCs used by the nodeOps since the previous checkpoint
     */
    function _removeConsumedVCs() internal nonReentrant {
        uint256 dailyConsumedVCs = numberDV4 * 4 + numberDV7 * 7;
        uint256 totalConsumedVCs = _getElapsedDays(checkpoint.updateTime) * dailyConsumedVCs;
        if (totalVCs < totalConsumedVCs) revert TotalVCsLessThanConsumedVCs();
        totalVCs -= totalConsumedVCs;
    }

    /**
     * @notice Update totalPendingRewards by adding the distributed rewards since the previous checkpoint
     * @dev Rewards that were already sent to StratVaultETH should be subtracted from totalPendingRewards
     */
    function _updatePendingRewards(uint256 _rewardsToVault) internal nonReentrant {
        uint256 elapsedDays = _getElapsedDays(checkpoint.updateTime);
        uint256 distributedRewards = checkpoint.dailyRewardsPer32ETH * elapsedDays * (numberDV4 + numberDV7);

        if (_rewardsToVault == 0) {
            totalPendingRewards += distributedRewards;
        } else {
            totalPendingRewards = totalPendingRewards + distributedRewards - _rewardsToVault;
        }
    }

    /**
     * @notice Update the checkpoint struct including calculating and updating dailyRewardsPer32ETH
     * @dev Revert if there are no active DVs or if totalVCs is 0
     */
    function _updateCheckpoint() internal nonReentrant {
        if (numberDV4 == 0 && numberDV7 == 0) revert NoActiveDVs();
        if (totalVCs == 0) revert TotalVCsCannotBeZero();

        uint256 consumedVCsPerDayPerValidator = ((numberDV4 * 4 + numberDV7 * 7) * _WAD) / (numberDV4 + numberDV7);
        uint256 dailyRewardsPer32ETH = (getAllocatableRewards() / totalVCs) * consumedVCsPerDayPerValidator / _WAD;
        checkpoint.dailyRewardsPer32ETH = dailyRewardsPer32ETH;
        checkpoint.updateTime = block.timestamp;
    }

    /**
     * @notice Get the number of days that have elapsed between the last checkpoint and the current one
     * @param _lastTimestamp can be Checkpoint's updateTime or StratVaultETH's lastUpdate
     */
    function _getElapsedDays(uint256 _lastTimestamp) internal view returns (uint256) {
        if (_lastTimestamp == 0) revert InvalidTimestamp();
        return (block.timestamp - _lastTimestamp) / _ONE_DAY;
    }

    /**
     * @notice Get the daily VC price of a node
     * @param _bidPrice The bid price paid by the node
     * @param _vcNumber The VC number bought by the node
     */
    function _getDailyVcPrice(uint256 _bidPrice, uint32 _vcNumber) internal pure returns(uint256) {
        return _bidPrice / _vcNumber;
    }
}