// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC7535Upgradeable} from "./ERC7535/ERC7535Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/**
 * @title ERC7535MultiRewardVault
 * @author Byzantine-Finance
 * @notice ERC-7535: Native Asset ERC-4626 Tokenized Vault with support for multiple reward tokens
 */
contract ERC7535MultiRewardVault is ERC7535Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ============== STATE VARIABLES ============== */

    /// @notice List of reward tokens
    address[] public rewardTokens;

    /// @notice Oracle implementation
    IOracle public oracle;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

    /* ============== CUSTOM ERRORS ============== */

    error TokenAlreadyAdded();
    error InvalidAddress();
    error TokenDoesNotHaveDecimalsFunction(address token);
    error TokenHasMoreThan18Decimals(address token);
    /* ============== EVENTS ============== */

    event RewardTokenAdded(address indexed token);
    event OracleUpdated(address newOracle);
    event RewardTokenWithdrawn(address indexed receiver, address indexed rewardToken, uint256 amount);
    
    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /**
     * @notice Initializes the ERC7535MultiRewardVault contract.
     * @param _oracle The oracle implementation address to use for the vault.
     */
    function initialize(address _oracle) public virtual initializer {
        __ERC7535MultiRewardVault_init(_oracle);
    }

    function __ERC7535MultiRewardVault_init(address _oracle) internal onlyInitializing {
        __ERC7535_init();
        __ERC20_init("ETH Byzantine StrategyVault Token", "byzETH");
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __ERC7535MultiRewardVault_init_unchained(_oracle);
    }

    function __ERC7535MultiRewardVault_init_unchained(address _oracle) internal onlyInitializing {
        oracle = IOracle(_oracle);
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Deposits ETH into the vault in return for vault shares.
     * @param assets The amount of ETH being deposited.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Deposits ETH into the vault. Amount is determined by number of shares minting.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of ETH deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override payable returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Withdraws ETH and reward tokens from the vault.
     * @dev User proportionally receives ETH and reward tokens that are combined worth the amount of `assets` specified.
     * @param assets The value to withdraw from the vault, in ETH amount.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {   
        // Calculate the amount of shares that will be burned
        uint256 sharesToBurn = previewWithdraw(assets);

        // Get the total ETH value of assets and reward tokens owned by the user
        uint256 userTotalETHValue = getUserTotalValue(owner);

        // Calculate the proportion of total value being withdrawn
        uint256 userWithdrawProportion = (assets * 1e18) / userTotalETHValue;

        // Get user's owned assets and rewards
        (, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate the amount of ETH that will be withdrawn, based on the withdrawn proportion
        uint256 ethToWithdraw = (tokenAmounts[0] * userWithdrawProportion) / 1e18;
        
        // Withdraw assets
        uint256 sharesBurnedForETH = super.withdraw(ethToWithdraw, receiver, owner);
        
        // Burn shares representing reward tokens
            // withdraw() must ensure that it burns amount of `shares` specified by the user.
            // If there are reward tokens, user will not have burned all shares in the super.withdraw() call.
            // If there are no reward tokens, the user will have burned all shares.
        uint256 sharesBurningForRewardTokens = sharesToBurn - sharesBurnedForETH;
        _burn(owner, sharesBurningForRewardTokens);

        // Withdraw proportional amount of each reward token
        _distributeRewards(receiver, userWithdrawProportion, tokenAmounts);

        uint256 totalSharesBurned = sharesBurnedForETH + sharesBurningForRewardTokens;
        return totalSharesBurned;
    }

    /**
     * @notice Withdraws ETH from the vault. Amount is determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for ETH.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * return The amount of ETH withdrawn (includes ETH + ETH value of all reward tokens).
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        // Calculate the proportion of shares the user is redeeming
        uint256 userWithdrawProportion = (shares * 1e18) / balanceOf(owner);

        // Get user's owned assets and rewards 
        (, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate amount of ETH user is withdrawing
        uint256 ethToWithdraw = (tokenAmounts[0] * userWithdrawProportion) / 1e18;

        // Calculate amount of shares to burn to withdraw ETH
        uint256 sharesToBurn = previewWithdraw(ethToWithdraw);

        // Withdraw ETH
        uint256 ethWithdrawn = super.redeem(sharesToBurn, receiver, owner);

        // Burn shares representing reward tokens
        // redeem() must ensure that it burns amount of `shares` specified by the user.
        // If there are reward tokens, user will not have burned all shares in the super.redeem() call.
        // If there are no reward tokens, the user will have burned all shares.
        uint256 sharesBurningForRewardTokens = shares - sharesToBurn;
        _burn(owner, sharesBurningForRewardTokens);

        // Withdraw proportional amount of each reward token
        uint256 totalRewardTokenValueWithdrawn = _distributeRewards(receiver, userWithdrawProportion, tokenAmounts);

        uint256 totalValueWithdrawn = ethWithdrawn + totalRewardTokenValueWithdrawn;
        return totalValueWithdrawn;
    }

    /**
     * @notice Adds a reward token to the vault.
     * @param _token The reward token to add.
     */
    function addRewardToken(address _token) external onlyOwner {
        // Validate the reward token has decimals() function
        _validateTokenDecimals(_token);

        // Check if the token is already in the rewardTokens array
        for (uint i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == _token) revert TokenAlreadyAdded();
        }
        rewardTokens.push(_token);
        emit RewardTokenAdded(_token);
    }

    /**
     * @notice Updates the oracle implementation address for the vault.
     * @param _oracle The new oracle implementation address.
     */
    function updateOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert InvalidAddress();
        oracle = IOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the total value in the vault.
     * @return The total value of assets and reward tokens in the vault, in ETH amount.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depositing or withdrawing, a user receives a proportional amount of assets or shares.
     * @dev Assumes that the oracle returns the price in 18 decimals.
     */
    function totalAssets() public view override returns (uint256) {        
        // Calculate USD value of reward tokens
        uint256 rewardTokenUSDValue;

        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint8 tokenDecimals = IERC20Metadata(token).decimals();

            // Normalize balance to 18 decimals before multiplying by price
            uint256 normalizedBalance = balance * 10**(18 - tokenDecimals);
            uint256 price = oracle.getPrice(token);
            rewardTokenUSDValue += (normalizedBalance * price) / 1e18;
        }

        // Convert total value of reward tokens from USD to ETH
        uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        uint256 rewardTokenETHAmount = (rewardTokenUSDValue * 1e18) / ethPrice;

        // Add the ETH value of the reward tokens to the ETH balance to get total ETH amount
        uint256 ethBalance = _getETHBalance();
        uint256 totalETHAmount = ethBalance + rewardTokenETHAmount;
        return totalETHAmount;
    }
    /**
     * @notice Returns the total ETH value of assets and reward tokens in the vault for a user.
     * @param user The address of the user.
     * @return The total value of assets in the vault for the user, in ETH amount.
     */
    function getUserTotalValue(address user) public view returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 userSharesProportion = (userShares * 1e18) / totalSupply();
        uint256 userTotalETHValue = (userSharesProportion * totalAssets()) / 1e18;
        return userTotalETHValue;
    }

    /**
     * @notice Returns the assets and reward tokens owned by a user.
     * @dev The ETH amount is the first element of the returned array.
     * @param user The address of the user.
     * @return The assets/reward tokens owned by the user and their respective amounts.
     */
    function getUsersOwnedAssetsAndRewards(address user) public view returns (address[] memory, uint256[] memory) {
        // Get the proportion of shares (and thus ETH) the user owns
        uint256 userShares = balanceOf(user);
        uint256 userSharesProportion = (userShares * 1e18) / totalSupply();

        // Get the amount of ETH owned by the user
        uint256 userEthAmount = (userSharesProportion * address(this).balance) / 1e18;

        // Setup arrays for assets and reward tokens
        address[] memory tokenAddresses = new address[](rewardTokens.length + 1);
        uint256[] memory tokenAmounts = new uint256[](rewardTokens.length + 1);
        
        // Add ETH to the arrays
        tokenAddresses[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        tokenAmounts[0] = userEthAmount;

        // Add reward tokens to the arrays
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            uint256 vaultBalance = IERC20(token).balanceOf(address(this));
            uint256 userTokenAmount = (vaultBalance * userSharesProportion) / 1e18;

            tokenAddresses[i + 1] = token;
            tokenAmounts[i + 1] = userTokenAmount;
        }

        return (tokenAddresses, tokenAmounts);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
    * @dev Distributes rewards to the receiver based on withdrawal proportion
    * @param receiver The address to receive the rewards
    * @param withdrawProportion The users proportion being withdrawn (in 1e18)
    * @return totalRewardTokenValueWithdrawn The total value of reward tokens withdrawn in asset terms
    */
    function _distributeRewards(
        address receiver,
        uint256 withdrawProportion,
        uint256[] memory tokenAmounts
    ) internal returns (uint256 totalRewardTokenValueWithdrawn) {
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint8 tokenDecimals = IERC20Metadata(token).decimals();

            // Calculate amount to withdraw based on user's balance and withdraw proportion
            uint256 tokenToWithdraw = (tokenAmounts[i + 1] * withdrawProportion) / 1e18;

            if (tokenToWithdraw > 0) {
                IERC20(token).safeTransfer(receiver, tokenToWithdraw);
                emit RewardTokenWithdrawn(receiver, token, tokenToWithdraw);
                
                // Convert reward token value to ETH terms
                uint256 tokenPrice = oracle.getPrice(token);
                uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
                uint256 normalizedTokenAmount = tokenToWithdraw * 10**(18 - tokenDecimals);
                uint256 tokenValueInUSD = (normalizedTokenAmount * tokenPrice) / 1e18;
                uint256 tokenValueInETH = (tokenValueInUSD * 1e18) / ethPrice;
                
                totalRewardTokenValueWithdrawn += tokenValueInETH;
            }
        }
        return totalRewardTokenValueWithdrawn;
    }

    /**
     * @dev Returns the ETH balance of the vault.
     * @return The ETH balance of the vault.
     */
    function _getETHBalance() internal view virtual returns (uint256) {
        return address(this).balance;
    }

    function _validateTokenDecimals(address rewardToken) internal view returns (uint8) {
        (bool success, uint8 tokenDecimals) = _tryGetTokenDecimals(rewardToken);
        if (!success) {
            revert TokenDoesNotHaveDecimalsFunction(rewardToken);
        }

        if (tokenDecimals > 18) revert TokenHasMoreThan18Decimals(rewardToken);

        return tokenDecimals;
    }
   
    /**
    * @dev Attempts to get the decimals of a token, returning a boolean for success
    * @param token The token to query
    * @return (bool, uint8) Success and decimals of the token
    */
    function _tryGetTokenDecimals(address token) internal view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = token.staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }
}