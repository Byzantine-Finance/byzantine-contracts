// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./eigenlayer-helper/EigenLayerDeployer.t.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import "./utils/ProofParsing.sol";

import "../src/core/StrategyModuleManager.sol";
import "../src/core/StrategyModule.sol";

import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";

contract StrategyModuleManagerTest is ProofParsing, EigenLayerDeployer {
    using BeaconChainProofs for *;

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
        address stratModAddrAlice1 = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.numStratMods(), 1);
        assertEq(StrategyModule(stratModAddrAlice1).stratModOwner(), alice);

        // Bob creates a StrategyModule
        vm.prank(bob);
        address stratModAddrBob = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.numStratMods(), 2);

        address stratModOwnerBob = StrategyModule(stratModAddrBob).stratModOwner();
        assertEq(stratModOwnerBob, bob);

        // Alice creates a second StrategyModule
        vm.prank(alice);
        address stratModAddrAlice2 = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.numStratMods(), 3);
        assertEq(StrategyModule(stratModAddrAlice2).stratModOwner(), alice);

        // Get Alice StrategyModules
        IStrategyModule[] memory aliceStratMods = strategyModuleManager.getStratMods(alice);
        assertEq(aliceStratMods.length, 2);
        assertEq(address(aliceStratMods[0]), stratModAddrAlice1);
        assertEq(address(aliceStratMods[1]), stratModAddrAlice2);
        
        // Get Bob StrategyModules
        IStrategyModule[] memory bobStratMods = strategyModuleManager.getStratMods(bob);
        assertEq(bobStratMods.length, 1);
        assertEq(address(bobStratMods[0]), stratModAddrBob);
    }

    function test_RevertWhen_createPodForNonValidStratModIndex() public {
        // Alice creates a StrategyModule
        vm.startPrank(alice);
        strategyModuleManager.createStratMod();
        // Alice creates an EigenPod for a non valid index
        uint256 nonValidIndex = 1;
        vm.expectRevert(abi.encodeWithSignature("InvalidStratModIndex(uint256)", nonValidIndex));
        strategyModuleManager.createPod(nonValidIndex);
        vm.stopPrank();

        // Bob creates two StrategyModules
        vm.startPrank(bob);
        strategyModuleManager.createStratMod();
        strategyModuleManager.createStratMod();
        // Bob creates an EigenPod for a non valid index
        nonValidIndex = 10;
        vm.expectRevert(abi.encodeWithSignature("InvalidStratModIndex(uint256)", nonValidIndex));
        strategyModuleManager.createPod(nonValidIndex);
        vm.stopPrank();
    }

    function test_CreatePods() public {
        vm.startPrank(bob);
        // Bob creates two StrategyModules
        address stratMod1 = strategyModuleManager.createStratMod();
        address stratMod2 = strategyModuleManager.createStratMod();

        // Bob creates an EigenPod in its both StrategyModules
        address stratMod1Pod = strategyModuleManager.createPod(0);
        assertEq(stratMod1Pod, address(strategyModuleManager.getPod(stratMod1)));
        address stratMod2Pod = strategyModuleManager.createPod(1);
        assertEq(stratMod2Pod, address(strategyModuleManager.getPod(stratMod2)));

        vm.stopPrank();
    }

    function test_RevertWhen_CreateTwoPodsForSameStratMod() public {
        vm.startPrank(bob);
        address stratMod1 = strategyModuleManager.createStratMod();
        strategyModuleManager.createPod(0);
        vm.expectRevert(abi.encodeWithSignature("CallFailed(bytes)", abi.encodeWithSignature("createPod()")));
        strategyModuleManager.createPod(0);
    }

    function test_HasPod() public {
        vm.startPrank(bob);
        address stratMod1 = strategyModuleManager.createStratMod();
        assertEq(strategyModuleManager.hasPod(bob, 0), false);
        strategyModuleManager.createPod(0);
        assertEq(strategyModuleManager.hasPod(bob, 0), true);
    }

    function test_RevertWhen_notStratModOwnerCreatesPod() public {
        // Alice creates a StrategyModule
        vm.prank(alice);
        address stratModAddrAlice = strategyModuleManager.createStratMod();

        // The contract try to create a pod for Alice's StrategyModule
        vm.expectRevert(abi.encodeWithSignature("DoNotHaveStratMod(address)", address(this)));
        strategyModuleManager.createPod(10);
    }

    function testCreateStratModAndPrecalculatePodAddress() public {
        vm.startPrank(alice);
        // Alice create a StrategyModule
        address stratMod = strategyModuleManager.createStratMod();
        // Pre-calculate alice's EigenPod address
        IEigenPod expectedEigenPod = strategyModuleManager.getPod(stratMod);
        // Alice deploys an EigenPod
        address eigenPod = strategyModuleManager.createPod(0);
        assertEq(eigenPod, address(expectedEigenPod));
        vm.stopPrank();
    }

    function testNativeStacking() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Alice create StrategyModule and stake 32 ETH
        vm.deal(alice, 40 ether);
        vm.startPrank(alice);
        strategyModuleManager.createStratMod();
        strategyModuleManager.stakeNativeETH{value: 32 ether}(0, pubkey, signature, depositDataRoot);

        assertEq(alice.balance, 8 ether);
        vm.stopPrank();
    }

    function testFail_Not32ETHDeposited() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Alice create StrategyModule and stake 31 ETH
        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.createStratMod();
        strategyModuleManager.stakeNativeETH{value: 31 ether}(0, pubkey, signature, depositDataRoot);

    }

    // That test reverts because the `withdrawal_credential_proof` file generated with the Byzantine API
    // doesn't point to the correct EigenPod (alice's EigenPod which is locally deployed)
    function test_RevertWhen_WrongWithdrawalCredentials() public {

        // Read required data from example files

        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Get the validator fields proof
        (
            BeaconChainProofs.StateRootProof memory stateRootProofStruct,
            uint40[] memory validatorIndices,
            bytes[] memory proofsArray,
            bytes32[][] memory validatorFieldsArray
        ) = 
            _getValidatorFieldsProof(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

        // Start the test

        uint64 timestamp = 0;
        vm.warp(timestamp);

        vm.deal(alice, 40 ether);
        vm.startPrank(alice);

        // Create a pod and stake ETH
        strategyModuleManager.createStratMod();
        strategyModuleManager.createPod(0);
        strategyModuleManager.stakeNativeETH{value: 32 ether}(0, pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        IStrategyModule stratMod = strategyModuleManager.getStratModByIndex(alice, 0);
        cheats.expectRevert(
            bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod")
        );
        stratMod.verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

        vm.stopPrank();

    }

    // TODO: Test the `VerifyWithdrawalCredential` function when the proof is correct

    // This test revert because we are trying to update the balance of a Pod whose validator
    // hasn't been activated by calling `verifyWithdrawalCredentials`
    function test_RevertWhen_UpdatePodBalanceForInactiveValidator() public {

        // Read required data from example files

        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Get the validator fields proof
        (
            BeaconChainProofs.StateRootProof memory stateRootProofStruct,
            uint40[] memory validatorIndices,
            bytes[] memory proofsArray,
            bytes32[][] memory validatorFieldsArray
        ) = 
            _getValidatorFieldsProof(abi.encodePacked("./test/test-data/balance_update_proof_1634654.json"));


        // Start the test

        uint64 timestamp = 0;
        vm.warp(timestamp);

        vm.deal(alice, 40 ether);
        vm.startPrank(alice);

        // Create a pod and stake ETH
        strategyModuleManager.createStratMod();
        strategyModuleManager.createPod(0);
        strategyModuleManager.stakeNativeETH{value: 32 ether}(0, pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        IStrategyModule stratMod = strategyModuleManager.getStratModByIndex(alice, 0);
        cheats.expectRevert(
            bytes("EigenPod.verifyBalanceUpdate: Validator not active")
        );
        stratMod.verifyBalanceUpdates(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

        vm.stopPrank();

    }

    // TODO: Test the `verifyBalanceUpdates` function when the proof is correct 
    //       and the validator is ACTIVE (has called `verifyWithdrawalCredentials` function)


    //--------------------------------------------------------------------------------------
    //------------------------------  INTERNAL FUNCTIONS  ----------------------------------
    //--------------------------------------------------------------------------------------

    function _getDepositData(
        bytes memory depositFilePath
    ) internal returns (
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) {
        // File generated with the Obol LaunchPad
        setJSON(string(depositFilePath));

        pubkey = getDVPubKey();
        signature = getDVSignature();
        depositDataRoot = getDVDepositDataRoot();
        //console.logBytes(pubkey);
        //console.logBytes(signature);
        //console.logBytes32(depositDataRoot);
    }

    function _getValidatorFieldsProof(
        bytes memory proofFilePath
    ) internal returns (
        BeaconChainProofs.StateRootProof memory,
        uint40[] memory,
        bytes[] memory,
        bytes32[][] memory
    ) {
        // File generated with the Byzantine API
        setJSON(string(proofFilePath));

        BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

        uint40[] memory validatorIndices = new uint40[](1);
        validatorIndices[0] = uint40(getValidatorIndex());

        bytes32[][] memory validatorFieldsArray = new bytes32[][](1);
        validatorFieldsArray[0] = getValidatorFields();

        bytes[] memory proofsArray = new bytes[](1);
        proofsArray[0] = abi.encodePacked(getWithdrawalCredentialProof());

        return (stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);
    }

    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }

    function _setOracleBlockRoot() internal {
        bytes32 latestBlockRoot = getLatestBlockRoot();
        //set beaconStateRoot
        beaconChainOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);
    }

}