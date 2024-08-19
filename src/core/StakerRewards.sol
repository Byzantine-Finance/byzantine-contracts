// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

import {AutomationCompatibleInterface} from "chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {OwnerIsCreator} from "chainlink/v0.8/shared/access/OwnerIsCreator.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IStrategyModule.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IByzNft.sol";
import {console} from "forge-std/console.sol";

contract StakerRewards is Initializable, ReentrancyGuardUpgradeable, AutomationCompatibleInterface, OwnerIsCreator, IStakerRewards {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    IStrategyModuleManager public immutable stratModManager;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Time in seconds for a day
    uint32 internal constant _ONE_DAY = 1 days; 

    /* ============== STATE VARIABLES ============== */
    
    /// @notice Total of non consumed VCs at the time of `startAt` (Checkpoint struct), 1 VC consumed per day per nodeOp 
    uint256 public totalVCs; 
    /// @notice Number of active DVs that are generating daily rewards
    uint256 public totalActiveDVs;  
    /// @notice Sum of all rewards distributed to stakers but not yet claimed by them
    uint256 public totalNotYetClaimedRewards;
    /// @notice Interval of rewards claim
    uint256 public claimInterval;

    /// @notice Address deployed by Chainlink at each registration of upkeep, it is the address that calls `performUpkeep`
    address public forwarderAddress;
    /// @notice Interval of time between two upkeeps
    uint256 public upkeepInterval; 
    /// @notice Tracks the last upkeep performed
    uint256 public lastUpkeepTimestamp; 

    /// @notice Global struct recording checkpoint data at each new event
    /// @dev dailyRewardsPerDV = `getAllocatableRewards` / totalVCs
    /// @dev The Checkpoint is not updated if `totalActiveDVs` is 0 at the time `claimRewards` or `performUpkeep` is called. 
    struct Checkpoint {
        uint256 startAt; 
        uint256 dailyRewardsPerDV; // Daily rewards distributed to each staker
        uint256 clusterSize; 
    }
    Checkpoint public checkpoint;

    /// @notice Strategy module data
    struct StratModData {
        uint256 lastUpdateTime; // Staking time or last claim time
        uint256 smallestVCNumber; // Maximum number of days the owner of the stratMod can claim rewards 
        uint256 exitTimestamp; // = block.timestamp + smallestVCNumber * _ONE_DAY
        uint256 remainingRewardsAtExit; // The remaining rewards available for claim after `performUpkeep` is invoked 
        uint256 claimPermission; // 1: claim permitted, 2: last time to claim, 3: claim denied
    }
    /// @notice Strategy module address => StratModData
    mapping(address => StratModData) public stratMods;

    /* ============== MODIFIERS ============== */

    modifier onlyStratModManagerOrStakerRewards() {
        if (msg.sender != address(stratModManager) && msg.sender != address(this)) revert OnlyStratModManagerOrStakerRewards();
        _;
    }

    modifier onlyStratModManager() {
        if (msg.sender != address(stratModManager)) revert OnlyStrategyModuleManager();
        _;
    }

    modifier onlyStratModOwner(address _owner, address _stratMod) {
        uint256 stratModNftId = IStrategyModule(_stratMod).stratModNftId();
        if (byzNft.ownerOf(stratModNftId) != _owner) revert NotStratModOwner();
        _;
    }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyModuleManager _stratModManager,
        IEscrow _escrow,
        IByzNft _byzNft
    ) {
        stratModManager = _stratModManager;
        escrow = _escrow;
        byzNft = _byzNft;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(uint256 _upkeepInterval, uint256 _claimInterval) external initializer {
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
     * @notice Update the Checkpoint struct when new DVs are pre-created or a strategy module is deployed (= new staker)
     * @param _newVCs Total VCs brought by the new DV
     * @param _clusterSize Number of nodeOps in the cluster
     * @dev If the checkpoint is updated due to `preCreateDVs`, the DVs are batched and are considered as one checkpoint.
     * @dev The function does the following actions:
     * 1. Increase totalVCs by the number of VCs brought by the new DVs
     * 2. Update totalVCs and totalNotYetClaimedRewards variables if necessary
     * 3. Update the checkpoint data
    */ 
    function updateCheckpoint(uint256 _newVCs, uint256 _clusterSize) public onlyStratModManagerOrStakerRewards {   
        // Increase totalVCs
        totalVCs += _newVCs;

        // If totalActiveDVs is not 0
        if (totalActiveDVs > 0 && block.timestamp - checkpoint.startAt > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs();
            _updateTotalNotClaimedRewards(0);
        }

        // Update the checkpoint
        _updateCheckpoint(_clusterSize);
    }

    /**
     * @notice Update the Checkpoint and StratModData structs when a strategy module is deployed (becomes an active DV)
     * @param _stratModAddr Address of the strategy module
     * @param _smallestVCNumber Maximum number of days the owner of the stratMod can claim rewards 
     * @param _newVCs Number of VCs brought by the new DV precreated by the new staker if any, otherwise 0
     * @param _clusterSize Number of nodeOps in the cluster
     * @dev Revert if the strategy module has already been deployed
    */ 
    function strategyModuleDeployed(address _stratModAddr, uint256 _smallestVCNumber, uint256 _newVCs, uint256 _clusterSize) public onlyStratModManager {
        StratModData storage stratMod = stratMods[_stratModAddr];
        require(stratMod.claimPermission == 0, "Strategy module already deployed");

        // If a DV is precreated OR if there is at least one active DV at joining time
        if (_newVCs != 0 || totalActiveDVs > 0) {
            updateCheckpoint(_newVCs, _clusterSize);
        } else {
            _updateCheckpoint(_clusterSize); 
        }

        stratMod.lastUpdateTime = block.timestamp;
        stratMod.smallestVCNumber = _smallestVCNumber;
        stratMod.exitTimestamp = block.timestamp + _smallestVCNumber * _ONE_DAY;
        stratMod.claimPermission = 1;
        ++totalActiveDVs;
    }

    /**
     * @notice Function that allows the staker to claim rewards
     * @param _stratModAddr Address of the strategy module
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send them to the staker
     * 2. Update totalNotYetClaimedRewards 
     * 3. Update the checkpoint data and totalVCs if necessary
     * 4. Update the strategy module data
     * @dev Revert if last claim was within the last 4 days or the strategy module was deployed less than 4 days ago
    */ 
    function claimRewards(address _stratModAddr) public onlyStratModOwner(msg.sender, _stratModAddr) {
        StratModData storage stratMod = stratMods[_stratModAddr];
        uint256 daysSinceLastUpdateTime = (block.timestamp - stratMod.lastUpdateTime) / 1 days;
        require(daysSinceLastUpdateTime >= claimInterval, "Claim interval or joining time less than 4 days"); 

        // Calculate the rewards and send them to the staker
        uint256 rewardsClaimed = calculateRewards(_stratModAddr);
        (bool success,) = payable(msg.sender).call{value: rewardsClaimed}("");
        if (!success) revert FailedToSendRewards();

        // Update totalNotYetClaimedRewards
        _updateTotalNotClaimedRewards(rewardsClaimed);

        // Remove the consumed VCs from totalVCs and update the checkpoint if totalActiveDVs is not 0 
        if (totalActiveDVs > 0 && block.timestamp - checkpoint.startAt > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs(); 
            _updateCheckpoint(checkpoint.clusterSize);
        }

        // Update the stretegy module data
        if (stratMod.claimPermission == 2) {
            stratMod.claimPermission = 3;
        }
        stratMod.lastUpdateTime = block.timestamp;
    }

    /**
    * @notice Update the claim interval 
    * @param _claimInterval New claim interval
    */
    function updateClaimInterval(uint256 _claimInterval) public onlyStratModManager {
        claimInterval = _claimInterval;
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
    * @notice Calculate the rewards for a staker
    * @param _stratModAddr Address of the strategy module
    * @dev Revert if all rewards have been claimed or if the staker calls the function after exitTimestamp and claimPermission is not 2
    * @dev The second check aims to ensure that `performUpkeep` has been called to exit the strategy module
    */
    function calculateRewards(address _stratModAddr) public view onlyStratModOwner(msg.sender, _stratModAddr) returns(uint256) {
        StratModData storage stratMod = stratMods[_stratModAddr];
        uint256 permission = stratMod.claimPermission;
        if (permission == 3) revert AllRewardsHaveBeenClaimed();
        if (block.timestamp > stratMod.exitTimestamp) {
            require(permission == 2, "Error regarding claim permission: please contact the team.");
        }

        if (permission == 1) {
            uint256 elapsedDays = _getElapsedDays(stratMod.lastUpdateTime);
            return checkpoint.dailyRewardsPerDV * elapsedDays;
        } else if (permission == 2) {
            return stratMod.remainingRewardsAtExit;
        }
    }

    /**
    * @notice Calculate the amount of ETH in the contract that can be allocated to the stakers
    * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards 
    * @dev The calculation of the dailyRewardsPerDV cannot take into account the rewards that were already distributed to the stakers.
    */
    /// TODO: is it ok to be viewed by anyone or access control needed?
    function getAllocatableRewards() public view returns(uint256) {
        return address(this).balance - totalNotYetClaimedRewards;
    }

    /**
     * @notice Returns the strategy module data of a given strategy module address
     */
    function getStratModData(address _stratModAddr) public view returns(uint256, uint256, uint256, uint256, uint256) {
        StratModData memory stratModData = stratMods[_stratModAddr];
        return (stratModData.lastUpdateTime, stratModData.smallestVCNumber, stratModData.exitTimestamp, stratModData.remainingRewardsAtExit, stratModData.claimPermission);
    }

    /**
    * @notice Returns the current checkpoint data
    */
    function getCheckpointData() public view returns(uint256, uint256, uint256) {
        return (checkpoint.startAt, checkpoint.dailyRewardsPerDV, checkpoint.clusterSize);
    }

    /* ============== CHAINLINK AUTOMATION FUNCTIONS ============== */

    /**
     * @notice Function called at every block time by the Chainlink Automation Nodes to check if an active DV should exit
     * @return upkeepNeeded is true if the block timestamp is bigger than exitTimestamp of any strategy module
     * @return performData is not used to pass the encoded data from `checkUpkeep` to `performUpkeep`  
     * @dev If `upkeepNeeded` returns `true`,  `performUpkeep` is called. 
     * @dev This function doe not consume any gas and is simulated offchain.
     * @dev `checkData` is not used in our case.
     * @dev Revert if totalActiveDVs is 0
     * @dev Revert if the time interval since the last upkeep is less than the upkeep interval
     */
    function checkUpkeep(bytes memory /* checkData */ ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        if (totalActiveDVs == 0) revert UpkeepNotNeeded();
        if (block.timestamp - lastUpkeepTimestamp < upkeepInterval) revert UpkeepNotNeeded();

        // Get the number of strategy modules requiring update
        uint256 numStratMods = stratModManager.numStratMods();
        uint256 counter;
        for (uint256 i; i < numStratMods;) {
            uint256 nftId = uint256(keccak256(abi.encode(i)));
            address stratModAddr = stratModManager.getStratModByNftId(nftId);
            StratModData storage stratMod = stratMods[stratModAddr];

            // For each strategy module, check if the current block timestamp is bigger than exitTimestamp
            if (stratMod.claimPermission == 1 && stratMod.exitTimestamp < block.timestamp) {
                ++counter;
            }

            unchecked {
                ++i;
            }
        }

        // Initialize array of addresses of strategy modules at the size of counter
        address[] memory stratModAddresses = new address[](counter);
        // Initialize array of VC numbers of each strategy module at the size of counter
        uint256[] memory stratModTotalVCs = new uint256[](counter);

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over all the strategy modules again to get the addresses of the strategy modules and set upkeepNeeded to true
        for (uint256 i; i < numStratMods;) {
            uint256 nftId = uint256(keccak256(abi.encode(i)));
            address stratModAddr = stratModManager.getStratModByNftId(nftId);
            StratModData storage stratMod = stratMods[stratModAddr];

            // For each strategy module, check if the current block timestamp is equal to the exitTimestamp
            if (stratMod.claimPermission == 1 && stratMod.exitTimestamp < block.timestamp) { 
                // If yes, set the upkeepNeeded to true
                upkeepNeeded = true;

                // Store the address of the strategy module to the array
                stratModAddresses[indexCounter] = stratModAddr;

                // Store the VC number of the strategy module to the array
                IStrategyModule.Node[4] memory nodes = IStrategyModule(stratModAddr).getDVNodesDetails();
                uint256 totalVcNumber;
                for (uint256 j; j < 4;) {
                    totalVcNumber += nodes[j].vcNumber;

                    unchecked {
                        ++j;
                    }
                }
                stratModTotalVCs[indexCounter] = totalVcNumber;

                ++indexCounter;
            }

            unchecked {
                ++i;
            }
        }
        
        performData = abi.encode(stratModAddresses, stratModTotalVCs);
        return (upkeepNeeded, performData); 
    }

    /**
     * @notice Function triggered by `checkUpkeep` to perform the upkeep onchain if `checkUpkeep` returns `true`
     * @param performData is the encoded data returned by `checkUpkeep` 
     * @dev This function does the following:
       1. Update lastUpkeepTimestamp to the current block timestamp
       2. Iterate over all the strategy modules and update the VC number of each node
       3. Update totalVCs and totalNotYetClaimedRewards variables
       4. Add up the remaining VCs of all relevant strategy modules to be subtracted from totalVCs
       5. TODO: Send back the bid prices of the exited DVs to the Escrow contract
       6. Update the checkpoint data
     * @dev Revert if it is called by a non-forwarder address
    */
    function performUpkeep(bytes calldata performData) external override {
        // Double check that the upkeep is needed
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) revert UpkeepNotNeeded();
        if (msg.sender != forwarderAddress) revert NoPermissionToCallPerformUpkeep();

        lastUpkeepTimestamp = block.timestamp;

        // Decode `performData` to get the strategy module addresses and their total VC number
        (address[] memory stratModAddresses, uint256[] memory stratModTotalVCs) = abi.decode(performData, (address[], uint256[]));

        uint256 remainingVCsToSubtract;
        uint256 numOfActiveDVsToExit;
        for (uint256 i; i < stratModAddresses.length;) {
            address stratModAddr = stratModAddresses[i];
            StratModData storage stratMod = stratMods[stratModAddr];
            uint256 consumedVCs = stratMod.smallestVCNumber;

            // Subtract the consumed VC number for each node
            IStrategyModule(stratModAddr).updateNodeVcNumber(consumedVCs);

            // Add up the remaining VCs of every strategy module
            remainingVCsToSubtract += (stratModTotalVCs[i] - consumedVCs * 4);
            // Add up the number of active DVs to exit
            ++numOfActiveDVsToExit;

            // Update claimPermission from 1 to 2
            stratMod.claimPermission = 2; 
            // Record the remaining rewards available for claim
            stratMod.remainingRewardsAtExit = checkpoint.dailyRewardsPerDV * ((stratMod.exitTimestamp - stratMod.lastUpdateTime) / _ONE_DAY);   

            unchecked {
                ++i;
            }
        }

        // Update totalVCs and totalNotYetClaimedRewards variables
        if (block.timestamp - checkpoint.startAt > _ONE_DAY) {
            _subtractConsumedVCsFromTotalVCs();
            _updateTotalNotClaimedRewards(0);
        }

        // Subtract the total remaining non-consumed VCs from totalVCs
        totalVCs -= remainingVCsToSubtract;
        // Decrease totalActiveDVs by 1 as the DV is no longer active
        totalActiveDVs -= numOfActiveDVsToExit;

        // Step 5 here

        // No need to update if totalActiveDVs is 0 as either precreation of new DVs or creation of a strategy module will do it
        if (totalActiveDVs > 0) {
            _updateCheckpoint(checkpoint.clusterSize);
        }
    }

     /**
     * @notice Set the address that `performUpkeep` is called from
     * @param _forwarderAddress The new address to set
     * @dev Only callable by the StrategyModuleManager
     */
    function setForwarderAddress(address _forwarderAddress) external  onlyStratModManager {
        forwarderAddress = _forwarderAddress;
    }

     /**
     * @notice Update upkeepInterval
     * @dev Only callable by the StrategyModuleManager
     * @param _upkeepInterval The new interval between upkeep calls
     */
    function updateUpkeepInterval(uint256 _upkeepInterval) external onlyStratModManager {
        upkeepInterval = _upkeepInterval;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
    * @notice Decrease totalVCs by the number of VCs consumed by all the stakers since the previous checkpoint
    * @dev This function is only called if totalActiveDVs is not 0.
    */
    function _subtractConsumedVCsFromTotalVCs() internal nonReentrant {
        uint256 consumedVCs = _getElapsedDays(checkpoint.startAt) * checkpoint.clusterSize * totalActiveDVs;
        totalVCs -= consumedVCs;
    }

    /**
    * @notice Update totalNotYetClaimedRewards by adding the rewards ditributed to all stakers since the previous checkpoint
    * @dev This function is only called if totalActiveDVs is not 0. 
    * @dev Rewards that were claimed by a staker should be subtracted from totalNotYetClaimedRewards.
    */
    function _updateTotalNotClaimedRewards(uint256 _rewardsClaimed) internal nonReentrant {
        uint256 elapsedDays = _getElapsedDays(checkpoint.startAt);
        uint256 rewardsDistributed = checkpoint.dailyRewardsPerDV * elapsedDays * totalActiveDVs;

        if (_rewardsClaimed == 0) {
            totalNotYetClaimedRewards += rewardsDistributed;
        } else {
            totalNotYetClaimedRewards = totalNotYetClaimedRewards + rewardsDistributed - _rewardsClaimed;
        }
    }

    /**
    * @notice Update the checkpoint struct including calculating and updating dailyRewardsPerDV
    * @param _clusterSize is the number of nodeOps in a cluster
    */
    function _updateCheckpoint(uint256 _clusterSize) internal nonReentrant {
        checkpoint.dailyRewardsPerDV = getAllocatableRewards() / totalVCs * _clusterSize; // rewards per validator (4 nodeOp = 4 VCs consumed/day)
        checkpoint.clusterSize = _clusterSize;
        checkpoint.startAt = block.timestamp;
    }

    /**
    * @notice Get the number of days that have elapsed between the last checkpoint and the current one
    * @param _lastTimestamp can be the last update time of Checkpoint or StratModData
    */
    function _getElapsedDays(uint256 _lastTimestamp) internal view returns(uint256) {
        return (block.timestamp - _lastTimestamp) / _ONE_DAY;
    }
}