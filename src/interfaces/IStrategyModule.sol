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
    uint256 reputation;
    // The node's address on the execution layer
    address eth1Addr;
  }

  /// @notice Struct to store the details of a Distributed Validator created on Byzantine
  struct ClusterDetails {
    // Must be calculated / verified offchain by Byzantine to ensure the integrity of the DV's deposit data 
    bytes trustedPubKey;
    // The node responsible to deposit the 32ETH on the Beacon Chain
    address clusterManager;
    // The status of the Distributed Validator
    DVStatus dvStatus;
    // A record of the 4 nodes being part of the cluster
    Node[4] nodes;
  }

  /**
   * @notice Used to initialize the  nftId of that StrategyModule.
   * @dev Called on construction by the StrategyModuleManager.
   */
  function initialize(uint256 _nftId) external;

  /**
   * @notice Returns the owner of this StrategyModule
   */
  function stratModNftId() external view returns (uint256);

  /**
   * @notice Returns the address of the owner of the Strategy Module's ByzNft.
   */
  function stratModOwner() external view returns (address);

  /**
   * @notice Creates an EigenPod for the strategy module.
   * @dev Function will revert if not called by the StrategyModule owner or StrategyModuleManager.
   * @dev Function will revert if the StrategyModule already has an EigenPod.
   * @dev Returns EigenPod address
   */
  function createPod() external returns (address);

  /**
   * @notice Deposit 32ETH from the contract's balance in the beacon chain to activate a Distributed Validator.
   * @param pubkey The 48 bytes public key of the beacon chain DV.
   * @param signature The DV's signature of the deposit data.
   * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
   * @dev Function is callable only by the StrategyModule owner or the cluster manager => Byzantine is non-custodian
   * @dev Byzantine or Strategy Module owner must first initialize the trusted pubkey of the DV.
   */
  function beaconChainDeposit(
    bytes calldata pubkey, 
    bytes calldata signature, 
    bytes32 depositDataRoot
  ) 
    external; 

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
   * @notice Edit the `clusterDetails` struct once the auction is over
   * @param nodes An array of Node making up the DV (the first `CLUSTER_SIZE` winners of the auction)
   * @param clusterManager The node responsible for handling the DKG and deposit the 32ETH in the Beacon Chain (more rewards to earn)
   * @dev Callable only by the AuctionContract. Should be called once an auction is over and `CLUSTER_SIZE` validators have been selected.
   * @dev Reverts if the `nodes` array is not of length `CLUSTER_SIZE`.
   */
  function updateClusterDetails(
    Node[] calldata nodes,
    address clusterManager
  ) 
    external;

  /**
   * @notice StrategyModuleManager or Owner fill the expected/ trusted public key for its DV (retrievable from the Obol SDK/API).
   * @dev Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator (in `beaconChainDeposit`)
   * @param trustedPubKey The public key of the DV retrieved with the Obol SDK/API from the configHash
   * @dev Revert if the pubkey is not 48 bytes long.
   * @dev Revert if not callable by StrategyModuleManager or StrategyModule owner.
   */
  function setTrustedDVPubKey(bytes calldata trustedPubKey) external;

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
   * @notice Returns the DV's public key set by a trusted party
   */
  function getTrustedDVPubKey() external view returns (bytes memory);

  /**
   * @notice Returns the status of the Distributed Validator (DV)
   */
  function getDVStatus() external view returns (DVStatus);

  /**
   * @notice Returns the DV's cluster manager
   */
  function getClusterManager() external view returns (address);

  /**
   * @notice Returns the DV's nodes' eth1 addresses
   */
  function getDVNodesAddr() external view returns (address[] memory);


  /// @dev Error when unauthorized call to a function callable only by the Strategy Module Owner (aka the ByzNft holder).
  error OnlyNftOwner();

  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleOwner or the StrategyModuleManager.
  error OnlyStrategyModuleOwnerOrManager();
  
  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleOwner or the DV Manager.
  error OnlyStrategyModuleOwnerOrDVManager();

  /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
  error OnlyStrategyModuleManager();

  /// @dev Returned when unauthorized call to a function only callable by the Auction contract
  error OnlyAuctionContract();

  /// @dev Returned when not privided the right number of nodes 
  error InvalidClusterSize();

  /// @dev Returned on failed Eigen Layer contracts call
  error CallFailed(bytes data);

}