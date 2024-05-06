// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./eigenlayer-helper/EigenLayerDeployer.t.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import "./utils/ProofParsing.sol";

import "../src/core/StrategyModuleManager.sol";
import "../src/core/StrategyModule.sol";
import "../src/tokens/ByzNft.sol";

import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";

contract StrategyModuleManagerTest is ProofParsing, EigenLayerDeployer {
    using BeaconChainProofs for *;

    StrategyModuleManager public strategyModuleManager;

    /// @notice Canonical, virtual beacon chain ETH strategy
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    address alice = address(0x123456789);
    address bob = address(0x1011121314);
    address ELOperator1 = address(0x1516171819);

    function setUp() public override {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();

        // deploy StrategyModuleManager
        strategyModuleManager = new StrategyModuleManager(
            eigenPodManager,
            delegation
        );
        
    }

    function testStratModManagerOwner() public view {
        assertEq(strategyModuleManager.owner(), address(this));
    }

    function testByzNftContractOwner() public view {
        ByzNft byzNftContract = ByzNft(address(strategyModuleManager.byzNft()));
        assertEq(byzNftContract.owner(), address(strategyModuleManager));
    }

    function testCreateStratMods() public {

        // Alice creates a StrategyModule
        address stratModAddrAlice1 = _createStratMod(alice);
        uint256 nft1 = IStrategyModule(stratModAddrAlice1).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 1);
        assertEq(StrategyModule(stratModAddrAlice1).stratModOwner(), alice);
        assertEq(strategyModuleManager.getStratModByNftId(nft1), stratModAddrAlice1);

        // Bob creates a StrategyModule
        address stratModAddrBob = _createStratMod(bob);
        uint256 nft2 = IStrategyModule(stratModAddrBob).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 2);
        assertEq(strategyModuleManager.getStratModByNftId(nft2), stratModAddrBob);

        address stratModOwnerBob = StrategyModule(stratModAddrBob).stratModOwner();
        assertEq(stratModOwnerBob, bob);

        // Alice creates a second StrategyModule
        address stratModAddrAlice2 = _createStratMod(alice);
        uint256 nft3 = IStrategyModule(stratModAddrAlice2).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 3);
        assertEq(StrategyModule(stratModAddrAlice2).stratModOwner(), alice);
        assertEq(strategyModuleManager.getStratModByNftId(nft3), stratModAddrAlice2);

        // Get Alice StrategyModules
        address[] memory aliceStratMods = strategyModuleManager.getStratMods(alice);
        assertEq(aliceStratMods.length, 2);
        assertEq(aliceStratMods[0], stratModAddrAlice1);
        assertEq(aliceStratMods[1], stratModAddrAlice2);
        
        // Get Bob StrategyModules
        address[] memory bobStratMods = strategyModuleManager.getStratMods(bob);
        assertEq(bobStratMods.length, 1);
        assertEq(bobStratMods[0], stratModAddrBob);

    }

    function testStratModNftId() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);
        uint256 expectedNftId = uint256(keccak256(abi.encodePacked(alice, strategyModuleManager.numStratMods())));

        assertEq(expectedNftId, IStrategyModule(stratModAddrAlice).stratModNftId());
    }

    function testStratModTransfer() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);

        vm.startPrank(alice);
        
        // Alice approves the StrategyModule to transfer to Bob
        ByzNft byzNftContract = ByzNft(address(strategyModuleManager.byzNft()));
        byzNftContract.approve(address(strategyModuleManager), IStrategyModule(stratModAddrAlice).stratModNftId());

        // Alice transfers the StrategyModule to Bob
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, bob);

        // Verify if Bob is the new owner
        assertEq(bob, IStrategyModule(stratModAddrAlice).stratModOwner());

        vm.stopPrank();

        // Verify if the mappings has been correctly updated
        address[] memory aliceStratMods = strategyModuleManager.getStratMods(alice);
        assertEq(aliceStratMods.length, 0);
        assertEq(aliceStratMods, new address[](0));
        address[] memory bobStratMods = strategyModuleManager.getStratMods(bob);
        assertEq(bobStratMods.length, 1);
        assertEq(bobStratMods[0], stratModAddrAlice);
    }

    function test_RevertWhen_NonStratModOwnerTransfersStratMod() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);
        
        vm.startPrank(alice);

        // Alice approves the StrategyModule to transfer to Bob
        ByzNft byzNftContract = ByzNft(address(strategyModuleManager.byzNft()));
        byzNftContract.approve(address(strategyModuleManager), IStrategyModule(stratModAddrAlice).stratModNftId());

        vm.stopPrank();

        // This smart contract transfers the StrategyModule to Bob
        vm.expectRevert(IStrategyModuleManager.NotStratModOwner.selector);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, bob);
    }

    function test_RevertWhen_notStratModOwnercreatesPod() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);

        // Bob try to create an EigenPod for Alice's StrategyModule
        vm.expectRevert(IStrategyModule.OnlyNftOwner.selector);
        vm.prank(bob);
        IStrategyModule(stratModAddrAlice).createPod();
    }

    function test_CreatePods() public {
        // Bob creates two StrategyModules
        address stratModAddr1 = _createStratMod(bob);
        address stratModAddr2 = _createStratMod(bob);

        vm.startPrank(bob);
        // Bob creates an EigenPod in its both StrategyModules
        address stratMod1PodAddr = IStrategyModule(stratModAddr1).createPod();
        assertEq(stratMod1PodAddr, strategyModuleManager.getPodByStratModAddr(stratModAddr1));
        address stratMod2PodAddr = IStrategyModule(stratModAddr2).createPod();
        assertEq(stratMod2PodAddr, strategyModuleManager.getPodByStratModAddr(stratModAddr2));

        vm.stopPrank();
    }

    function test_RevertWhen_CreateTwoPodsForSameStratMod() public {
        // Bob creates a StrategyModule
        address stratModAddr = _createStratMod(bob);

        vm.startPrank(bob);
        // Bob creates an EigenPod in its StrategyModule
        IStrategyModule(stratModAddr).createPod();
        // Bob tries to create another EigenPod
        vm.expectRevert(bytes("EigenPodManager.createPod: Sender already has a pod"));
        IStrategyModule(stratModAddr).createPod();

        vm.stopPrank();
    }

    function test_HasPod() public {
        address stratModAddr = _createStratMod(bob);
        assertEq(strategyModuleManager.hasPod(stratModAddr), false);
        vm.prank(bob);
        IStrategyModule(stratModAddr).createPod();
        assertEq(strategyModuleManager.hasPod(stratModAddr), true);
    }

    function testCreateStratModAndPrecalculatePodAddress() public {
        // Alice create a StrategyModule
        address stratModAddr = _createStratMod(alice);

        // Pre-calculate alice's EigenPod address
        address expectedEigenPod = strategyModuleManager.getPodByStratModAddr(stratModAddr);

        vm.prank(alice);
        // Alice deploys an EigenPod
        address eigenPod = IStrategyModule(stratModAddr).createPod();

        assertEq(eigenPod, expectedEigenPod);
        vm.stopPrank();
    }

    /*function testPrecalculatePodAddress() public {
        // Alice already has a StrategyModule
        _createStratMod(alice);
        // And we want to know the Pod address of its second one without having to create it
        address computedPod = strategyModuleManager.computePodAddr(alice);

        address secondStratModAddr = _createStratMod(alice);
        address realPod = strategyModuleManager.getPodByStratModAddr(secondStratModAddr);
        assertEq(strategyModuleManager.getStratModNumber(alice), 2);
        assertEq(realPod, computedPod);

        // Bob want to know the Pod address of its first StrategyModule without having to create it
        address computedBobPod = strategyModuleManager.computePodAddr(bob);
        address firstStratModAddr = _createStratMod(bob);
        address realBobPod = strategyModuleManager.getPodByStratModAddr(firstStratModAddr);
        assertEq(realBobPod, computedBobPod);

    }*/

    function testNativeStacking() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Alice create StrategyModule and stake 32 ETH
        vm.deal(alice, 40 ether);
        address stratMod = _createStratMod(alice);
        vm.prank(alice);
        IStrategyModule(stratMod).stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        assertEq(alice.balance, 8 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_Not32ETHDeposited() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Alice create StrategyModule and stake 31 ETH
        vm.deal(alice, 40 ether);
        address stratMod = _createStratMod(alice);
        vm.prank(alice);
        vm.expectRevert(bytes("EigenPod.stake: must initially stake for any validator with 32 ether"));
        IStrategyModule(stratMod).stakeNativeETH{value: 31 ether}(pubkey, signature, depositDataRoot);
        vm.stopPrank();
    }

    function test_directlyStakeNativeETH() public {
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));

        // Alice stakes 32 ETH on Byzantine. The function creates StrategyModule for her
        vm.deal(alice, 40 ether);
        vm.prank(alice);
        strategyModuleManager.createStratModAndStakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        assertEq(alice.balance, 8 ether);
        assertEq(strategyModuleManager.numStratMods(), 1);

        // Verify StrategyModule ownership
        address stratModAddr = strategyModuleManager.getStratMods(alice)[0];
        assertEq(IStrategyModule(stratModAddr).stratModOwner(), alice);
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
        address stratMod = strategyModuleManager.createStratMod();
        IStrategyModule(stratMod).createPod();
        IStrategyModule(stratMod).stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        cheats.expectRevert(
            bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod")
        );
        IStrategyModule(stratMod).verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

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
        address stratMod = strategyModuleManager.createStratMod();
        IStrategyModule(stratMod).createPod();
        IStrategyModule(stratMod).stakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot();

        // Verify the proof
        cheats.expectRevert(
            bytes("EigenPod.verifyBalanceUpdate: Validator not active")
        );
        IStrategyModule(stratMod).verifyBalanceUpdates(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

        vm.stopPrank();

    }

    // TODO: Test the `verifyBalanceUpdates` function when the proof is correct 
    //       and the validator is ACTIVE (has called `verifyWithdrawalCredentials` function)

    // The operator shares for the beacon chain strategy hasn't been updated because alice didn't verify the withdrawal credentials
    // of its validator (DV)
    function testDelegateTo() public {

        // Create the operator details for the operator to delegate to
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: ELOperator1,
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        _registerAsOperator(ELOperator1, operatorDetails);

        // Create a restaking strategy: only beacon chain ETH Strategy
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        // Get the operator shares before delegation
        uint256[] memory operatorSharesBefore = delegation.getOperatorShares(ELOperator1, strategies);
        assertEq(operatorSharesBefore[0], 0);
        
        // Alice stake 32 ETH
        vm.deal(alice, 40 ether);
        vm.startPrank(alice);
        // Get the validator deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/alice-eigenPod-deposit-data.json"));
        address stratModAddr = strategyModuleManager.createStratModAndStakeNativeETH{value: 32 ether}(pubkey, signature, depositDataRoot);
        // Alice delegate its staked ETH to the ELOperator1
        IStrategyModule(stratModAddr).delegateTo(ELOperator1);
        vm.stopPrank();

        // Verify if alice's strategy module is registered as a delegator
        bool[] memory stratModsDelegated = strategyModuleManager.isDelegated(alice);
        assertTrue(stratModsDelegated[0], "testDelegateTo: Alice's Strategy Module  didn't delegate to ELOperator1 correctly");
        // Verify if Alice delegated to the correct operator
        address[] memory stratModsDelegateTo = strategyModuleManager.delegateTo(alice);
        assertEq(stratModsDelegateTo[0], ELOperator1);

        // Operator shares didn't increase because alice didn't verify its withdrawal credentials -> podOwnerShares[stratModAddr] = 0
        uint256[] memory operatorSharesAfter = delegation.getOperatorShares(ELOperator1, strategies);
        //console.log("operatorSharesAfter", operatorSharesAfter[0]);
        //assertEq(operatorSharesBefore[0], 0);

    }

    // TODO: Verify the operator shares increase correctly when staker has verified correctly its withdrawal credentials
    // TODO: Delegate to differents operators by creating new strategy modules -> necessary to not put the 32ETH in the same DV

    //--------------------------------------------------------------------------------------
    //------------------------------  INTERNAL FUNCTIONS  ----------------------------------
    //--------------------------------------------------------------------------------------


    function _createStratMod(address _stratModCreator) internal returns (address) {
        vm.prank(_stratModCreator);
        return strategyModuleManager.createStratMod();
    }

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

    function _registerAsOperator(
        address operator,
        IDelegationManager.OperatorDetails memory operatorDetails
    ) internal {
        string memory emptyStringForMetadataURI;

        vm.startPrank(operator);
        delegation.registerAsOperator(operatorDetails, emptyStringForMetadataURI);
        vm.stopPrank();

        assertTrue(delegation.isOperator(operator), "_registerAsOperator: failed to resgister `operator` as an EL operator");
        assertTrue(
            keccak256(abi.encode(delegation.operatorDetails(operator))) == keccak256(abi.encode(operatorDetails)),
            "_registerAsOperator: operatorDetails not set appropriately"
        );
        assertTrue(delegation.isDelegated(operator), "_registerAsOperator: operator doesn't delegate itself");
    }

}