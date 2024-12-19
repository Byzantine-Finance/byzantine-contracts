// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SymbioticVaultFactory} from "../src/core/symbiotic/SymbioticVaultFactory.sol";
import {ISymbioticVaultFactory} from "../src/interfaces/ISymbioticVaultFactory.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import {ByzFiNativeSymbioticVault} from "../src/vault/symbiotic/ByzFiNativeSymbioticVault.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {IVetoSlasher} from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";
import {INetworkRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/IFullRestakeDelegator.sol";

contract SymbioticVaultFactoryTest is Test {
    uint256 holeskyFork;
    string HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");

    SymbioticVaultFactory symbioticVaultFactory;

    // Define the addresses required for the constructor
    address public BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b; // deployed on holesky   
    address public VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA; // deployed on holesky
    address public DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD; // deployed on holesky
    address public STAKING_MINIVAULT = vm.addr(1); 

    // Parameters to be used or the createVault function
    address public hook = vm.addr(2);
    address public network1 = vm.addr(3);
    address public network2 = vm.addr(4);
    address public operator1 = vm.addr(5);
    address public operator2 = vm.addr(6);
    address public receiver1 = vm.addr(7);
    address public receiver2 = vm.addr(8);

    address alice = vm.addr(9);
    // vm.deal(alice, 1000 ether);

    function setUp() public {
        // Make forked tests on Holesky
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
        // Define the parameters for _createBurnerRouterParams
        uint48 delay = 21 days;
        address globalReceiver = 0x0000000000000000000000000000000000000000;
        IBurnerRouter.NetworkReceiver[] memory networkReceivers = new IBurnerRouter.NetworkReceiver[](2);
        IBurnerRouter.OperatorNetworkReceiver[] memory operatorNetworkReceivers = new IBurnerRouter.OperatorNetworkReceiver[](2);
        networkReceivers[0] = IBurnerRouter.NetworkReceiver({network: network1, receiver: receiver1});
        networkReceivers[1] = IBurnerRouter.NetworkReceiver({network: network2, receiver: receiver2});
        operatorNetworkReceivers[0] = IBurnerRouter.OperatorNetworkReceiver({network: network1, operator: operator1, receiver: receiver1});
        operatorNetworkReceivers[1] = IBurnerRouter.OperatorNetworkReceiver({network: network2, operator: operator2, receiver: receiver2}); 
        // Define the parameters for _createConfiguratorParams
        uint64 delegatorIndex = 1;
        uint64 slasherIndex = 0;
        // Define the parameters for _createVaultParams
        uint48 epochDuration = 21 days;
        bool isDepositLimit = true;
        uint256 depositLimit = 1000 ether;
        // Define the parameters for _createDelegatorParams
        address hookSetRoleHolder = address(symbioticVaultFactory);
        // Define the parameters for _createSlasherParams
        bool isBurnerHook = true;
        uint48 vetoDuration = 2 days;
        uint256 resolverSetEpochsDelay = 21 days;
        // Define the parameters for _createStakerRewardsParams
        uint256 adminFee = 100;

        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams = _createBurnerRouterParams(delay, globalReceiver, networkReceivers, operatorNetworkReceivers);
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams = _createConfiguratorParams(delegatorIndex, slasherIndex);
        ISymbioticVaultFactory.VaultParams memory vaultParams = _createVaultParams(epochDuration, isDepositLimit, depositLimit);
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams = _createDelegatorParams(hook, hookSetRoleHolder);
        ISymbioticVaultFactory.SlasherParams memory slasherParams = _createSlasherParams(isBurnerHook, vetoDuration, resolverSetEpochsDelay);
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams = _createStakerRewardsParams(adminFee);

        // Call the createAdvancedVault function
        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) = symbioticVaultFactory.createVault(
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            stakerRewardsParams,
            false // isStandardVault
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

        // Verify if depositLimit is set to 1000 ether, meaning that an advanced vault is created
        uint256 limit = IVault(vault).depositLimit();
        assertEq(limit, 1000 ether); 
    }


    function test_createStandardizedVault() public {
        // Define the parameters for _createBurnerRouterParams
        uint48 delay = 21 days;
        address globalReceiver = 0x0000000000000000000000000000000000000000;
        IBurnerRouter.NetworkReceiver[] memory networkReceivers = new IBurnerRouter.NetworkReceiver[](2);
        IBurnerRouter.OperatorNetworkReceiver[] memory operatorNetworkReceivers = new IBurnerRouter.OperatorNetworkReceiver[](2);
        networkReceivers[0] = IBurnerRouter.NetworkReceiver({network: network1, receiver: receiver1});
        networkReceivers[1] = IBurnerRouter.NetworkReceiver({network: network2, receiver: receiver2});
        operatorNetworkReceivers[0] = IBurnerRouter.OperatorNetworkReceiver({network: network1, operator: operator1, receiver: receiver1});
        operatorNetworkReceivers[1] = IBurnerRouter.OperatorNetworkReceiver({network: network2, operator: operator2, receiver: receiver2}); 
        // Define the parameters for _createConfiguratorParams
        uint64 delegatorIndex = 1; // FullRestakeDelegator but NetworkRestakeDelegator is preset for standard vaults
        uint64 slasherIndex = 0; // instant slasher but veto slasher is preset for standard vaults
        // Define the parameters for _createVaultParams
        uint48 epochDuration = 21 days;
        bool isDepositLimit = true; // false is preset for standard vaults
        uint256 depositLimit = 1000 ether; // 0 is preset for standard vaults
        // Define the parameters for _createDelegatorParams
        address hookSetRoleHolder = address(symbioticVaultFactory);
        // Define the parameters for _createSlasherParams
        bool isBurnerHook = true;
        uint48 vetoDuration = 2 days;
        uint256 resolverSetEpochsDelay = 21 days;
        // Define the parameters for _createStakerRewardsParams
        uint256 adminFee = 100;

        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams = _createBurnerRouterParams(delay, globalReceiver, networkReceivers, operatorNetworkReceivers);
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams = _createConfiguratorParams(delegatorIndex, slasherIndex);
        ISymbioticVaultFactory.VaultParams memory vaultParams = _createVaultParams(epochDuration, isDepositLimit, depositLimit);
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams = _createDelegatorParams(hook, hookSetRoleHolder);
        ISymbioticVaultFactory.SlasherParams memory slasherParams = _createSlasherParams(isBurnerHook, vetoDuration, resolverSetEpochsDelay);
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams = _createStakerRewardsParams(adminFee);

        // Call the createAdvancedVault function
        (address vault, address delegator, address slasher, , , ) = symbioticVaultFactory.createVault(
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            stakerRewardsParams,
            true // isStandardVault
        );

        // Verify if isDepositLimit is set to false and depositLimit is set to 0, meaning that a standardized vault is created
        bool isLimit = IVault(vault).isDepositLimit();
        assertEq(isLimit, false);
        uint256 limit = IVault(vault).depositLimit();
        assertEq(limit, 0);

        // Verify if operatorNetworkSharesSetRoleHolders is set to byzFiNativeSymbioticVault
        bytes32 role = INetworkRestakeDelegator(delegator).OPERATOR_NETWORK_SHARES_SET_ROLE();
        assertNotEq(role, 0);

        // Verify if vetoDuration is set to 2 days
        uint48 duration = IVetoSlasher(slasher).vetoDuration();
        assertEq(duration, 2 days);
    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _createBurnerRouterParams(
        uint48 _delay,
        address _globalReceiver,
        IBurnerRouter.NetworkReceiver[] memory _networkReceivers,
        IBurnerRouter.OperatorNetworkReceiver[] memory _operatorNetworkReceivers
    ) private pure returns (ISymbioticVaultFactory.BurnerRouterParams memory) {
        ISymbioticVaultFactory.BurnerRouterParams memory params = ISymbioticVaultFactory.BurnerRouterParams({
            delay: _delay,
            globalReceiver: _globalReceiver,
            networkReceivers: _networkReceivers, 
            operatorNetworkReceivers: _operatorNetworkReceivers 
        });

        return params;
    }

    function _createConfiguratorParams(uint64 _delegatorIndex, uint64 _slasherIndex) private pure returns (ISymbioticVaultFactory.VaultConfiguratorParams memory) {
        return ISymbioticVaultFactory.VaultConfiguratorParams({
            delegatorIndex: _delegatorIndex,
            slasherIndex: _slasherIndex
        });
    }

    function _createVaultParams(uint48 _epochDuration, bool _isDepositLimit, uint256 _depositLimit) private pure returns (ISymbioticVaultFactory.VaultParams memory) {
        return ISymbioticVaultFactory.VaultParams({
            epochDuration: _epochDuration,
            isDepositLimit: _isDepositLimit,
            depositLimit: _depositLimit
        });
    }

    function _createDelegatorParams(address _hook, address _hookSetRoleHolder) private pure returns (ISymbioticVaultFactory.DelegatorParams memory) {
        return ISymbioticVaultFactory.DelegatorParams({
            hook: _hook,
            hookSetRoleHolder: _hookSetRoleHolder
        });
    }

    function _createSlasherParams(bool _isBurnerHook, uint48 _vetoDuration, uint256 _resolverSetEpochsDelay) private pure returns (ISymbioticVaultFactory.SlasherParams memory) {
        return ISymbioticVaultFactory.SlasherParams({
            isBurnerHook: _isBurnerHook,
            vetoDuration: _vetoDuration,
            resolverSetEpochsDelay: _resolverSetEpochsDelay
        });
    }

    function _createStakerRewardsParams(uint256 adminFee) private pure returns (ISymbioticVaultFactory.StakerRewardsParams memory) {
        return ISymbioticVaultFactory.StakerRewardsParams({
            adminFee: adminFee
        });
    }
}
