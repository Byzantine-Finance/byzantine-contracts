// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

contract ERC4626MultiRewardVault is Initializable, ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ============== STATE VARIABLES ============== */

    /// @notice List of reward tokens
    IERC20Upgradeable[] public rewardTokens;

    /// @notice Mapping of reward token to its decimals
    mapping(IERC20Upgradeable => uint8) public rewardTokenDecimals;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /**
     * @notice Used to initialize the ERC4626MultiRewardVault given it's setup parameters.
     * @dev ETH is used as the asset for this vault, represented as 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE.
     */
    function initialize() public initializer {
        __ERC4626_init(IERC20MetadataUpgradeable(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        __ERC20_init("ETH Byzantine StrategyVault Token", "byzETH");
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /* =================== FALLBACK =================== */
    /**
     * @notice Payable fallback function that receives ether deposited to the StrategyVault contract
     */
    receive() external payable {
        // TODO: emit an event to notify
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Adds a reward token to the vault.
     * @param _rewardToken The reward token to add.
     */
    function addRewardToken(IERC20Upgradeable _rewardToken) external onlyOwner {
        rewardTokens.push(_rewardToken);
        uint8 decimals = IERC20MetadataUpgradeable(address(_rewardToken)).decimals();
        rewardTokenDecimals[_rewardToken] = decimals;
    }

    /**
     * @notice Deposits ETH into the vault.
     * @param assets The amount of ETH being deposit.
     * @param receiver The address to receive the deposited assets.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable nonReentrant returns (uint256) {
        require(msg.value == assets, "Incorrect ETH amount");
        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Withdraws ETH from the vault.
     * @param assets The amount of ETH to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The address that is withdrawing the assets.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        uint256 shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        _distributeRewards(receiver, shares);
        payable(receiver).transfer(assets);
        return shares;
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
            IERC20Upgradeable rewardToken = rewardTokens[i];
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            uint256 rewardAmount = (rewardBalance * sharesBurned) / totalShares;
            if (rewardAmount > 0) {
                rewardToken.safeTransfer(receiver, rewardAmount);
            }
        }
    }

}
