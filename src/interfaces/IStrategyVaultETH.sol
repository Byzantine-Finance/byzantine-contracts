// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BeaconChainProofs} from "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import {IERC7535} from "../vault/ERC7535/IERC7535.sol";

import "./IStrategyVault.sol";

interface IStrategyVaultETH is IStrategyVault, IERC7535 {

  /* ============== EVENTS ============== */

  /// @notice Emitted when ETH is deposited into the Strategy Vault (either mint or deposit function)
  event ETHDeposited(address indexed receiver, uint256 assets, uint256 shares);

  /* ============== GETTERS ============== */

  /// @notice Get the address of the beacon chain admin
  function beaconChainAdmin() external view returns (address);

  /* ============== EXTERNAL FUNCTIONS ============== */

  /**
   * @notice Used to initialize the StrategyVaultETH given it's setup parameters.
   * @param _nftId The id of the ByzNft associated to this StrategyVault.
   * @param _stratVaultCreator The address of the creator of the StrategyVault.
   * @param _whitelistedDeposit Whether the deposit function is whitelisted or not.
   * @param _upgradeable Whether the StrategyVault is upgradeable or not.
   * @param _oracle The oracle implementation to use for the vault.
   * @dev Called on construction by the StrategyVaultManager.
   * @dev StrategyVaultETH so the deposit token is 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
   */
  function initialize(
      uint256 _nftId,
      address _stratVaultCreator,
      bool _whitelistedDeposit,
      bool _upgradeable,
      address _oracle
  ) external;

  /**
   * @dev Verify one or more validators (DV) have their withdrawal credentials pointed at this StrategyVault's EigenPod, and award
   * shares based on their effective balance. Proven validators are marked `ACTIVE` within the EigenPod, and
   * future checkpoint proofs will need to include them.
   * @dev Withdrawal credential proofs MUST NOT be older than `currentCheckpointTimestamp`.
   * @dev Validators proven via this method MUST NOT have an exit epoch set already (i.e MUST NOT have initiated an exit).
   * @param beaconTimestamp the beacon chain timestamp sent to the 4788 oracle contract. Corresponds
   * to the parent beacon block root against which the proof is verified. MUST be greater than `currentCheckpointTimestamp` and
   * included in the last 8192 (~27 hours) Beacon Blocks.
   * @param stateRootProof proves a beacon state root against a beacon block root
   * @param validatorIndices a list of validator indices being proven
   * @param validatorFieldsProofs proofs of each validator's `validatorFields` against the beacon state root
   * @param validatorFields the fields of the beacon chain "Validator" container. See consensus specs for
   * details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   * @param clusterIds The IDs of the clusters associated to these proofs.
   * @dev Revert if the number of cluster IDs and proofs mismatch.
   */
  function verifyWithdrawalCredentials(
      uint64 beaconTimestamp,
      BeaconChainProofs.StateRootProof calldata stateRootProof,
      uint40[] calldata validatorIndices,
      bytes[] calldata validatorFieldsProofs,
      bytes32[][] calldata validatorFields,
      bytes32[] calldata clusterIds
  ) external;

  /**
   * @dev Progress the current checkpoint towards completion by submitting one or more validator
   * checkpoint proofs. Anyone can call this method to submit proofs towards the current checkpoint.
   * For each validator proven, the current checkpoint's `proofsRemaining` decreases.
   * @dev If the checkpoint's `proofsRemaining` reaches 0, the checkpoint is finalized.
   * @dev This method can only be called when there is a currently-active checkpoint.
   * @param balanceContainerProof proves the beacon's current balance container root against a checkpoint's `beaconBlockRoot`
   * @param proofs Proofs for one or more validator current balances against the `balanceContainerRoot`
   */
  function verifyCheckpointProofs(
      BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof,
      BeaconChainProofs.BalanceProof[] calldata proofs
  ) external;

   /**
    * @dev Prove that one of this vault's active validators was slashed on the beacon chain. A successful
    * staleness proof allows the caller to start a checkpoint.
    * @param beaconTimestamp the beacon chain timestamp sent to the 4788 oracle contract. Corresponds
    * to the parent beacon block root against which the proof is verified.
    * @param stateRootProof proves a beacon state root against a beacon block root
    * @param proof the fields of the beacon chain "Validator" container, along with a merkle proof against
    * the beacon state root. See the consensus specs for more details:
    * https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
    */
   function verifyStaleBalance(
      uint64 beaconTimestamp,
      BeaconChainProofs.StateRootProof calldata stateRootProof,
      BeaconChainProofs.ValidatorProof calldata proof
   ) external;

  /* ============== BEACON CHAIN ADMIN FUNCTIONS ============== */

  /**
   * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
   * @dev Function callable only by BeaconChainAdmin to be sure the deposit data are the ones of a DV created within the Byzantine protocol. 
   * @param pubkey The 48 bytes public key of the beacon chain DV.
   * @param signature The DV's signature of the deposit data.
   * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
   * @param clusterId The ID of the cluster associated to these deposit data.
   * @dev Reverts if not exactly 32 ETH are sent.
   * @dev Reverts if the cluster is not in the vault.
   */
  function activateCluster(
      bytes calldata pubkey, 
      bytes calldata signature,
      bytes32 depositDataRoot,
      bytes32 clusterId
  ) external;

  /**
   * @dev Create a checkpoint used to prove the vault's active validator set. Checkpoints are completed
   * by submitting one checkpoint proof per ACTIVE validator. During the checkpoint process, the total
   * change in ACTIVE validator balance is tracked, and any validators with 0 balance are marked `WITHDRAWN`.
   * @dev Once finalized, the vault is awarded shares corresponding to:
   * - the total change in their ACTIVE validator balances
   * - any ETH in the pod not already awarded shares
   * @dev A checkpoint cannot be created if the pod already has an outstanding checkpoint. If
   * this is the case, the pod owner, i.e the vault, MUST complete the existing checkpoint before starting a new one.
   * @param revertIfNoBalance Forces a revert if the pod ETH balance is 0. This allows the pod owner
   * to prevent accidentally starting a checkpoint that will not increase their shares
   * @dev If waiting too long to submit your checkpoint proof, you may need to use a full archival beacon node to re-generate the proofs.
   * This is because the EIP-4788 oracle is valid for 27 hours, 8191 blocks.
   */
  function startCheckpoint(bool revertIfNoBalance) external;

  /* ============== VIEW FUNCTIONS ============== */

  /**
   * @notice Returns the number of active DVs staked by the Strategy Vault.
   */
  function getVaultDVNumber() external view returns (uint256);

  /**
   * @notice Returns the IDs of the active DVs staked by the Strategy Vault.
   */
  function getAllDVIds() external view returns (bytes32[] memory);

  /* ============== STRATEGY VAULT MANAGER FUNCTIONS ============== */

  /**
   * @notice Create an EigenPod for the StrategyVault.
   * @dev Can only be called by the StrategyVaultManager during the vault creation.
   */
  function createEigenPod() external;

    /* ============== ERRORS ============== */

    /// @dev Returned when trying to deposit an incorrect amount of ETH. Can only deposit a multiple of 32 ETH. (32, 64, 96, 128, etc.)
    error CanOnlyDepositMultipleOf32ETH();

    /// @dev Returned when trying to trigger Beacon Chain transactions from an unauthorized address
    error OnlyBeaconChainAdmin();

    /// @dev Returned when trying to interact with a cluster ID not in the vault
    error ClusterNotInVault();

    /// @dev Returned when the number of cluster IDs and proofs mismatch in `verifyWithdrawalCredentials`
    error NumberOfClusterIDsAndProofsMismatch();
}