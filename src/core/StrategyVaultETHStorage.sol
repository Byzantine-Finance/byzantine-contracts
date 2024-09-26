// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IByzNft} from "../interfaces/IByzNft.sol";
import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEigenPodManager} from "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "eigenlayer-contracts/interfaces/IEigenPod.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "../interfaces/IStrategyVaultETH.sol";

abstract contract StrategyVaultETHStorage is IStrategyVaultETH {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice Average time for block finality in the Beacon Chain
    uint16 internal constant FINALITY_TIME = 16 minutes;

    uint8 internal constant CLUSTER_SIZE = 4;

    /// @notice The single StrategyVaultManager for Byzantine
    IStrategyVaultManager public immutable stratVaultManager;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Address of the Auction contract
    IAuction public immutable auction;

    /// @notice EigenLayer's EigenPodManager contract
    /// @dev this is the pod manager transparent proxy
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;
    

    /* ============== STATE VARIABLES ============== */

    /// @notice The ByzNft associated to this StrategyVault.
    /// @notice The owner of the ByzNft is the StrategyVault owner.
    /// TODO When non-upgradeable put that variable immutable and set it in the constructor
    uint256 public stratVaultNftId;

    // Empty struct, all the fields have their default value
    ClusterDetails public clusterDetails;

    /// @notice Whether the deposit function is whitelisted or not.
    bool public whitelistedDeposit;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}