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
     * @return The total value of assets in the vault.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depositing or withdrawing, a user receives the correct amount of assets or shares.
     * @dev Allows for assets to be priced in USD, ETH or any other asset, as long as the oracles are updated accordingly and uniformly.
     * @dev Assumes that the oracle returns the price in 18 decimals.
     */
    function totalAssets() public view override returns (uint256) {
        // Calculate value of native ETH
        uint256 ethBalance = _getETHBalance();
        uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        uint256 totalValue = ethBalance * ethPrice;
        
        // Calculate value of reward tokens, add them to the total value
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
            uint256 price = oracle.getPrice(token);
            totalValue += (balance * price);
        }
        
        return totalValue / 1e18;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     * @dev This function is overriden to calculate total value of assets including reward tokens.
     * @dev Treats totalAssets() as the total value of ETH + reward tokens in USD rather than the total amount of ETH.
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply() + 10 ** _decimalsOffset(); // Supply includes virtual reserves
        if (totalSupply() == 0) {
            return assets; // On first deposit, totalSupply is 0, so return assets (amount of ETH deposited) as shares
        } else {
            uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
            uint256 assetsUsdValue = assets * ethPrice / 1e18;
            return assetsUsdValue.mulDiv(supply, totalAssets(), rounding);
        }
    }
    
    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     * @dev This function is overriden to calculate total value of assets including reward tokens.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply() + 10 ** _decimalsOffset(); // Supply includes virtual reserves
        if (totalSupply() == 0) {
            return shares; // If there are no shares, return the number of shares as assets. TODO: Remove unnecessary code?
        } else {
            uint256 assetsUsdValue = shares.mulDiv(totalAssets(), supply, rounding);
            uint256 ethPrice = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
            return assetsUsdValue * 1e18 / ethPrice;
        }
    }

    /**
     * @dev Distributes rewards to the receiver for all rewardTokens.
     * @param receiver The address to receive the rewards.
     * @param sharesBurned The amount of shares burned.
     */
    function _distributeRewards(address receiver, uint256 sharesBurned) internal {
        uint256 totalShares = totalSupply();
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