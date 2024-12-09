// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

interface ISymbioticVaultManager {
    // Struct of parameters for deploying a BurnerRouter
    struct BurnerRouterParams {
        address owner;
        address collateral;
        uint48 delay;
        address globalReceiver;
        IBurnerRouter.NetworkReceiver[] networkReceivers;
        IBurnerRouter.OperatorNetworkReceiver[] operatorNetworkReceivers;
    }

    // Struct of parameters for deploying a Vault
    struct VaultConfiguratorParams {
        uint64 version; // predefined at initialization
        address owner;
        bytes vaultParams;
        uint64 delegatorIndex; // predefined at initialization
        bytes delegatorParams;
        bool withSlasher; // predefined at initialization
        uint64 slasherIndex;
        bytes slasherParams;
    }

    // Struct of parameters for vault configuration
    struct VaultParams {
        address collateral;
        address burnerRouter;
        uint48 epochDuration;
        bool depositWhitelist;
        bool isDepositLimit;
        uint256 depositLimit;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
        address isDepositLimitSetRoleHolder;
        address depositLimitSetRoleHolder;
    }

    // Struct of parameters for delegator configuration
    struct DelegatorParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
        address[] networkLimitSetRoleHolders;
        address[] operatorNetworkSharesSetRoleHolders;
    }

    // Struct of parameters for slasher configuration
    struct SlasherParams {
        bool isBurnerHook;
    }

    // Struct of parameters for staker rewards configuration
    struct StakerRewardsParams {
        address vault;
        uint256 adminFee;
        address defaultAdminRoleHolder;
        address adminFeeClaimRoleHolder;
        address adminFeeSetRoleHolder;
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
     * @param slasherIndex The index of the slasher.
     * @param stakerRewardsParams The parameters for the staker rewards.
     */
    function createAdvancedVault(
        BurnerRouterParams memory burnerRouterParams,
        VaultParams memory vaultParams,
        DelegatorParams memory delegatorParams,
        SlasherParams memory slasherParams,
        uint64 slasherIndex,
        StakerRewardsParams memory stakerRewardsParams
    ) external returns (address vault, address delegator, address slasher, address defaultStakerRewards);
}
