// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";

interface IStrategyVault {

  enum DVStatus {
    NATIVE_RESTAKING_NOT_ACTIVATED, // Native restaking is not activated and 0 ETH has been deposited
    DEPOSITED_NOT_VERIFIED, // Deposited on ethpos but withdrawal credentials has not been verified
    ACTIVE_AND_VERIFIED, // Staked on ethpos and withdrawal credentials has been verified
    EXITED // Withdraw the principal and exit the DV
  }
  
  /// @notice Struct to store the details of a DV node registered on Byzantine 
  struct Node {
    // The number of Validation Credits (1 VC = the right to run a validator as part of a DV for a day)
    uint256 vcNumber;
    // The node reputation (TODO : Add a reputation system to the protocol)
    uint128 reputation;
    // The node's address on the execution layer
    address eth1Addr;
  }

  /// @notice Struct to store the details of a Distributed Validator created on Byzantine
  /// @dev Byzantine is the owner of the Split contract and can thus update it if the DV changes
  struct ClusterDetails {
    // The Split contract address
    address splitAddr;
    // The status of the Distributed Validator
    DVStatus dvStatus;
    // A record of the 4 nodes being part of the cluster
    Node[4] nodes;
  }

  /**
   * @notice Used to initialize the nftId of that StrategyVault and its owner.
   * @dev Called on construction by the StrategyVaultManager.
  */
  function initialize(uint256 _nftId,address _initialOwner) external;

  /**
   * @notice Returns the owner of this StrategyVault
   */
  function stratVaultNftId() external view returns (uint256);

  /**
   * @notice Returns the address of the owner of the Strategy Vault's ByzNft.
   */
  function stratVaultOwner() external view returns (address);

  /**
   * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
   * Also creates an EigenPod for the StrategyVault. The NFT owner can staker additional native ETH by calling again this function.
   * @param pubkey The 48 bytes public key of the beacon chain DV.
   * @param signature The DV's signature of the deposit data.
   * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
   * @dev Function is callable only by the StrategyVaultManager or the NFT Owner.
   * @dev The first call to this function is done by the StrategyVaultManager and creates the StrategyVault's EigenPod.
   */
  function stakeNativeETH(
    bytes calldata pubkey, 
    bytes calldata signature, 
    bytes32 depositDataRoot
  ) 
    external payable; 

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
   * @notice The caller delegate its Strategy Vault's stake to an Eigen Layer operator.
   * @notice /!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.
   * @param operator The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.
   * @dev The operator must not have set a delegation approver, everyone can delegate to it without permission.
   * @dev Ensures that:
   *          1) the `staker` is not already delegated to an operator
   *          2) the `operator` has indeed registered as an operator in EigenLayer
   */
  function delegateTo(address operator) external;

  /**
   * @notice Set the `clusterDetails` struct of the StrategyVault.
   * @param nodes An array of Node making up the DV
   * @param splitAddr The address of the Split contract.
   * @param dvStatus The status of the DV, refer to the DVStatus enum for details.
   * @dev Callable only by the StrategyVaultManager and bound a pre-created DV to this StrategyVault.
   */
  function setClusterDetails(
    Node[4] calldata nodes,
    address splitAddr,
    DVStatus dvStatus
  ) 
    external;

  /**
   * @notice Distributes the tokens issued from the PoS rewards evenly between the node operators.
   * @param _split The current split struct of the StrategyVault. Can be reconstructed offchain since the only variable is the `recipients` field.
   * @param _token The address of the token to distribute. NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
   * @dev The distributor is the msg.sender. He will earn the distribution fees.
   * @dev If the push failed, the tokens will be sent to the SplitWarehouse. NodeOp will have to call the withdraw function.
   */
  function distributeSplitBalance(
      SplitV2Lib.Split calldata _split,
      address _token
  )
    external;

  /**
   * @notice Allow the Strategy Vault's owner to withdraw the smart contract's balance.
   * @dev Revert if the caller is not the owner of the Strategy Vault's ByzNft.
   */
  function withdrawContractBalance() external;

  /**
   * @notice Call the EigenPodManager contract
   * @param data to call contract 
   */
  function callEigenPodManager(bytes calldata data) external payable returns (bytes memory);

  /**
   * @notice Returns the status of the Distributed Validator (DV)
   */
  function getDVStatus() external view returns (DVStatus);

  /**
   * @notice Returns the DV nodes details of the Strategy Vault
   * It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.
   */
  function getDVNodesDetails() external view returns (IStrategyVault.Node[4] memory);

  /**
   * @notice Returns the address of the Split contract.
   * @dev Contract where the PoS rewards will be sent (both execution and consensus rewards).
   */
  function getSplitAddress() external view returns (address);

  /// @dev Error when unauthorized call to a function callable only by the Strategy Vault Owner (aka the ByzNft holder).
  error OnlyNftOwner();

  /// @dev Error when unauthorized call to the deposit function when whitelistedDeposit is true and caller is not whitelisted.
  error OnlyWhitelistedDeposit();

  /// @dev Error when unauthorized call to a function callable only by the StrategyVaultManager.
  error OnlyStrategyVaultManager();

  /// @dev Returned when not privided the right number of nodes 
  error InvalidClusterSize();

  /// @dev Returned on failed Eigen Layer contracts call
  error CallFailed(bytes data);

  /// @dev Returned when trying to access DV data but no ETH has been deposited
  error NativeRestakingNotActivated();

  /// @dev Returned when trying to deposit an incorrect token
  error IncorrectToken();

  /// @dev Returned when trying to deposit ETH into a token StrategyVault
  error CannotDepositETHIntoTokenVault();

}