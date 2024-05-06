// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";

interface IStrategyModule {

  /**
   * @notice Returns the owner of this StrategyModule
   */
  function stratModNftId() external view returns (uint256);

  /**
   * @notice Returns the address of the owner of the Strategy Module's ByzNft.
   */
  function stratModOwner() external view returns (address);

  /**
   * @notice Call the EigenPodManager contract
   * @param data to call contract 
   */
  function callEigenPodManager(bytes calldata data) external payable returns (bytes memory);

  /**
   * @notice Creates an EigenPod for the strategy module.
   * @dev Function will revert if not called by the StrategyModule owner.
   * @dev Function will revert if the StrategyModule already has an EigenPod.
   * @dev Returns EigenPod address
   */
  function createPod() external returns (address);

  /**
   * @notice Stakes Native ETH for a new beacon chain validator on the sender's StrategyModule.
   * Also creates an EigenPod for the StrategyModule if it doesn't have one already.
   * @param pubkey The 48 bytes public key of the beacon chain validator.
   * @param signature The validator's signature of the deposit data.
   * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
   * @dev Function will revert if the sender is not the StrategyModule's owner.
   */
  function stakeNativeETH(
    bytes calldata pubkey, 
    bytes calldata signature, 
    bytes32 depositDataRoot
  ) 
    external payable; 

  /**
   * @notice This function verifies that the withdrawal credentials of the Distributed Validator(s) owned by
   * the stratModOwner are pointed to the EigenPod of this contract. It also verifies the effective balance of the DV.
   * It verifies the provided proof of the ETH DV against the beacon chain state root, marks the validator as 'active'
   * in EigenLayer, and credits the restaked ETH in Eigenlayer.
   * @param proofTimestamp is the exact timestamp where the proof was generated
   * @param stateRootProof proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param validatorIndices is the list of indices of the validators being proven, refer to consensus specs
   * @param validatorFieldsProofs proofs against the `beaconStateRoot` for each validator in `validatorFields`
   * @param validatorFields are the fields of the "Validator Container", refer to consensus specs for details: 
   * https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   * @dev That function must be called for a validator which is "INACTIVE".
   * @dev The timestamp used to generate the Beacon Block Root is `block.timestamp - FINALITY_TIME` to be sure
   * that the Beacon Block is finalized.
   * @dev The arguments can be generated with the Byzantine API.
   * @dev /!\ The Withdrawal credential proof must be recent enough to be valid (no older than VERIFY_BALANCE_UPDATE_WINDOW_SECONDS).
   * It entails to re-generate a proof every 4.5 hours.
   */
  function verifyWithdrawalCredentials(
    uint64 proofTimestamp,
    BeaconChainProofs.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  )
    external;

  /**
   * @notice This function records an update (either increase or decrease) in a validator's balance which is active,
   * (which has already called `verifyWithdrawalCredentials`).
   * @param proofTimestamp is the exact timestamp where the proof was generated
   * @param stateRootProof proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param validatorIndices is the list of indices of the validators being proven, refer to consensus specs 
   * @param validatorFieldsProofs proofs against the `beaconStateRoot` for each validator in `validatorFields`
   * @param validatorFields are the fields of the "Validator Container", refer to consensus specs:
   * https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   * @dev That function must be called for a validator which is "ACTIVE".
   * @dev The timestamp used to generate the Beacon Block Root is `block.timestamp - FINALITY_TIME` to be sure
   * that the Beacon Block is finalized.
   * @dev The arguments can be generated with the Byzantine API.
   * @dev /!\ The Withdrawal credential proof must be recent enough to be valid (no older than VERIFY_BALANCE_UPDATE_WINDOW_SECONDS).
   * It entails to re-generate a proof every 4.5 hours.
   */
  function verifyBalanceUpdates(
      uint64 proofTimestamp,
      BeaconChainProofs.StateRootProof calldata stateRootProof,
      uint40[] calldata validatorIndices,
      bytes[] calldata validatorFieldsProofs,
      bytes32[][] calldata validatorFields
  )
    external;

  /**
     * @notice The caller delegate its Strategy Module's stake to an Eigen Layer operator.
     * @notice /!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.
     * @param operator The account teh STrategy Module is delegating its assets to for use in serving applications built on EigenLayer.
     * @dev The operator must not have set a delegation approver, everyone can delegate to it without permission.
     * @dev Ensures that:
     *          1) the `staker` is not already delegated to an operator
     *          2) the `operator` has indeed registered as an operator in EigenLayer
     */
    function delegateTo(address operator) external;

  
  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
  error OnlyStrategyModuleManager();

  
  /// @dev Error when unauthorized call to a function callable only by the Strategy Module Owner (aka the ByzNft holder).
  error OnlyNftOwner();
  
  /// @dev Returned on failed Eigen Layer contracts call
  error CallFailed(bytes data);

}