// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";

interface IStrategyModule {

  enum DVStatus {
    WAITING_ACTIVATION, // Waiting for the cluster manager to deposit the 32ETH on the Beacon Chain
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
  struct ClusterDetails {
    // The status of the Distributed Validator
    DVStatus dvStatus;
    // A record of the 4 nodes being part of the cluster
    Node[4] nodes;
  }

  /**
   * @notice Used to initialize the nftId of that StrategyModule and its owner.
   * @dev Called on construction by the StrategyModuleManager.
  */
  function initialize(uint256 _nftId,address _initialOwner) external;

  /**
   * @notice Returns the owner of this StrategyModule
   */
  function stratModNftId() external view returns (uint256);

  /**
   * @notice Returns the address of the owner of the Strategy Module's ByzNft.
   */
  function stratModOwner() external view returns (address);

  /**
   * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
   * Also creates an EigenPod for the StrategyModule. The NFT owner can staker additional native ETH by calling again this function.
   * @param pubkey The 48 bytes public key of the beacon chain DV.
   * @param signature The DV's signature of the deposit data.
   * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
   * @dev Function is callable only by the StrategyModuleManager or the NFT Owner.
   * @dev The first call to this function is done by the StrategyModuleManager and creates the StrategyModule's EigenPod.
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

  /**
   * @notice Set the `clusterDetails` struct of the StrategyModule.
   * @param nodes An array of Node making up the DV
   * @param dvStatus The status of the DV, refer to the DVStatus enum for details.
   * @dev Callable only by the StrategyModuleManager and bound a pre-created DV to this StrategyModule.
   */
  function setClusterDetails(
    Node[4] calldata nodes,
    DVStatus dvStatus
  ) 
    external;

  /**
   * @notice Allow the Strategy Module's owner to withdraw the smart contract's balance.
   * @dev Revert if the caller is not the owner of the Strategy Module's ByzNft.
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
   * @notice Returns the DV nodes details of the Strategy Module
   * It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.
   */
  function getDVNodesDetails() external view returns (IStrategyModule.Node[4] memory);


  /// @dev Error when unauthorized call to a function callable only by the Strategy Module Owner (aka the ByzNft holder).
  error OnlyNftOwner();

  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleOwner or the StrategyModuleManager.
  error OnlyNftOwnerOrStrategyModuleManager();

  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
  error OnlyStrategyModuleManager();

  /// @dev Returned when not privided the right number of nodes 
  error InvalidClusterSize();

  /// @dev Returned on failed Eigen Layer contracts call
  error CallFailed(bytes data);

}