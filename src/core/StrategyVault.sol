// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";

import "eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import { PushSplit } from "splits-v2/splitters/push/PushSplit.sol";

import "./StrategyVaultStorage.sol";

contract StrategyVault is Initializable, StrategyVaultStorage, AccessControlUpgradeable {
    using BeaconChainProofs for *;

    /* ============== MODIFIERS ============== */

    modifier onlyNftOwner() {
        if (msg.sender != stratVaultOwner()) revert OnlyNftOwner();
        _;
    }

    modifier onlyStratVaultManager() {
        if (msg.sender != address(stratVaultManager)) revert OnlyStrategyVaultManager();
        _;
    }

    modifier onlyIfNativeRestaking() {
        if (clusterDetails.dvStatus == DVStatus.NATIVE_RESTAKING_NOT_ACTIVATED) revert NativeRestakingNotActivated();
        _;
    }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyVaultManager _stratVaultManager,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) {
        stratVaultManager = _stratVaultManager;
        auction = _auction;
        byzNft = _byzNft;
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Used to initialize the StrategyVault given it's setup parameters.
     * @param _nftId The id of the ByzNft associated to this StrategyVault.
     * @param _initialOwner The initial owner of the ByzNft.
     * @param _token The address of the token to be staked. Address(0) if staking ETH.
     * @param _whitelistedDeposit Whether the deposit function is whitelisted or not.
     * @param _upgradeable Whether the StrategyVault is upgradeable or not.
     * @dev Called on construction by the StrategyVaultManager.
     */
    function initialize(uint256 _nftId, address _initialOwner, address _token, bool _whitelistedDeposit, bool _upgradeable) external initializer {
        try byzNft.ownerOf(_nftId) returns (address nftOwner) {
            require(nftOwner == _initialOwner, "Only NFT owner can initialize the StrategyVault");
            stratVaultNftId = _nftId;
        } catch Error(string memory reason) {
            revert(string.concat("Cannot initialize StrategyVault: ", reason));
        }

        // Define the token to be staked
        depositToken = _token;

        // Setup whitelist
        whitelistedDeposit = _whitelistedDeposit;
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);

        // If contract is not upgradeable, disable initialization (removing ability to upgrade contract)
        if (!_upgradeable) {
            _disableInitializers();
        }
    }

    /* =================== FALLBACK =================== */

    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyVault contract
     * @dev Strategy Vault is the address where to send the principal ethers post exit.
     */
    receive() external payable {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
     * Also creates an EigenPod for the StrategyVault.
     * @param pubkey The 48 bytes public key of the beacon chain DV.
     * @param signature The DV's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
     * @dev If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
     * @dev The first call to this function is done by the StrategyVaultManager and creates the StrategyVault's EigenPod.
     */
    function stakeNativeETH(
        bytes calldata pubkey, 
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        // Check that the deposit is a multiple of 32 ETH
        if (deposit % 32 ether != 0) revert CanOnlyDepositMultipleOf32ETH();
        
        // If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
        if (whitelistedDeposit && !hasRole(whitelisted, msg.sender)) revert OnlyWhitelistedDeposit();
        
        // Create Eigen Pod (if not already has one) and stake the native ETH
        eigenPodManager.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    /**
     * @notice Deposit ERC20 tokens into the StrategyVault.
     * @param strategy The EigenLayer StrategyBaseTVLLimits contract for the depositing token.
     * @param token The address of the ERC20 token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function stakeERC20(IStrategy strategy, IERC20 token, uint256 amount) external {
        // If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
        if (whitelistedDeposit && !hasRole(whitelisted, msg.sender)) revert OnlyWhitelistedDeposit();

        // Check the correct token is being deposited
        if (token != depositToken) revert IncorrectToken();

        // Deposit the ERC20 tokens into the StrategyVault
        strategyManager.depositIntoStrategy(strategy, token, amount);
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
    ) external onlyNftOwner onlyIfNativeRestaking {

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
     * @notice The caller delegate its Strategy Vault's stake to an Eigen Layer operator.
     * @notice /!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.
     * @param operator The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.
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
    ) external onlyStratVaultManager {

        for (uint8 i = 0; i < CLUSTER_SIZE;) {
            clusterDetails.nodes[i] = nodes[i];
            unchecked {
                ++i;
            }
        }
        clusterDetails.splitAddr = splitAddr;
        clusterDetails.dvStatus = dvStatus;
    }

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
    ) external onlyIfNativeRestaking {
        address splitAddr = clusterDetails.splitAddr;
        PushSplit(splitAddr).distribute(_split, _token, msg.sender);
    }

    /**
     * @notice Allow the Strategy Vault's owner to withdraw the smart contract's balance.
     * @dev Revert if the caller is not the owner of the Strategy Vault's ByzNft.
     */
    function withdrawContractBalance() external onlyNftOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Change the whitelistedDeposit flag.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function changeWhitelistedDeposit(bool _whitelistedDeposit) external onlyNftOwner {
        whitelistedDeposit = _whitelistedDeposit;
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the address of the owner of the Strategy Vault's ByzNft.
     */
    function stratVaultOwner() public view returns (address) {
        return byzNft.ownerOf(stratVaultNftId);
    }
    
    /**
     * @notice Returns the status of the Distributed Validator (DV)
     */
    function getDVStatus() public view returns (DVStatus) {
        return clusterDetails.dvStatus;
    }

    /**
     * @notice Returns the DV nodes details of the Strategy Vault
     * It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.
     */
    function getDVNodesDetails() public view onlyIfNativeRestaking returns (IStrategyVault.Node[4] memory) {
        return clusterDetails.nodes;
    }

    /**
     * @notice Returns the address of the Split contract.
     * @dev Contract where the PoS rewards will be sent (both execution and consensus rewards).
     */
    function getSplitAddress() public view onlyIfNativeRestaking returns (address) {
        return clusterDetails.splitAddr;
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