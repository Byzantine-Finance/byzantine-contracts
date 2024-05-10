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

    uint8 internal constant CLUSTER_SIZE = 4;

    /// @notice The single StrategyModuleManager for Byzantine
    IStrategyModuleManager public immutable stratModManager;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice EigenLayer's EigenPodManager contract
    /// @dev this is the pod manager transparent proxy
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /// @notice Address of the Auction contract
    address public immutable auctionAddr;

    /// @notice The ByzNft associated to this StrategyModule.
    /// @notice The owner of the ByzNft is the StrategyModule owner.
    uint256 public immutable stratModNftId;

    /* ============== STATE VARIABLES ============== */

    // Empty struct, all the fields have their default value
    ClusterDetails public clusterDetails;

    /* ============== MODIFIERS ============== */

    modifier onlyNftOwner() {
        if (msg.sender != stratModOwner()) revert OnlyNftOwner();
        _;
    }

    modifier onlyStratModOwnerOrManager() {
        if (msg.sender != stratModOwner() && msg.sender != address(stratModManager)) revert OnlyStrategyModuleOwnerOrManager();
        _;
    }

    modifier onlyStratModOwnerOrDVManager() {
        if (msg.sender != stratModOwner() && msg.sender != clusterDetails.clusterManager) revert OnlyStrategyModuleOwnerOrDVManager();
        _;
    }

    modifier onlyAuctionContract() {
        if (msg.sender != auctionAddr) revert OnlyAuctionContract();
        _;
    }

    /* ============== CONSTRUCTOR ============== */

    constructor(
        address _stratModManagerAddr,
        address _auctionAddr,
        IByzNft _byzNft,
        uint256 _nftId,
        address _eigenPodManagerAddr,
        address _delegationManagerAddr
    ) {
        stratModManager = IStrategyModuleManager(_stratModManagerAddr);
        auctionAddr = _auctionAddr;
        byzNft = _byzNft;
        eigenPodManager = IEigenPodManager(_eigenPodManagerAddr);
        delegationManager = IDelegationManager(_delegationManagerAddr);
        stratModNftId = _nftId;
    }

    /* =================== FALLBACK =================== */

    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyModule contract
     * @dev Used by the StrategyModuleManager to send the staker's deposited ETH while waiting for the DV creation.
     * @dev Strategy Module is the address where to send the principal ethers post exit.
     */
    receive() external payable {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates an EigenPod for the strategy module.
     * @dev Function will revert if not called by the StrategyModule owner or StrategyModuleManager.
     * @dev Function will revert if the StrategyModule already has an EigenPod.
     * @dev Returns EigenPod address
     */
    function createPod() external onlyStratModOwnerOrManager returns (address) {
        return eigenPodManager.createPod();
    }

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
    ) external onlyStratModOwnerOrDVManager {
        require(clusterDetails.trustedPubKey.length > 0, "StrategyModule.beaconChainDeposit: Trusted pubkey not initialized");
        require(_isValidPubKey(clusterDetails.trustedPubKey, pubkey), "StrategyModule.beaconChainDeposit: Invalid DV pubkey");
        require(address(this).balance >= 32 ether, "StrategyModule.beaconChainDeposit: Insufficient Strategy Module balance to activate the Distributed Validator");

        eigenPodManager.stake{value: 32 ether}(pubkey, signature, depositDataRoot);
        
        // Update DV Status to DEPOSITED_NOT_VERIFIED
        clusterDetails.dvStatus = DVStatus.DEPOSITED_NOT_VERIFIED;
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
     * @notice Edit the `clusterDetails` struct once the auction is over
     * @param nodes An array of Node making up the DV (the first `CLUSTER_SIZE` winners of the auction)
     * @param clusterManager The node responsible for handling the DKG and deposit the 32ETH in the Beacon Chain (more rewards to earn)
     * @dev Callable only by the AuctionContract. Should be called once an auction is over and `CLUSTER_SIZE` validators have been selected.
     * @dev Reverts if the `nodes` array is not of length `CLUSTER_SIZE`.
     */
    function updateClusterDetails(
        Node[] calldata nodes,
        address clusterManager
    ) external onlyAuctionContract {
        if (nodes.length != CLUSTER_SIZE) revert InvalidClusterSize();

        for (uint i = 0; i < CLUSTER_SIZE;) {
            clusterDetails.nodes[i] = nodes[i];
            unchecked {
                ++i;
            }
        }
        clusterDetails.clusterManager = clusterManager;
    }

    /**
     * @notice StrategyModuleManager or Owner fill the expected/ trusted public key for its DV (retrievable from the Obol SDK/API).
     * @dev Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator (in `beaconChainDeposit`)
     * @param trustedPubKey The public key of the DV retrieved with the Obol SDK/API from the configHash
     * @dev Revert if the pubkey is not 48 bytes long.
     * @dev Revert if not callable by StrategyModuleManager or StrategyModule owner.
     */
    function setTrustedDVPubKey(bytes calldata trustedPubKey) external onlyStratModOwnerOrManager {
        require(trustedPubKey.length == 48, "StrategyModuleManager.setDVPubKey: invalid pubkey length");
        clusterDetails.trustedPubKey = trustedPubKey;
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
     * @notice Returns the DV's public key set by a trusted party
     */
    function getTrustedDVPubKey() public view returns (bytes memory) {
        return clusterDetails.trustedPubKey;
    }
    
    /**
     * @notice Returns the status of the Distributed Validator (DV)
     */
    function getDVStatus() public view returns (DVStatus) {
        return clusterDetails.dvStatus;
    }

    /**
     * @notice Returns the DV's cluster manager
     */
    function getClusterManager() public view returns (address) {
        return clusterDetails.clusterManager;
    }

    /**
     * @notice Returns the DV's nodes' eth1 addresses
     */
    function getDVNodesAddr() public view returns (address[] memory) {
        address[] memory nodesAddr = new address[](CLUSTER_SIZE);
        for (uint i = 0; i < CLUSTER_SIZE;) {
            nodesAddr[i] = clusterDetails.nodes[i].eth1Addr;
            unchecked {
                ++i;
            }
        }
        return nodesAddr;
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

    /**
     * @notice Verify the public key provided by cluster Manager before depositing the ETH.
     * @param trustedPubKey The public key verified by Byzantine or the Strategy Module owner.
     * @param untrustedPubKey The public key provided by the cluster Manager when depositing the ETH.
     * @return true if the public keys match, false otherwise.
     */
    function _isValidPubKey(bytes memory trustedPubKey, bytes memory untrustedPubKey) private pure returns (bool) {
        for (uint8 i = 0; i < 48;) {
            if (trustedPubKey[i] != untrustedPubKey[i]) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

}