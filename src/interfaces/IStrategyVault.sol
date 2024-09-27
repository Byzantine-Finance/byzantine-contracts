// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";

interface IStrategyVault {

    /**
     * @notice Used to initialize the StrategyVault given it's setup parameters.
     * @param _nftId The id of the ByzNft associated to this StrategyVault.
     * @param _initialOwner The initial owner of the ByzNft.
     * @param _token The address of the token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking ETH.
     * @param _whitelistedDeposit Whether the deposit function is whitelisted or not.
     * @param _upgradeable Whether the StrategyVault is upgradeable or not.
     * @dev Called on construction by the StrategyVaultManager.
     */
    function initialize(
      uint256 _nftId,
      address _initialOwner,
      address _token,
      bool _whitelistedDeposit,
      bool _upgradeable
    ) external;

    /**
     * @notice Returns the owner of this StrategyVault
     */
    function stratVaultNftId() external view returns (uint256);

    /**
     * @notice Returns the address of the owner of the Strategy Vault's ByzNft.
     */
    function stratVaultOwner() external view returns (address);

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

    /// @dev Error when unauthorized call to a function callable only by the Strategy Vault Owner (aka the ByzNft holder).
    error OnlyNftOwner();

    /// @dev Error when unauthorized call to the deposit function when whitelistedDeposit is true and caller is not whitelisted.
    error OnlyWhitelistedDeposit();

    /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
    error OnlyStrategyVaultManager();

    /// @dev Returned on failed Eigen Layer contracts call
    error CallFailed(bytes data);

    /// @dev Returned when trying to deposit an incorrect token
    error IncorrectToken();

}