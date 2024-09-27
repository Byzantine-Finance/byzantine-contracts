// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStrategyVault.sol";

interface IStrategyVaultERC20 is IStrategyVault {

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