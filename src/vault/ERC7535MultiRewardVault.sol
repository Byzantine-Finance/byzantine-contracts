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

    /// @notice Struct to store token information
    struct TokenInfo {
        address priceFeed;
        uint8 decimals;
    }

    /// @notice Mapping of asset token address to its information
    mapping(IERC20Upgradeable => TokenInfo) public assetInfo;

    /// @notice Mapping of reward token address to its information
    mapping(IERC20Upgradeable => TokenInfo) public rewardInfo;

    // /// @notice List of asset tokens
    // IERC20Upgradeable[] public assetTokens;

    /// @notice List of reward tokens
    IERC20Upgradeable[] public rewardTokens;

    /// @notice Oracle implementation
    IOracle public oracle;

    /* ============== CUSTOM ERRORS ============== */
    error ETHTransferFailedOnWithdrawal();
    error TokenAlreadyAdded();
    error InvalidAddress();

    /* ============== EVENTS ============== */

    //event AssetTokenAdded(IERC20Upgradeable indexed token, address priceFeed, uint8 decimals);
    event RewardTokenAdded(IERC20Upgradeable indexed token, address priceFeed, uint8 decimals);
    event PriceFeedUpdated(IERC20Upgradeable indexed token, address newPriceFeed);
    event OracleUpdated(address newOracle);
    event RewardTokenWithdrawn(address indexed receiver, IERC20Upgradeable indexed rewardToken, uint256 amount);
    
    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /**
     * @notice Used to initialize the ERC7535MultiRewardVault given it's setup parameters.
     * @param _oracle The oracle implementation address to use for the vault.
     */
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
     * @notice Withdraws ETH from the vault. Amount is determined by ETH withdrawing. 
     * @param assets The amount of ETH to withdraw.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        uint256 shares = super.withdraw(assets, receiver, owner);
        _distributeRewards(receiver, shares);
        return shares;
    }

    /**
     * @notice Withdraws ETH from the vault. Amount is determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for ETH.
     * @param receiver The address to receive the ETH.
     * @param owner The address that is withdrawing ETH.
     * return The amount of ETH withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        uint256 assets = super.redeem(shares, receiver, owner);
        _distributeRewards(receiver, shares);
        return assets;
    }

    // /**
    //  * @notice Adds an asset token to the vault.
    //  * @param _token The asset token to add.
    //  * @param _priceFeed The price feed address for the token.
    //  */ 
    // function addAssetToken(IERC20Upgradeable _token, address _priceFeed) external onlyOwner {
    //     if (assetInfo[_token].priceFeed != address(0)) revert TokenAlreadyAdded();
        
    //     uint8 decimals = IERC20MetadataUpgradeable(address(_token)).decimals();
    //     assetInfo[_token] = TokenInfo({
    //         priceFeed: _priceFeed,
    //         decimals: decimals
    //     });
    //     assetTokens.push(_token);

    //     emit AssetTokenAdded(_token, _priceFeed, decimals);
    // }

    /**
     * @notice Adds a reward token to the vault.
     * @param _token The reward token to add.
     * @param _priceFeed The price feed address for the token.
     */
    function addRewardToken(IERC20Upgradeable _token, address _priceFeed) external onlyOwner {
        if (rewardInfo[_token].priceFeed != address(0)) revert TokenAlreadyAdded();
        
        uint8 decimals = IERC20MetadataUpgradeable(address(_token)).decimals();
        rewardInfo[_token] = TokenInfo({
            priceFeed: _priceFeed,
            decimals: decimals
        });
        rewardTokens.push(_token);

        emit RewardTokenAdded(_token, _priceFeed, decimals);
    }

    /**
     * @notice Updates the oracle address for an asset token.
     * @param _token The asset token to update.
     * @param _newPriceFeed The new price feed address for the token.
     */
    function updateAssetPriceFeed(IERC20Upgradeable _token, address _newPriceFeed) external onlyOwner {
        if (assetInfo[_token].priceFeed == address(0)) revert InvalidAddress();
        assetInfo[_token].priceFeed = _newPriceFeed;
        emit PriceFeedUpdated(_token, _newPriceFeed);
    }

    /**
     * @notice Updates the oracle address for a reward token.
     * @param _token The reward token to update.
     * @param _newPriceFeed The new price feed address for the token.
     */
    function updateRewardPriceFeed(IERC20Upgradeable _token, address _newPriceFeed) external onlyOwner {
        if (rewardInfo[_token].priceFeed == address(0)) revert InvalidAddress();
        rewardInfo[_token].priceFeed = _newPriceFeed;
        emit PriceFeedUpdated(_token, _newPriceFeed);
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
     * @return The total value of assets in the vault.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depositing or withdrawing, a user receives the correct amount of assets or shares.
     */
    function totalAssets() public view override returns (uint256) {
        // Calculate value of assets (native ETH)
        uint256 assetAmount = address(this).balance;
        address asset = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // Native ETH
        TokenInfo memory ethInfo = assetInfo[IERC20MetadataUpgradeable(asset)];
        uint256 totalValue = assetAmount * oracle.getPrice(asset, ethInfo.priceFeed);
        
        // Calculate value of reward tokens
        for (uint i = 0; i < rewardTokens.length; i++) {
            IERC20Upgradeable token = rewardTokens[i];
            uint256 balance = token.balanceOf(address(this));
            TokenInfo memory tokenInfo = rewardInfo[token];
            uint256 price = oracle.getPrice(address(token), tokenInfo.priceFeed);
            totalValue += (balance * price) / (10 ** tokenInfo.decimals);
        }
        
        return totalValue;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     * @dev This function is overriden to calculate total value of assets including reward tokens.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? assets
            : assets.mulDiv(supply, totalAssets(), rounding);
    }
    
    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     * @dev This function is overriden to calculate total value of assets including reward tokens.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares
            : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Distributes rewards to the receiver for all rewardTokens.
     * @param receiver The address to receive the rewards.
     * @param sharesBurned The amount of shares burned.
     */
    function _distributeRewards(address receiver, uint256 sharesBurned) internal {
        uint256 totalShares = totalSupply();
        for (uint i = 0; i < rewardTokens.length; i++) {
            IERC20Upgradeable rewardToken = rewardTokens[i];
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            uint256 rewardAmount = (rewardBalance * sharesBurned) / totalShares;
            if (rewardAmount > 0) {
                rewardToken.safeTransfer(receiver, rewardAmount);
                emit RewardTokenWithdrawn(receiver, rewardToken, rewardAmount);
            }
        }
    }
}