// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {ISymPod} from "./ISymPod.sol";

/// @title SymPodStorageV1
/// @author Obol
/// @notice The storage layout for SymPod
abstract contract SymPodStorageV1 is ERC4626, Initializable, ISymPod, ReentrancyGuard {
  ///@dev pod name
  string internal podName;

  /// @dev pod symbol
  string internal podSymbol;

  /// @dev total restaked amount in wei
  uint256 internal totalRestakedETH;

  /// @dev admin
  address public admin;

  /// @dev Address that receives withdrawn fundsof
  address public withdrawalAddress;

  /// @dev Address to recover tokens to
  address public recoveryAddress;

  /// @notice slashing contract
  /// @dev Address of entity that can slash the pod i.e. withdraw from the pod
  /// without any delay
  address public slasher;

  /// @dev withdrawable execution layer ETH
  uint256 public withdrawableRestakedPodWei;

  /// @dev pending to withdraw
  uint256 public pendingAmountToWithdrawWei;

  /// @dev number of active validators
  uint64 public numberOfActiveValidators;

  /// @dev currrent checkpoint timestamp
  uint64 public currentCheckPointTimestamp;

  /// @dev last checkpoint timestamp
  uint64 public lastCheckpointTimestamp;

  /// @dev current checkpoint information
  Checkpoint internal currentCheckPoint;

  /// @dev pubKeyHash to validator info mapping
  mapping(bytes32 validatorPubKeyHash => EthValidator validator) internal validatorInfo;

  /// @dev withdrawal data
  mapping(bytes32 withdrawalKey => WithdrawalInfo info) internal withdrawalQueue;

  /// @dev tracks exited validator balance per checkpoint timestamp
  mapping(uint64 => uint64) public checkpointBalanceExitedGwei;

  /// @notice to make the storage layout compatible and future upgradeable
  uint256[40] private __gap;

  modifier onlyAdmin() {
    if (msg.sender != admin) revert SymPod__Unauthorized();
    _;
  }
}
