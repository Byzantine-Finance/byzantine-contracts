// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";

interface IStrategyVault {

    /// @notice Returns the StrategyVault's ByzNft id
    function stratVaultNftId() external view returns (uint256);

    
    /// @notice Returns StrategyVault's creator address
    function stratVaultOwner() external view returns (address);

    /// @notice Returns whether a staker needs to be whitelisted to deposit in the vault
    function whitelistedDeposit() external view returns (bool);

    /// @notice Returns whether the StrategyVault's underlying strategy is upgradeable / updatable
    function upgradeable() external view returns (bool);

    /// @notice Returns whether a staker is whitelisted to deposit in the vault
    function isWhitelisted(address account) external view returns (bool);

    /**
     * @notice The caller delegate its Strategy Vault's stake to an Eigen Layer operator.
     * @notice /!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.
     * @param operator The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.
     * @dev The operator must not have set a delegation approver, everyone can delegate to it without permission.
     * @dev Ensures that:
     *          1) the `staker` is not already delegated to an operator
     *          2) the `operator` has indeed registered as an operator in EigenLayer
     */
    function delegateTo(address operator) external;

    
    /// @notice Returns the Eigen Layer operator that the Strategy Vault is delegated to
    function hasDelegatedTo() external view returns (address);

    /**
     * @notice Updates the whitelistedDeposit flag.
     * @param _whitelistedDeposit The new whitelistedDeposit flag.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function updateWhitelistedDeposit(bool _whitelistedDeposit) external;

    /**
     * @notice Whitelist a staker.
     * @param staker The address to whitelist.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function whitelistStaker(address staker) external;

    /// @dev Error when unauthorized call to a function callable only by the Strategy Vault Owner (aka the ByzNft holder).
    error OnlyNftOwner();

    /// @dev Error when unauthorized call to the deposit function when whitelistedDeposit is true and caller is not whitelisted.
    error OnlyWhitelistedDeposit();

    /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
    error OnlyStrategyVaultManager();

    /// @dev Returned when trying to deposit an incorrect token
    error IncorrectToken();

    /// @dev Error when whitelisting a staker already whitelisted
    error StakerAlreadyWhitelisted();

    /// @dev Returns when trying to whitelist a staker and whitelistedDeposit is disabled
    error WhitelistedDepositDisabled();
}