// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {IByzNft} from "../interfaces/IByzNft.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {IEigenPodManager} from "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import {HitchensUnorderedAddressSetLib} from "../libraries/HitchensUnorderedAddressSetLib.sol";

import "../interfaces/IStrategyVaultManager.sol";

abstract contract StrategyVaultManagerStorage is IStrategyVaultManager {
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice Beacon proxy to which all the StrategyVaultETHs point
    IBeacon public immutable stratVaultETHBeacon;

    /// @notice Beacon proxy to which all the StrategyVaultERC20s point
    IBeacon public immutable stratVaultERC20Beacon;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Auction contract
    IAuction public immutable auction;

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /* ============== STATE VARIABLES ============== */

    /// @notice Unordered Set of all the StratVaultETHs
    HitchensUnorderedAddressSetLib.Set internal _stratVaultETHSet;

    /// @notice ByzNft tokenId to its tied StrategyVault
    mapping(uint256 => address) public nftIdToStratVault;

    /// @notice The number of StratVaults that have been deployed
    uint64 public numStratVaults; // This is also the number of ByzNft minted

    /* ================= CONSTRUCTOR ================= */ 

    constructor(
        IBeacon _stratVaultETHBeacon,
        IBeacon _stratVaultERC20Beacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) {
        stratVaultETHBeacon = _stratVaultETHBeacon;
        stratVaultERC20Beacon = _stratVaultERC20Beacon;
        auction = _auction;
        byzNft = _byzNft;
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}