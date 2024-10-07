// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

import {AutomationCompatibleInterface} from "chainlink/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {OwnerIsCreator} from "chainlink/v0.8/shared/access/OwnerIsCreator.sol";

import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import {IStrategyVaultETH} from "../interfaces/IStrategyVaultETH.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {console} from "forge-std/console.sol";

// TODO: 1. refactor Checkpoint struct and _updateCheckpoint() function, reorg functions
// TODO: 2. check nonReentrant modifiers are correctly used
// TODO: 3. oldest DV exists due to staker's voluntary exit: StratVaultETH should notify SR to update its numValidatorsInVault.
// TODO: 4. DV exit due to lack of VCs: make sure numValidators >= num32ETHStaked, otherwise no rewards to distribute or force staker to exit

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
    /// @notice Rewards distributed to stakers but not yet sent to StratVaultETH
    uint256 public totalPendingRewards = 0;

    /// @dev A cluster becomes a validator when it is activated
    /// @notice Number of created cluster of size 4
    uint256 public numClusters4 = 0;
    /// @notice Number of created cluster of size 7
    uint256 public numClusters7 = 0;
    /// @notice Number of validators of size 4
    uint256 public numValidators4 = 0;
    /// @notice Number of validators of size 7
    uint256 public numValidators7 = 0;

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
        uint256 activeTime; // Timestamp of the activation of the cluster
        uint32 smallestVC; // Smallest number of VCs among the nodeOp of a cluster
        uint256 exitTimestamp; // = activeTime + smallestVC * _ONE_DAY
        uint8 clusterSize;
    }
    /// @notice ClusterId => ClusterData
    mapping(bytes32 => ClusterData) public clusters;

    struct VaultData {
        uint256 lastUpdate;
        uint256 numValidatorsInVault;
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
        cluster.clusterSize = clusterSize;

        // Update variables and checkpoint
        totalVCs += totalClusterVCs;
        if (numValidators4 + numValidators7 > 0 
            && _hasTimeElapsed(checkpoint.updateTime, _ONE_DAY)) {
            _removeConsumedVCs();
            _updatePendingRewards(0);
        }

        clusterSize == 4 ? ++numClusters4 : ++numClusters7;
        _updateCheckpoint();
    }

    /**
     * @notice Function called by StratVaultETH when a DV is activated to add a new checkpoint and update variables
     * @param _vaultAddr Address of the StratVaultETH
     * @param _clusterId The ID of the cluster
     */
    function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external onlyStratVaultETH {
        VaultData storage vault = vaults[_vaultAddr];
        uint256 numValsInVault = vault.numValidatorsInVault;

        // Send the pending rewards to the StratVaultETH 
        if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY)) {
            uint256 pendingRewards = _sendPendingRewards(_vaultAddr, numValsInVault);
            _updatePendingRewards(pendingRewards);
        }

        // Update global data 
        if ((numValidators4 + numValidators7 > 0) && _hasTimeElapsed(checkpoint.updateTime, _ONE_DAY)) {
            _removeConsumedVCs();
            _updateCheckpoint();
        }

        // Update Checkpoint updateTime and VaultData
        checkpoint.updateTime = block.timestamp;
        vault.lastUpdate = block.timestamp;
        ++vault.numValidatorsInVault;

        // Update the cluster data
        ClusterData storage cluster = clusters[_clusterId];
        cluster.activeTime = block.timestamp;
        cluster.exitTimestamp = block.timestamp + cluster.smallestVC * _ONE_DAY;
        cluster.clusterSize == 4 ? ++numValidators4 : ++numValidators7;
    }

    /** 
     * @notice Function called by StratVaultETH when a staker withdraws rewards
     * @dev The function does the following actions:
     * 1. Calculate the last set of pending rewards and send them to the StratVaultETH
     * 2. Update variables and checkpoint if necessary
     */
    function withdrawCheckpoint(address _vaultAddr) external onlyStratVaultETH {
        VaultData storage vault = vaults[_vaultAddr];
        uint256 numValsInVault = vault.numValidatorsInVault;

        // Send the pending rewards to the StratVaultETH 
        if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY)) {
            uint256 pendingRewards = _sendPendingRewards(_vaultAddr, numValsInVault);
            _updatePendingRewards(pendingRewards);
        }

        // Update global data 
        if ((numValidators4 + numValidators7 > 0) && _hasTimeElapsed(checkpoint.updateTime, _ONE_DAY)) {
            _removeConsumedVCs();
            _updateCheckpoint();
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
    function getClusterData(bytes32 _clusterId) public view returns (uint256, uint256, uint256, uint8) {
        ClusterData memory cluster = clusters[_clusterId];
        return (
            cluster.activeTime,
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
        return (vault.lastUpdate, vault.numValidatorsInVault);
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
        if (numValidators4 + numValidators7 == 0) return (false, "");
        if (block.timestamp - lastPerformUpkeep < upkeepInterval) return (false, "");

        // Get the number of clusters requiring update
        address[] memory stratVaults = stratVaultManager.getAllStratVaultETHs();
        uint256 counter = 0;

        // Iterate over all the clusters that are registered in the StakerRewards contract so are active
        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();
            if (clusterIds.length == 0) continue;

            for (uint256 j; j < clusterIds.length; ) {
                ClusterData memory cluster = clusters[clusterIds[j]];
                
                // Check if the current block timestamp becomes bigger than the exitTimestamp
                if (cluster.exitTimestamp != 0 && cluster.exitTimestamp < block.timestamp) {
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
                ClusterData memory cluster = clusters[clusterIds[j]];

                if (cluster.exitTimestamp != 0 && cluster.exitTimestamp < block.timestamp) {
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

        uint256 numClusters4ToExit;
        uint256 numClusters7ToExit;
        
        for (uint256 i; i < clusterIds.length; ) {
            ClusterData storage cluster = clusters[clusterIds[i]];
            uint32 consumedVCs = cluster.smallestVC;

            // Subtract the consumed VC number for each node
            auction.updateNodeVCNumber(clusterIds[i], consumedVCs);
            // Update cluster data to 0
            cluster.smallestVC = 0;
            cluster.activeTime = 0;
            cluster.exitTimestamp = 0;
            // Add up the number of active DVs to exit
            cluster.clusterSize == 4 ? ++numClusters4ToExit : ++numClusters7ToExit;

            unchecked {
                ++i;
            }
        }
         
        (bool success, ) = payable(address(escrow)).call{value: totalBidsToEscrow}("");
        if (!success) revert FailedToSendBidsToEscrow();

        // Update totalVCs and totalPendingRewards variables
        if (_hasTimeElapsed(checkpoint.updateTime, _ONE_DAY)) {
            _removeConsumedVCs();
            _updatePendingRewards(0);
            checkpoint.updateTime = block.timestamp;
        }

        // Subtract the remaining VCs of the exited DVs from totalVCs
        if (totalVCs < remainingVCsToRemove) revert TotalVCsLessThanConsumedVCs(); // TODO: can be removed if TODO4 mentioned above is fixed
        totalVCs -= remainingVCsToRemove;
        // Decrease the number of DVs
        numClusters4 -= numClusters4ToExit;
        numClusters7 -= numClusters7ToExit;

        // Update the checkpoint data
        if (numClusters4 + numClusters7 != 0 && totalVCs != 0) {
            _updateCheckpoint();
        } 
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
     * @notice Send the pending rewards to the StratVaultETH
     * @param _vaultAddr Address of the StratVaultETH
     * @param _numDVs Number of validators in the vault
     */
    function _sendPendingRewards(address _vaultAddr, uint256 _numDVs) private returns (uint256) {
        uint256 pendingRewards = calculateRewards(_vaultAddr, _numDVs);
        (bool success, ) = payable(_vaultAddr).call{value: pendingRewards}("");
        if (!success) revert FailedToSendRewards();
        return pendingRewards;
    }

    /**
     * @notice Get the total number of VCs and the smallest VC number of a cluster
     * @param nodes The nodes of the cluster
     */
    function _getTotalAndSmallestVCs(IAuction.NodeDetails[] memory nodes) internal pure returns (uint256 totalClusterVCs, uint32 smallestVcNumber, uint8 clusterSize) {
        clusterSize = uint8(nodes.length);
        smallestVcNumber = nodes[0].currentVCNumber; 
        totalClusterVCs = 0;
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
        uint256 dailyConsumedVCs = numValidators4 * 4 + numValidators7 * 7;
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
        uint256 distributedRewards = checkpoint.dailyRewardsPer32ETH * elapsedDays * (numValidators4 + numValidators7);

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
        if (numClusters4 + numClusters7 == 0) revert NoCreatedClusters();
        if (totalVCs == 0) revert TotalVCsCannotBeZero();

        uint256 averageVCsUsedPerDayPerValidator = ((numClusters4 * 4 + numClusters7 * 7) * _WAD) / (numClusters4 + numClusters7);
        uint256 dailyRewardsPer32ETH = (getAllocatableRewards() / totalVCs) * averageVCsUsedPerDayPerValidator / _WAD;
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

    /**
     * @notice Check if the time elapsed since the last update is greater than the given time
     * @param _lastTimestamp The last update time
     * @param _elapsedTime The time elapsed
     */
    function _hasTimeElapsed(uint256 _lastTimestamp, uint256 _elapsedTime) private view returns (bool) {
        return block.timestamp - _lastTimestamp >= _elapsedTime;
    }
}