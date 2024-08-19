// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {AutomationCompatibleInterface} from "chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "./StrategyModuleMock.sol";
import "./StratModManagerMock.sol";
import {console} from "forge-std/console.sol";

/// @dev To simplify the Chainlik Upkeep App testing without the need to wait for days, all secondes are considered days in this mock
contract StakerRewardsMock is AutomationCompatibleInterface {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    StratModManagerMock public immutable stratModManager;

    /* ============== STATE VARIABLES ============== */

    /// @notice Total of non consumed VCs at the time of `startAt` (Checkpoint struct), 1 VC consumed per day per nodeOp 
    uint256 public totalVCs; 
    /// @notice Number of active DVs that are generating daily rewards
    uint256 public totalActiveDVs;  
    /// @notice Sum of all rewards distributed to stakers but not yet claimed by them
    uint256 public totalNotYetClaimedRewards;

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

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    constructor(
        StratModManagerMock _stratModManager,
        uint256 _upkeepInterval
    ) {
        stratModManager = _stratModManager;
        upkeepInterval = _upkeepInterval;
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
    function updateCheckpoint(uint256 _newVCs, uint256 _clusterSize) public {   
        // Increase totalVCs
        totalVCs += _newVCs;

        // If totalActiveDVs is not 0
        if (totalActiveDVs > 0) {
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
    function strategyModuleDeployed(address _stratModAddr, uint256 _smallestVCNumber, uint256 _newVCs, uint256 _clusterSize) public {
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
        stratMod.exitTimestamp = block.timestamp + _smallestVCNumber; // Simplified version of block.timestamp + _smallestVCNumber * _ONE_DAY for mock testing
        stratMod.claimPermission = 1;
        ++totalActiveDVs;
    }

    /**
    * @notice Calculate the amount of ETH in the contract that can be allocated to the stakers
    * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards 
    * @dev The calculation of the dailyRewardsPerDV cannot take into account the rewards that were already distributed to the stakers.
    */
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
                StrategyModuleMock.Node[4] memory nodes = StrategyModuleMock(stratModAddr).getDVNodesDetails();
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
            StrategyModuleMock(stratModAddr).updateNodeVcNumber(consumedVCs);

            // Add up the remaining VCs of every strategy module
            remainingVCsToSubtract += (stratModTotalVCs[i] - consumedVCs * 4);
            // Add up the number of active DVs to exit
            ++numOfActiveDVsToExit;

            // Update claimPermission from 1 to 2
            stratMod.claimPermission = 2; 
            // Record the remaining rewards available for claim
            stratMod.remainingRewardsAtExit = checkpoint.dailyRewardsPerDV * (stratMod.exitTimestamp - stratMod.lastUpdateTime); // simplified version of calculation for mock testing

            unchecked {
                ++i;
            }
        }

        // Update totalVCs and totalNotYetClaimedRewards variables
        _subtractConsumedVCsFromTotalVCs();
        _updateTotalNotClaimedRewards(0);
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

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
    * @notice Decrease totalVCs by the number of VCs consumed by all the stakers since the previous checkpoint
    * @dev This function is only called if totalActiveDVs is not 0.
    */
    function _subtractConsumedVCsFromTotalVCs() internal {
        uint256 consumedVCs = _getElapsedDays(checkpoint.startAt) * checkpoint.clusterSize * totalActiveDVs;
        totalVCs -= consumedVCs;
    }

    /**
    * @notice Update totalNotYetClaimedRewards by adding the rewards ditributed to all stakers since the previous checkpoint
    * @dev This function is only called if totalActiveDVs is not 0. 
    * @dev Rewards that were claimed by a staker should be subtracted from totalNotYetClaimedRewards.
    */
    function _updateTotalNotClaimedRewards(uint256 _rewardsClaimed) internal {
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
    function _updateCheckpoint(uint256 _clusterSize) internal {
        checkpoint.dailyRewardsPerDV = getAllocatableRewards() / totalVCs * _clusterSize; // rewards per validator (4 nodeOp = 4 VCs consumed/day)
        checkpoint.clusterSize = _clusterSize;
        checkpoint.startAt = block.timestamp;
    }

    /**
    * @notice Get the number of days that have elapsed between the last checkpoint and the current one
    * @param _lastTimestamp can be the last update time of Checkpoint or StratModData
    */
    function _getElapsedDays(uint256 _lastTimestamp) internal view returns(uint256) {
        return (block.timestamp - _lastTimestamp); // simplified version of calculation for mock testing
    }


    /// @notice Returned when the staker has claimed all the rewards
    error AllRewardsHaveBeenClaimed();

    /// @notice Returned when the claimer has no strategy modules
    error NotEligibleToClaim();

    /// @notice Returned when the strategy module has already deployed 
    error StratModAlreadyExists();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();

    /// @dev Returned when the transfer of the rewards to the staker failed
    error FailedToSendRewards();
}