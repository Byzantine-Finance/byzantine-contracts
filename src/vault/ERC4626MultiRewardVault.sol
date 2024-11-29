// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/math/MathUpgradeable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title ERC4626MultiRewardVault
 * @author Byzantine-Finance
 * @notice ERC-4626: Tokenized Vault with support for multiple reward tokens
 */
contract ERC4626MultiRewardVault is Initializable, ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
     * @notice Used to initialize the ERC4626MultiRewardVault given it's setup parameters.
     * @param _oracle The oracle implementation address to use for the vault.
     * @param _asset The asset to be staked.
     */
    function initialize(address _oracle, address _asset) public initializer {
        __ERC4626MultiRewardVault_init(_oracle, _asset);
    }

    function __ERC4626MultiRewardVault_init(address _oracle, address _asset) internal onlyInitializing {
        _validateTokenDecimals(_asset);
        
        string memory assetSymbol = IERC20MetadataUpgradeable(_asset).symbol();
        string memory vaultName = string(abi.encodePacked(assetSymbol, " Byzantine StrategyVault Token"));
        string memory vaultSymbol = string(abi.encodePacked("bvz", assetSymbol));

        __ERC4626_init(IERC20MetadataUpgradeable(address(_asset)));
        __ERC20_init(vaultName, vaultSymbol);
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC4626MultiRewardVault_init_unchained(_oracle);
    }

    function __ERC4626MultiRewardVault_init_unchained(address _oracle) internal onlyInitializing {
        oracle = IOracle(_oracle);
    }

    /* =================== FALLBACK =================== */

    /**
     * @notice Payable fallback function that receives ether rewards deposited to the StrategyVault contract
     */
    receive() external virtual payable {}

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Deposits assets into the vault in return for vault shares.
     * @param assets The amount of assets being deposited.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Deposits assets into the vault. Amount is determined by number of shares minting.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of assets deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Withdraws assets and reward tokens from the vault.
     * @dev User proportionally receives assets and reward tokens that are combined worth the amount of `assets` specified.
     * @param assets The value to withdraw from the vault, in asset amount.
     * @param receiver The address to receive the assets.
     * @param owner The address that is withdrawing assets.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {   
        // Calculate the amount of shares that will be burned
        uint256 sharesToBurn = previewWithdraw(assets);

        // Get the total asset value of assets + reward tokens owned by the user
        uint256 userTotalAssetValue = getUserTotalValue(owner);

        // Calculate the proportion of total value being withdrawn
        uint256 userWithdrawProportion = (assets * 1e18) / userTotalAssetValue;

        // Get user's owned assets and rewards
        (address[] memory tokenAddresses, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate the amount of assets that will be withdrawn, based on the withdrawn proportion
        uint256 assetsToWithdraw = (tokenAmounts[0] * userWithdrawProportion) / 1e18;
        
        // Withdraw assets
        uint256 sharesBurnedForAssets = super.withdraw(assetsToWithdraw, receiver, owner);
        
        // Burn shares representing reward tokens
            // withdraw() must ensure that it burns amount of `shares` specified by the user.
            // If there are reward tokens, user will not have burned all shares in the super.withdraw() call.
            // If there are no teward tokens, the user will have burned all shares.
        uint256 sharesBurningForRewardTokens = sharesToBurn - sharesBurnedForAssets;
        _burn(owner, sharesBurningForRewardTokens);

        // Withdraw proportional amount of each reward token
        _distributeRewards(receiver, userWithdrawProportion, tokenAmounts);

        uint256 totalSharesBurned = sharesBurnedForAssets + sharesBurningForRewardTokens;
        return totalSharesBurned;
    }

    /**
     * @notice Withdraws assets from the vault. Amount is determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for assets.
     * @param receiver The address to receive the assets.
     * @param owner The address that is withdrawing assets.
     * return The amount of assets withdrawn (includes asset + asset value of all reward tokens).
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        // Calculate the proportion of shares the user owns
        uint256 userShareProportion = (balanceOf(owner) * 1e18) / totalSupply();
        
        // Calculate the proportion of shares the user is redeeming
        uint256 userWithdrawProportion = (shares * 1e18) / balanceOf(owner);

        // Get user's owned assets and rewards 
        (address[] memory tokenAddresses, uint256[] memory tokenAmounts) = getUsersOwnedAssetsAndRewards(owner);

        // Calculate amount of assets user is withdrawing
        uint256 assetsToWithdraw = (tokenAmounts[0] * userWithdrawProportion) / 1e18;

        // Calculate amount of shares to burn to withdraw assets
        uint256 sharesToBurn = previewWithdraw(assetsToWithdraw);

        // Withdraw assets
        uint256 assetsWithdrawn = super.redeem(sharesToBurn, receiver, owner);

        // Burn shares representing reward tokens
        // redeem() must ensure that it burns amount of `shares` specified by the user.
        // If there are reward tokens, user will not have burned all shares in the super.redeem() call.
        // If there are no reward tokens, the user will have burned all shares.
        uint256 sharesBurningForRewardTokens = shares - sharesToBurn;
        _burn(owner, sharesBurningForRewardTokens);

        // Withdraw proportional amount of each reward token
        uint256 totalRewardTokenValueWithdrawn = _distributeRewards(receiver, userWithdrawProportion, tokenAmounts);

        uint256 totalValueWithdrawn = assetsWithdrawn + totalRewardTokenValueWithdrawn;
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
     * @return The total value of assets and reward tokens in the vault, in asset token amount.
     * @dev This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.
     * @dev This ensures that when depositing or withdrawing, a user receives a proportional amount of assets or shares.
     * @dev Assumes that the oracle returns the price in 18 decimals.
     */
    function totalAssets() public view override returns (uint256) {
        // Calculate USD value of reward tokens
        uint256 rewardTokenUSDValue;
        uint8 assetDecimals = IERC20MetadataUpgradeable(address(asset())).decimals();

        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance;
            uint8 tokenDecimals;

            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                balance = address(this).balance;
                tokenDecimals = 18;
            } else {
                balance = IERC20Upgradeable(token).balanceOf(address(this));
                tokenDecimals = IERC20MetadataUpgradeable(token).decimals();
            }

            // Normalize balance to 18 decimals
            uint256 normalizedBalance = balance * 10**(18 - tokenDecimals);
            uint256 price = oracle.getPrice(token);
            rewardTokenUSDValue += (normalizedBalance * price) / 1e18;
        }

        // Convert total value of reward tokens from USD to asset token
        uint256 assetPrice = oracle.getPrice(address(asset()));
        uint256 rewardTokenAssetAmount = (rewardTokenUSDValue * 10**assetDecimals) / assetPrice;

        // Add the asset value of the reward tokens to the asset balance to get total asset amount
        uint256 assetBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
        uint256 totalAssetAmount = assetBalance + rewardTokenAssetAmount;
        return totalAssetAmount;
    }

    /**
     * @notice Returns the total asset value of assets and reward tokens in the vault for a user.
     * @param user The address of the user.
     * @return The total value of assets in the vault for the user, in asset token amount.
     */
    function getUserTotalValue(address user) public view returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 userSharesProportion = (userShares * 1e18) / totalSupply();
        uint256 userTotalETHValue = (userSharesProportion * totalAssets()) / 1e18;
        return userTotalETHValue;
    }

    /**
     * @notice Returns the assets and reward tokens owned by a user.
     * @dev The asset amount is the first element of the returned array.
     * @param user The address of the user.
     * @return The assets/reward tokens owned by the user and their respective amounts.
     */
    function getUsersOwnedAssetsAndRewards(address user) public view returns (address[] memory, uint256[] memory) {
        // Get the proportion of shares (and thus assets) the user owns
        uint256 userShares = balanceOf(user);
        uint256 userSharesProportion = (userShares * 1e18) / totalSupply();

        // Get the amount of assets owned by the user
        address asset = super.asset();
        uint256 userAssetAmount = (userSharesProportion * IERC20Upgradeable(asset).balanceOf(address(this))) / 1e18;

        // Setup arrays for tokens owned by the user
        address[] memory tokenAddresses = new address[](rewardTokens.length + 1);
        uint256[] memory tokenAmounts = new uint256[](rewardTokens.length + 1);
        
        // Add asset to the arrays
        tokenAddresses[0] = asset;
        tokenAmounts[0] = userAssetAmount;

        // Add reward tokens to the arrays
        for (uint i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 vaultBalance;

            if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                vaultBalance = address(this).balance;
            } else {
                vaultBalance = IERC20Upgradeable(token).balanceOf(address(this));
            }

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
            uint8 tokenDecimals;
            
            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                tokenDecimals = 18;
            } else {
                tokenDecimals = IERC20MetadataUpgradeable(token).decimals();
            }

            // Calculate amount to withdraw based on user's balance and withdraw proportion
            uint256 tokenToWithdraw = (tokenAmounts[i + 1] * withdrawProportion) / 1e18;

            if (tokenToWithdraw > 0) {
                if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                    (bool success,) = payable(receiver).call{value: tokenToWithdraw}("");
                    require(success, "ETH transfer failed");
                } else {
                    IERC20Upgradeable(token).safeTransfer(receiver, tokenToWithdraw);
                }
                emit RewardTokenWithdrawn(receiver, token, tokenToWithdraw);
                
                // Convert reward token value to asset terms
                uint256 tokenPrice = oracle.getPrice(token);
                uint256 assetPrice = oracle.getPrice(address(asset()));
                uint256 normalizedTokenAmount = tokenToWithdraw * 10**(18 - tokenDecimals);
                uint256 tokenValueInUSD = (normalizedTokenAmount * tokenPrice) / 1e18;
                uint256 tokenValueInAsset = (tokenValueInUSD * 10**IERC20MetadataUpgradeable(address(asset())).decimals()) / assetPrice;
                
                totalRewardTokenValueWithdrawn += tokenValueInAsset;
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
        // Skip validation for ETH
        if (rewardToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            return 18; // ETH has 18 decimals
        }
        
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
        try IERC20MetadataUpgradeable(token).decimals() returns (uint8 value) {
            return (true, value);
        } catch {
            return (false, 0);
        }
    }
}
