// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {BeaconChainProofs} from "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import {ISignatureUtils} from "eigenlayer-contracts/interfaces/ISignatureUtils.sol";

import {ERC4626MultiRewardVault} from "../vault/ERC4626MultiRewardVault.sol";
import "./StrategyVaultETHStorage.sol";

// TODO: Finish withdrawal logic
import "../vault/ERC4626ETHMultiRewardVault.sol";

contract StrategyVaultETH is Initializable, StrategyVaultETHStorage, ERC4626ETHMultiRewardVault {
    using FIFOLib for FIFOLib.FIFO;
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

    modifier checkWhitelist() {
        if (whitelistedDeposit && !isWhitelisted[msg.sender]) revert OnlyWhitelistedDeposit();
        _;
    }

    modifier checkDelegator() {
        if (msg.sender != address(stratVaultManager)) { // delegation during the vault creation
            if (!upgradeable || msg.sender != stratVaultOwner()) revert OnlyNftOwner();
        }
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
     * @notice Used to initialize the StrategyVaultETH given it's setup parameters.
     * @param _nftId The id of the ByzNft associated to this StrategyVault.
     * @param _stratVaultCreator The address of the creator of the StrategyVault.
     * @param _whitelistedDeposit Whether the deposit function is whitelisted or not.
     * @param _upgradeable Whether the StrategyVault is upgradeable or not.
     * @param _oracle The oracle implementation to use for the vault.
     * @dev Called on construction by the StrategyVaultManager.
     * @dev StrategyVaultETH so the deposit token is 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
     */
    function initialize(uint256 _nftId, address _stratVaultCreator, bool _whitelistedDeposit, bool _upgradeable, address _oracle) external initializer {

        // Set up the vault state variables
        stratVaultNftId = _nftId;
        whitelistedDeposit = _whitelistedDeposit;
        upgradeable = _upgradeable;        

        // Initialize the ERC4626ETHMultiRewardVault
        __ERC4626ETHMultiRewardVault_init(_oracle);

        // If whitelisted Vault, whitelist the creator
        if (_whitelistedDeposit) {
            isWhitelisted[_stratVaultCreator] = true;
        }
    }

    /* =================== FALLBACK =================== */

    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyVault contract
     * @dev Strategy Vault is the address where to send the principal ethers post exit.
     */
    receive() external override payable {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    // /**
    //  * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
    //  * Also creates an EigenPod for the StrategyVault.
    //  * @param pubkey The 48 bytes public key of the beacon chain DV.
    //  * @param signature The DV's signature of the deposit data.
    //  * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
    //  * @dev If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
    //  * @dev The first call to this function is done by the StrategyVaultManager and creates the StrategyVault's EigenPod.
    //  * @dev The caller receives Byzantine StrategyVault shares in return for the ETH staked.
    //  */
    // function stakeNativeETH(
    //     bytes calldata pubkey, 
    //     bytes calldata signature,
    //     bytes32 depositDataRoot
    // ) external payable {
    //     /// TODO Check the whitelist --> creator is whitelisted in initialize function
    //     /// TODO Put these checks in a modifier
    //     /// TODO Remove the roles
    //     /// if (whitelistedDeposit && !hasRole(whitelisted, msg.sender)) revert OnlyWhitelistedDeposit();

    //     // Check that the deposit is a multiple of 32 ETH
    //     if (msg.value % 32 ether != 0) revert CanOnlyDepositMultipleOf32ETH();

    //     // Calculate how many bundles of 32 ETH were sent
    //     uint256 num32ETHBundles = msg.value / 32 ether;

    //     // Trigger an auction for each bundle of 32 ETH
    //     for (uint256 i = 0; i < num32ETHBundles;) {
    //         bytes32 winningClusterId = auction.triggerAuction();
    //         clusterIdsFIFO.push(winningClusterId);
    //         unchecked {
    //             ++i;
    //         }
    //     }
        
    //     // Mint vault shares to the staker in return for the ETH staked
    //     _mintVaultShares(msg.value, msg.sender);

    //     // Create Eigen Pod (if not already has one) and stake the native ETH
    //     // eigenPodManager.stake{value: msg.value}(pubkey, signature, depositDataRoot);

    // }

    /**
     * @notice Deposit ETH to the StrategyVault and get Vault shares in return.
     * @dev If first deposit, create an Eigen Pod for the StrategyVault.
     * @dev If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ETH staked.
     * @dev Revert if the amount deposited is not a multiple of 32 ETH.
     * @dev Trigger auction(s) for each bundle of 32 ETH deposited to get Distributed Validator(s)
     */
    function stakeNativeETH() external payable checkWhitelist {

        // Check that the deposit is a multiple of 32 ETH
        if (msg.value % 32 ether != 0) revert CanOnlyDepositMultipleOf32ETH();

        // Calculate how many bundles of 32 ETH were sent
        uint256 num32ETHBundles = msg.value / 32 ether;

        // Trigger an auction for each bundle of 32 ETH
        for (uint256 i = 0; i < num32ETHBundles;) {
            bytes32 winningClusterId = auction.triggerAuction();
            clusterIdsFIFO.push(winningClusterId);
            unchecked {
                ++i;
            }
        }
        
        // Mint vault shares to the staker in return for the ETH staked
        _mintVaultShares(msg.value, msg.sender);
    }

    /**
     * @notice Begins the withdrawal process to pull ETH out of the StrategyVault
     * @param queuedWithdrawalParams TODO: Fill in
     * @param strategies An array of strategy contracts for all tokens being withdrawn from EigenLayer.
     * @dev Withdrawal is not instant - a withdrawal delay exists for removing the assets from EigenLayer
     */
    function startWithdrawETH(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams,
        IStrategy[] memory strategies
        ) external {
        // Begins withdrawal procedure with EigenLayer.
        delegationManager.queueWithdrawals(queuedWithdrawalParams);

        // Calculate the withdrawal delay
        uint256 withdrawalDelay = delegationManager.getWithdrawalDelay(strategies);

        // Setup scheduled function call for finishWithdrawETH after withdrawal delay is finished.
        // TODO
    }

    /**
     * @notice Finalizes the withdrawal of ETH from the StrategyVault
     * @param withdrawal TODO: Fill in
     * @param tokens TODO: Fill in
     * @param middlewareTimesIndex TODO: Fill in
     * @param receiveAsTokens TODO: Fill in
     * @dev Can only be called after the withdrawal delay is finished
     */
    // function finishWithdrawETH(
    //     withdrawal,
    //     tokens[],
    //     middlewareTimesIndex,
    //     receiveAsTokens
    // ) external {
    //     // Have StrategyVault unstake from the EigenLayer Strategy contract
    //     delegationManager.completeQueuedWithdrawal(
    //         /*
    //         Withdrawal calldata withdrawal,
    //         IERC20[] calldata tokens,
    //         uint256 middlewareTimesIndex,
    //         bool receiveAsTokens
    //         */
    //     );
        
    //     // Burn caller's shares and exchange for deposit asset (ETH) + reward tokens
    //     super.withdraw(assetAmount, receiver, msg.sender);
    // }

    /* ============== VAULT CREATOR FUNCTIONS ============== */

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
     * @param strategy The EigenLayer StrategyBaseTVLLimits contract for the depositing token.
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
        bytes32[][] calldata validatorFields,
        IStrategy strategy
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
        // clusterDetails.dvStatus = DVStatus.ACTIVE_AND_VERIFIED;

        // Update the amount of tokens that the StrategyVault is delegating.
        // delegationManager.increaseDelegatedShares(address(this), strategy, amount);
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
    function delegateTo(address operator) external checkDelegator {

        // Create an empty delegation approver signature
        ISignatureUtils.SignatureWithExpiry memory emptySignatureAndExpiry;

        delegationManager.delegateTo(operator, emptySignatureAndExpiry, bytes32(0));
    }

    /**
     * @notice Change the whitelistedDeposit flag.
     * @param _whitelistedDeposit The new whitelistedDeposit flag.
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
     * @notice Returns the number of active DVs staked by the Strategy Vault.
     */
    function getVaultDVNumber() public view returns (uint256) {
        return clusterIdsFIFO.getNumElements();
    }

    /**
     * @notice Returns the IDs of the active DVs staked by the Strategy Vault.
     */
    function getAllDVIds() public view returns (bytes32[] memory) {
        return clusterIdsFIFO.getAllElements();
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _mintVaultShares(uint256 amount, address receiver) internal {
        if (receiver != address(stratVaultManager)) {
            deposit(amount, receiver);
        } else {
            deposit(amount, stratVaultOwner());
        }
    }

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