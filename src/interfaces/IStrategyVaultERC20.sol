// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStrategyVault.sol";

interface IStrategyVaultERC20 is IStrategyVault {

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
    * @notice Deposit ERC20 tokens into the StrategyVault.
    * @param token The address of the ERC20 token to deposit.
    * @param amount The amount of tokens to deposit.
    * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
    */
  function stakeERC20(
    IERC20 token,
    uint256 amount
  ) external;

}