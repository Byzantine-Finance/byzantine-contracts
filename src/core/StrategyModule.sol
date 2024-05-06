// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IStrategyModule.sol";

// TODO: Allow Strategy Module ByzNft to be tradeable => conceive a fair exchange mechanism between the seller and the buyer

contract StrategyModule is IStrategyModule {
    using BeaconChainProofs for *;

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice Average time for block finality in the Beacon Chain
    uint16 internal constant FINALITY_TIME = 16 minutes;

    /// @notice The single StrategyModuleManager for Byzantine
    IStrategyModuleManager public immutable stratModManager;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice The ByzNft associated to this StrategyModule.
    /// @notice The owner of the ByzNft is the StrategyModule owner.
    uint256 public immutable stratModNftId;

    /// @notice EigenLayer's EigenPodManager contract
    /// @dev this is the pod manager transparent proxy
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /* ============== MODIFIERS ============== */

    modifier onlyStratModManager() {
        if (msg.sender != address(stratModManager)) revert OnlyStrategyModuleManager();
        _;
    }

    modifier onlyNftOwner() {
        if (msg.sender != stratModOwner()) revert OnlyNftOwner();
        _;
    }

    /* ============== CONSTRUCTOR ============== */

    constructor(
        address _stratModManagerAddr,
        IByzNft _byzNft,
        uint256 _nftId,
        address _eigenPodManagerAddr,
        address _delegationManagerAddr
    ) {
        stratModManager = IStrategyModuleManager(_stratModManagerAddr);
        byzNft = _byzNft;
        eigenPodManager = IEigenPodManager(_eigenPodManagerAddr);
        delegationManager = IDelegationManager(_delegationManagerAddr);
        stratModNftId = _nftId;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates an EigenPod for the strategy module.
     * @dev Function will revert if not called by the StrategyModule owner.
     * @dev Function will revert if the StrategyModule already has an EigenPod.
     * @dev Returns EigenPod address
     */
    function createPod() external onlyNftOwner returns (address) {
        return eigenPodManager.createPod();
    }

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
    ) external payable onlyNftOwner {
        eigenPodManager.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    /**
     * @notice Call the EigenPodManager contract
     * @param data to call contract 
     */
    function callEigenPodManager(bytes calldata data) external payable onlyStratModManager returns (bytes memory) {
        return _executeCall(payable(address(eigenPodManager)), msg.value, data);
    }

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
    ) external onlyNftOwner {

        IEigenPod myPod = eigenPodManager.ownerToPod(address(this));

        myPod.verifyWithdrawalCredentials(
            proofTimestamp,
            stateRootProof,
            validatorIndices,
            validatorFieldsProofs,
            validatorFields
        );

    }

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
    ) external {

        IEigenPod myPod = eigenPodManager.ownerToPod(address(this));

        myPod.verifyBalanceUpdates(
            proofTimestamp,
            validatorIndices,
            stateRootProof,
            validatorFieldsProofs,
            validatorFields
        );

    }

    /**
     * @notice The caller delegate its Strategy Module's stake to an Eigen Layer operator.
     * @notice /!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.
     * @param operator The account teh STrategy Module is delegating its assets to for use in serving applications built on EigenLayer.
     * @dev The operator must not have set a delegation approver, everyone can delegate to it without permission.
     * @dev Ensures that:
     *          1) the `staker` is not already delegated to an operator
     *          2) the `operator` has indeed registered as an operator in EigenLayer
     */
    function delegateTo(address operator) external onlyNftOwner {

        // Create an empty delegation approver signature
        ISignatureUtils.SignatureWithExpiry memory emptySignatureAndExpiry;

        delegationManager.delegateTo(operator, emptySignatureAndExpiry, bytes32(0));
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the address of the owner of the Strategy Module's ByzNft.
     */
    function stratModOwner() public view returns (address) {
        return byzNft.ownerOf(stratModNftId);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @notice Execute a low level call
     * @param to address to execute call
     * @param value amount of ETH to send with call
     * @param data bytes array to execute
     */
    function _executeCall(
        address payable to,
        uint256 value,
        bytes memory data
    ) private returns (bytes memory) {
        (bool success, bytes memory retData) = address(to).call{value: value}(data);
        if (!success) revert CallFailed(data);
        return retData;
    }

}