// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";

import "./StrategyVaultStorage.sol";
import "../vault/ERC4626MultiRewardVault.sol";

contract StrategyVault is Initializable, StrategyVaultStorage, AccessControlUpgradeable, ERC4626MultiRewardVault {

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
     * @param _initialOwner The initial owner of the ByzNft.
     * @param _token The address of the token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking ETH.
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

        // Initialize the ERC4626MultiRewardVault
        ERC4626MultiRewardVault.initialize(_token);

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
        if (whitelistedDeposit && !hasRole(whitelisted, msg.sender)) revert OnlyWhitelistedDeposit();

        // Check the correct token is being deposited
        if (token != depositToken) revert IncorrectToken();

        // Stake the ERC20 tokens into StrategyVault
        ERC4626MultiRewardVault.deposit(amount, msg.sender);

        // Deposit the ERC20 tokens into the EigenLayer StrategyManager
        strategyManager.depositIntoStrategy(strategy, token, amount);
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