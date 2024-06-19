// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IStrategyModule.sol";
import "../interfaces/IAuction.sol";

// TODO: Allow Strategy Module ByzNft to be tradeable => conceive a fair exchange mechanism between the seller and the buyer

contract StrategyModule is IStrategyModule, Initializable {
    using BeaconChainProofs for *;

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice Average time for block finality in the Beacon Chain
    uint16 internal constant FINALITY_TIME = 16 minutes;

    uint8 internal constant CLUSTER_SIZE = 4;

    /// @notice The single StrategyModuleManager for Byzantine
    IStrategyModuleManager public immutable stratModManager;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Address of the Auction contract
    IAuction public immutable auction;

    /// @notice EigenLayer's EigenPodManager contract
    /// @dev this is the pod manager transparent proxy
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /* ============== STATE VARIABLES ============== */

    /// @notice The ByzNft associated to this StrategyModule.
    /// @notice The owner of the ByzNft is the StrategyModule owner.
    /// TODO When non-upgradeable put that variable immutable and set it in the constructor
    uint256 public stratModNftId;

    // Empty struct, all the fields have their default value
    ClusterDetails public clusterDetails;

    /* ============== MODIFIERS ============== */

    modifier onlyNftOwner() {
        if (msg.sender != stratModOwner()) revert OnlyNftOwner();
        _;
    }

    modifier onlyNftOwnerOrStratModManager() {
        if (msg.sender != stratModOwner() && msg.sender != address(stratModManager)) revert OnlyNftOwnerOrStrategyModuleManager();
        _;
    }

    modifier onlyStratModManager() {
        if (msg.sender != address(stratModManager)) revert OnlyStrategyModuleManager();
        _;
    }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyModuleManager _stratModManager,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) {
        stratModManager = _stratModManager;
        auction = _auction;
        byzNft = _byzNft;
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Used to initialize the nftId of that StrategyModule and its owner.
     * @dev Called on construction by the StrategyModuleManager.
     */
    function initialize(uint256 _nftId, address _initialOwner) external initializer {
        try byzNft.ownerOf(_nftId) returns (address nftOwner) {
            require(nftOwner == _initialOwner, "Only NFT owner can initialize the StrategyModule");
            stratModNftId = _nftId;
        } catch Error(string memory reason) {
            revert(string.concat("Cannot initialize StrategyModule: ", reason));
        }
    }

    /* =================== FALLBACK =================== */

    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyModule contract
     * @dev Strategy Module is the address where to send the principal ethers post exit.
     */
    receive() external payable {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

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
    ) external payable onlyNftOwnerOrStratModManager {
        // Create Eigen Pod (if not already has one) and stake the native ETH
        eigenPodManager.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    /**
     * @notice Call the EigenPodManager contract
     * @param data to call contract 
     */
    function callEigenPodManager(bytes calldata data) external payable onlyNftOwner returns (bytes memory) {
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

        // Update DV Status to ACTIVE_AND_VERIFIED
        clusterDetails.dvStatus = DVStatus.ACTIVE_AND_VERIFIED;

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

    /**
     * @notice Set the `clusterDetails` struct of the StrategyModule.
     * @param nodes An array of Node making up the DV
     * @param dvStatus The status of the DV, refer to the DVStatus enum for details.
     * @dev Callable only by the StrategyModuleManager and bound a pre-created DV to this StrategyModule.
     */
    function setClusterDetails(
        Node[4] calldata nodes,
        DVStatus dvStatus
    ) external onlyStratModManager {

        for (uint8 i = 0; i < CLUSTER_SIZE;) {
            clusterDetails.nodes[i] = nodes[i];
            unchecked {
                ++i;
            }
        }

        clusterDetails.dvStatus = dvStatus;
    }

    /**
     * @notice Allow the Strategy Module's owner to withdraw the smart contract's balance.
     * @dev Revert if the caller is not the owner of the Strategy Module's ByzNft.
     */
    function withdrawContractBalance() external onlyNftOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the address of the owner of the Strategy Module's ByzNft.
     */
    function stratModOwner() public view returns (address) {
        return byzNft.ownerOf(stratModNftId);
    }
    
    /**
     * @notice Returns the status of the Distributed Validator (DV)
     */
    function getDVStatus() public view returns (DVStatus) {
        return clusterDetails.dvStatus;
    }

    /**
     * @notice Returns the DV nodes details of the Strategy Module
     * It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.
     */
    function getDVNodesDetails() public view returns (IStrategyModule.Node[4] memory) {
        return clusterDetails.nodes;
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