// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "../interfaces/IStrategyModule.sol";

interface IStrategyModuleManager {

    /**
     * @notice Creates a StrategyModule for the sender.
     * @dev Returns StrategyModule address 
     */
    function createStratMod() external returns (address);

    /**
     * @notice Creates an EigenPod for the specified strategy module.
     * @param stratModIndex The index of the StrategyModules owner to create a Pod.
     * @dev Function will revert if the `stratModIndex` is out of bounds (i.e greater than the number of StrategyModules the sender has).
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     * @dev Returns EigenPod address
     */
    function createPod(uint256 stratModIndex) external returns (address);

    /**
     * @notice Stakes Native ETH for a new beacon chain validator on the sender's StrategyModule.
     * Also creates an EigenPod for the StrategyModule if it doesn't have one already.
     * @param stratModIndex The index of the StrategyModule's sender to restake Native ETH.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     * @dev Function will revert if `stratModAddr` is not a StrategyModule contract.
     * @dev Function will revert if the sender is not the StrategyModule's owner.
     */
    function stakeNativeETH(uint256 stratModIndex, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    /**
     * @notice Returns the addresses of the `stratModOwner`'s StrategyModules
     * @param stratModOwner The address you want to know the Strategy Modules it owns.
     */      
    function getStratMods(address stratModOwner) external view returns (IStrategyModule[] memory);

    /**
     * @notice Returns the StrategyModule of an address by its index.
     * @param stratModOwner The address of the StrategyModule's owner.
     * @param stratModIndex The index of the StrategyModule.
     */
    function getStratModByIndex(address stratModOwner, uint256 stratModIndex) external view returns (IStrategyModule);
    
    /**
     * @notice Returns 'true' if the `stratModOwner` has created at least one StrategyModule, and 'false' otherwise.
     * @param stratModOwner The address you want to know if it owns at least a StrategyModule.
     */       
    function hasStratMods(address stratModOwner) external view returns (bool);
    
    /**
     * @notice Returns the address of the `stratMod`'s EigenPod (whether it is deployed yet or not).
     * @param stratMod The address of the StrategyModule contract you want to know the EigenPod address.
     * @dev If the `stratMod` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address.
     */      
    function getPod(address stratMod) external view returns (IEigenPod);

    /**
     * @notice Returns 'true' if the `stratMod` has created an EigenPod, and 'false' otherwise.
     * @param stratModOwner The owner of the StrategyModule
     * @param stratModIndex The index of the `stratModOwner` StrategyModules you want to know if it has an EigenPod.
     */
    function hasPod(address stratModOwner, uint256 stratModIndex) external view returns (bool);

    /// @dev Returned when a specific address doesn't have a StrategyModule
    error DoNotHaveStratMod(address);

    /// @dev Returned if sender sender doesn't have StrategyModule at `stratModIndex`
    error InvalidStratModIndex(uint256);
    
}