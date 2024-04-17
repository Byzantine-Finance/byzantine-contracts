// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./eigenlayer-helper/EigenLayerDeployer.t.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "./utils/ProofParsing.sol";

import "../src/core/StrategyModuleManager.sol";
import "../src/core/StrategyModule.sol";

import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";

contract StrategyModuleManagerTest is ProofParsing, EigenLayerDeployer {

    StrategyModuleManager public strategyModuleManager;

    address alice = address(0x123456789);
    address bob = address(0x1011121314);

    function setUp() public override {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();

        // deploy StrategyModuleManager
        strategyModuleManager = new StrategyModuleManager(
            eigenPodManager
        );
        
    }

    function testStratModManagerOwner() public view {
        assertEq(strategyModuleManager.owner(), address(this));
    }

    function testCreateStratMods() public {

        // Alice creates a StrategyModule
        vm.prank(alice);
        address stratModAddrAlice = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.numStratMods(), 1);

        address stratModOwnerAlice = StrategyModule(stratModAddrAlice).stratModOwner();
        assertEq(stratModOwnerAlice, alice);

        // Bob creates a StrategyModule
        vm.prank(bob);
        address stratModAddrBob = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.numStratMods(), 2);

        address stratModOwnerBob = StrategyModule(stratModAddrBob).stratModOwner();
        assertEq(stratModOwnerBob, bob);
    }

    function test_RevertWhen_AlreadyHasStratMod() public {
        vm.startPrank(address(0x123));
        // Create a first StrategyModule
        strategyModuleManager.createStratMod();
        vm.expectRevert(IStrategyModuleManager.AlreadyHasStrategyModule.selector);
        // Create a second StrategyModule
        strategyModuleManager.createStratMod();
        vm.stopPrank();
    }

    function testPreCalculationStratModAddr() public {
        vm.startPrank(alice);
        // Pre-calculate alice's StrategyModule address
        IStrategyModule stratMod = strategyModuleManager.getStratMod(alice);
        address exeptedStratModAddr = address(stratMod);
        // Alice deploys a StrategyModule
        address stratModAddr = strategyModuleManager.createStratMod();
        assertEq(stratModAddr, exeptedStratModAddr);
        vm.stopPrank();
    }

    function testCreatePodAndPrecalculateItsAddress() public {
        vm.startPrank(alice);
        // Pre-calculate alice's EigenPod address
        IEigenPod expectedEigenPod = strategyModuleManager.getPod(alice);
        // Alice deploys an EigenPod
        (address eigenPod,) = strategyModuleManager.createPod();
        assertEq(eigenPod, address(expectedEigenPod));
        vm.stopPrank();
    }

    // Verify is the action to directly create an EigenPod also creates a StrategyModule
    function testCreatePodDirectly() public {
        strategyModuleManager.createPod();
        assertEq(strategyModuleManager.numStratMods(), 1);
    }

    function testNativeStacking() public {
        // File generated with the Obol LaunchPad
        setJSON("./test/test-data/alice-eigenPod-deposit-data.json");

        bytes memory pubkey = getDVPubKey();
        bytes memory signature = getDVSignature();
        bytes32 depositDataRoot = getDVDepositDataRoot();
        //console.logBytes(pubkey);
        //console.logBytes(signature);
        //console.logBytes32(depositDataRoot);

        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        assertEq(alice.balance, 8 ether);
    }

    function testFail_Not32ETHDeposited() public {
        // File generated with the Obol LaunchPad
        setJSON("./test/test-data/alice-eigenPod-deposit-data.json");

        bytes memory pubkey = getDVPubKey();
        bytes memory signature = getDVSignature();
        bytes32 depositDataRoot = getDVDepositDataRoot();
        //console.logBytes(pubkey);
        //console.logBytes(signature);
        //console.logBytes32(depositDataRoot);

        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.stakeNativeETH{value: 31 ether}(pubkey, signature, depositDataRoot);

    }

}