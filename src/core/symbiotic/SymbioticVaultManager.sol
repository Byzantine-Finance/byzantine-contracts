// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {IBurnerRouterFactory} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouterFactory.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import {IVaultConfigurator} from "@symbioticfi/core/src/interfaces/IVaultConfigurator.sol";
import {IDefaultStakerRewardsFactory} from "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewardsFactory.sol";
import {IDefaultStakerRewards} from "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IBaseDelegator} from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseSlasher} from "@symbioticfi/core/src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import {ISymbioticVaultManager} from "../../interfaces/ISymbioticVaultManager.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

import {ByzFiNativeSymbioticVault} from "../../vault/symbiotic/ByzFiNativeSymbioticVault.sol";

contract SymbioticVaultManager is Initializable, OwnableUpgradeable {

    // ============= Deployment Addresses =============
    address public BURNER_ROUTER_FACTORY;
    address public VAULT_CONFIGURATOR;
    address public DEFAULT_STAKER_REWARDS_FACTORY;
    address public STAKING_MINIVAULT;

    // ============= Vault Configuration =============
    uint64 public constant VERSION = 1; // 1: standard vault, 2: tokenized vault
    bool public constant WITH_SLASHER = true;
    uint64 public constant DEFAULT_DELEGATOR_INDEX = 0; // 0: NetworkRestakeDelegator, 1: FullRestakeDelegatorWithSlasher

    /* ===================== CONSTRUCTOR & INITIALIZER ===================== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _burnerRouterFactory,
        address _vaultConfigurator,
        address _defaultStakerRewardsFactory,
        address _stakingMinivault
    ) {
        BURNER_ROUTER_FACTORY = _burnerRouterFactory;
        VAULT_CONFIGURATOR = _vaultConfigurator;
        DEFAULT_STAKER_REWARDS_FACTORY = _defaultStakerRewardsFactory;
        STAKING_MINIVAULT = _stakingMinivault;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        address initialOwner
    ) external initializer {
        _transferOwnership(initialOwner);
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Creates a standard vault with a burner router, delegator, and default staker rewards.
     */
    function createStandardVault() external returns (address vault, address delegator, address defaultStakerRewards) {
        // TODO: Implement standard vault creation
    }

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
        ISymbioticVaultManager.BurnerRouterParams memory burnerRouterParams,
        ISymbioticVaultManager.VaultParams memory vaultParams,
        ISymbioticVaultManager.DelegatorParams memory delegatorParams,
        ISymbioticVaultManager.SlasherParams memory slasherParams,
        uint64 slasherIndex,
        ISymbioticVaultManager.StakerRewardsParams memory stakerRewardsParams
    ) external returns (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault) {
        
        // Deploy ByzFiNativeSymbioticVault
        byzFiNativeSymbioticVault = payable(address(new ByzFiNativeSymbioticVault()));

        // Deploy BurnerRouter
        address burnerRouter = _deployBurnerRouter(burnerRouterParams);

        // Update the vaultParams with the deployed burnerRouter address
        vaultParams.burnerRouter = burnerRouter;

        // Initialize VaultConfiguratorParams with predefined and input values
        ISymbioticVaultManager.VaultConfiguratorParams memory vaultConfiguratorParams = ISymbioticVaultManager.VaultConfiguratorParams({
            version: VERSION,
            owner: byzFiNativeSymbioticVault,
            vaultParams: abi.encode(vaultParams),
            delegatorIndex: DEFAULT_DELEGATOR_INDEX,
            delegatorParams: abi.encode(delegatorParams),
            withSlasher: WITH_SLASHER,
            slasherIndex: slasherIndex,
            slasherParams: abi.encode(slasherParams)
        });

        // Deploy Vault
        (vault, delegator, slasher) = _deployVault(
            vaultConfiguratorParams
        );

        // Whitelist the StakingMiniVault being the only whitelisted depositor
        IVault(vault).setDepositorWhitelistStatus(STAKING_MINIVAULT, true);

        // Initialize ByzFiNativeSymbioticVault
        ByzFiNativeSymbioticVault(byzFiNativeSymbioticVault).initialize(vault);
        
        // Deploy DefaultStakerRewards
        defaultStakerRewards = _deployDefaultStakerRewards(stakerRewardsParams);

        return (vault, delegator, slasher, defaultStakerRewards, byzFiNativeSymbioticVault);
    }

    /* ===================== PRIVATE FUNCTIONS ===================== */

    function _deployBurnerRouter(
        ISymbioticVaultManager.BurnerRouterParams memory params
    ) private returns (address) {
        return IBurnerRouterFactory(BURNER_ROUTER_FACTORY).create(
            IBurnerRouter.InitParams({
                owner: params.owner,
                collateral: params.collateral,
                delay: params.delay,
                globalReceiver: params.globalReceiver,
                networkReceivers: params.networkReceivers,
                operatorNetworkReceivers: params.operatorNetworkReceivers
            })
        );
    }

    function _deployVault(
        ISymbioticVaultManager.VaultConfiguratorParams memory configParams
    ) private returns (address, address, address) {
        return IVaultConfigurator(VAULT_CONFIGURATOR).create(
            IVaultConfigurator.InitParams({
                version: configParams.version,
                owner: configParams.owner,
                vaultParams: configParams.vaultParams,
                delegatorIndex: configParams.delegatorIndex,
                delegatorParams: configParams.delegatorParams,
                withSlasher: configParams.withSlasher,
                slasherIndex: configParams.slasherIndex,
                slasherParams: configParams.slasherParams
            })
        );
    }

    function _deployDefaultStakerRewards(
        ISymbioticVaultManager.StakerRewardsParams memory params
    ) private returns (address) {
        return IDefaultStakerRewardsFactory(DEFAULT_STAKER_REWARDS_FACTORY).create(
            IDefaultStakerRewards.InitParams({
                vault: params.vault,
                adminFee: params.adminFee,
                defaultAdminRoleHolder: params.defaultAdminRoleHolder,
                adminFeeClaimRoleHolder: params.adminFeeClaimRoleHolder,
                adminFeeSetRoleHolder: params.adminFeeSetRoleHolder
            })
        );
    }
}