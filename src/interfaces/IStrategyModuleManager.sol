// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";
import "../interfaces/IStrategyModule.sol";

interface IStrategyModuleManager {

    /// @notice Struct to hold the details of a pending cluster
    struct PendingClusterDetails {
        // The parameters of the Split contract
        SplitV2Lib.Split splitParams;
        // A record of the 4 nodes being part of the cluster
        IStrategyModule.Node[4] nodes;
    }

    /// @notice Get total number of pre-created clusters.
    function numPreCreatedClusters() external view returns (uint64);

    /// @notice Get the total number of Strategy Modules that have been deployed.
    function numStratMods() external view returns (uint64);

    /**
     * @notice Function to pre-create Distributed Validators. Must be called at least one time to allow stakers to enter in the protocol.
     * @param _numDVsToPreCreate Number of Distributed Validators to pre-create.
     * @dev This function is only callable by Byzantine Finance. Once the first DVs are pre-created, the stakers
     * pre-create a new DV every time they create a new StrategyModule (if enough operators in Auction).
     * @dev Make sure there are enough bids and node operators before calling this function.
     * @dev Pre-create clusters of size 4.
     */
    function preCreateDVs(uint8 _numDVsToPreCreate) external;

    /**
     * @notice A 32ETH staker create a Strategy Module, use a pre-created DV as a validator and activate it by depositing 32ETH.
     * @param pubkey The 48 bytes public key of the beacon chain DV.
     * @param signature The DV's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
     * @dev This action triggers a new auction to pre-create a new Distributed Validator for the next staker (if enough operators in Auction).
     * @dev It also fill the ClusterDetails struct of the newly created StrategyModule.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) 
        external payable;

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
     * @notice Returns the address of the EigenPod and the Split contract of the next StrategyModule to be created.
     * @param _nounce The index of the StrategyModule you want to know the EigenPod and Split contract address.
     * @dev Ownership of the Split contract belongs to ByzantineAdmin to be able to update it.
     * @dev Function essential to pre-create DVs as their withdrawal address has to be the EigenPod and fee recipient address the Split.
     */
    function preCalculatePodAndSplitAddr(uint64 _nounce) external view returns (address, address);
    
    /// @notice Returns the number of current pending clusters waiting for a Strategy Module.
    function getNumPendingClusters() external view returns (uint64);

    /**
     * @notice Returns the node details of a pending cluster.
     * @param clusterIndex The index of the pending cluster you want to know the node details.
     * @dev If the index does not exist, it returns the default value of the Node struct.
     */
    function getPendingClusterNodeDetails(uint64 clusterIndex) external view returns (IStrategyModule.Node[4] memory);

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
     * @notice Specify to which operators `staker`'s StrategyModules has delegated to.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function hasDelegatedTo(address staker) external view returns (address[] memory);

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