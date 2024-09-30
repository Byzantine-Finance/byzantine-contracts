// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IByzNft} from "../interfaces/IByzNft.sol";
import {IStrategyVaultManager} from "../interfaces/IStrategyVaultManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "../interfaces/IStrategyVaultERC20.sol";

abstract contract StrategyVaultERC20Storage is IStrategyVaultERC20 {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice The single StrategyVaultManager for Byzantine
    IStrategyVaultManager public immutable stratVaultManager;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice EigenLayer's StrategyManager contract
    IStrategyManager public immutable strategyManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /* ============== STATE VARIABLES ============== */

    /// @notice The ByzNft associated to this StrategyVault.
    /// @notice The owner of the ByzNft is the StrategyVault creator.
    /// TODO When non-upgradeable put that variable immutable and set it in the constructor
    uint256 public stratVaultNftId;

    /// @notice Whitelisted addresses that are allowed to deposit into the StrategyVault (activated only the whitelistedDeposit == true)
    mapping (address => bool) public isWhitelisted;

    /// @notice Whether the deposit function is whitelisted or not.
    bool public whitelistedDeposit;

    /// @notice Whether the strategy is upgradeable (i.e can delegate to a different operator)
    bool public upgradeable;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}