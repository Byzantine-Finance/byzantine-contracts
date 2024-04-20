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
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        assertEq(alice.balance, 8 ether);
    }

    function testFail_Not32ETHDeposited() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.stakeNativeETH{value: 31 ether}(pubkey, signature, depositDataRoot);

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
        strategyModuleManager.createPod();
        strategyModuleManager.stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        IStrategyModule stratMod = strategyModuleManager.ownerToStratMod(alice);
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
        strategyModuleManager.createPod();
        strategyModuleManager.stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        IStrategyModule stratMod = strategyModuleManager.ownerToStratMod(alice);
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