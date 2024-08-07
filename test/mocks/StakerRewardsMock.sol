// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {AutomationCompatibleInterface} from "chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "./StrategyModuleMock.sol";
import "./StratModManagerMock.sol";
import {console} from "forge-std/console.sol";

contract StakerRewardsMock is AutomationCompatibleInterface {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice StrategyModuleManager contract
    StratModManagerMock public immutable stratModManager;

    /* ============== STATE VARIABLES ============== */

    /// @notice Set to true if there is at least one strategy module
    bool private _hasActiveDVs;
    /// @notice Total of non consumed VCs in circulation: 1 VC consumed per day per nodeOp 
    uint256 public totalVCs; 
    /// @notice Number of strategy modules
    uint256 public totalActiveDVs;  
    /// @notice Sum of all the strategy module rewards distributed at current timestamp but not yet claimed by the stakers
    uint256 public totalNotYetClaimedRewards;

    /// @notice Interval specifies the time between upkeeps
    uint256 public upkeepInterval; 
    /// @notice Tracks the last upkeep performed
    uint256 public lastUpkeepTimeStamp; 

    /// @notice Global struct recording the last checkpoint details
    /// @dev Formula: dailyRewardsPerDV = allocableRewardsInContract / total_number_of_VCs_in_circulation
    struct Checkpoint {
        uint256 startAt; 
        uint256 dailyRewardsPerDV; // Latest average VC price per validator = stakers' daily rewards  
        uint256 clusterSize; 
    }
    Checkpoint public checkpoint;

    /// @notice Strategy module data
    struct StratModData {
        uint256 lastUpdateTime; // Staking time or last claim time
        uint256 smallestVCNumber; // Max number of days the owner of the stratMod can claim rewards 
        uint256 exitTimestamp; // The day where the VC number of at least one of the node operators should be reset to 0 (block.timestamp + smallestVCNumber * _ONE_DAY)
        uint256 claimPermission; // 0: can claim, 1: last time to claim, 2: cannot claim
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
     * @notice Fallback function which receives funds from the Escrow contract when the node operator wins the auction
     * @dev The funds are locked in the StakerRewards contract and are distributed to the stakers on a daily basis
     */
    receive() external payable {}

    /**
     * @notice Update the global checkpoint details when new DVs are pre-created or when a staker staked 32ETH
     * @param _newVCs Total VCs brought by the new DV
     * @param _clusterSize Number of DVs in the cluster
     * @dev Function triggered in 2 scenarios: precreation of DVs and arrival of a new staker.
     * If the checkpoint is updated due to the preCreateDVs function, the precreated DVs are batched and are considered as one checkpoint.
     * The function does the following actions:
     * 1. Increase totalVCs by the number of VCs brought by the new DVs
     * 2. If there is at least one staker has staked 32ETH, update totalVCs and totalNotYetClaimedRewards variables
     * 3. Update the checkpoint details
    */ 
    function updateCheckpoint(uint256 _newVCs, uint256 _clusterSize) public {   
        // Increase totalVCs
        totalVCs += _newVCs;

        // If there is at least one strategy module deployed
        if (_hasActiveDVs) {
            // update totalVCs
            _updateTotalVCs();
            // Update totalNotYetClaimedRewards 
            _increaseTotalNotClaimedRewards();
        }

        // Update the checkpoint
        _updateCheckpoint(_clusterSize);
    }

    /**
     * @notice Function triggered when a staker has staked 32ETH, a strategy module is created
     * @param _stratModAddr Address of the strategy module
     * @param _smallestVCNumber Maximum number of days the staker can claim rewards, which is also the smallest number of VCs in the strategy module
     * @param _newVCs Number of VCs brought by the new DV if there was one created by the new staker, otherwise 0
     * @param _clusterSize Number of DVs in the cluster
    */ 
    function stakerJoined(address _stratModAddr, uint256 _smallestVCNumber, uint256 _newVCs, uint256 _clusterSize) public {
        StratModData storage stratMod = stratMods[_stratModAddr];
        if (stratMod.lastUpdateTime != 0) revert StratModAlreadyExists();

        // If a DV is precreated OR if there is at least one strategy module, update the checkpoint and/or variables
        if (_newVCs != 0 || _hasActiveDVs) {
            updateCheckpoint(_newVCs, _clusterSize);
        } else {
            checkpoint.startAt = block.timestamp;
        }

        // Update the stretegy module data
        if (!_hasActiveDVs) {
            _hasActiveDVs = true;   
        }
        stratMod.lastUpdateTime = block.timestamp;
        stratMod.smallestVCNumber = _smallestVCNumber;
        stratMod.exitTimestamp = block.timestamp + _smallestVCNumber; // Simplified version of block.timestamp + _smallestVCNumber * _ONE_DAY for mock testing
        ++totalActiveDVs;
    }

    /**
     * @notice Staker claims rewards and receive rewards
     * @param _stratModAddr Address of the strategy module
     * @dev The function does the following actions: 
     * 1. Calculate the rewards and send them to the staker
     * 2. Update totalVCs and/or totalNotYetClaimedRewards if condition is met
     * 3. Update the checkpoint data
     * 4. Update the strategy module data
    */ 
    function claimRewards(address _stratModAddr) public {
        StratModData storage stratMod = stratMods[_stratModAddr];

        require(stratMod.lastUpdateTime != 0, "Not eligible to claim.");
        if (stratMod.claimPermission == 2) revert AllRewardsHaveBeenClaimed();

        // Calculate the rewards and send them to the staker
        uint256 rewardsClaimed = calculateRewards(_stratModAddr);
        (bool success,) = payable(msg.sender).call{value: rewardsClaimed}("");
        require(success, "Transfer failed.");

        // If there is at least one strategy module deployed
        if (_hasActiveDVs) {
            _updateTotalVCs();
            _increaseTotalNotClaimedRewards();
        }

        // Decrease totalNotYetClaimedRewards by subtracting the claimed rewards from it
        totalNotYetClaimedRewards -= rewardsClaimed;

        // Update checkpoint
        _updateCheckpoint(checkpoint.clusterSize);

        // Update the stretegy module data
        if (stratMod.claimPermission == 1) {
            stratMod.claimPermission = 2;
        }
        stratMod.lastUpdateTime = block.timestamp;
    }
    
    /**
    * @notice Calculate the rewards for a staker
    * @param _stratModAddr Address of the strategy module
    * @dev Staker cannot claim rewards for more than smallestVCNumber
    * @return The rewards for the staker and the number of days that the staker has claime rewards for
    */
    function calculateRewards(address _stratModAddr) public view returns(uint256) {
        StratModData storage stratMod = stratMods[_stratModAddr];
        if (stratMod.lastUpdateTime == 0) revert NotEligibleToClaim();
        if (stratMod.claimPermission == 2) revert AllRewardsHaveBeenClaimed();

        if (stratMod.claimPermission == 0) {
            uint256 elapsedDays = _getElapsedDays(stratMod.lastUpdateTime);
            return checkpoint.dailyRewardsPerDV * elapsedDays;
        } else if (stratMod.claimPermission == 1) {
            uint256 elapsedDays = stratMod.exitTimestamp - stratMod.lastUpdateTime; // simplified version of calculation for mock testing
            return checkpoint.dailyRewardsPerDV * elapsedDays;
        }
    }

    /**
    * @notice Calculate the locked rewards of the StakerRewards contract which can be distributed to stakers
    * @dev allocatableRewards = address(this).balance - totalNotYetClaimedRewards 
    * This is used to calculate the correct total rewards in the contract that can be distributed to the stakers
    * The rewards related to the days that have elapsed between the last checkpoint and the current checkpoint cannot be distributed again to stakers
    */
    function getAllocatableRewards() public view returns(uint256) {
        return address(this).balance - totalNotYetClaimedRewards;
    }

    /**
     * @notice Returns the strategy module data of a given strategy module address
     */
    function getStratModData(address _stratModAddr) public view  returns(uint256, uint256, uint256, uint256) {
        StratModData memory stratModData = stratMods[_stratModAddr];
        return (stratModData.lastUpdateTime, stratModData.smallestVCNumber, stratModData.exitTimestamp, stratModData.claimPermission);
    }

    /**
    * @notice Returns the current checkpoint data
    */
    function getCheckpointData() public view returns(uint256, uint256, uint256) {
        return (checkpoint.startAt, checkpoint.dailyRewardsPerDV, checkpoint.clusterSize);
    }

    /* ============== CHAINLINK AUTOMATION FUNCTIONS ============== */

    /**
     * @notice Function to check offchain if a node operator of any strategy module has consumed all of its VCs
     * @return upkeepNeeded is true if the current block timestamp is equal to the exitTimestamp of any strategy module
     * @return performData is not used to pass the response from checkUpkeep to the performUpkeep function 
     * @dev This method is called by the Chainlink Automation Nodes to check if `performUpkeep` must be done. 
        This function doe not consume any gas and is simulated offchain.
        checkData is not used in this function.
     */
    function checkUpkeep(bytes memory /* checkData */ ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        // Check the interval between the current block timestamp and the last upkeep 
        if (block.timestamp - lastUpkeepTimeStamp < upkeepInterval) revert UpkeepNotNeeded();

        // Get the number of strategy modules requiring update
        uint256 counter;
        for (uint256 i; i < stratModManager.numStratMods();) {
            address stratModAddr = stratModManager.getStratModByNftId(i);

            // For each strategy module, check if the current block timestamp is equal to the exitTimestamp
            if (stratMods[stratModAddr].exitTimestamp < block.timestamp && stratMods[stratModAddr].claimPermission == 0) {
                ++counter;
            }

            unchecked {
                ++i;
            }
        }

        // Initialize array of addresses of strategy modules at the size of counter
        address[] memory statModAddresses = new address[](counter);
        // Initialize array of VC numbers of each strategy module at the size of counter
        uint256[] memory stratModTotalVCs = new uint256[](counter);

        upkeepNeeded = false;
        uint256 indexCounter;

        // Iterate over all the strategy modules again to get the addresses of the strategy modules and set upkeepNeeded to true
        for (uint256 i; i < stratModManager.numStratMods();) {
            address stratModAddr = stratModManager.getStratModByNftId(i);

            // For each strategy module, check if the current block timestamp is equal to the exitTimestamp
            if (stratMods[stratModAddr].exitTimestamp < block.timestamp && stratMods[stratModAddr].claimPermission == 0) { 
                // If yes, set the upkeepNeeded to true
                upkeepNeeded = true;

                // Store the address of the strategy module to the array
                statModAddresses[indexCounter] = stratModAddr;

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
        
        performData = abi.encode(statModAddresses, stratModTotalVCs);
        return (upkeepNeeded, performData); 
    }

    /**
     * @notice Function to perform upkeep onchain to update the node VC number for each node in all relevant strategy modules and update its status
     * @param performData is the data returned by the checkUpkeep function
     * @dev this method is called by the Automation Nodes. When checkUpkeep returns upkeepNeeded == true, Chainlink broadcasts a transaction to the blockchain to execute the performUpkeep function
     * TODO: Send back the bid prices of the DV to the Escrow contract
    */
    function performUpkeep(bytes calldata performData) external override {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) revert UpkeepNotNeeded();

        lastUpkeepTimeStamp = block.timestamp;

        // Decode the performData to get the strategy module addresses
        (address[] memory statModAddresses, uint256[] memory stratModTotalVCs) = abi.decode(performData, (address[], uint256[]));

        uint256 remainingVCsToSubtract;
        uint256 numOfActiveDVsToDisable;

        for (uint256 i; i < statModAddresses.length;) {
            address stratModAddr = statModAddresses[i];
            uint256 consumedVCs = stratMods[stratModAddr].smallestVCNumber;

            // Add up the remaining VCs of the strategy module
            remainingVCsToSubtract += (stratModTotalVCs[i] - consumedVCs * 4);
            // Update the node VC number for each node
            StrategyModuleMock(stratModAddr).updateNodeVcNumber(consumedVCs);
            // Add up the number of active DVs to disable
            ++numOfActiveDVsToDisable;

            // Update claimPermission to 1 
            stratMods[stratModAddr].claimPermission = 1;

            unchecked {
                ++i;
            }
        }

        // Update totalVCs and totalNotYetClaimedRewards variables
        if (_hasActiveDVs) {
            _updateTotalVCs();
            _increaseTotalNotClaimedRewards();
        }
        
        // Decrease totalActiveDVs by 1 as the DV is no longer active
        totalActiveDVs -= numOfActiveDVsToDisable;

        // "Remove" the strategy module by removing the node operators' remaining VCs from totalVCs
        totalVCs -= remainingVCsToSubtract;

        // Update checkpoint
        _updateCheckpoint(checkpoint.clusterSize);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
    * @notice Function to decrease totalVCs by the number of VCs consumed by all the stakers since the previous checkpoint
    * @dev this function is only called when _hasActiveDVs is true 
    */
    function _updateTotalVCs() internal {
        uint256 consumedVCs = _getElapsedDays(checkpoint.startAt) * checkpoint.clusterSize * totalActiveDVs;
        totalVCs -= consumedVCs;
    }

    /**
    * @notice Function to update the checkpoint struct including calculating and updating the daily rewards per DV 
    * @param _clusterSize is the number of DVs in a cluster
    */
    function _updateCheckpoint(uint256 _clusterSize) internal {
        checkpoint.dailyRewardsPerDV = getAllocatableRewards() / totalVCs * _clusterSize; // rewards per validator (4 nodeOp = 4 VCs consumed/day)
        checkpoint.clusterSize = _clusterSize;
        checkpoint.startAt = block.timestamp;
    }

    /**
    * @notice Get the number of days that have elapsed between the last checkpoint and the current one
    * @param _lastTimestamp The timestamp of the last checkpoint or the last update time of the staker
    */
    function _getElapsedDays(uint256 _lastTimestamp) internal view returns(uint256) {
        return (block.timestamp - _lastTimestamp); // simplified version of calculation for mock testing
    }

    /**
    * @notice Increase the totalNotYetClaimedRewards variable by adding up the rewards ditributed to all stakers since the previous checkpoint
    * @dev this function is only called when _hasActiveDVs is true. Claimed rewards should be subtracted from the totalNotYetClaimedRewards
    */
    function _increaseTotalNotClaimedRewards() internal {
        uint256 elapsedDays = _getElapsedDays(checkpoint.startAt);
        uint256 rewardsDistributed = checkpoint.dailyRewardsPerDV * elapsedDays * totalActiveDVs;
        totalNotYetClaimedRewards += rewardsDistributed;
    }

    /// @notice Returned when the staker has claimed all the rewards
    error AllRewardsHaveBeenClaimed();

    /// @notice Returned when the claimer has no strategy modules
    error NotEligibleToClaim();

    /// @notice Returned when the strategy module has already deployed 
    error StratModAlreadyExists();

    /// @dev Returned when the upkeep is not needed
    error UpkeepNotNeeded();
}