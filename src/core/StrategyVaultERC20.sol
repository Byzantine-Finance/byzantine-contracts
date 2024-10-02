// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {ERC4626MultiRewardVault} from "../vault/ERC4626MultiRewardVault.sol";
import "./StrategyVaultERC20Storage.sol";

contract StrategyVaultERC20 is Initializable, StrategyVaultERC20Storage, ERC4626MultiRewardVault {

    /* ============== MODIFIERS ============== */

    modifier onlyNftOwner() {
        if (msg.sender != stratVaultOwner()) revert OnlyNftOwner();
        _;
    }

    modifier onlyStratVaultManager() {
        if (msg.sender != address(stratVaultManager)) revert OnlyStrategyVaultManager();
        _;
    }

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IStrategyVaultManager _stratVaultManager,
        IByzNft _byzNft,
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager
    ) {
        stratVaultManager = _stratVaultManager;
        byzNft = _byzNft;
        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @notice Used to initialize the StrategyVault given it's setup parameters.
     * @param _nftId The id of the ByzNft associated to this StrategyVault.
     * @param _token The address of the token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking ETH.
     * @param _whitelistedDeposit Whether the deposit function is whitelisted or not.
     * @param _upgradeable Whether the StrategyVault is upgradeable or not.
     * @param _oracle The oracle implementation to use for the vault.
     * @dev Called on construction by the StrategyVaultManager.
     */
    function initialize(uint256 _nftId, address _token, bool _whitelistedDeposit, bool _upgradeable, address _oracle) external initializer {

        // Setup whitelist
        stratVaultNftId = _nftId;
        whitelistedDeposit = _whitelistedDeposit;
        upgradeable = _upgradeable;

        // Initialize the ERC4626MultiRewardVault
        ERC4626MultiRewardVault.initialize(IERC20MetadataUpgradeable(_token), _oracle);

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
     * @notice Deposit ERC20 tokens into the StrategyVault.
     * @param strategy The EigenLayer StrategyBaseTVLLimits contract for the depositing token.
     * @param token The address of the ERC20 token to deposit.
     * @param amount The amount of tokens to deposit.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
     */
    function stakeERC20(IStrategy strategy, IERC20 token, uint256 amount) external {
        // If whitelistedDeposit is true, then only users with the whitelisted role can call this function.
        //if (whitelistedDeposit && !hasRole(whitelisted, msg.sender)) revert OnlyWhitelistedDeposit();

        // Check the correct token is being deposited
        if (address(token) != asset()) revert IncorrectToken();

        // Stake the ERC20 tokens into StrategyVault
        super.deposit(amount, msg.sender);

        // Deposit the ERC20 tokens into the EigenLayer StrategyManager
        //strategyManager.depositIntoStrategy(strategy, token, amount);

        // Update the amount of tokens that the StrategyVault is delegating
        //delegationManager.increaseDelegatedShares(address(this), strategy, amount);
    }

    /**
     * @notice Begins the withdrawal process to pull ERC20 tokens out of the StrategyVault
     * @param queuedWithdrawalParams TODO: Fill in
     * @param strategies An array of strategy contracts for all tokens being withdrawn from EigenLayer.
     * @dev Withdrawal is not instant - a withdrawal delay exists for removing the assets from EigenLayer
     */
    function startWithdrawERC20(
        IDelegationManager.QueuedWithdrawalParams[] calldata queuedWithdrawalParams,
        IStrategy[] calldata strategies
        ) external {
        // Begins withdrawal procedure with EigenLayer.
        delegationManager.queueWithdrawals(queuedWithdrawalParams);

        // Calculate the withdrawal delay
        uint256 withdrawalDelay = delegationManager.getWithdrawalDelay(strategies);

        // Setup scheduled function call for finishWithdrawERC20 after withdrawal delay is finished.
        // TODO
    }

    /**
     * @notice Finalizes the withdrawal of ERC20 tokens from the StrategyVault
     * @param withdrawal TODO: Fill in
     * @param tokens TODO: Fill in
     * @param middlewareTimesIndex TODO: Fill in
     * @param receiveAsTokens TODO: Fill in
     * @dev Can only be called after the withdrawal delay is finished
     */
    // function finishWithdrawERC20(
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
        
    //     // Burn caller's shares and exchange for deposit token + reward tokens
    //     super.withdraw(assetAmount, receiver, msg.sender);
    // }

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
     * @notice Updates the whitelistedDeposit flag.
     * @param _whitelistedDeposit The new whitelistedDeposit flag.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function updateWhitelistedDeposit(bool _whitelistedDeposit) external onlyNftOwner {
        whitelistedDeposit = _whitelistedDeposit;
    }

    /**
     * @notice Whitelist a staker.
     * @param staker The address to whitelist.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function whitelistStaker(address staker) external onlyNftOwner {
        if (!whitelistedDeposit) revert WhitelistedDepositDisabled();
        if (isWhitelisted[staker]) revert StakerAlreadyWhitelisted();
        isWhitelisted[staker] = true;
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the address of the owner of the Strategy Vault's ByzNft.
     */
    function stratVaultOwner() public view returns (address) {
        return byzNft.ownerOf(stratVaultNftId);
    }

    /**
     * @notice Returns the Eigen Layer operator that the Strategy Vault is delegated to
     */
    function hasDelegatedTo() public view returns (address) {
        return delegationManager.delegatedTo(address(this));
    }

    /* ============== INTERNAL FUNCTIONS ============== */

}