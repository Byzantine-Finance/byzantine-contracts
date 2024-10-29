// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC7535/ERC7535Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin-upgrades/contracts/utils/math/MathUpgradeable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title ERC7535MultiRewardVault
 * @author Byzantine-Finance
 * @notice ERC-7535: Native Asset ERC-4626 Tokenized Vault with support for multiple reward tokens
 */
contract ERC7535MultiRewardVault is ERC7535Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

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
    error ETHTransferFailedOnWithdrawal();
    error TokenAlreadyAdded();
    error InvalidAddress();

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
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC7535MultiRewardVault_init_unchained(_oracle);
    }

    function __ERC7535MultiRewardVault_init_unchained(address _oracle) internal onlyInitializing {
        oracle = IOracle(_oracle);
    }

    /* =================== FALLBACK =================== */
    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyVault contract
     */
    receive() external payable virtual override {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Deposits ETH into the vault. Amount is determined by ETH depositing.
     * @param assets The amount of ETH being deposit.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Deposits ETH into the vault. Amount is determined by number of shares minting.
     * @param shares The amount of vault shares to mint.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of ETH deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override payable returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Withdraws ETH & Reward Tokens from the vault. Amount is determined by ETH withdrawing
     * @dev User proportionally receives ETH and reward tokens that are combined worth the amount of `assets` specified.
     * @param assets The amount of ETH to withdraw.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {     
        // Get the total ETH value of assets + reward tokens owned by the user
        uint256 userTotalETHValue = getUserTotalETHValue(owner);
        
        // Calculate the proportion of total value being withdrawn
        uint256 withdrawProportion = (assets * 1e18) / userTotalETHValue;

        // Get user's owned assets and rewards
        (address[] memory tokenAddresses, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate shares to burn based on the ETH withdrawal
        uint256 ethToWithdraw = (tokenAmounts[0] * withdrawProportion) / 1e18;
        uint256 shares = previewWithdraw(ethToWithdraw);

        // Withdraw ETH
        super.withdraw(ethToWithdraw, receiver, owner);

        // Withdraw proportional amount of each reward token
        for (uint i = 1; i < tokenAddresses.length; i++) {
            address token = tokenAddresses[i];
            uint256 tokenAmount = tokenAmounts[i];
            uint256 tokenToWithdraw = (tokenAmount * withdrawProportion) / 1e18;
            
            if (tokenToWithdraw > 0) {
                IERC20Upgradeable(token).safeTransfer(receiver, tokenToWithdraw);
                emit RewardTokenWithdrawn(receiver, token, tokenToWithdraw);
            }
        }

        return shares;
    }

    /**
     * @notice Withdraws ETH from the vault. Amount is determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for ETH.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * return The amount of ETH withdrawn (includes ETH + ETH value of all reward tokens).
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        // Calculate the proportion of shares the user owns
        uint256 userShareProportion = (balanceOf(owner) * 1e18) / totalSupply();
        
        // Calculate the proportion of shares the user is redeeming
        uint256 userWithdrawProportion = (shares * 1e18) / balanceOf(owner);

        // Get user's owned assets and rewards 
        (address[] memory tokenAddresses, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate amount of ETH user is withdrawing
        uint256 ethToWithdraw = (tokenAmounts[0] * userWithdrawProportion) / 1e18;

        // Calculate amount of shares to burn to withdraw ETH
        uint256 sharesToBurn = previewWithdraw(ethToWithdraw);

        // Withdraw ETH
        uint256 ethWithdrawn = super.redeem(sharesToBurn, receiver, owner);
        uint256 totalValueWithdrawn = ethWithdrawn;

        // Burn shares representing Reward Tokens
        // redeem() must ensure that it burns amount of `shares` specified by the user.
        // If there are Reward Tokens, user will not have burned all shares in the super.redeem() call.
        // If there are no Reward Tokens, the user will have burned all shares.
        uint256 sharesBurningForRewardTokens = shares - sharesToBurn;
        _burn(owner, sharesBurningForRewardTokens);

        // Withdraw proportional amount of each reward token
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            // Get the total amount of the reward token owned by the user
            uint256 totalTokenOwnedByUser = tokenAmounts[i + 1];

            // Calculate the amount of the reward token to withdraw
            uint256 tokensToWithdraw = (totalTokenOwnedByUser * userWithdrawProportion) / 1e18;

            if (tokensToWithdraw > 0) {
                IERC20Upgradeable(token).safeTransfer(receiver, tokensToWithdraw);
                emit RewardTokenWithdrawn(receiver, token, tokensToWithdraw);

                // Add the ETH value of the withdrawn reward token to the total
                uint256 tokenPrice = oracle.getPrice(token);

                uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
                uint256 tokenValueInEth = (tokensToWithdraw * tokenPrice) / ethPrice;

                totalValueWithdrawn += tokenValueInEth;
            }
        }

        return totalValueWithdrawn;
    }

    /**
     * @notice Adds a reward token to the vault.
     * @param _token The reward token to add.
     */
    function addRewardToken(address _token) external onlyOwner {
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
     * @notice Returns the total value of assets in the vault.
     * @return The total value of assets in the vault, in ETH amount.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depositing or withdrawing, a user receives the correct amount of assets or shares.
     * @dev Allows for assets to be priced in USD, ETH or any other asset, as long as the oracles are updated accordingly and uniformly.
     * @dev Assumes that the oracle returns the price in 18 decimals.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 ethBalance = _getETHBalance();
        uint256 rewardTokenUSDValue;
        
        // Calculate value of reward tokens, add them to the total value
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
            uint256 price = oracle.getPrice(token);
            rewardTokenUSDValue += (balance * price);
        }
        
        // Convert totalValue from USD to ETH
        uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        uint256 rewardTokenETHAmount = rewardTokenUSDValue / ethPrice;

        uint256 totalETHAmount = ethBalance + rewardTokenETHAmount;

        return totalETHAmount;
    }

    /**
     * @notice Returns the total value of assets in the vault for a user.
     * @dev Includes ETH amount and ETH value of all reward tokens.
     * @param user The address of the user.
     * @return The total value of assets in the vault for the user, in ETH amount.
     */
    function getUserTotalETHValue(address user) public view returns (uint256) {
        uint256 userShares = balanceOf(user);

        uint256 scalingFactor = 1e18;

        uint256 userSharesProportion = (userShares * scalingFactor) / totalSupply();

        uint256 userTotalETHValue = (userSharesProportion * totalAssets()) / scalingFactor;

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
        uint256 scalingFactor = 1e18;
        uint256 userSharesProportion = (userShares * scalingFactor) / totalSupply();

        // Get the amount of ETH owned by the user
        uint256 userEthAmount = (userSharesProportion * address(this).balance) / scalingFactor;

        address[] memory tokenAddresses = new address[](rewardTokens.length + 1);
        uint256[] memory tokenAmounts = new uint256[](rewardTokens.length + 1);
        
        // Add ETH to the arrays
        tokenAddresses[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        tokenAmounts[0] = userEthAmount;

        // Add reward tokens to the arrays
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            uint256 vaultBalance = IERC20Upgradeable(token).balanceOf(address(this));
            uint256 userTokenAmount = (vaultBalance * userSharesProportion) / scalingFactor;

            tokenAddresses[i + 1] = token;
            tokenAmounts[i + 1] = userTokenAmount;
        }

        return (tokenAddresses, tokenAmounts);
    }

    /**
     * @notice Returns the ETH value of shares being redeemed. Includes ETH amount + ETH value of all reward tokens.
     * @param shares The amount of shares to redeem.
     * @return The ETH value of the shares being redeemed.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            return 0;
        }

        // Calculate proportion of total assets that these shares represent
        uint256 totalAssetValue = totalAssets();
        return (shares * totalAssetValue) / totalShares;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @dev Distributes rewards to the receiver for all rewardTokens.
     * @param receiver The address to receive the rewards.
     * @param sharesBurned The amount of shares burned.
     * @param totalSharesPreWithdraw The total number of shares before the withdrawal sequence was initiated.
     */
    function _distributeRewards(address receiver, uint256 sharesBurned, uint256 totalSharesPreWithdraw) internal {
        uint256 totalShares = totalSharesPreWithdraw;

        for (uint i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 rewardBalance = IERC20Upgradeable(rewardToken).balanceOf(address(this));
            uint256 rewardAmount = (rewardBalance * sharesBurned) / totalShares;
            if (rewardAmount > 0) {
                IERC20Upgradeable(rewardToken).safeTransfer(receiver, rewardAmount);
                emit RewardTokenWithdrawn(receiver, rewardToken, rewardAmount);
            }
        }
    }

    /**
     * @dev Returns the ETH balance of the vault.
     * @return The ETH balance of the vault.
     */
    function _getETHBalance() internal view virtual returns (uint256) {
        return address(this).balance;
    }

}