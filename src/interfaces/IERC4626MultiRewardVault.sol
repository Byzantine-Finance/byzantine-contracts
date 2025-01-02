// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracle} from "../interfaces/IOracle.sol";

interface IERC4626MultiRewardVault is IERC4626 {
    /* ============== EVENTS ============== */
    
    event RewardTokenAdded(address indexed token);
    event OracleUpdated(address newOracle);
    event RewardTokenWithdrawn(address indexed receiver, address indexed rewardToken, uint256 amount);

    /* ============== ERRORS ============== */

    error TokenAlreadyAdded();
    error InvalidAddress();
    error TokenDoesNotHaveDecimalsFunction(address token);
    error TokenHasMoreThan18Decimals(address token);

    /* ============== FUNCTIONS ============== */

    /// @notice Payable fallback function that receives ether rewards
    receive() external payable;

    /**
     * @notice Used to initialize the ERC4626MultiRewardVault given it's setup parameters.
     * @param _oracle The oracle implementation address to use for the vault.
     * @param _asset The asset to be staked.
     */
    function initialize(address _oracle, address _asset) external;

    /**
     * @notice Deposits assets into the vault in return for vault shares.
     * @param assets The amount of assets being deposited.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256);

    /**
     * @notice Deposits assets into the vault. Amount determined by number of shares minting.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the Byzantine vault shares.
     * @return The amount of assets deposited.
     */
    function mint(uint256 shares, address receiver) external returns (uint256);

    /**
     * @notice Withdraws assets and reward tokens from the vault.
     * @dev User proportionally receives assets and reward tokens that are combined worth the amount of `assets` specified.
     * @param assets The value to withdraw from the vault, in asset amount.
     * @param receiver The address to receive the assets.
     * @param owner The address that is withdrawing assets.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);

    /**
     * @notice Withdraws assets from the vault. Amount determined by number of shares burning.
     * @param shares The amount of shares to burn to exchange for assets.
     * @param receiver The address to receive the assets.
     * @param owner The address that is withdrawing assets.
     * @return The amount of assets withdrawn (includes asset + asset value of all reward tokens).
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    /**
     * @notice Adds a reward token to the vault.
     * @param _token The reward token to add.
     */
    function addRewardToken(address _token) external;

    /**
     * @notice Updates the oracle implementation address for the vault.
     * @param _oracle The new oracle implementation address.
     */
    function updateOracle(address _oracle) external;

    /**
     * @notice Returns the total value in the vault.
     * @return The total value of assets and reward tokens in the vault, in asset token amount.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the total asset value of assets and reward tokens in the vault for a user.
     * @param user The address of the user.
     * @return The total value of assets in the vault for the user, in asset token amount.
     */
    function getUserTotalValue(address user) external view returns (uint256);

    /**
     * @notice Returns the assets and reward tokens owned by a user.
     * @param user The address of the user.
     * @return tokenAddresses The addresses of tokens owned by the user
     * @return tokenAmounts The amounts of tokens owned by the user
     */
    function getUsersOwnedAssetsAndRewards(address user) external view returns (address[] memory tokenAddresses, uint256[] memory tokenAmounts);

    /**
     * @notice Returns the list of reward tokens
     * @param index The index in the reward tokens array
     * @return The address of the reward token at the given index
     */
    function rewardTokens(uint256 index) external view returns (address);

    /**
     * @notice Returns the oracle implementation
     * @return The oracle contract address
     */
    function oracle() external view returns (IOracle);
}