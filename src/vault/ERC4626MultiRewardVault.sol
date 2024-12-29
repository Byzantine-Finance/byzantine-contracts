// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract ERC4626MultiRewardVault is ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ============== STATE VARIABLES ============== */

    struct TokenInfo {
        address priceFeed;
        uint8 decimals;
    }

    /// @notice Mapping of asset token address to its information
    mapping(IERC20 => TokenInfo) public assetInfo;

    /// @notice Mapping of reward token address to its information
    mapping(IERC20 => TokenInfo) public rewardInfo;

    /// @notice List of asset tokens
    IERC20[] public assetTokens;

    /// @notice List of reward tokens
    IERC20[] public rewardTokens;

    /// @notice Oracle implementation
    IOracle public oracle;

    /* ============== CUSTOM ERRORS ============== */

    error TokenAlreadyAdded();
    error InvalidToken();

    /* ============== EVENTS ============== */

    event AssetTokenAdded(IERC20 indexed token, address priceFeed, uint8 decimals);
    event RewardTokenAdded(IERC20 indexed token, address priceFeed, uint8 decimals);
    event PriceFeedUpdated(IERC20 indexed token, address newPriceFeed);

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /**
     * @notice Used to initialize the ERC4626MultiRewardVault given it's setup parameters.
     * @param _asset The asset to be staked.
     * @param _oracle The oracle implementation address to use for the vault.
     */
    function initialize(IERC20 _asset, address _oracle) public initializer {
        string memory assetSymbol = IERC20Metadata(address(_asset)).symbol();
        string memory vaultName = string(abi.encodePacked(assetSymbol, " Byzantine StrategyVault Token"));
        string memory vaultSymbol = string(abi.encodePacked("bvz", assetSymbol));

        __ERC4626_init(IERC20Metadata(address(_asset)));
        __ERC20_init(vaultName, vaultSymbol);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    // /**
    //  * @notice Adds a reward token to the vault.
    //  * @param _rewardToken The reward token to add.
    //  */
    // function addRewardToken(IERC20 _rewardToken) external onlyOwner {
    //     rewardTokens.push(_rewardToken);
    //     uint8 decimals = IERC20Metadata(address(_rewardToken)).decimals();
    //     rewardTokenDecimals[_rewardToken] = decimals;
    // }

    /**
     * @notice Withdraws assets from the vault.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The address that is withdrawing the assets.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        uint256 shares = super.withdraw(assets, receiver, owner);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        _distributeRewards(receiver, shares);
        return shares;
    }

    /**
     * @notice Withdraws assets from the vault. Amount is determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for assets.
     * @param receiver The address to receive the assets.
     * @param owner The address that is withdrawing assets.
     * return The amount of assets withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    /* ================ VIEW FUNCTIONS ================ */

    /**
     * @notice Returns the total assets in the vault.
     * @return The total value of assets in the vault.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depsoiting or withdrawing, a user receives the correct amount of assets or shares.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 totalValue = super.totalAssets();
        // TODO: Integrate with oracle to determine total value of all tokens in vault
        return totalValue;
    }

    /**
     * @notice Converts assets to shares.
     * @param assets The amount of assets to convert.
     * @return The amount of shares.
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0)
            ? assets
            : (assets * supply) / totalAssets();
    }

    /**
     * @notice Converts shares to assets.
     * @param shares The amount of shares to convert.
     * @return The amount of assets.
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares 
            :(shares * totalAssets()) / supply;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @notice Distributes rewards to the receiver for all rewardTokens.
     * @param receiver The address to receive the rewards.
     * @param sharesBurned The amount of shares burned.
     */
    function _distributeRewards(address receiver, uint256 sharesBurned) internal {
        uint256 totalShares = totalSupply();
        for (uint i = 0; i < rewardTokens.length; i++) {
            IERC20 rewardToken = rewardTokens[i];
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            uint256 rewardAmount = (rewardBalance * sharesBurned) / totalShares;
            if (rewardAmount > 0) {
                rewardToken.safeTransfer(receiver, rewardAmount);
            }
        }
    }

}
