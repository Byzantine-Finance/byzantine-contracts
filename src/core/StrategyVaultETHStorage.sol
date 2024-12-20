// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IByzNft} from "../interfaces/IByzNft.sol";
import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEigenPodManager} from "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "eigenlayer-contracts/interfaces/IEigenPod.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStakerRewards} from "../interfaces/IStakerRewards.sol";

import {FIFOLib} from "../libraries/FIFOLib.sol";

import "../interfaces/IStrategyVaultETH.sol";

abstract contract StrategyVaultETHStorage is IStrategyVaultETH {

    /* ============== CONSTANTS + IMMUTABLES ============== */

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

    /// @notice StakerRewards contract
    IStakerRewards public immutable stakerRewards;

    /// @notice Average time for block finality in the Beacon Chain
    uint16 internal constant FINALITY_TIME = 16 minutes;

    /// @notice The token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking Native ETH.
    address public constant depositToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice The address allowed to activate a DV and submit Beacon Merkle Proofs
    address public immutable beaconChainAdmin;

    /* ============== STATE VARIABLES ============== */

    /// @notice The ByzNft associated to this StrategyVault.
    /// @notice The owner of the ByzNft is the StrategyVault creator.
    /// TODO When non-upgradeable put that variable immutable and set it in the constructor
    uint256 public stratVaultNftId;

    /// @notice Whitelisted addresses that are allowed to deposit into the StrategyVault (activated only the whitelistedDeposit == true)
    mapping (address => bool) public isWhitelisted;

    /// @notice FIFO of all the cluster IDs of the StrategyVault
    FIFOLib.FIFO public clusterIdsFIFO;

    /// @notice Whether the deposit function is whitelisted or not.
    bool public whitelistedDeposit;

    /// @notice Whether the strategy is upgradeable (i.e can delegate to a different operator)
    bool public upgradeable;

    /// @notice Amount of ETH in the vault. Includes deposits from stakers as well as the accumulated Proof of Stake rewards.
    uint256 public amountOfETH;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[43] private __gap;

}