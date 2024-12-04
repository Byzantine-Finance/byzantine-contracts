// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {IBurnerRouterFactory} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouterFactory.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import {IVaultConfigurator} from "@symbioticfi/core/src/interfaces/IVaultConfigurator.sol";
import {IDefaultStakerRewardsFactory} from "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewardsFactory.sol";
import {IDefaultStakerRewards} from "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import {IBaseDelegator} from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseSlasher} from "@symbioticfi/core/src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";

/**
 * @notice Script used to deploy a Byzantine Symbiotic Vault to Holesky
 * forge script script/deploy/holesky/Deploy_Symbiotic_Vault.s.sol:DeploySymbioticVault --rpc-url https://ethereum-holesky-rpc.publicnode.com --chain holesky --broadcast -vvv
 */
contract DeploySymbioticVault is Script {
    // ============= Deployment Addresses =============
    address public constant BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b;
    address public constant VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA;
    address public constant DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD;
    address public constant STAKING_MINIVAULT = 0x0000000000000000000000000000000000000000; // TO DO: Set actual staking minivault
    address public constant HOOK = address(0); // TO DO: Set actual hook

    // ============= Access Control Configuration =============
    address public constant OWNER = address(0); // TO DO: Set actual owner
    bool public constant DEPOSIT_WHITELIST = true;
    address public constant GLOBAL_RECEIVER = STAKING_MINIVAULT;
    address public constant DEFAULT_ADMIN_ROLE = STAKING_MINIVAULT;
    address public constant DEPOSIT_WHITELIST_SET_ROLE = STAKING_MINIVAULT;
    address public constant DEPOSITOR_WHITELIST_ROLE = STAKING_MINIVAULT;
    address public constant IS_DEPOSIT_LIMIT_SET_ROLE = STAKING_MINIVAULT;
    address public constant DEPOSIT_LIMIT_SET_ROLE = STAKING_MINIVAULT;
    address public constant DEFAULT_ADMIN_ROLE_HOLDER = STAKING_MINIVAULT;
    address public constant ADMIN_FEE_CLAIM_ROLE_HOLDER = STAKING_MINIVAULT;
    address public constant ADMIN_FEE_SET_ROLE_HOLDER = STAKING_MINIVAULT;
    address public constant HOOK_SET_ROLE_HOLDER = STAKING_MINIVAULT;
    address[] public networkLimitSetRoleHolders = [STAKING_MINIVAULT];
    address[] public operatorNetworkSharesSetRoleHolders = [STAKING_MINIVAULT];

    // ============= Core Configuration =============
    // Non-customizable parameters (fixed for security)
    uint48 public constant DELAY = 1814400; // 21 days
    uint256 public constant ADMIN_FEE = 1000; // 10%
    uint64 public constant VERSION = 1;
    bool public constant WITH_SLASHER = true;
    uint64 public constant SLASHER_INDEX = 0; // 0: Slasher, instant execute. 1: VetoSlasher, veto slash request with resolvers.
    bool public constant IS_BURNER_HOOK = true;

    // ============= Default Vault Configuration =============
    // 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D wstETH
    // Basic configuration (for normal users)
    address public vaultCollateral;
    uint48 public constant DEFAULT_EPOCH_DURATION = 7 days;
    bool public constant DEFAULT_IS_DEPOSIT_LIMIT = true;
    uint256 public constant DEFAULT_DEPOSIT_LIMIT = 1000 ether;
    uint48 public constant DEFAULT_VETO_DURATION = 1 days;
    uint64 public constant DEFAULT_DELEGATOR_INDEX = 0;

    // ============= Advanced Configuration =============
    // For advanced users (customizable during deployment)
    uint48 public epochDuration;
    bool public isDepositLimit;
    uint256 public depositLimit;
    uint48 public vetoDuration;
    uint64 public delegatorIndex;
    
    function run(address _collateral) public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        vaultCollateral = _collateral;

        // 1. Deploy BurnerRouter
        address burnerRouter = IBurnerRouterFactory(BURNER_ROUTER_FACTORY).create(
            IBurnerRouter.InitParams({
                owner: OWNER,
                collateral: _collateral,
                delay: DELAY,
                globalReceiver: GLOBAL_RECEIVER,
                networkReceivers: new IBurnerRouter.NetworkReceiver[](0),
                operatorNetworkReceivers: new IBurnerRouter.OperatorNetworkReceiver[](0)
            })
        );
        console2.log("Burner Router deployed at:", burnerRouter);

        // 2. Deploy Vault
        (address vault, address delegator, address slasher) = IVaultConfigurator(VAULT_CONFIGURATOR).create(
            IVaultConfigurator.InitParams({
                version: VERSION,
                owner: OWNER,
                vaultParams: _getVaultParams(burnerRouter),
                delegatorIndex: DEFAULT_DELEGATOR_INDEX,
                delegatorParams: _getDelegatorParams(),
                withSlasher: WITH_SLASHER,
                slasherIndex: SLASHER_INDEX,
                slasherParams: _getSlasherParams()
            })
        );
        console2.log("Vault deployed at:", vault);
        console2.log("Delegator deployed at:", delegator);
        console2.log("Slasher deployed at:", slasher);

        // 3. Deploy DefaultStakerRewards
        address defaultStakerRewards = IDefaultStakerRewardsFactory(DEFAULT_STAKER_REWARDS_FACTORY).create(
            IDefaultStakerRewards.InitParams({
                vault: vault,
                adminFee: ADMIN_FEE,
                defaultAdminRoleHolder: DEFAULT_ADMIN_ROLE_HOLDER,
                adminFeeClaimRoleHolder: ADMIN_FEE_CLAIM_ROLE_HOLDER,
                adminFeeSetRoleHolder: ADMIN_FEE_SET_ROLE_HOLDER
            })
        );
        console2.log("DefaultStakerRewards deployed at:", defaultStakerRewards);
        
        vm.stopBroadcast();
    }

    function _getVaultParams(address burnerRouter) internal view returns (bytes memory) {
        return abi.encode(
            vaultCollateral,             // collateral
            burnerRouter,                // burner
            DEFAULT_EPOCH_DURATION,      // epochDuration
            DEFAULT_DEPOSIT_WHITELIST,   // depositWhitelist
            DEFAULT_IS_DEPOSIT_LIMIT,    // isDepositLimit
            DEFAULT_DEPOSIT_LIMIT,       // depositLimit
            DEFAULT_ADMIN_ROLE,          // defaultAdminRoleHolder
            DEPOSIT_WHITELIST_SET_ROLE,  // depositWhitelistSetRoleHolder
            DEPOSITOR_WHITELIST_ROLE,    // depositorWhitelistRoleHolder
            IS_DEPOSIT_LIMIT_SET_ROLE,   // isDepositLimitSetRoleHolder
            DEPOSIT_LIMIT_SET_ROLE       // depositLimitSetRoleHolder
        );
    }
    
    function _getDelegatorParams() internal view returns (bytes memory) {
        return abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: IBaseDelegator.BaseParams({
                    defaultAdminRoleHolder: DEFAULT_ADMIN_ROLE_HOLDER,
                    hook: HOOK,
                    hookSetRoleHolder: HOOK_SET_ROLE_HOLDER
                }),
                networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
            })
        );
    }

    function _getSlasherParams() internal pure returns (bytes memory) {
        return abi.encode(
            ISlasher.InitParams({
                baseParams: IBaseSlasher.BaseParams({
                    isBurnerHook: IS_BURNER_HOOK
                })
            })
        );
    }
}