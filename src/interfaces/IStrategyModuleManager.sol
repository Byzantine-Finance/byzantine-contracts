// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStrategyModuleManager {

    /**
     * @notice Creates a StrategyModule for the sender.
     * @dev Function will revert if the `msg.sender` already has a StrategyModule.
     * @dev Returns StrategyModule address 
     */
    function createStratMod() external returns (address);

    /**
     * @notice Creates an EigenPod for the sender's strategy module.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     * @dev Function will create a StrategyModule if the sender doesn't have one already.
     * @dev Returns EigenPod address and StrategyModule address (which is the EigenPod owner)
     */
    function createPod() external returns (address, address);

    /**
     * @dev Error when sender already has StrategyModule.
     */
    error AlreadyHasStrategyModule();

    /**
     * @dev Returned on failed Eigen Layer contracts call
     */
    error GetPodCallFailed();
    
}