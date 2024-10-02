// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEigenPod} from "eigenlayer-contracts/interfaces/IEigenPod.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {SplitV2Lib} from "splits-v2/libraries/SplitV2.sol";

interface IStrategyVaultManager {

    /* ============== GETTERS ============== */

    /// @notice Get the total number of Strategy Vaults that have been deployed.
    function numStratVaults() external view returns (uint64);

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice A strategy designer creates a StrategyVault for Native ETH.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @param oracle The oracle implementation to use for the vault.
     * @param stakerReward The address of the StakerReward contract.
     * @return The address of the newly created StrategyVaultETH.
     */
    function createStratVaultETH(
        bool whitelistedDeposit,
        bool upgradeable,
        address operator,
        address oracle,
        address stakerReward
    ) 
        external returns (address);

    /**
     * @notice A staker (which can also be referred as to a strategy designer) first creates a Strategy Vault ETH and then stakes ETH on it.
     * @dev It calls newStratVault.stakeNativeETH(): that function triggers the necessary number of auctions to create the DVs who gonna validate the ETH staked.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @param oracle The oracle implementation to use for the vault.
     * @param stakerReward The address of the StakerReward contract.
     * @dev This action triggers (a) new auction(s) to get (a) new Distributed Validator(s) to stake on the Beacon Chain. The number of Auction triggered depends on the number of ETH sent.
     * @dev Function will revert unless a multiple of 32 ETH are sent with the transaction.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ETH staked.
     * @return The address of the newly created StrategyVaultETH.
     */
    function createStratVaultAndStakeNativeETH(
        bool whitelistedDeposit,
        bool upgradeable,
        address operator,
        address oracle,
        address stakerReward
    ) 
        external payable returns (address);

    /**
     * @notice Staker creates a StrategyVault with an ERC20 deposit token.
     * @param token The ERC20 deposit token for the StrategyVault.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @param oracle The oracle implementation to use for the vault.
     * @return stratVaultAddr address of the newly created StrategyVault.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
     */
    function createStratVaultERC20(
        IERC20 token,
        bool whitelistedDeposit,
        bool upgradeable,
        address operator,
        address oracle
    ) external returns (address);

    /**
     * @notice Staker creates a Strategy Vault and stakes ERC20.
     * @param strategy The EigenLayer StrategyBaseTVLLimits contract for the depositing token.
     * @param token The ERC20 token to stake.
     * @param amount The amount of token to stake.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @param oracle The oracle implementation to use for the vault.
     * @return stratVaultAddr address of the newly created StrategyVault.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
     */
    function createStratVaultAndStakeERC20(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        bool whitelistedDeposit,
        bool upgradeable,
        address operator,
        address oracle
    ) external returns (address);

    /**
     * @notice Distributes the tokens issued from the PoS rewards evenly between the node operators of a specific cluster.
     * @param _clusterId The cluster ID to distribute the POS rewards for.
     * @param _split The current split struct of the cluster. Can be reconstructed offchain since the only variable is the `recipients` field.
     * @param _token The address of the token to distribute. NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
     * @dev Reverts if the cluster doesn't have a split address set / doesn't exist
     * @dev The distributor is the msg.sender. He will earn the distribution fees.
     * @dev If the push failed, the tokens will be sent to the SplitWarehouse. NodeOp will have to call the withdraw function.
     */
    function distributeSplitBalance(
        bytes32 _clusterId,
        SplitV2Lib.Split calldata _split,
        address _token
    ) external;

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the StrategyVault address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Vault.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Vault (nftId is not a ByzNft)
     */
    function getStratVaultByNftId(uint256 nftId) external view returns (address);

    /// @notice Returns the number of Native Strategy Vaults (aka StratVaultETH)
    function numStratVaultETHs() external view returns (uint256);
    
    /// @notice Returns all the Native Strategy Vaults addresses (aka StratVaultETH)
    function getAllStratVaultETHs() external view returns (address[] memory);

    /**
     * @notice Returns 'true' if the `stratVault` is a Native Strategy Vault (a StratVaultETH), and 'false' otherwise.
     * @param stratVault The address of the StrategyVault contract you want to know if it is a StratVaultETH.
     */
    function isStratVaultETH(address stratVault) external view returns (bool);

    /* ============== EIGEN LAYER INTERACTION ============== */

    /**
     * @notice Returns the address of the Strategy Vault's EigenPod (whether it is deployed yet or not).
     * @param stratVaultAddr The address of the StrategyVault contract you want to know the EigenPod address.
     * @dev If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function getPodByStratVaultAddr(address stratVaultAddr) external view returns (address);

    /// @dev Returned when a specific address doesn't have a StrategyVault
    error DoNotHaveStratVault(address);

    /// @dev Returned when unauthorized call to a function only callable by the StrategyVault owner
    error NotStratVaultOwner();

    /// @dev Returned when not enough node operators in Auction to create a new DV
    error EmptyAuction();

    /// @dev Returned when trying to distribute the split balance of a cluster that doesn't have a split address set
    error SplitAddressNotSet();
}
