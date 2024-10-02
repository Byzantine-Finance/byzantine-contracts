// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BeaconChainProofs} from "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";

import "./IStrategyVault.sol";

interface IStrategyVaultETH is IStrategyVault {

  /* ============== GETTERS ============== */

  /// @notice Get the address of the beacon chain admin
  function beaconChainAdmin() external view returns (address);

    /* ============== INITIALIZER ============== */

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

    /* ============== EXTERNAL FUNCTIONS ============== */

  /**
   * @notice Deposit ETH to the StrategyVault and get Vault shares in return.
   * @dev If first deposit, create an Eigen Pod for the StrategyVault.
   * @dev If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
   * @dev The caller receives Byzantine StrategyVault shares in return for the ETH staked.
   * @dev Revert if the amount deposited is not a multiple of 32 ETH.
   * @dev Trigger auction(s) for each bundle of 32 ETH deposited to get Distributed Validator(s)
   */
  function stakeNativeETH() external payable; 

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
   * @notice This function verifies that the withdrawal credentials of the Distributed Validator(s) owned by
   * the stratVaultOwner are pointed to the EigenPod of this contract. It also verifies the effective balance of the DV.
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
   * @notice Call the EigenPodManager contract
   * @param data to call contract 
   */
  function callEigenPodManager(bytes calldata data) external payable returns (bytes memory);

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

    /// @dev Returned when not provided the right number of nodes 
    error InvalidClusterSize();

    /// @dev Returned when trying to deposit an incorrect amount of ETH. Can only deposit a multiple of 32 ETH. (32, 64, 96, 128, etc.)
    error CanOnlyDepositMultipleOf32ETH();

    /// @dev Returned when trying to access DV data but no ETH has been deposited
    error NativeRestakingNotActivated();

    /// @dev Returned when trying to trigger Beacon Chain transactions from an unauthorized address
    error OnlyBeaconChainAdmin();

    /// @dev Returned when trying to interact with a cluster ID not in the vault
    error ClusterNotInVault();

}