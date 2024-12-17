// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

interface ISymbioticVaultFactory {
    // Struct of parameters for deploying a BurnerRouter
    struct BurnerRouterParams {
        // address owner; // predefined
        // address collateral; 
        uint48 delay;
        address globalReceiver;
        IBurnerRouter.NetworkReceiver[] networkReceivers;
        IBurnerRouter.OperatorNetworkReceiver[] operatorNetworkReceivers;
    }

    // Struct of parameters for deploying a Vault
    struct VaultConfiguratorParams {
        // uint64 version; // predefined 
        // address owner; // predefined 
        // bytes vaultParams;
        uint64 delegatorIndex; 
        // bytes delegatorParams;
        // bool withSlasher; // predefined 
        uint64 slasherIndex;
        // bytes slasherParams;
    }

    // Struct of parameters for vault configuration
    struct VaultParams {
        // address collateral; // predefined
        // address burnerRouter; // predefined
        uint48 epochDuration;
        // bool depositWhitelist; // predefined 
        bool isDepositLimit;
        uint256 depositLimit;
        // address defaultAdminRoleHolder; // predefined 
        // address depositWhitelistSetRoleHolder; // predefined 
        // address depositorWhitelistRoleHolder; // predefined 
        // address isDepositLimitSetRoleHolder; // predefined 
        // address depositLimitSetRoleHolder; // predefined 
    }

    // Struct of parameters for delegator configuration
    struct DelegatorParams {
        // address defaultAdminRoleHolder; // predefined
        address hook;
        address hookSetRoleHolder;
        // address[] networkLimitSetRoleHolders; // predefined
        // address[] operatorNetworkSharesSetRoleHolders; // predefined
    }

    // Struct of parameters for slasher configuration
    struct SlasherParams {
        bool isBurnerHook;
        uint48 vetoDuration;
        uint256 resolverSetEpochsDelay;
    }

    // Struct of parameters for staker rewards configuration
    struct StakerRewardsParams {
        // address vault; // predefined
        uint256 adminFee;
        // address defaultAdminRoleHolder; // predefined
        // address adminFeeClaimRoleHolder; // predefined
        // address adminFeeSetRoleHolder; // predefined
    }

    /**
     * @notice Creates a standard vault with a burner router, delegator, and default staker rewards.
     */
    function createStandardVault() external returns (address vault, address delegator, address defaultStakerRewards);

    /**
     * @notice Creates an advanced vault with a burner router, delegator, slasher, and default staker rewards.
     * @param burnerRouterParams The parameters for the burner router.
     * @param vaultParams The parameters for the vault.
     * @param delegatorParams The parameters for the delegator.
     * @param slasherParams The parameters for the slasher.
     * @param stakerRewardsParams The parameters for the staker rewards.
     */
    function createAdvancedVault(
        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
        ISymbioticVaultFactory.VaultParams memory vaultParams,
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
        ISymbioticVaultFactory.SlasherParams memory slasherParams,
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
    ) external returns (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault);
}
