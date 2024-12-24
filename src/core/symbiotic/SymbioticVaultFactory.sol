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
import {IFullRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseSlasher} from "@symbioticfi/core/src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";
import {ISymbioticVaultFactory} from "../../interfaces/ISymbioticVaultFactory.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

import {ByzFiNativeSymbioticVault} from "../../vault/symbiotic/ByzFiNativeSymbioticVault.sol";
import {StakingMinivault} from "../../vault/symbiotic/StakingMinivault.sol";

contract SymbioticVaultFactory is Initializable, OwnableUpgradeable {

    /* ===================== CONSTANTS + IMMUTABLES ===================== */

    /// @notice Deployment Addresses
    address public BURNER_ROUTER_FACTORY;
    address public VAULT_CONFIGURATOR;
    address public DEFAULT_STAKER_REWARDS_FACTORY;

    /// @notice Standardized parameters for all vaults
    uint64 public constant VERSION = 1; // 1: standard vault, 2: tokenized vault
    bool public constant WITH_SLASHER = true;

    /// @notice Standardized parameters for standard vaults
    uint64 public constant DELEGATOR_INDEX = 0; // 0: NetworkRestakeDelegator, 1: FullRestakeDelegatorWithSlasher
    uint64 public constant SLASHER_INDEX = 1;
    bool public constant IS_DEPOSIT_LIMIT = false;
    uint256 public constant DEPOSIT_LIMIT = 0;
    bool public constant IS_BURNER_HOOK = true;

    /* ===================== CONSTRUCTOR & INITIALIZER ===================== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _burnerRouterFactory,
        address _vaultConfigurator,
        address _defaultStakerRewardsFactory
    ) {
        BURNER_ROUTER_FACTORY = _burnerRouterFactory;
        VAULT_CONFIGURATOR = _vaultConfigurator;
        DEFAULT_STAKER_REWARDS_FACTORY = _defaultStakerRewardsFactory;
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
     * @notice Creates a vault with a burner router, delegator, slasher, and default staker rewards based on whether it is a standard or advanced vault
     * @param burnerRouterParams The parameters for the burner router
     * @param configuratorParams The parameters for the vault configurator
     * @param vaultParams The parameters for the vault
     * @param delegatorParams The parameters for the delegator
     * @param slasherParams The parameters for the slasher
     * @param stakerRewardsParams The parameters for the staker rewards
     * @param isStandardVault Whether to create a standard or advanced vault
     */
    function createVault(
        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
        ISymbioticVaultFactory.VaultParams memory vaultParams,
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
        ISymbioticVaultFactory.SlasherParams memory slasherParams,
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams,
        bool isStandardVault
    ) external returns (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) {
        
        // Deploy ByzFiNativeSymbioticVault
        byzFiNativeSymbioticVault = payable(address(new ByzFiNativeSymbioticVault()));
        
        // Deploy StakingMinivault
        stakingMinivault = address(new StakingMinivault(
            address(0),                 // _symPodFactory (mock)
            address(0),                 // _auction (mock)
            address(0)                  // _beaconChainAdmin (mock)
        ));

        // Deploy BurnerRouter
        address burnerRouter = _deployBurnerRouter(burnerRouterParams, byzFiNativeSymbioticVault, stakingMinivault);

        // If it is a standard vault, use the preset parameters for the vault configurator
        if (isStandardVault) { 
            // Use the preset parameters for the vault configurator
            configuratorParams.delegatorIndex = DELEGATOR_INDEX;
            configuratorParams.slasherIndex = SLASHER_INDEX;

            // Use the preset parameters for the vault
            vaultParams.isDepositLimit = IS_DEPOSIT_LIMIT;
            vaultParams.depositLimit = DEPOSIT_LIMIT;

            // Use the preset parameters for the slasher
            slasherParams.isBurnerHook = IS_BURNER_HOOK;
        }

        // Deploy Vault
        (vault, delegator, slasher) = _deployVault(configuratorParams, vaultParams, delegatorParams, slasherParams, burnerRouter, byzFiNativeSymbioticVault, stakingMinivault);

        // Deploy DefaultStakerRewards
        defaultStakerRewards = _deployDefaultStakerRewards(stakerRewardsParams, vault, byzFiNativeSymbioticVault);

        // Initialize ByzFiNativeSymbioticVault and whitelist the stakingMinivault as a depositor
        ByzFiNativeSymbioticVault(byzFiNativeSymbioticVault).initialize(byzFiNativeSymbioticVault, vault, stakingMinivault);

        return (vault, delegator, slasher, defaultStakerRewards, byzFiNativeSymbioticVault, stakingMinivault);
    }

    /* ===================== PRIVATE FUNCTIONS ===================== */

    /**
     * @notice Deploys a BurnerRouter with the given parameters
     * @param params The parameters for the BurnerRouter
     * @param byzFiNativeSymbioticVault The address of the ByzFiNativeSymbioticVault
     * @param stakingMinivault The address of the StakingMinivault
     */
    function _deployBurnerRouter(
        ISymbioticVaultFactory.BurnerRouterParams memory params,
        address byzFiNativeSymbioticVault,
        address stakingMinivault
    ) private returns (address) {
        return IBurnerRouterFactory(BURNER_ROUTER_FACTORY).create(
            IBurnerRouter.InitParams({
                owner: byzFiNativeSymbioticVault,
                collateral: stakingMinivault, // the minivault is also an ERC20 token
                delay: params.delay,
                globalReceiver: params.globalReceiver,
                networkReceivers: params.networkReceivers,
                operatorNetworkReceivers: params.operatorNetworkReceivers
            })
        );
    }

    /**
     * @notice Deploys a Vault with the given parameters
     * @param configuratorParams The parameters for the Vault Configurator
     * @param vaultParams The parameters for the Vault
     * @param delegatorParams The parameters for the Delegator
     * @param slasherParams The parameters for the Slasher
     * @param burnerRouter The address of the BurnerRouter
     * @param byzFiNativeSymbioticVault The address of the ByzFiNativeSymbioticVault
     * @param stakingMinivault The address of the StakingMinivault
     */
    function _deployVault(
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
        ISymbioticVaultFactory.VaultParams memory vaultParams,
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
        ISymbioticVaultFactory.SlasherParams memory slasherParams,
        address burnerRouter,
        address byzFiNativeSymbioticVault,
        address stakingMinivault
    ) private returns (address, address, address) {
        // Initialize vaultInitParams
        bytes memory vaultInitParams = _initializeVaultInitParams(
            vaultParams,
            burnerRouter,
            byzFiNativeSymbioticVault,
            stakingMinivault
        );

        // Initialize delegatorInitParams
        bytes memory delegatorInitParams = _initializeDelegatorInitParams(
            configuratorParams,
            delegatorParams,
            byzFiNativeSymbioticVault
        );

        // Initialize slasherInitParams
        bytes memory slasherInitParams = _initializeSlasherInitParams(
            slasherParams,
            configuratorParams.slasherIndex
        );

        uint64 delegatorIndex = configuratorParams.delegatorIndex;
        uint64 slasherIndex = configuratorParams.slasherIndex;

        // Deploy Vault using the VaultConfigurator from Symbiotic
        return IVaultConfigurator(VAULT_CONFIGURATOR).create(
            IVaultConfigurator.InitParams({
                version: VERSION,
                owner: byzFiNativeSymbioticVault,
                vaultParams: vaultInitParams,
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorInitParams,
                withSlasher: WITH_SLASHER,
                slasherIndex: slasherIndex,
                slasherParams: slasherInitParams
            })
        );
    }

    /**
     * @notice Deploys a DefaultStakerRewards with the given parameters
     * @param params The parameters for the DefaultStakerRewards
     * @param vault The address of the Vault
     * @param byzFiNativeSymbioticVault The address of the ByzFiNativeSymbioticVault
     */
    function _deployDefaultStakerRewards(
        ISymbioticVaultFactory.StakerRewardsParams memory params,
        address vault,
        address byzFiNativeSymbioticVault
    ) private returns (address) {
        return IDefaultStakerRewardsFactory(DEFAULT_STAKER_REWARDS_FACTORY).create(
            IDefaultStakerRewards.InitParams({
                vault: vault,
                adminFee: params.adminFee,
                defaultAdminRoleHolder: byzFiNativeSymbioticVault,
                adminFeeClaimRoleHolder: byzFiNativeSymbioticVault,
                adminFeeSetRoleHolder: byzFiNativeSymbioticVault
            })
        );
    }
    
    /**
     * @notice Initializes the InitParams from the Symbiotic IVault
     * @param vaultParams The parameters for the Vault
     * @param burnerRouter The address of the BurnerRouter
     * @param byzFiNativeSymbioticVault The address of the ByzFiNativeSymbioticVault
     * @param stakingMinivault The address of the StakingMinivault
     */
    function _initializeVaultInitParams(
        ISymbioticVaultFactory.VaultParams memory vaultParams,
        address burnerRouter,
        address byzFiNativeSymbioticVault,
        address stakingMinivault
    ) private pure returns (bytes memory) {
        return abi.encode(IVault.InitParams({
            collateral: stakingMinivault,
            burner: burnerRouter,
            epochDuration: vaultParams.epochDuration,
            depositWhitelist: true,
            isDepositLimit: vaultParams.isDepositLimit,
            depositLimit: vaultParams.depositLimit,
            defaultAdminRoleHolder: byzFiNativeSymbioticVault,
            depositWhitelistSetRoleHolder: byzFiNativeSymbioticVault,
            depositorWhitelistRoleHolder: byzFiNativeSymbioticVault,
            isDepositLimitSetRoleHolder: byzFiNativeSymbioticVault,
            depositLimitSetRoleHolder: byzFiNativeSymbioticVault
        }));
    }


    /**
     * @notice Initializes the InitParams from the Symbiotic IBaseDelegator
     * @param configuratorParams The parameters for the Vault Configurator
     * @param delegatorParams The parameters for the Delegator
     * @param byzFiNativeSymbioticVault The address of the ByzFiNativeSymbioticVault
     */
    function _initializeDelegatorInitParams(
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
        address byzFiNativeSymbioticVault
    ) private pure returns (bytes memory) {
        // Initialize BaseParams of Symbiotic IBaseDelegator
        IBaseDelegator.BaseParams memory delegatorBaseParams = IBaseDelegator.BaseParams({
            defaultAdminRoleHolder: byzFiNativeSymbioticVault,
            hook: delegatorParams.hook,
            hookSetRoleHolder: delegatorParams.hookSetRoleHolder
        });

        // Initialize InitParams of Symbiotic INetworkRestakeDelegator or IFullRestakeDelegator
        if (configuratorParams.delegatorIndex == 0) {
            INetworkRestakeDelegator.InitParams memory initParams = INetworkRestakeDelegator.InitParams({
                baseParams: delegatorBaseParams,
                networkLimitSetRoleHolders: new address[](1),
                operatorNetworkSharesSetRoleHolders: new address[](1)
            });
            initParams.networkLimitSetRoleHolders[0] = byzFiNativeSymbioticVault;
            initParams.operatorNetworkSharesSetRoleHolders[0] = byzFiNativeSymbioticVault;
            return abi.encode(initParams);
        } else {
            IFullRestakeDelegator.InitParams memory initParams = IFullRestakeDelegator.InitParams({
                baseParams: delegatorBaseParams,
                networkLimitSetRoleHolders: new address[](1),
                operatorNetworkLimitSetRoleHolders: new address[](1)
            });
            initParams.networkLimitSetRoleHolders[0] = byzFiNativeSymbioticVault;
            initParams.operatorNetworkLimitSetRoleHolders[0] = byzFiNativeSymbioticVault;
            return abi.encode(initParams);
        }
    }

    function _initializeSlasherInitParams(
        ISymbioticVaultFactory.SlasherParams memory slasherParams,
        uint64 slasherIndex
    ) private pure returns (bytes memory) {

        // Initialize ISlasher.InitParams if slasherIndex is 0, otherwise initialize IVetoSlasher.InitParams
        if (slasherIndex == 0) {
        return abi.encode(
                ISlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({
                        isBurnerHook: slasherParams.isBurnerHook
                    })
                })
            );
        } else {
            return abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({
                        isBurnerHook: slasherParams.isBurnerHook
                    }),
                    vetoDuration: slasherParams.vetoDuration,
                    resolverSetEpochsDelay: slasherParams.resolverSetEpochsDelay
                })
            );
        }
    }
}