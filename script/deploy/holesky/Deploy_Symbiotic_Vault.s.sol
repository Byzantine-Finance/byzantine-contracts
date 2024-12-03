
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
    // BurnerRouter parameters
    address public constant BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b;
    address public constant OWNER = 0xe8616DEcea16b5216e805B0b8caf7784de7570E7;
    address public constant COLLATERAL = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
    uint48 public constant DELAY = 1814400;
    address public constant GLOBAL_RECEIVER = 0x25133c2c49A343F8312bb6e896C1ea0Ad8CD0EBd;

    // Vault parameters
    address public constant VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA;
    uint48 public constant EPOCH_DURATION = 7 days;
    uint256 public constant DEPOSIT_LIMIT = 1000 ether;
    uint64 public constant DELEGATOR_INDEX = 0; // NetworkRestakeDelegator
    address public constant HOOK = address(0);
    bool public constant WITH_SLASHER = true;
    uint64 public constant SLASHER_INDEX = 0;
    uint48 public constant VETO_DURATION = 1 days;

    // Vault initialization parameters
    uint64 public constant VERSION = 1;
    bool public constant DEPOSIT_WHITELIST = false;
    bool public constant IS_DEPOSIT_LIMIT = true;
    address public constant DEFAULT_ADMIN_ROLE = OWNER;
    address public constant DEPOSIT_WHITELIST_SET_ROLE = OWNER;
    address public constant DEPOSITOR_WHITELIST_ROLE = OWNER;
    address public constant IS_DEPOSIT_LIMIT_SET_ROLE = OWNER;
    address public constant DEPOSIT_LIMIT_SET_ROLE = OWNER;

    // DefaultStakerRewards parameters
    address public constant DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD;
    uint256 public constant ADMIN_FEE = 1000; // 10% (assuming base 10000)
    
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        // 1. Deploy BurnerRouter
        address burnerRouter = IBurnerRouterFactory(BURNER_ROUTER_FACTORY).create(
            IBurnerRouter.InitParams({
                owner: OWNER,
                collateral: COLLATERAL,
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
                delegatorIndex: DELEGATOR_INDEX,
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
                defaultAdminRoleHolder: OWNER,
                adminFeeClaimRoleHolder: OWNER,
                adminFeeSetRoleHolder: OWNER
            })
        );
        console2.log("DefaultStakerRewards deployed at:", defaultStakerRewards);
        
        vm.stopBroadcast();
    }

    function _getVaultParams(address burnerRouter) internal pure returns (bytes memory) {
        return abi.encode(
            COLLATERAL,                  // collateral
            burnerRouter,                // burner
            EPOCH_DURATION,              // epochDuration
            DEPOSIT_WHITELIST,           // depositWhitelist
            IS_DEPOSIT_LIMIT,            // isDepositLimit
            DEPOSIT_LIMIT,               // depositLimit
            DEFAULT_ADMIN_ROLE,          // defaultAdminRoleHolder
            DEPOSIT_WHITELIST_SET_ROLE,  // depositWhitelistSetRoleHolder
            DEPOSITOR_WHITELIST_ROLE,    // depositorWhitelistRoleHolder
            IS_DEPOSIT_LIMIT_SET_ROLE,   // isDepositLimitSetRoleHolder
            DEPOSIT_LIMIT_SET_ROLE       // depositLimitSetRoleHolder
        );
    }
    
    function _getDelegatorParams() internal pure returns (bytes memory) {
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = OWNER;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = OWNER;
        return abi.encode(
            INetworkRestakeDelegator.InitParams({
                baseParams: IBaseDelegator.BaseParams({
                    defaultAdminRoleHolder: OWNER,
                    hook: HOOK,
                    hookSetRoleHolder: OWNER
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
                    isBurnerHook: true
                })
            })
        );
    }
}