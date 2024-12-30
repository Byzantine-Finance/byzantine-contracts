// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {AutomationCompatibleInterface} from "chainlink/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {OwnerIsCreator} from "chainlink/v0.8/shared/access/OwnerIsCreator.sol";

import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import {IStrategyVaultETH} from "../interfaces/IStrategyVaultETH.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {console} from "forge-std/console.sol";

// TODO: 1. The oldest DV exists due to staker's voluntary exit: StratVaultETH should notify SR to update its numValidatorsInVault and cluster data.
// TODO: 2. DV exits due to lack of VCs: make sure numValidators >= num32ETHStaked, otherwise no rewards to distribute or force staker to exit

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

    /// @notice Interval of time between two upkeeps
    uint256 public upkeepInterval;
    /// @notice Tracks the last upkeep performed
    uint256 public lastPerformUpkeep;

    /// @notice Checkpoint updated at every new event
    Checkpoint internal _checkpoint;

    /// @notice ClusterId => ClusterData
    mapping(bytes32 => ClusterData) internal _clusters;

    /// @notice StratVaultETH address => VaultData
    mapping(address => VaultData) internal _vaults;

    /// @dev A cluster becomes a validator when it is activated with 32ETH
    /// @notice Number of created cluster of size 4
    uint16 public numClusters4;
    /// @notice Number of created cluster of size 7
    uint16 public numClusters7;
    /// @notice Number of validators of size 4
    uint16 public numValidators4;
    /// @notice Number of validators of size 7
    uint16 public numValidators7;

    /// @notice Address deployed by Chainlink at each registration of upkeep, it is the address that calls `performUpkeep`
    address public forwarderAddress;

    /**
    * @dev This empty reserved space is put in place to allow future versions to add new
    * variables without shifting down storage in the inheritance chain.
    * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
    */
    uint256[44] private __gap;

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
     * @notice Function called by StratVaultETH when a DV is created 
     * 1. Add a new cluster
     * 2. Update the checkpoint and cluster counter
     * @param _clusterId The ID of the cluster
     */
    function dvCreationCheckpoint(bytes32 _clusterId) external onlyStratVaultETH {
        // Get the total new VCs, the smallest VC and the cluster size
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(_clusterId);
        IAuction.NodeDetails[] memory nodes = clusterDetails.nodes;
        (uint64 totalClusterVCs, uint32 smallestVC, uint8 clusterSize) = _getTotalAndSmallestVCs(nodes);

        // Update ClusterData
        ClusterData storage cluster = _clusters[_clusterId];
        cluster.smallestVC = smallestVC;
        cluster.clusterSize = clusterSize;

        // Update checkpoint and cluster counter
        _checkpoint.totalVCs += totalClusterVCs;
        if (numValidators4 + numValidators7 > 0 
            && _hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            _updateVCsAndPendingRewards(0);
        }
        clusterSize == 4 ? ++numClusters4 : ++numClusters7;
        _adjustDailyRewards();
    }

    /**
     * @notice Function called by StratVaultETH when a DV is activated
     * 1. Send rewards to the vault and update the checkpoint 
     *    or send rewards to the vault and decrease the totalPendingRewards
     *    or update the checkpoint
     * 2. Update the timestamps and validator counter in any case 
     * 3. Update the cluster data
     * @param _vaultAddr Address of the StratVaultETH
     * @param _clusterId The ID of the cluster
     */
    function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external onlyStratVaultETH {
        VaultData storage vault = _vaults[_vaultAddr];
        uint256 numValsInVault = vault.numValidatorsInVault;

        // Ensure that there is at least one validator, and that both the vault's and the checkpoint's update times have elapsed by at least one day
        if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY) && _hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            // Send pending rewards to StratVaultETH
            uint256 rewardsToVault = _sendPendingRewards(_vaultAddr, numValsInVault);
            // Update global data 
            _updateVCsAndPendingRewards(rewardsToVault);
            _adjustDailyRewards();
        } else if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY)) {
            // Send pending rewards to StratVaultETH
            uint256 rewardsToVault = _sendPendingRewards(_vaultAddr, numValsInVault);
            // Only remove rewardsToVault from totalPendingRewards
            _updateVCsAndPendingRewards(rewardsToVault);
        } else if (numValidators4 + numValidators7 > 0 && _hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            _updateVCsAndPendingRewards(0);
            _adjustDailyRewards();
        }

        // Update Checkpoint updateTime and VaultData
        _checkpoint.updateTime = block.timestamp;
        vault.lastUpdate = block.timestamp;
        ++vault.numValidatorsInVault;

        // Update the cluster data
        ClusterData storage cluster = _clusters[_clusterId];
        cluster.activeTime = block.timestamp;
        cluster.exitTimestamp = block.timestamp + cluster.smallestVC * _ONE_DAY;
        cluster.clusterSize == 4 ? ++numValidators4 : ++numValidators7;
    }

    /** 
     * @notice Function called by StratVaultETH when a staker exits the validator (unstake)
     * Send rewards to the vault and update the checkpoint 
     *    or send rewards to the vault and decrease the totalPendingRewards
     *    or update the checkpoint
     * @param _vaultAddr Address of the StratVaultETH
     */
    function withdrawCheckpoint(address _vaultAddr) external onlyStratVaultETH {
        VaultData storage vault = _vaults[_vaultAddr];
        uint256 numValsInVault = vault.numValidatorsInVault;

        // Ensure that there is at least one validator, and that both the vault's and the checkpoint's update times have elapsed by at least one day
        if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY) && _hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            // Send pending rewards to StratVaultETH
            uint256 rewardsToVault = _sendPendingRewards(_vaultAddr, numValsInVault);
            // Update global data 
            _updateVCsAndPendingRewards(rewardsToVault);
            _adjustDailyRewards();
        } else if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY)) {
            // Send pending rewards to StratVaultETH
            uint256 rewardsToVault = _sendPendingRewards(_vaultAddr, numValsInVault);
            // Only remove rewardsToVault from totalPendingRewards
            _updateVCsAndPendingRewards(rewardsToVault);
        } else if (numValidators4 + numValidators7 > 0 && _hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            _updateVCsAndPendingRewards(0);
            _adjustDailyRewards();
        }
    }

    /* ============== CHAINLINK AUTOMATION FUNCTIONS ============== */

    /**
     * @notice Function called at every block time by the Chainlink Automation Nodes to check if an active DV should exit
     * @return upkeepNeeded is true if the block timestamp is bigger than exitTimestamp of any strategy module
     * @return performData contains the list of clusterIds that need to exit, their total remaining VCs to remove and their total bid prices to send back to Escrow contract
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
                ClusterData memory cluster = _clusters[clusterIds[j]];
                
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
        uint64 remainingVCsToRemove;
        // Total bid prices to send back to Escrow contract
        uint256 totalBidsToEscrow;

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over the clusters again to set upkeepNeeded to true and prepare the performData
        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();

            for (uint256 j; j < clusterIds.length; ) {
                ClusterData memory cluster = _clusters[clusterIds[j]];

                if (cluster.exitTimestamp != 0 && cluster.exitTimestamp < block.timestamp) {
                    // Set the upkeepNeeded to true
                    upkeepNeeded = true;
                    // Store the clusterId to the array
                    listClusterIds[indexCounter] = clusterIds[j];
                    // Get the total number of VCs and the smallest VC number of the cluster
                    IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(clusterIds[j]).nodes;
                    (uint64 totalClusterVCs, uint32 smallestVC, ) = _getTotalAndSmallestVCs(nodes);
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
       2. Update the VC number of each node, reset the cluster data to 0 and add up the total number of clusters4 and/or clusters7 to exit
       3. Send back the total bid prices of the exited DVs to the Escrow contract
       4. Update totalVCs and totalPendingRewards variables if necessary
       5. Remove the total remaining VCs of the exited DVs from totalVCs if any and decrease the number of clusters4 and/or clusters7
       6. Recalculate the dailyRewardsPer32ETH if there are still clusters
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
        (bytes32[] memory clusterIds, uint64 remainingVCsToRemove, uint256 totalBidsToEscrow) = abi.decode(performData, (bytes32[], uint64, uint256));

        uint16 numClusters4ToExit;
        uint16 numClusters7ToExit;
        
        for (uint256 i; i < clusterIds.length; ) {
            ClusterData storage cluster = _clusters[clusterIds[i]];
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
        if (_hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            _updateVCsAndPendingRewards(0);
            _checkpoint.updateTime = block.timestamp;
        }

        // Subtract the remaining VCs of the exited DVs from totalVCs
        if (_checkpoint.totalVCs < remainingVCsToRemove) revert TotalVCsLessThanConsumedVCs(); // TODO: can be removed if TODO2 mentioned above is fixed
        _checkpoint.totalVCs -= remainingVCsToRemove;
        // Decrease the number of DVs
        numClusters4 -= numClusters4ToExit;
        numClusters7 -= numClusters7ToExit;

        // Update the checkpoint data
        if (numClusters4 + numClusters7 != 0 && _checkpoint.totalVCs != 0) {
            _adjustDailyRewards();
        } 
    }

    /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StratVaultManager
     */
    function setForwarderAddress(address _forwarderAddress) external onlyStratVaultManager {
        forwarderAddress = _forwarderAddress;
    }

    /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StratVaultManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external onlyStratVaultManager {
        upkeepInterval = _upkeepInterval;
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Calculate the pending rewards since last update of a given vault 
     * @param _vaultAddr Address of the StratVaultETH
     * @param _numDVs Number of validators in the vault
     */
    function calculateRewards(address _vaultAddr, uint256 _numDVs) public view returns (uint256) {
        VaultData storage vault = _vaults[_vaultAddr];
        uint256 elapsedDays = _getElapsedDays(vault.lastUpdate);
        return _checkpoint.dailyRewardsPer32ETH * elapsedDays * _numDVs;
    }

    /**
     * @notice Calculate the allocatable amount of ETH in the StakerRewards contract 
     * @dev The calculation of the dailyRewardsPer32ETH cannot take into account the rewards that were already distributed to the stakers.
     */
    function getAllocatableRewards() public view returns (uint256) {
        return address(this).balance - _checkpoint.totalPendingRewards;
    }

    /**
     * @notice Returns the cluster data of a given clusterId
     * @param _clusterId The ID of the cluster
     */
    function getClusterData(bytes32 _clusterId) public view returns (ClusterData memory) {
        return _clusters[_clusterId];
    }

    /**
     * @notice Returns the current checkpoint data
     */
    function getCheckpointData() public view returns (Checkpoint memory) {
        return _checkpoint;
    }

    /**
     * @notice Returns the last update timestamp and the number of active DVs of a given StratVaultETH
     * @param _vaultAddr Address of the StratVaultETH
     */
    function getVaultData(address _vaultAddr) public view returns (VaultData memory) {
        return _vaults[_vaultAddr];
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @notice Send rewards to the StratVaultETH
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
    function _getTotalAndSmallestVCs(IAuction.NodeDetails[] memory nodes) internal pure returns (uint64 totalClusterVCs, uint32 smallestVcNumber, uint8 smallClusterSize) {
        uint256 bigClusterSize = nodes.length;
        smallestVcNumber = nodes[0].currentVCNumber; 
        totalClusterVCs = 0;
        for (uint256 i; i < bigClusterSize;) {
            totalClusterVCs += nodes[i].currentVCNumber; 
            if (nodes[i].currentVCNumber < smallestVcNumber) {
                smallestVcNumber = nodes[i].currentVCNumber;
            }
            unchecked {
                ++i;
            }
        }
        smallClusterSize = uint8(bigClusterSize);
    }
    
    /**
     * @notice Decrease totalVCs by the number of VCs used by the nodeOps since the previous checkpoint
     * and update totalPendingRewards by adding the distributed rewards since the previous checkpoint
     * @dev Rewards that were already sent to StratVaultETH should be subtracted from totalPendingRewards
     */
    function _updateVCsAndPendingRewards(uint256 _rewardsToVault) internal nonReentrant {
        // Calculate totalVCs
        uint256 dailyConsumedVCs = numValidators4 * 4 + numValidators7 * 7;
        uint256 totalConsumedVCs = _getElapsedDays(_checkpoint.updateTime) * dailyConsumedVCs;
        if (_checkpoint.totalVCs < totalConsumedVCs) revert TotalVCsLessThanConsumedVCs();
        _checkpoint.totalVCs -= uint64(totalConsumedVCs);

        // Update totalPendingRewards
        uint256 elapsedDays = _getElapsedDays(_checkpoint.updateTime);
        uint256 distributedRewards = _checkpoint.dailyRewardsPer32ETH * elapsedDays * (numValidators4 + numValidators7);
        if (_rewardsToVault == 0) {
            _checkpoint.totalPendingRewards += distributedRewards;
        } else {
            _checkpoint.totalPendingRewards = _checkpoint.totalPendingRewards + distributedRewards - _rewardsToVault;
        }
    }

    /**
     * @notice Update the checkpoint struct including calculating and updating dailyRewardsPer32ETH
     * @dev Revert if there are no active DVs or if totalVCs is 0
     */
    function _adjustDailyRewards() internal nonReentrant {
        if (numClusters4 + numClusters7 == 0) revert NoCreatedClusters();
        if (_checkpoint.totalVCs == 0) revert TotalVCsCannotBeZero();

        uint256 averageVCsUsedPerDayPerValidator = ((numClusters4 * 4 + numClusters7 * 7) * _WAD) / (numClusters4 + numClusters7);
        uint256 dailyRewardsPer32ETH = (getAllocatableRewards() / _checkpoint.totalVCs) * averageVCsUsedPerDayPerValidator / _WAD;
        _checkpoint.dailyRewardsPer32ETH = dailyRewardsPer32ETH;
        _checkpoint.updateTime = block.timestamp;
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

    /* ============== MODIFIERS ============== */

    modifier onlyStratVaultETH() {
        if (!stratVaultManager.isStratVaultETH(msg.sender)) revert OnlyStratVaultETH();
        _;
    }

    modifier onlyStratVaultManager() {
        if (msg.sender != address(stratVaultManager)) revert OnlyStrategyVaultManager();
        _;
    }
}