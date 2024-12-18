// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

interface ISymbioticVaultFactory {
    // Struct of parameters for deploying a BurnerRouter
    struct BurnerRouterParams {
        uint48 delay;
        address globalReceiver;
        IBurnerRouter.NetworkReceiver[] networkReceivers;
        IBurnerRouter.OperatorNetworkReceiver[] operatorNetworkReceivers;
    }

    // Struct of parameters for the vault configurator
    struct VaultConfiguratorParams {
        uint64 delegatorIndex; 
        uint64 slasherIndex;
    }

    // Struct of parameters for the vault
    struct VaultParams {
        uint48 epochDuration;
        bool isDepositLimit;
        uint256 depositLimit;
    }

    // Struct of parameters for delegator configuration
    struct DelegatorParams {
        address hook;
        address hookSetRoleHolder;
    }

    // Struct of parameters for slasher configuration
    struct SlasherParams {
        bool isBurnerHook;
        uint48 vetoDuration;
        uint256 resolverSetEpochsDelay;
    }

    // Struct of parameters for staker rewards configuration
    struct StakerRewardsParams {
        uint256 adminFee;
    }

    /**
     * @notice Creates a standard vault with a burner router, delegator, and default staker rewards.
     */
    function createStandardVault() external returns (address vault, address delegator, address defaultStakerRewards);

    /**
     * @notice Creates an advanced vault with a burner router, delegator, slasher, and default staker rewards.
     * @param burnerRouterParams The parameters for the burner router.
     * @param configuratorParams The parameters for the vault configurator.
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
