// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SymbioticVaultFactory} from "../src/core/symbiotic/SymbioticVaultFactory.sol";
import {ISymbioticVaultFactory} from "../src/interfaces/ISymbioticVaultFactory.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import {ByzFiNativeSymbioticVault} from "../src/vault/symbiotic/ByzFiNativeSymbioticVault.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

contract SymbioticVaultFactoryTest is Test {
    uint256 holeskyFork;
    string HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");

    SymbioticVaultFactory symbioticVaultFactory;

    // Define the addresses required for the constructor
    address public BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b; // deployed on holesky   
    address public VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA; // deployed on holesky
    address public DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD; // deployed on holesky
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

    address alice = vm.addr(9);
    // vm.deal(alice, 1000 ether);

    function setUp() public {
        holeskyFork = vm.createFork(HOLESKY_RPC_URL);
        vm.selectFork(holeskyFork);


        // Deploy the SymbioticVaultManager contract with constructor parameters
        symbioticVaultFactory = new SymbioticVaultFactory(
            BURNER_ROUTER_FACTORY,
            VAULT_CONFIGURATOR,
            DEFAULT_STAKER_REWARDS_FACTORY
        );
    }

    function testCanSelectFork() public {
        // select the fork
        vm.selectFork(holeskyFork);
        assertEq(vm.activeFork(), holeskyFork);
    }

    function test_createAdvancedVault() public {
        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams = createBurnerRouterParams();
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams = createConfiguratorParams();
        ISymbioticVaultFactory.VaultParams memory vaultParams = createVaultParams();
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams = createDelegatorParams();
        ISymbioticVaultFactory.SlasherParams memory slasherParams = createSlasherParams();
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams = createStakerRewardsParams();

        // Call the createAdvancedVault function
        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) = symbioticVaultFactory.createAdvancedVault(
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
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

        // Verifiy if the ByzFiNativeSymbioticVault is initialized with the correct vault address
        address vaultAddr = address(ByzFiNativeSymbioticVault(byzFiNativeSymbioticVault).vault());
        assertEq(vaultAddr, vault);

        // Verify if the ByzFiNativeSymbioticVault is initialized with the correct staking minivault address
        address stakingMinivaultAddr = ByzFiNativeSymbioticVault(byzFiNativeSymbioticVault).stakingMinivault();
        assertEq(stakingMinivaultAddr, stakingMinivault);
        console.log("stakingMinivaultAddr", stakingMinivaultAddr);

        // Verify if the stakingMinivault is whitelisted
        assertEq(IVault(vault).isDepositorWhitelisted(stakingMinivault), true);
    }

    function test_deposit() public {
        // TODO To complete
    }

    function createBurnerRouterParams() internal view returns (ISymbioticVaultFactory.BurnerRouterParams memory) {
        ISymbioticVaultFactory.BurnerRouterParams memory params = ISymbioticVaultFactory.BurnerRouterParams({
            delay: DELAY,
            globalReceiver: GLOBAL_RECEIVER,
            networkReceivers: new IBurnerRouter.NetworkReceiver[](2), 
            operatorNetworkReceivers: new IBurnerRouter.OperatorNetworkReceiver[](2) 
        });

        params.networkReceivers[0] = IBurnerRouter.NetworkReceiver({network: network1, receiver: receiver1});
        params.networkReceivers[1] = IBurnerRouter.NetworkReceiver({network: network2, receiver: receiver2});
        params.operatorNetworkReceivers[0] = IBurnerRouter.OperatorNetworkReceiver({network: network1, operator: operator1, receiver: receiver1});
        params.operatorNetworkReceivers[1] = IBurnerRouter.OperatorNetworkReceiver({network: network2, operator: operator2, receiver: receiver2});

        return params;
    }

    function createConfiguratorParams() internal view returns (ISymbioticVaultFactory.VaultConfiguratorParams memory) {
        return ISymbioticVaultFactory.VaultConfiguratorParams({
            delegatorIndex: 0,
            slasherIndex: 1
        });
    }

    function createVaultParams() internal view returns (ISymbioticVaultFactory.VaultParams memory) {
        return ISymbioticVaultFactory.VaultParams({
            epochDuration: 7 days,
            isDepositLimit: false,
            depositLimit: 0
        });
    }

    function createDelegatorParams() internal view returns (ISymbioticVaultFactory.DelegatorParams memory) {
        return ISymbioticVaultFactory.DelegatorParams({
            hook: address(0),
            hookSetRoleHolder: address(symbioticVaultFactory)
        });
    }

    function createSlasherParams() internal view returns (ISymbioticVaultFactory.SlasherParams memory) {
        return ISymbioticVaultFactory.SlasherParams({
            isBurnerHook: true,
            vetoDuration: 2 days,
            resolverSetEpochsDelay: 10
        });
    }

    function createStakerRewardsParams() internal view returns (ISymbioticVaultFactory.StakerRewardsParams memory) {
        return ISymbioticVaultFactory.StakerRewardsParams({
            adminFee: 100
        });
    }
}
