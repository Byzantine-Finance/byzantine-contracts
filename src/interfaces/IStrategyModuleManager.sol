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
     * @notice Create a StrategyModule for the sender and then stake native ETH for a new beacon chain validator
     * on that newly created StrategyModule. Also creates an EigenPod for the StrategyModule.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH(
        bytes calldata pubkey, 
        bytes calldata signature, 
        bytes32 depositDataRoot
    ) 
        external payable returns (address);

    /**
     * @notice Returns the number of StrategyModules owned by an address.
     * @param stratModOwner The address you want to know the number of Strategy Modules it owns.
     */
    function getStratModNumber(address stratModOwner) external view returns (uint256);

    /**
     * @notice Pre-calculate the address of a new StrategyModule `stratModOwner` will deploy.
     * @dev The salt will be the address of the creator (`stratModOwner`) and the index of the new StrategyModule in creator's portfolio.
     * @param stratModOwner The address of the future StrategyModule owner.
     */
    function computeStratModAddr(address stratModOwner) external view returns (address);

    /**
     * @notice Pre-calculate the address of a new EigenPod `stratModOwner` will deploy (via a new StrategyModule).
     * @dev The pod will be deployed on a new StrategyModule owned by `stratModOwner`.
     * @param stratModOwner The address of the future StrategyModule owner.
     */
    function computePodAddr(address stratModOwner) external view returns (address);

    /**
     * @notice Returns the addresses of the `stratModOwner`'s StrategyModules
     * @param stratModOwner The address you want to know the Strategy Modules it owns.
     */      
    function getStratMods(address stratModOwner) external view returns (address[] memory);

    /**
     * @notice Returns the StrategyModule address of an owner by its index.
     * @param stratModOwner The address of the StrategyModule's owner.
     * @param stratModIndex The index of the StrategyModule.
     * @dev Revert if owner doesn't have StrategyModule or if index is invalid.
     */
    function getStratModByIndex(address stratModOwner, uint256 stratModIndex) external view returns (address);
    
    /**
     * @notice Returns 'true' if the `stratModOwner` has created at least one StrategyModule, and 'false' otherwise.
     * @param stratModOwner The address you want to know if it owns at least a StrategyModule.
     */       
    function hasStratMods(address stratModOwner) external view returns (bool);
    
    /**
     * @notice Returns the address of the `stratMod`'s EigenPod (whether it is deployed yet or not).
     * @param stratMod The address of the StrategyModule contract you want to know the EigenPod address.
     * @dev If the `stratMod` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address. So use that function carefully.
     */     
    function getPodByStratModAddr(address stratMod) external view returns (address);

    /**
     * @notice Returns 'true' if the `stratMod` has created an EigenPod, and 'false' otherwise.
     * @param stratModOwner The owner of the StrategyModule
     * @param stratModIndex The index of the `stratModOwner` StrategyModules you want to know if it has an EigenPod.
     * @dev Revert if owner doesn't have StrategyModule or if index is invalid.
     */
    function hasPod(address stratModOwner, uint256 stratModIndex) external view returns (bool);

    /**
     * @notice Specify which `stratModOwner`'s StrategyModules are delegated.
     * @param stratModOwner The address of the StrategyModules' owner.
     * @dev Revert if the `stratModOwner` doesn't have any StrategyModule.
     */
    function isDelegated(address stratModOwner) external view returns (bool[] memory);

    /**
     * @notice Specify to which operators `stratModOwner`'s StrategyModules are delegated to.
     * @param stratModOwner The address of the StrategyModules' owner.
     * @dev Revert if the `stratModOwner` doesn't have any StrategyModule.
     */
    function delegateTo(address stratModOwner) external view returns (address[] memory);

    /// @dev Returned when a specific address doesn't have a StrategyModule
    error DoNotHaveStratMod(address);

    /// @dev Returned if sender sender doesn't have StrategyModule at `stratModIndex`
    error InvalidStratModIndex(uint256);
    
}