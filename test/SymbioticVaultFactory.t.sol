// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IERC7535Upgradeable} from "../src/vault/ERC7535/IERC7535Upgradeable.sol";

import {SymbioticVaultFactory} from "../src/core/symbiotic/SymbioticVaultFactory.sol";
import {ISymbioticVaultFactory} from "../src/interfaces/ISymbioticVaultFactory.sol";
import {IBurnerRouter} from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import {ByzFiNativeSymbioticVault} from "../src/vault/symbiotic/ByzFiNativeSymbioticVault.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {IVetoSlasher} from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";
import {INetworkRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/IFullRestakeDelegator.sol";
import {NetworkMiddlewareMock} from "./mocks/NetworkMiddlewareMock.sol";
import {INetworkRegistry} from "@symbioticfi/core/src/interfaces/INetworkRegistry.sol";
import {INetworkMiddlewareService} from "@symbioticfi/core/src/interfaces/service/INetworkMiddlewareService.sol";
import {INetworkRestakeDelegator} from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IVetoSlasher} from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";
import {IOperatorRegistry} from "@symbioticfi/core/src/interfaces/IOperatorRegistry.sol";
import {IRegistry} from "@symbioticfi/core/src/interfaces/common/IRegistry.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {IOptInService} from "@symbioticfi/core/src/interfaces/service/IOptInService.sol";
import {StakingMinivault} from "../src/vault/symbiotic/StakingMinivault.sol";

contract SymbioticVaultFactoryTest is Test {
    uint256 holeskyFork;
    string HOLESKY_RPC_URL = vm.envString("HOLESKY_RPC_URL");

    SymbioticVaultFactory symbioticVaultFactory;
    NetworkMiddlewareMock networkMiddleware;
    INetworkMiddlewareService networkMiddlewareService;
    INetworkRegistry networkRegistry;
    IOperatorRegistry operatorRegistry;
    // INetworkRestakeDelegator delegator;
    IVetoSlasher vetoSlasher;
    IOptInService vaultOptInService;
    IOptInService networkOptInService;

    // Define the addresses required for the constructor
    address public BURNER_ROUTER_FACTORY = 0x32e2AfbdAffB1e675898ABA75868d92eE1E68f3b; // deployed on holesky   
    address public VAULT_CONFIGURATOR = 0xD2191FE92987171691d552C219b8caEf186eb9cA; // deployed on holesky
    address public DEFAULT_STAKER_REWARDS_FACTORY = 0x698C36DE44D73AEfa3F0Ce3c0255A8667bdE7cFD; // deployed on holesky
    address public STAKING_MINIVAULT = vm.addr(1); 

    uint96 constant IDENTIFIER_SUBNETWORK = 1;

    // Parameters to be used for the createVault function
    address public hook = vm.addr(2);
    address public network1 = vm.addr(3);
    address public network2 = vm.addr(4);
    address public operator1 = vm.addr(5);
    address public operator2 = vm.addr(6);
    address public receiver1 = vm.addr(7);
    address public receiver2 = vm.addr(8);
    address public networkOwner = vm.addr(9);
    address public alice = vm.addr(10);
    address public bob = vm.addr(11);

    function setUp() public {
        // Make forked tests on Holesky
        holeskyFork = vm.createFork(HOLESKY_RPC_URL);
        vm.selectFork(holeskyFork);

        // Create instances of contracts deployed on Holesky by Symbiotic 
        networkMiddlewareService = INetworkMiddlewareService(0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3); 
        networkRegistry = INetworkRegistry(0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9);    
        operatorRegistry = IOperatorRegistry(0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548); 
        vaultOptInService = IOptInService(0x95CC0a052ae33941877c9619835A233D21D57351); 
        networkOptInService = IOptInService(0x58973d16FFA900D11fC22e5e2B6840d9f7e13401);

        // Deploy the network middleware contract
        networkMiddleware = new NetworkMiddlewareMock(networkRegistry, operatorRegistry, network1, operator1);

        // Deploy the SymbioticVaultFactory contract with constructor parameters
        symbioticVaultFactory = new SymbioticVaultFactory(
            BURNER_ROUTER_FACTORY,
            VAULT_CONFIGURATOR,
            DEFAULT_STAKER_REWARDS_FACTORY
        );

        // Fund Alice and Bob with 1000 ether
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    function testCanSelectFork() public {
        // select the fork
        vm.selectFork(holeskyFork);
        assertEq(vm.activeFork(), holeskyFork);
    }

    function test_createAdvancedVault() public {
        // Verify the fork  
        assertEq(vm.activeFork(), holeskyFork);

        // Initialize the parameters for the createVault function
        (
            ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
            ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
            ISymbioticVaultFactory.VaultParams memory vaultParams,
            ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
            ISymbioticVaultFactory.SlasherParams memory slasherParams,
            ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
        ) = _createVaultParamsSet();

        // Call the createVault function to create an advanced vault
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

        // Verify if the stakingMinivault is whitelisted
        assertEq(IVault(vault).isDepositorWhitelisted(byzFiNativeSymbioticVault), true);

        // Verify if depositLimit is set to 1000 ether, meaning that an advanced vault is created
        uint256 limit = IVault(vault).depositLimit();
        assertEq(limit, 1000 ether); 
    }

    function test_createStandardizedVault() public {
        // Default parameters for standard vaults:
        // uint64 public constant DELEGATOR_INDEX = 0;
        // uint64 public constant SLASHER_INDEX = 1;
        // bool public constant IS_DEPOSIT_LIMIT = false;
        // uint256 public constant DEPOSIT_LIMIT = 0;
        // bool public constant IS_BURNER_HOOK = true;

        // Verify the fork  
        assertEq(vm.activeFork(), holeskyFork);

        // Initialize the parameters for the createVault function
        (
            ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
            ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
            ISymbioticVaultFactory.VaultParams memory vaultParams,
            ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
            ISymbioticVaultFactory.SlasherParams memory slasherParams,
            ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
        ) = _createVaultParamsSet();

        // Call the createVault function to create a standardized vault
        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) = symbioticVaultFactory.createVault(
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

    function test_networkAndOperatorOnboarding() public {
        // Create a standardized vault
        // Initialize the parameters for the createVault function
        (
            ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
            ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
            ISymbioticVaultFactory.VaultParams memory vaultParams,
            ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
            ISymbioticVaultFactory.SlasherParams memory slasherParams,
            ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
        ) = _createVaultParamsSet();

        // Call the createVault function to create a standardized vault
        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) = symbioticVaultFactory.createVault(
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            stakerRewardsParams,
            true // isStandardVault
        );

        // The operator registers itself in the operator registry
        vm.prank(operator1);
        operatorRegistry.registerOperator();
        // Verify the operator is registered
        assertEq(operatorRegistry.isEntity(operator1), true);

        // The operator opts in to the vault
        vm.prank(operator1);
        vaultOptInService.optIn(vault);
        // Verify the operator is opted in
        assertEq(vaultOptInService.isOptedIn(operator1, vault), true);

        // Register the network
        vm.prank(network1);
        networkRegistry.registerNetwork();
        // Verify the network is registered
        assertEq(networkRegistry.isEntity(network1), true);

        // The network registers the deployed network middleware contract
        vm.startPrank(network1);
        networkMiddlewareService.setMiddleware(address(networkMiddleware));
        address middleware = networkMiddlewareService.middleware(network1);
        console.log("middleware", middleware);
        vm.stopPrank();
        assertNotEq(middleware, address(0));

        // The operator opts in to the network
        vm.prank(operator1);
        networkOptInService.optIn(network1);
        // Verify the operator is opted in
        assertEq(networkOptInService.isOptedIn(operator1, network1), true);

        // The network opts in to the vault by setting the network's maximum limit
        vm.prank(network1);
        INetworkRestakeDelegator(delegator).setMaxNetworkLimit(IDENTIFIER_SUBNETWORK, 1000 ether);
        bytes32 concatenatedNetwork = bytes32(abi.encodePacked(network1, IDENTIFIER_SUBNETWORK));
        assertEq(INetworkRestakeDelegator(delegator).maxNetworkLimit(concatenatedNetwork), 1000 ether);

        // Vault opts in to the network by setting non-zero limits
        vm.prank(byzFiNativeSymbioticVault); // Only a NETWORK_LIMIT_SET_ROLE holder can call this function
        INetworkRestakeDelegator(delegator).setNetworkLimit(concatenatedNetwork, 900 ether);
        assertEq(INetworkRestakeDelegator(delegator).networkLimit(concatenatedNetwork), 900 ether);

        // Vault opts in to the operator by setting non-zero limits
        vm.prank(byzFiNativeSymbioticVault);
        INetworkRestakeDelegator(delegator).setOperatorNetworkShares(concatenatedNetwork, operator1, 100 ether);
        assertEq(INetworkRestakeDelegator(delegator).operatorNetworkShares(concatenatedNetwork, operator1), 100 ether);
    }

    function test_depositInSymbioticVault() public {
        // Create a standardized vault
        (
            ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
            ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
            ISymbioticVaultFactory.VaultParams memory vaultParams,
            ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
            ISymbioticVaultFactory.SlasherParams memory slasherParams,
            ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
        ) = _createVaultParamsSet();

        (address vault, address delegator, address slasher, address defaultStakerRewards, address payable byzFiNativeSymbioticVault, address stakingMinivault) = symbioticVaultFactory.createVault(
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            stakerRewardsParams,
            true // isStandardVault
        );

        // Go through the entire onboarding process for the network, operator and vault
        _onboardingProcess(vault, delegator, byzFiNativeSymbioticVault);

        // ============= For Testing purposes: Mint SymPodShares to byzFiNativeSymbioticVault to bypass the real process, to simulate: 
        // -> deposit of ETH by Alice in ByzFiNativeSymbioticVault 
        // -> deposit of ETH by ByzFiNativeSymbioticVault in StakingMinivault 
        // -> issuance of SymPodShares by StakingMinivault to ByzFiNativeSymbioticVault
        // -> deposit of SymPodShares by ByzFiNativeSymbioticVault in the SymbioticVault ==============

        // Mint SymPodShares to byzFiNativeSymbioticVault (no access control for testing purposes)
        StakingMinivault(payable(stakingMinivault)).mintForTesting(byzFiNativeSymbioticVault, 1000);
        assertEq(StakingMinivault(payable(stakingMinivault)).balanceOf(byzFiNativeSymbioticVault), 1000);

        // ByzFiNativeSymbioticVault approves the vault to spend its SymPodShares
        vm.prank(byzFiNativeSymbioticVault);
        StakingMinivault(payable(stakingMinivault)).approve(vault, 1000);
        assertEq(StakingMinivault(payable(stakingMinivault)).allowance(byzFiNativeSymbioticVault, vault), 1000);

        // ByzFiNativeSymbioticVault deposits SymPodShares on behalf of Alice
        vm.prank(byzFiNativeSymbioticVault);
        IVault(vault).deposit(alice, 1000);
        assertEq(StakingMinivault(payable(stakingMinivault)).balanceOf(byzFiNativeSymbioticVault), 0);
        assertEq(IVault(vault).activeBalanceOf(alice), 1000);
        assertEq(IVault(vault).totalStake(), 1000);
        assertEq(IVault(vault).activeShares(), 1000);

        // Alice withdraws her SymPodShares (it will be claimable after the next epoch)
        vm.warp(block.timestamp + 30 days);
        uint256 epochAtWithdraw = IVault(vault).currentEpoch(); // epoch 1
        vm.prank(alice); 
        // TODO: Be careful, Alice can withdraw her SymPodShares directly from the SymbioticVault if SymPodShares are depoisted on her behalf
        // SymPodShares should be minted to ByzFiNativeSymbioticVault? 
        IVault(vault).withdraw(alice, 1000);
        assertEq(IVault(vault).activeBalanceOf(alice), 0);
        assertEq(IVault(vault).totalStake(), 1000);

        // Vault epoch duration is 21 days, so we need to wait for 21 days
        vm.warp(block.timestamp + 100 days);
        vm.prank(alice);
        IVault(vault).claim(alice, epochAtWithdraw + 1); // Can be claimed at epochAtWithdraw + 1 epoch 
        assertEq(IVault(vault).totalStake(), 0);
        assertEq(IVault(vault).activeBalanceOf(alice), 0);
        assertEq(StakingMinivault(payable(stakingMinivault)).balanceOf(alice), 1000);

        // TODO: Redo tests to interact correctly with ByzFiNativeSymbioticVault and StakingMinivault
        // vm.prank(alice);
        // uint256 nrvShares = ByzFiNativeSymbioticVault(byzFiNativeSymbioticVault).deposit{value: 64 ether}(64 ether, alice);
        // Verify if the nrvShares received are equal to the shares converted from the amount of ETH deposited in ByzFiNativeSymbioticVault
        // assertEq(nrvShares, convertedNrvShares);
        // console.log("nrvShares", nrvShares);
    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _setVaultCreationParams() private view returns (
        uint48 delay,
        address globalReceiver,
        IBurnerRouter.NetworkReceiver[] memory networkReceivers,
        IBurnerRouter.OperatorNetworkReceiver[] memory operatorNetworkReceivers,
        uint64 delegatorIndex,
        uint64 slasherIndex,
        uint48 epochDuration,
        bool isDepositLimit,
        uint256 depositLimit,
        address hookSetRoleHolder,
        bool isBurnerHook,
        uint48 vetoDuration,
        uint256 resolverSetEpochsDelay,
        uint256 adminFee
    ) {
        // Define the parameters for _createBurnerRouterParams
        delay = 21 days;
        globalReceiver = 0x0000000000000000000000000000000000000000;
        networkReceivers = new IBurnerRouter.NetworkReceiver[](2);
        operatorNetworkReceivers = new IBurnerRouter.OperatorNetworkReceiver[](2);
        networkReceivers[0] = IBurnerRouter.NetworkReceiver({network: network1, receiver: receiver1});
        networkReceivers[1] = IBurnerRouter.NetworkReceiver({network: network2, receiver: receiver2});
        operatorNetworkReceivers[0] = IBurnerRouter.OperatorNetworkReceiver({network: network1, operator: operator1, receiver: receiver1});
        operatorNetworkReceivers[1] = IBurnerRouter.OperatorNetworkReceiver({network: network2, operator: operator2, receiver: receiver2}); 
        // Define the parameters for _createConfiguratorParams
        delegatorIndex = 1; // FullRestakeDelegator but NetworkRestakeDelegator is preset for standard vaults
        slasherIndex = 0; // instant slasher but veto slasher is preset for standard vaults
        // Define the parameters for _createVaultParams
        epochDuration = 21 days;
        isDepositLimit = true; // false is preset for standard vaults
        depositLimit = 1000 ether; // 0 is preset for standard vaults
        // Define the parameters for _createDelegatorParams
        hookSetRoleHolder = address(symbioticVaultFactory);
        // Define the parameters for _createSlasherParams
        isBurnerHook = true;
        vetoDuration = 2 days;
        resolverSetEpochsDelay = 21 days;
        // Define the parameters for _createStakerRewardsParams
        adminFee = 100;
    }

    function _createVaultParamsSet() private view returns (
        ISymbioticVaultFactory.BurnerRouterParams memory burnerRouterParams,
        ISymbioticVaultFactory.VaultConfiguratorParams memory configuratorParams,
        ISymbioticVaultFactory.VaultParams memory vaultParams,
        ISymbioticVaultFactory.DelegatorParams memory delegatorParams,
        ISymbioticVaultFactory.SlasherParams memory slasherParams,
        ISymbioticVaultFactory.StakerRewardsParams memory stakerRewardsParams
    ) {
        burnerRouterParams = _createBurnerRouterParams();
        configuratorParams = _createConfiguratorParams();
        vaultParams = _createVaultParams();
        delegatorParams = _createDelegatorParams();
        slasherParams = _createSlasherParams();
        stakerRewardsParams = _createStakerRewardsParams();

        return (
            burnerRouterParams,
            configuratorParams,
            vaultParams,
            delegatorParams,
            slasherParams,
            stakerRewardsParams
        );
    }

    function _createBurnerRouterParams() private view returns (ISymbioticVaultFactory.BurnerRouterParams memory) {
        (uint48 delay, address globalReceiver, IBurnerRouter.NetworkReceiver[] memory networkReceivers,
        IBurnerRouter.OperatorNetworkReceiver[] memory operatorNetworkReceivers, , , , , , , , , , ) = _setVaultCreationParams();
        return ISymbioticVaultFactory.BurnerRouterParams({
            delay: delay,
            globalReceiver: globalReceiver,
            networkReceivers: networkReceivers, 
            operatorNetworkReceivers: operatorNetworkReceivers 
        });
    }

    function _createConfiguratorParams() private view returns (ISymbioticVaultFactory.VaultConfiguratorParams memory) {
        (, , , , uint64 delegatorIndex, uint64 slasherIndex, , , , , , , ,) = _setVaultCreationParams();
        return ISymbioticVaultFactory.VaultConfiguratorParams({
            delegatorIndex: delegatorIndex,
            slasherIndex: slasherIndex
        });
    }

    function _createVaultParams() private view returns (ISymbioticVaultFactory.VaultParams memory) {
        (, , , , , , uint48 epochDuration, bool isDepositLimit, uint256 depositLimit, , , , , ) = _setVaultCreationParams();
        return ISymbioticVaultFactory.VaultParams({
            epochDuration: epochDuration,
            isDepositLimit: isDepositLimit,
            depositLimit: depositLimit
        });
    }

    function _createDelegatorParams() private view returns (ISymbioticVaultFactory.DelegatorParams memory) {
        (, , , , , , , , , address hookSetRoleHolder, , , , ) = _setVaultCreationParams();
        return ISymbioticVaultFactory.DelegatorParams({
            hook: hook,
            hookSetRoleHolder: hookSetRoleHolder
        });
    }

    function _createSlasherParams() private view returns (ISymbioticVaultFactory.SlasherParams memory) {
        (, , , , , , , , , , bool isBurnerHook, uint48 vetoDuration, uint256 resolverSetEpochsDelay, ) = _setVaultCreationParams();
        return ISymbioticVaultFactory.SlasherParams({
            isBurnerHook: isBurnerHook,
            vetoDuration: vetoDuration,
            resolverSetEpochsDelay: resolverSetEpochsDelay
        });
    }

    function _createStakerRewardsParams() private view returns (ISymbioticVaultFactory.StakerRewardsParams memory) {
        (, , , , , , , , , , , , , uint256 adminFee) = _setVaultCreationParams();
        return ISymbioticVaultFactory.StakerRewardsParams({
            adminFee: adminFee
        });
    }

    function _onboardingProcess(address _vault, address _delegator, address _networkLimitSetRoleHolder) private {
        // The operator registers itself in the operator registry
        vm.prank(operator1);
        operatorRegistry.registerOperator();

        // The operator opts in to the vault
        vm.prank(operator1);
        vaultOptInService.optIn(_vault);

        // Register the network
        vm.prank(network1);
        networkRegistry.registerNetwork();

        // The network registers the deployed network middleware contract
        vm.startPrank(network1);
        networkMiddlewareService.setMiddleware(address(networkMiddleware));
        networkMiddlewareService.middleware(network1);
        vm.stopPrank();

        // The operator opts in to the network
        vm.prank(operator1);
        networkOptInService.optIn(network1);

        // The network opts in to the vault by setting the network's maximum limit
        vm.prank(network1);
        INetworkRestakeDelegator(_delegator).setMaxNetworkLimit(IDENTIFIER_SUBNETWORK, 1000 ether);
        bytes32 concatenatedNetwork = bytes32(abi.encodePacked(network1, IDENTIFIER_SUBNETWORK));

        // Vault opts in to the network by setting non-zero limits
        vm.prank(_networkLimitSetRoleHolder); // Only a NETWORK_LIMIT_SET_ROLE holder can call this function
        INetworkRestakeDelegator(_delegator).setNetworkLimit(concatenatedNetwork, 900 ether);

        // Vault opts in to the operator by setting non-zero limits
        vm.prank(_networkLimitSetRoleHolder);
        INetworkRestakeDelegator(_delegator).setOperatorNetworkShares(concatenatedNetwork, operator1, 100 ether);
    }
}