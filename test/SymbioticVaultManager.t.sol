// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SymbioticVaultManager} from "../src/core/symbiotic/SymbioticVaultManager.sol";
import {ISymbioticVaultManager} from "../src/interfaces/ISymbioticVaultManager.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

contract SymbioticVaultManagerTest is Test{
    uint256 holeskyFork;
    string HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");

    SymbioticVaultManager symbioticVaultManager;

    // Define the addresses required for the constructor
    address public BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b;
    address public VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA;
    address public DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD;
    address public STAKING_MINIVAULT = vm.addr(1); 

    // Parameters for the createAdvancedVault function
    address public OWNER = vm.addr(2);
    address public COLLATERAL = 0x25133c2c49A343F8312bb6e896C1ea0Ad8CD0EBd; // address of the collateral - wstETH
    uint48 public DELAY = 21 days;
    address public GLOBAL_RECEIVER = 0x0000000000000000000000000000000000000000;
    address public network1 = vm.addr(3);
    address public network2 = vm.addr(4);
    address public operator1 = vm.addr(5);
    address public operator2 = vm.addr(6);
    address public receiver1 = vm.addr(7);
    address public receiver2 = vm.addr(8);

    function setUp() public {
        holeskyFork = vm.createFork(HOLESKY_RPC_URL);
        vm.selectFork(holeskyFork);


        // Deploy the SymbioticVaultManager contract with constructor parameters
        symbioticVaultManager = new SymbioticVaultManager(
            BURNER_ROUTER_FACTORY,
            VAULT_CONFIGURATOR,
            DEFAULT_STAKER_REWARDS_FACTORY,
            STAKING_MINIVAULT
        );
    }

    function testCanSelectFork() public {
        // select the fork
        vm.selectFork(holeskyFork);
        assertEq(vm.activeFork(), holeskyFork);
    }
    
    function test_createAdvancedVault() public {
        // Define the parameters for the createAdvancedVault function
        ISymbioticVaultManager.BurnerRouterParams memory burnerRouterParams = ISymbioticVaultManager.BurnerRouterParams({
            owner: OWNER,
            collateral: COLLATERAL,
            delay: DELAY,
            globalReceiver: GLOBAL_RECEIVER,
            networkReceivers: new IBurnerRouter.NetworkReceiver[](2), // Initialize with correct struct type
            operatorNetworkReceivers: new IBurnerRouter.OperatorNetworkReceiver[](2) // Initialize with correct struct type
        });

        // Initialize networkReceivers and operatorNetworkReceivers with actual values
        burnerRouterParams.networkReceivers[0] = IBurnerRouter.NetworkReceiver({network: network1, receiver: receiver1});
        burnerRouterParams.networkReceivers[1] = IBurnerRouter.NetworkReceiver({network: network2, receiver: receiver2});
        burnerRouterParams.operatorNetworkReceivers[0] = IBurnerRouter.OperatorNetworkReceiver({network: network1, operator: operator1, receiver: receiver1});
        burnerRouterParams.operatorNetworkReceivers[1] = IBurnerRouter.OperatorNetworkReceiver({network: network2, operator: operator2, receiver: receiver2});

        ISymbioticVaultManager.VaultParams memory vaultParams = ISymbioticVaultManager.VaultParams({
            collateral: COLLATERAL,
            burnerRouter: address(0), 
            epochDuration: 7 days,
            depositWhitelist: true,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: OWNER,
            depositWhitelistSetRoleHolder: OWNER,
            depositorWhitelistRoleHolder: address(symbioticVaultManager),
            isDepositLimitSetRoleHolder: OWNER,
            depositLimitSetRoleHolder: OWNER
        });

        ISymbioticVaultManager.DelegatorParams memory delegatorParams = ISymbioticVaultManager.DelegatorParams({
            defaultAdminRoleHolder: OWNER,
            hook: address(0),
            hookSetRoleHolder: OWNER,
            networkLimitSetRoleHolders: new address[](0), // Explicitly define as address array
            operatorNetworkSharesSetRoleHolders: new address[](0) // Explicitly define as address array
        });

        ISymbioticVaultManager.SlasherParams memory slasherParams = ISymbioticVaultManager.SlasherParams({
            isBurnerHook: false
        });

        uint64 slasherIndex = 0; 

        ISymbioticVaultManager.StakerRewardsParams memory stakerRewardsParams = ISymbioticVaultManager.StakerRewardsParams({
            vault: address(0), 
            adminFee: 100, 
            defaultAdminRoleHolder: OWNER,
            adminFeeClaimRoleHolder: OWNER,
            adminFeeSetRoleHolder: OWNER
        });

        // Call the createAdvancedVault function
        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault) = symbioticVaultManager.createAdvancedVault(
            burnerRouterParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            slasherIndex,
            stakerRewardsParams
        );

        // Verify if the vault and other contracts are deployed
        assert(vault != address(0));
        assert(delegator != address(0));
        assert(slasher != address(0));
        assert(defaultStakerRewards != address(0));
        assert(byzFiNativeSymbioticVault != address(0));
        console.log("vault", vault);
        console.log("delegator", delegator);
        console.log("slasher", slasher);
        console.log("defaultStakerRewards", defaultStakerRewards);
        console.log("byzFiNativeSymbioticVault", byzFiNativeSymbioticVault);    
    }

}
