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
     * @notice A 32ETH staker create a Strategy Module and deposit in its smart contract its stake.
     * @return The addresses of the newly created StrategyModule AND the address of its associated EigenPod (for the DV withdrawal address)
     * @dev This action triggers an auction to select node operators to create a Distributed Validator.
     * @dev One node operator of the DV (the DV manager) will have to deposit the 32ETH in the Beacon Chain.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH() external payable returns (address, address);

    /**
     * @notice Strategy Module owner can transfer its Strategy Module to another address.
     * Under the hood, he transfers the ByzNft associated to the StrategyModule.
     * That action makes him give the ownership of the StrategyModule and all the token it owns.
     * @param stratModAddr The address of the StrategyModule the owner will transfer.
     * @param newOwner The address of the new owner of the StrategyModule.
     * @dev The ByzNft owner must first call the `approve` function to allow the StrategyModuleManager to transfer the ByzNft.
     * @dev Function will revert if not called by the ByzNft holder.
     * @dev Function will revert if the new owner is the same as the old owner.
     */
    function transferStratModOwnership(address stratModAddr, address newOwner) external;

    /**
     * @notice Byzantine owner fill the expected/ trusted public key for a DV (retrievable from the Obol SDK/API).
     * @dev Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator.
     * @param stratModAddr The address of the Strategy Module to set the trusted DV pubkey
     * @param pubKey The public key of the DV retrieved with the Obol SDK/API from a configHash
     * @dev Revert if not callable by StrategyModuleManager owner.
     */
    function setTrustedDVPubKey(address stratModAddr, bytes calldata pubKey) external;

    /**
     * @notice Returns the number of StrategyModules owned by an address.
     * @param staker The address you want to know the number of Strategy Modules it owns.
     */
    function getStratModNumber(address staker) external view returns (uint256);

    /**
     * @notice Returns the StrategyModule address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Module.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Module (nftId is not a ByzNft)
     */
    function getStratModByNftId(uint256 nftId) external view returns (address);

    /**
     * @notice Returns the addresses of the `staker`'s StrategyModules
     * @param staker The staker address you want to know the Strategy Modules it owns.
     * @dev Returns an empty array if the staker has no Strategy Modules.
     */
    function getStratMods(address staker) external view returns (address[] memory);

    /**
     * @notice Returns the address of the Strategy Module's EigenPod (whether it is deployed yet or not).
     * @param stratModAddr The address of the StrategyModule contract you want to know the EigenPod address.
     * @dev If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function getPodByStratModAddr(address stratModAddr) external view returns (address);

    /**
     * @notice Returns 'true' if the `staker` owns at least one StrategyModule, and 'false' otherwise.
     * @param staker The address you want to know if it owns at least a StrategyModule.
     */
    function hasStratMods(address staker) external view returns (bool);

    /**
     * @notice Specify which `staker`'s StrategyModules are delegated.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function isDelegated(address staker) external view returns (bool[] memory);

    /**
     * @notice Specify to which operators `staker`'s StrategyModules are delegated to.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function delegateTo(address staker) external view returns (address[] memory);

    /**
     * @notice Returns 'true' if the `stratModAddr` has created an EigenPod, and 'false' otherwise.
     * @param stratModAddr The StrategyModule Address you want to know if it has created an EigenPod.
     * @dev If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function hasPod(address stratModAddr) external view returns (bool);

    /// @dev Returned when a specific address doesn't have a StrategyModule
    error DoNotHaveStratMod(address);

    /// @dev Returned when unauthorized call to a function only callable by the StrategyModule owner
    error NotStratModOwner();
    
}