// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {AutomationCompatibleInterface} from "chainlink/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {AutomationBase} from "chainlink/v0.8/AutomationBase.sol";

import {IEigenPodManager} from "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "eigenlayer-contracts/interfaces/IEigenPod.sol";
import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import {IStrategyVaultETH} from "../interfaces/IStrategyVaultETH.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {BidInvestmentMock} from "../../test/mocks/BidInvestmentMock.sol";

// TODO: The oldest DV exists due to staker's voluntary exit: StratVaultETH should notify SR to update its numValidatorsInVault and cluster data.
// TODO: DV exits due to lack of VCs: make sure numValidators >= num32ETHStaked, otherwise no rewards to distribute or force staker to exit

contract StakerRewards is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AutomationCompatibleInterface,
    AutomationBase,
    IStakerRewards
{
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StratVaultManager contract
    IStrategyVaultManager public immutable stratVaultManager;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice Auction contract
    IAuction public immutable auction;

    /// @notice BidInvestment contract
    BidInvestmentMock public immutable bidInvestment;

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    uint32 private constant _ONE_DAY = 1 days;
    uint256 private constant _WAD = 1e18;
    uint256 private constant _GWEI_TO_WEI = 1e9;
    uint256 private constant _STAKED_BALANCE_RATE_SCALE = 1e4;

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
        IAuction _auction,
        BidInvestmentMock _bidInvestment,
        IEigenPodManager _eigenPodManager
    ) {
        stratVaultManager = _stratVaultManager;
        escrow = _escrow;
        auction = _auction;
        bidInvestment = _bidInvestment;
        eigenPodManager = _eigenPodManager;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    function initialize(address _initialOwner, uint256 _upkeepInterval) external initializer {
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
        upkeepInterval = _upkeepInterval;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives the paid bid prices from the Escrow contract 
     */
    receive() external payable {}

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
        // Get the total new VCs, the smallest VC and the cluster size of the new DV
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(_clusterId);
        (uint256 totalBidPrice, uint64 totalClusterVCs, uint32 smallestVC, uint8 clusterSize) = auction.getClusterMetrics(clusterDetails.nodes);

        // Get the staked ETH balance rate of the new DV
        VaultData storage vault = _vaults[_vaultAddr];
        uint16 stakedBalanceRate = _getStakedBalanceRate(_vaultAddr, clusterDetails.clusterPubKeyHash);

        // Create the cluster data for the new DV
        ClusterData storage cluster = _clusters[_clusterId];
        cluster.smallestVC = smallestVC;
        cluster.clusterSize = clusterSize;
        cluster.activeTime = block.timestamp;
        cluster.exitTimestamp = block.timestamp + cluster.smallestVC * _ONE_DAY;

        // Update the data between the previous checkpoint and the current one
        _handleCheckpointUpdates(_vaultAddr);

        // Update the data with new bid prices and VCs
        _checkpoint.totalActivedBids += totalBidPrice;
        _checkpoint.totalVCs += totalClusterVCs;
        _checkpoint.totalStakedBalanceRate += stakedBalanceRate;
        uint64 dailyConsumedVCs = stakedBalanceRate * clusterSize;
        _checkpoint.totalDailyConsumedVCs += dailyConsumedVCs;

        // Update the vault's accruedStakedBalanceRate and the lastUpdate timestamp
        vault.accruedStakedBalanceRate += stakedBalanceRate;
        vault.lastUpdate = block.timestamp;

        // Update the validator counter 
        clusterSize == 4 ? ++numValidators4 : ++numValidators7;

        // Update daily32EthBaseRewards
        _adjustDaily32EthBaseRewards();
    }

    /** 
     * @notice Function called by StratVaultETH when a staker exits the validator (unstake)
     * Send rewards to the vault and update the checkpoint 
     *    or send rewards to the vault and decrease the totalPendingRewards
     *    or update the checkpoint
     * @param _vaultAddr Address of the StratVaultETH
     */
    function withdrawCheckpoint(address _vaultAddr) external onlyStratVaultETH {
        // Update the data between the previous checkpoint and the current one
        _handleCheckpointUpdates(_vaultAddr);

        // Send the pending rewards from the BidInvestment contract to the vault
        bidInvestment.sendRewardsToVault(_vaultAddr, _vaults[_vaultAddr].pendingRewards);

        // Update daily32EthBaseRewards
        _adjustDaily32EthBaseRewards();
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
    function checkUpkeep(bytes memory /*checkData*/) public view override cannotExecute returns (bool upkeepNeeded, bytes memory performData) {
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

        // Stores the cluster IDs that need to exit
        bytes32[] memory listClusterIds = new bytes32[](counter);
        // Stores the remaining VCs to remove for each cluster after exit
        uint64[] memory remainingVCsToRemove = new uint64[](counter);
        // Stores the total bid prices that need to be sent back to Escrow for each cluster
        uint256[] memory totalBidsToEscrow = new uint256[](counter);
        // Stores the staked balance rate to remove for each cluster
        uint16[] memory totalStakedBalanceRateToRemove = new uint16[](counter);
        // Stores the daily consumed VCs to remove for each cluster
        uint64[] memory totalDailyConsumedVCsToRemove = new uint64[](counter);

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over the clusters again to set upkeepNeeded to true and prepare the performData
        for (uint256 i; i < stratVaults.length; ) {
            address stratVaultAddr = stratVaults[i];
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();

            for (uint256 j; j < clusterIds.length; ) {
                ClusterData memory cluster = _clusters[clusterIds[j]];

                if (cluster.exitTimestamp != 0 && cluster.exitTimestamp < block.timestamp) {
                    // Set the upkeepNeeded to true
                    upkeepNeeded = true;

                    // Store the clusterId to the array
                    listClusterIds[indexCounter] = clusterIds[j];

                    // Get the total number of VCs and the smallest VC number of the cluster
                    IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(clusterIds[j]);
                    (, uint64 totalClusterVCs, uint32 smallestVC, ) = auction.getClusterMetrics(clusterDetails.nodes);
                    
                    // Store the remaining VC number
                    remainingVCsToRemove[indexCounter] = totalClusterVCs - smallestVC * cluster.clusterSize;

                    // Calculate and store total bids to return to escrow
                    uint256 clusterBidsToEscrow;
                    for (uint8 k; k < clusterDetails.nodes.length; ) {
                        IAuction.BidDetails memory bidDetails = auction.getBidDetails(clusterDetails.nodes[k].bidId);
                        uint256 dailyVcPrice = _getDailyVcPrice(bidDetails.bidPrice, bidDetails.vcNumber);
                        uint256 leftVCs = bidDetails.vcNumber - smallestVC;
                        clusterBidsToEscrow += (dailyVcPrice * leftVCs);

                        unchecked {
                            ++k;
                        }
                    }
                    totalBidsToEscrow[indexCounter] = clusterBidsToEscrow;

                    // Store staked balance rate metrics
                    uint16 stakedBalanceRate = _getStakedBalanceRate(stratVaultAddr, clusterDetails.clusterPubKeyHash);
                    totalStakedBalanceRateToRemove[indexCounter] = stakedBalanceRate;
                    totalDailyConsumedVCsToRemove[indexCounter] = stakedBalanceRate * cluster.clusterSize;

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
            performData = abi.encode(
                listClusterIds, 
                remainingVCsToRemove,
                totalBidsToEscrow,
                totalStakedBalanceRateToRemove,
                totalDailyConsumedVCsToRemove
            );
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
       6. Recalculate the daily32EthBaseRewards if there are still clusters
     * @dev Revert if it is called by a non-forwarder address
    */
    function performUpkeep(bytes calldata performData) external override {
        if (msg.sender != forwarderAddress) revert NoPermissionToCallPerformUpkeep();
        lastPerformUpkeep = block.timestamp;

        // Update totalVCs and totalPendingRewards variables for the period from the last checkpoint to this checkpoint
        if (_hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)) {
            _updateVCsAndPendingRewards(0);
            _checkpoint.updateTime = block.timestamp;
        }

        // Decode arrays in performData
        (
            bytes32[] memory clusterIds,
            uint64[] memory remainingVCsToRemove,
            uint256[] memory totalBidsToEscrow,
            uint16[] memory totalStakedBalanceRateToRemove,
            uint64[] memory totalDailyConsumedVCsToRemove
        ) = abi.decode(performData, (bytes32[], uint64[], uint256[], uint16[], uint64[]));

        for (uint256 i; i < clusterIds.length; ) {
            ClusterData storage cluster = _clusters[clusterIds[i]];

            // Double check performData sent by checkUpkeep by checking if the current block timestamp becomes bigger than the exitTimestamp
            if (cluster.exitTimestamp != 0 && cluster.exitTimestamp < block.timestamp) {
                uint32 consumedVCs = cluster.smallestVC;

                // Subtract the consumed VC number for each node
                auction.updateNodeVCNumber(clusterIds[i], consumedVCs);
                // Update cluster data to 0
                cluster.smallestVC = 0;
                cluster.activeTime = 0;
                cluster.exitTimestamp = 0;
                // Decrease the number of validators
                cluster.clusterSize == 4 ? --numValidators4 : --numValidators7;

                // Send back remaining bid prices of exited DVs to the Escrow contract
                bidInvestment.sendBidsToEscrow(totalBidsToEscrow[i]);

                // Subtract the remaining VCs of the exited DVs from totalVCs
                if (_checkpoint.totalVCs < remainingVCsToRemove[i]) revert TotalVCsLessThanConsumedVCs();
                _checkpoint.totalVCs -= remainingVCsToRemove[i];

                // Update total staked balance rate and total daily consumed VCs
                _checkpoint.totalStakedBalanceRate -= totalStakedBalanceRateToRemove[i];
                _checkpoint.totalDailyConsumedVCs -= totalDailyConsumedVCsToRemove[i];
            }

            unchecked {
                ++i;
            }
        }

        // Update daily32EthBaseRewards based on the updated data
        if (numValidators4 + numValidators7 != 0) {
            _adjustDaily32EthBaseRewards();
        }
    }

    /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StratVaultManager
     */
    function setForwarderAddress(address _forwarderAddress) external onlyOwner {
        forwarderAddress = _forwarderAddress;
    }

    /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StratVaultManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external onlyOwner {
        upkeepInterval = _upkeepInterval;
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Get the pending rewards of a given vault
     * @param _vaultAddr Address of the StratVaultETH
     */
    function getVaultRewards(address _vaultAddr) external view returns (uint256) {
        VaultData storage vault = _vaults[_vaultAddr];
        uint256 rewardsSinceLastUpdate = _calculateRewardsSinceLastUpdate(vault.accruedStakedBalanceRate, vault.lastUpdate);
        return vault.pendingRewards + rewardsSinceLastUpdate;
    }

    /**
     * @notice Calculate the allocatable amount of ETH in the StakerRewards contract 
     * @dev The calculation of the daily32EthBaseRewards cannot take into account the rewards that were already distributed to the stakers.
     */
    function getAllocatableRewards() public view returns (uint256) {
        return _checkpoint.totalActivedBids - _checkpoint.totalPendingRewards;
    }

    /**
     * @notice Returns the cluster data of a given clusterId
     * @param _clusterId The ID of the cluster
     */
    function getClusterData(bytes32 _clusterId) external view returns (ClusterData memory) {
        return _clusters[_clusterId];
    }

    /**
     * @notice Returns the current checkpoint data
     */
    function getCheckpointData() external view returns (Checkpoint memory) {
        return _checkpoint;
    }

    /**
     * @notice Returns the last update timestamp and the number of active DVs of a given StratVaultETH
     * @param _vaultAddr Address of the StratVaultETH
     */
    function getVaultData(address _vaultAddr) external view returns (VaultData memory) {
        return _vaults[_vaultAddr];
    }

    /* ============== INTERNAL FUNCTIONS ============== */


    /**
     * @notice Calculate the pending rewards since last update of a given vault
     * @param _accruedStakedBalanceRate Accumulated staked balance rate of the vault
     * @param _vaultUpdateTime Last update time of the vault
     */
    function _calculateRewardsSinceLastUpdate(uint16 _accruedStakedBalanceRate, uint256 _vaultUpdateTime) private view returns (uint256) {
        uint256 elapsedDays = _getElapsedDays(_vaultUpdateTime);
        return (_checkpoint.daily32EthBaseRewards * elapsedDays * _accruedStakedBalanceRate) / _STAKED_BALANCE_RATE_SCALE;
    }

    /**
     * @notice Decrease totalVCs by the number of VCs used by the nodeOps since the previous checkpoint
     * and update totalPendingRewards by adding the distributed rewards since the previous checkpoint
     * @dev Rewards that were already sent to StratVaultETH should be subtracted from totalPendingRewards
     */
    function _updateVCsAndPendingRewards(uint256 _rewardsToVault) private nonReentrant {
        uint256 elapsedDays = _getElapsedDays(_checkpoint.updateTime);

        // Update totalVCs
        uint256 totalConsumedVCs = elapsedDays * _checkpoint.totalDailyConsumedVCs;
        if (_checkpoint.totalVCs < totalConsumedVCs) revert TotalVCsLessThanConsumedVCs();
        _checkpoint.totalVCs -= uint64(totalConsumedVCs);

        // Update totalPendingRewards
        uint256 distributedRewards = _checkpoint.daily32EthBaseRewards * elapsedDays * _checkpoint.totalStakedBalanceRate;
        if (_rewardsToVault == 0) {
            _checkpoint.totalPendingRewards += distributedRewards;
        } else {
            _checkpoint.totalPendingRewards = _checkpoint.totalPendingRewards + distributedRewards - _rewardsToVault;
        }
    }

    /**
     * @notice Calculate and update daily32EthBaseRewards based on new values
     * @dev Revert if there are no active DVs or if totalVCs is 0
     * @dev Checkpoint updateTime should be updated after calculation 
     */
    function _adjustDaily32EthBaseRewards() private nonReentrant {
        if (_checkpoint.totalVCs == 0) revert TotalVCsCannotBeZero();

        uint256 dailyUsedVCsPer32ETH = ((numValidators4 * 4 + numValidators7 * 7) * _WAD) / (numValidators4 + numValidators7);
        uint256 daily32EthBaseRewards = (getAllocatableRewards() / _checkpoint.totalVCs) * dailyUsedVCsPer32ETH / _WAD;
        _checkpoint.daily32EthBaseRewards = daily32EthBaseRewards;
        _checkpoint.updateTime = block.timestamp;
    }

    /**
     * @notice Get the number of days that have elapsed between the last checkpoint and the current one
     * @param _lastTimestamp can be Checkpoint's updateTime or StratVaultETH's lastUpdate
     */
    function _getElapsedDays(uint256 _lastTimestamp) private view returns (uint256) {
        if (_lastTimestamp == 0) revert InvalidTimestamp();
        return (block.timestamp - _lastTimestamp) / _ONE_DAY;
    }

    /**
     * @notice Get the daily VC price of a node
     * @param _bidPrice The bid price paid by the node
     * @param _vcNumber The VC number bought by the node
     */
    function _getDailyVcPrice(uint256 _bidPrice, uint32 _vcNumber) private pure returns(uint256) {
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

    /**
     * @notice Handle data updates between the previous checkpoint and the current one
     * @param _vaultAddr Address of the StratVaultETH
     */
    function _handleCheckpointUpdates(address _vaultAddr) private {
        VaultData storage vault = _vaults[_vaultAddr];
        uint16 accruedStakedBalanceRate = vault.accruedStakedBalanceRate;
        uint256 vaultUpdateTime = vault.lastUpdate;

        bool rewardUpdateNeeded = accruedStakedBalanceRate != 0 && _hasTimeElapsed(vaultUpdateTime, _ONE_DAY);
        bool hasValidators = numValidators4 + numValidators7 != 0;

        if (rewardUpdateNeeded) {
            // Store the pending rewards generated by the previous validator(s) in VaultData
            uint256 pendingRewards = _calculateRewardsSinceLastUpdate(accruedStakedBalanceRate, vaultUpdateTime);
            vault.pendingRewards += pendingRewards;

            // Update totalVCs and totalPendingRewards variables
            _updateVCsAndPendingRewards(pendingRewards);

        } else if (hasValidators) {
            // Update totalVCs and totalPendingRewards variables
            _updateVCsAndPendingRewards(0);
        }
    }

    /**
     * @notice Get the staked ETH balance rate of a given validator
     * @param _vaultAddr Address of the StratVaultETH
     * @param _clusterPubKeyHash The pubkey hash of the validator
     */
    function _getStakedBalanceRate(address _vaultAddr, bytes32 _clusterPubKeyHash) private view returns (uint16) {
        // Calculate the staked balance rate and add it up to accruedStakedBalanceRate
        IEigenPod eigenPod = eigenPodManager.ownerToPod(_vaultAddr);
        IEigenPod.ValidatorInfo memory validatorInfo = eigenPod.validatorPubkeyHashToInfo(_clusterPubKeyHash);

        return uint16((validatorInfo.restakedBalanceGwei * _GWEI_TO_WEI * _STAKED_BALANCE_RATE_SCALE) / 32 ether);
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