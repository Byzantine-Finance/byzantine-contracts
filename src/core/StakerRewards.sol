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

contract StakerRewards is
    Initializable,
    ReentrancyGuardUpgradeable,
    AutomationCompatibleInterface,
    OwnerIsCreator,
    IStakerRewards
{
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    IStrategyVaultManager public immutable stratVaultManager;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Auction contract
    IAuction public immutable auction;

    /// @notice Time in seconds for a day
    uint32 internal constant _ONE_DAY = 1 days;

    /* ============== STATE VARIABLES ============== */

    /// @notice Total of non consumed VCs at Checkpoint's `updateTime`, 1 VC consumed per day per nodeOp
    uint256 public totalVCs;
    /// @notice Number of active DVs of size 4
    uint256 public numberDV4;
    /// @notice Number of active DVs of size 7
    uint256 public numberDV7;
    /// @notice Sum of all rewards distributed to stakers but not yet claimed by them
    uint256 public totalNotYetClaimedRewards;
    /// @notice Interval of rewards claim
    uint256 public claimInterval;

    /// @notice Address deployed by Chainlink at each registration of upkeep, it is the address that calls `performUpkeep`
    address public forwarderAddress;
    /// @notice Interval of time between two upkeeps
    uint256 public upkeepInterval;
    /// @notice Tracks the last upkeep performed
    uint256 public lastPerformUpkeep;

    /// @notice Checkpoint updated at every new event
    /// @dev dailyRewardsPer32ETH = `getAllocatableRewards` / totalVCs
    struct Checkpoint {
        uint256 updateTime;
        uint256 dailyRewardsPer32ETH; // Daily rewards distributed to each staker for every 32ETH staked
    }
    Checkpoint public checkpoint;

    /// @notice Cluster data
    struct ClusterData {
        uint32 smallestVC; // Maximum number of days the owner of the stratMod can claim rewards TODO: check if still needed
        uint256 exitTimestamp; // = block.timestamp + smallestVC * _ONE_DAY
        uint8 clusterSize;
    }
    /// @notice ClusterId => ClusterData
    mapping(bytes32 => ClusterData) public clusters;

    struct StakerData {
        uint256 updateTime; // When staking multiple of 32ETH
        uint256 lastClaim; //
        uint256 multipleOf32ETH; // Number of 32ETH staked
        uint256 rewardsToClaim; // In case a staker stake multiple of 32ETH at different moments, the rewards that are not yet claimed
        bool isExit; // if exit, no permission to claim
    }
    /// @notice Staker => StakerData
    mapping(address => StakerData) public stakers;

    /* ============== MODIFIERS ============== */

    // modifier onlyStratModManagerOrStakerRewards() {
    //     if (
    //         msg.sender != address(stratModManager) &&
    //         msg.sender != address(this)
    //     ) revert OnlyStratModManagerOrStakerRewards();
    //     _;
    // }

    modifier onlyStratVaultManager() {
        if (msg.sender != address(stratVaultManager)) revert OnlyStrategyVaultManager();
        _;
    }

    // modifier onlyStratModOwner(address _owner, address _stratMod) {
    //     uint256 stratModNftId = IStrategyModule(_stratMod).stratModNftId();
    //     if (byzNft.ownerOf(stratModNftId) != _owner) revert NotStratModOwner();
    //     _;
    // }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyVaultManager _stratVaultManager,
        IEscrow _escrow,
        IByzNft _byzNft,
        IAuction _auction
    ) {
        stratVaultManager = _stratVaultManager;
        escrow = _escrow;
        byzNft = _byzNft;
        auction = _auction;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        uint256 _upkeepInterval,
        uint256 _claimInterval
    ) external initializer {
        __ReentrancyGuard_init();
        upkeepInterval = _upkeepInterval;
        claimInterval = _claimInterval;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives the paid bid prices from the Escrow contract when the node operator wins the auction
     * @dev The funds are locked in the StakerRewards contract and are distributed to the stakers on a daily basis
     */
    receive() external payable {}

    /**
     * @notice Update the Checkpoint and StratModData structs when a strategy module is deployed (becomes an active DV)
     * @param _staker Address of the staker
     * @param _clusterId Id of the cluster
     * @dev Revert if the strategy module has already been deployed
     */
    function registerNativeStaking(
        address _staker,
        bytes32 _clusterId
    ) public onlyStratVaultManager {
        // Get the total number of new VCs, the smallest VC and the cluster size
        IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(_clusterId).nodes;
        (uint256 totalClusterVCs, uint32 smallestVC, uint8 clusterSize) = _getTotalAndSmallestVCs(nodes);

        // Update variables and checkpoint
        totalVCs += totalClusterVCs;
        if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs();
            _updateTotalNotClaimedRewards(0);
        }
        _updateCheckpoint();

        // Update DV counters
        clusterSize == 4 ? ++numberDV4 : ++numberDV7;

        // Update ClusterData
        ClusterData storage cluster = clusters[_clusterId];
        cluster.smallestVC = smallestVC;
        cluster.exitTimestamp = block.timestamp + smallestVC * _ONE_DAY;
        cluster.clusterSize = clusterSize;

        // Update StakerData
        StakerData storage staker = stakers[_staker];
        // If the staker has already staked 32 ETH, calculate the rewards until now
        if (staker.multipleOf32ETH > 0) {
            staker.rewardsToClaim = claimableRewards(_staker);
        }
        staker.updateTime = block.timestamp;
        ++staker.multipleOf32ETH;
    }

    /**
     * @notice Function that allows the staker to claim rewards
     * @dev The function does the following actions:
     * 1. Calculate the rewards and send them to the staker
     * 2. Update totalNotYetClaimedRewards
     * 3. Update the checkpoint data and totalVCs if necessary
     * 4. Update the strategy module data
     * @dev Revert if last claim was within the last 4 days or the strategy module was deployed less than 4 days ago
     */
    function claimRewards(
        address _staker
    ) public {
        StakerData storage staker = stakers[_staker];
        if (staker.isExit || staker.updateTime == 0) revert RewardsClaimedOrNoPermission();

        uint256 daysSinceLastClaim = (block.timestamp - staker.lastClaim) / _ONE_DAY;
        require(
            daysSinceLastClaim >= claimInterval,
            "Claim interval or joining time less than 4 days"
        );

        // Calculate the rewards and send them to the staker
        uint256 claimable = claimableRewards(_staker);
        (bool success, ) = payable(msg.sender).call{value: claimable}("");
        if (!success) revert FailedToSendRewards();

        // Update totalNotYetClaimedRewards
        _updateTotalNotClaimedRewards(claimable);

        // Remove the consumed VCs from totalVCs and update the checkpoint if totalActiveDVs is not 0
        if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs();
            _updateCheckpoint();
        }

        // Update stakerData
        staker.updateTime = block.timestamp;
        staker.lastClaim = block.timestamp;
    }

    /**
     * @notice Update the claim interval
     * @param _claimInterval New claim interval
     */
    function updateClaimInterval(
        uint256 _claimInterval
    ) public {
        claimInterval = _claimInterval;
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Calculate the rewards for a staker
     * @param _staker Address of the staker
     * @dev Revert if all rewards have been claimed or if the staker calls the function after exitTimestamp and claimPermission is not 2
     * @dev The second check aims to ensure that `performUpkeep` has been called to exit the strategy module
     */
    function claimableRewards(address _staker) public view returns (uint256) {
        StakerData storage staker = stakers[_staker];
        uint256 elapsedDays = _getElapsedDays(staker.updateTime);
        return checkpoint.dailyRewardsPer32ETH * elapsedDays * staker.multipleOf32ETH + staker.rewardsToClaim;
    }

    /**
     * @notice Calculate the amount of ETH in the contract that can be allocated to the stakers
     * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards
     * @dev The calculation of the dailyRewardsPer32ETH cannot take into account the rewards that were already distributed to the stakers.
     */
    function getAllocatableRewards() public view returns (uint256) {
        return address(this).balance - totalNotYetClaimedRewards;
    }

    /**
     * @notice Returns the strategy module data of a given strategy module address
     */
    function getClusterData(
        bytes32 _clusterId
    ) public view returns (uint256, uint256, uint8) {
        ClusterData memory clusterData = clusters[_clusterId];
        return (
            clusterData.smallestVC,
            clusterData.exitTimestamp,
            clusterData.clusterSize
        );
    }

    /**
     * @notice Returns the current checkpoint data
     */
    function getCheckpointData()
        public
        view
        returns (uint256, uint256)
    {
        return (
            checkpoint.updateTime,
            checkpoint.dailyRewardsPer32ETH
        );
    }

    function getStakerData(
        address _staker
    ) public view returns (uint256, uint256, uint256, uint256, bool) {
        StakerData memory staker = stakers[_staker];
        return (
            staker.updateTime,
            staker.lastClaim,
            staker.multipleOf32ETH,
            staker.rewardsToClaim,
            staker.isExit
        );
    }

    /* ============== CHAINLINK AUTOMATION FUNCTIONS ============== */

    /**
     * @notice Function called at every block time by the Chainlink Automation Nodes to check if an active DV should exit
     * @return upkeepNeeded is true if the block timestamp is bigger than exitTimestamp of any strategy module
     * @return performData is not used to pass the encoded data from `checkData` to `performUpkeep`
     * @dev If `upkeepNeeded` returns `true`,  `performUpkeep` is called.
     * @dev This function doe not consume any gas and is simulated offchain.
     * @dev `checkData` is not used in our case.
     * @dev Revert if totalActiveDVs is 0
     * @dev Revert if the time interval since the last upkeep is less than the upkeep interval
     */
    function checkUpkeep(bytes memory /*checkData*/) public view override returns (bool upkeepNeeded, bytes memory performData) {
        if (numberDV4 == 0 && numberDV7 == 0) revert UpkeepNotNeeded();
        if (block.timestamp - lastPerformUpkeep < upkeepInterval)
            revert UpkeepNotNeeded();

        // Get the number of strategy modules requiring update
        address[] memory stratVaults = stratVaultManager.getAllStratVaultETHs();
        uint256 counter;

        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();

            for (uint256 j; j < clusterIds.length; ) {  
                ClusterData memory clusterData = clusters[clusterIds[j]];
                if (clusterData.exitTimestamp < block.timestamp) {
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

        // Initialize array of addresses of strategy modules at the size of counter
        bytes32[] memory listClusterIds = new bytes32[](counter);
        // Initialize array of VC numbers of each strategy module at the size of counter
        uint256[] memory clusterTotalVCs = new uint256[](counter);

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over all the strategy modules again to get the addresses of the strategy modules and set upkeepNeeded to true
        for (uint256 i; i < stratVaults.length; ) {
            bytes32[] memory clusterIds = IStrategyVaultETH(stratVaults[i]).getAllDVIds();

            // For each strategy module, check if the current block timestamp is equal to the exitTimestamp
            for (uint256 j; j < clusterIds.length; ) {
                ClusterData memory clusterData = clusters[clusterIds[j]];

                if (clusterData.exitTimestamp < block.timestamp) {
                    // If yes, set the upkeepNeeded to true
                    upkeepNeeded = true;
                    // Store the address of the strategy module to the array
                    listClusterIds[indexCounter] = clusterIds[j];
                    // Store the VC number of the strategy module to the array
                    IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(clusterIds[j]).nodes;
                    (uint256 totalClusterVCs, uint256 smallestVC, uint8 clusterSize) = _getTotalAndSmallestVCs(nodes);
                    clusterTotalVCs[indexCounter] = totalClusterVCs;
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

        performData = abi.encode(listClusterIds, clusterTotalVCs);
        return (upkeepNeeded, performData);
    }

    /**
     * @notice Function triggered by `checkUpkeep` to perform the upkeep onchain if `checkUpkeep` returns `true`
     * @param performData is the encoded data returned by `checkUpkeep` 
     * @dev This function does the following:
       1. Update lastPerformUpkeep to the current block timestamp
       2. Iterate over all the strategy modules and update the VC number of each node
       3. Update totalVCs and totalNotYetClaimedRewards variables
       4. Add up the remaining VCs of all relevant strategy modules to be subtracted from totalVCs
       5. TODO: Send back the bid prices of the exited DVs to the Escrow contract
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

        // Decode `performData` to get the strategy module addresses and their total VC number
        (
            bytes32[] memory clusterIds,
            uint256[] memory clusterTotalVCs
        ) = abi.decode(performData, (bytes32[], uint256[]));

        uint256 remainingVCsToSubtract;
        uint256 numberDV4ToExit;
        uint256 numberDV7ToExit;
        for (uint256 i; i < clusterIds.length; ) {
            ClusterData storage cluster = clusters[clusterIds[i]];
            uint32 consumedVCs = cluster.smallestVC;

            // Subtract the consumed VC number for each node
            _updateNodeVcNumber(clusterIds[i], consumedVCs);

            // Add up the remaining VCs of every strategy module
            remainingVCsToSubtract += (clusterTotalVCs[i] - consumedVCs * cluster.clusterSize);
            // Add up the number of active DVs to exit
            cluster.clusterSize == 4 ? ++numberDV4ToExit : ++numberDV7ToExit;

            // Record the remaining rewards available for claim
            // TODO: assume that there is always new DV to replace the exited DV 
            // cluster.remainingRewardsAtExit =
            //     checkpoint.dailyRewardsPer32ETH *
            //     ((stratMod.exitTimestamp - stratMod.lastUpdateTime) / _ONE_DAY);

            unchecked {
                ++i;
            }
        }

        // Update totalVCs and totalNotYetClaimedRewards variables
        if (block.timestamp - checkpoint.updateTime > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs();
            _updateTotalNotClaimedRewards(0);
        }

        // Subtract the total remaining non-consumed VCs from totalVCs
        totalVCs -= remainingVCsToSubtract;
        // Decrease totalActiveDVs by 1 as the DV is no longer active
        numberDV4 -= numberDV4ToExit;
        numberDV7 -= numberDV7ToExit;

        // TODO: Step 5 here

        // Update the checkpoint data
        _updateCheckpoint();
    }

    /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StrategyModuleManager
     */
    function setForwarderAddress(
        address _forwarderAddress
    ) external onlyStratVaultManager {
        forwarderAddress = _forwarderAddress;
    }

    /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StrategyModuleManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(
        uint256 _upkeepInterval
    ) external onlyStratVaultManager {
        upkeepInterval = _upkeepInterval;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

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


    function _updateNodeVcNumber(bytes32 _clusterId, uint32 _smallestVC) internal view{
        IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(_clusterId).nodes;

        for (uint8 i; i < nodes.length;) {
            nodes[i].currentVCNumber = uint32(uint256(nodes[i].currentVCNumber)) - _smallestVC;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Decrease totalVCs by the number of VCs consumed by all the stakers since the previous checkpoint
     * @dev This function is only called if totalActiveDVs is not 0.
     */
    function _subtractConsumedVCsFromTotalVCs() internal nonReentrant {
        uint256 dailyConsumedVCs = numberDV4 * 4 + numberDV7 * 7;
        uint256 totalConsumedVCs = _getElapsedDays(checkpoint.updateTime) * dailyConsumedVCs;
        totalVCs -= totalConsumedVCs;
    }

    /**
     * @notice Update totalNotYetClaimedRewards by adding the rewards ditributed to all stakers since the previous checkpoint
     * @dev This function is only called if totalActiveDVs is not 0.
     * @dev Rewards that were claimed by a staker should be subtracted from totalNotYetClaimedRewards.
     */
    function _updateTotalNotClaimedRewards(
        uint256 _rewardsClaimed
    ) internal nonReentrant {
        uint256 elapsedDays = _getElapsedDays(checkpoint.updateTime);
        uint256 rewardsDistributed = checkpoint.dailyRewardsPer32ETH * elapsedDays * (numberDV4 + numberDV7);

        if (_rewardsClaimed == 0) {
            totalNotYetClaimedRewards += rewardsDistributed;
        } else {
            totalNotYetClaimedRewards = totalNotYetClaimedRewards + rewardsDistributed -_rewardsClaimed;
        }
    }

    /**
     * @notice Update the checkpoint struct including calculating and updating dailyRewardsPer32ETH
     */
    function _updateCheckpoint() internal nonReentrant {
        uint256 consumedVCsPerDayPerValidator = (numberDV4 * 4 + numberDV7 * 7) / (numberDV4 + numberDV7);
        checkpoint.dailyRewardsPer32ETH = (getAllocatableRewards() / totalVCs) * consumedVCsPerDayPerValidator;
        checkpoint.updateTime = block.timestamp;
    }

    /**
     * @notice Get the number of days that have elapsed between the last checkpoint and the current one
     * @param _lastTimestamp can be the last update time of Checkpoint or StratModData
     */
    function _getElapsedDays(
        uint256 _lastTimestamp
    ) internal view returns (uint256) {
        return (block.timestamp - _lastTimestamp) / _ONE_DAY;
    }

    function _getDailyVcPrice(uint256 _bidPrice, uint32 _vcNumber) internal pure returns(uint256) {
        return _bidPrice / _vcNumber;
    }
}