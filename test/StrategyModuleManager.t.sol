// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import "./utils/ProofParsing.sol";

import "./ByzantineDeployer.t.sol";

import "../src/tokens/ByzNft.sol";
import "../src/core/Auction.sol";

import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";

contract StrategyModuleManagerTest is ProofParsing, ByzantineDeployer {
    using BeaconChainProofs for *;

    /// @notice Canonical, virtual beacon chain ETH strategy
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    address alice = address(0x123456789);
    address bob = address(0x1011121314);
    address ELOperator1 = address(0x1516171819);

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();
    }

    function testStratModManagerOwner() public view {
        assertEq(strategyModuleManager.owner(), address(this));
    }

    function testByzNftContractOwner() public view {
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.owner(), address(strategyModuleManager));
    }

    function testCreateStratMods() public {

        // First, verify if ALice and Bob have StrategyModules
        assertFalse(strategyModuleManager.hasStratMods(alice));
        assertFalse(strategyModuleManager.hasStratMods(bob));

        // Alice creates a StrategyModule
        address stratModAddrAlice1 = _createStratMod(alice);
        uint256 nft1 = IStrategyModule(stratModAddrAlice1).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 1);
        assertTrue(strategyModuleManager.hasStratMods(alice));
        assertEq(strategyModuleManager.getStratModNumber(alice), 1);
        assertEq(IStrategyModule(stratModAddrAlice1).stratModOwner(), alice);
        assertEq(strategyModuleManager.getStratModByNftId(nft1), stratModAddrAlice1);

        // Bob creates a StrategyModule
        address stratModAddrBob = _createStratMod(bob);
        uint256 nft2 = IStrategyModule(stratModAddrBob).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 2);
        assertTrue(strategyModuleManager.hasStratMods(bob));
        assertEq(strategyModuleManager.getStratModNumber(bob), 1);
        assertEq(IStrategyModule(stratModAddrBob).stratModOwner(), bob);
        assertEq(strategyModuleManager.getStratModByNftId(nft2), stratModAddrBob);

        // Alice creates a second StrategyModule
        address stratModAddrAlice2 = _createStratMod(alice);
        uint256 nft3 = IStrategyModule(stratModAddrAlice2).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 3);
        assertEq(strategyModuleManager.getStratModNumber(alice), 2);
        assertEq(IStrategyModule(stratModAddrAlice2).stratModOwner(), alice);
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

        // Alice approves the StrategyModuleManager to transfer to Bob
        _approveNftTransferByStratModManager(alice, IStrategyModule(stratModAddrAlice).stratModNftId());

        // Alice transfers the StrategyModule to Bob
        vm.prank(alice);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, bob);
        assertEq(strategyModuleManager.getStratModNumber(alice), 0);

        // Verify if Bob is the new owner
        assertEq(bob, IStrategyModule(stratModAddrAlice).stratModOwner());
        assertEq(strategyModuleManager.getStratModNumber(bob), 1);

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

        // Alice approves the StrategyModuleManager to transfer to Bob
        _approveNftTransferByStratModManager(alice, IStrategyModule(stratModAddrAlice).stratModNftId());

        // This smart contract transfers the StrategyModule to Bob
        vm.expectRevert(IStrategyModuleManager.NotStratModOwner.selector);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, bob);
    }

    function test_RevertWhen_TransferStratModToItself() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);

        // Alice approves the StrategyModule to transfer to herself
        _approveNftTransferByStratModManager(alice, IStrategyModule(stratModAddrAlice).stratModNftId());     

        vm.expectRevert(bytes("StrategyModuleManager.transferStratModOwnership: cannot transfer ownership to the same address"));
        vm.prank(alice);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, alice);
    }

    function test_RevertWhen_notStratModOwnerCreatesPod() public {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratMod(alice);

        // Bob try to create an EigenPod for Alice's StrategyModule
        vm.expectRevert(IStrategyModule.OnlyStrategyModuleOwnerOrManager.selector);
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
        assertFalse(strategyModuleManager.hasPod(stratModAddr));
        vm.prank(bob);
        IStrategyModule(stratModAddr).createPod();
        assertTrue(strategyModuleManager.hasPod(stratModAddr));
    }

    function testCreateStratModAndPrecalculatePodAddress() public {
        // Alice create a StrategyModule
        address stratModAddr = _createStratMod(alice);

        // Pre-calculate alice's EigenPod address
        address expectedEigenPod = strategyModuleManager.getPodByStratModAddr(stratModAddr);

        // Alice deploys an EigenPod
        vm.prank(alice);
        address eigenPod = IStrategyModule(stratModAddr).createPod();

        assertEq(eigenPod, expectedEigenPod);
        vm.stopPrank();
    }

    function test_callEigenPodManager() public {
        // Alice creates a StrategyModule
        address stratModAddr = _createStratMod(alice);
        // Alice creates an EigenPod
        vm.prank(alice);
        IStrategyModule(stratModAddr).createPod();

        // Alice wants to call EigenPodManager directly
        bytes memory functionToCall = abi.encodeWithSignature("ownerToPod(address)", stratModAddr);
        vm.prank(alice);
        bytes memory ret = IStrategyModule(stratModAddr).callEigenPodManager(functionToCall);
        IEigenPod pod = abi.decode(ret, (IEigenPod));

        assertEq(address(pod), strategyModuleManager.getPodByStratModAddr(stratModAddr));
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

    function testStakerDeposit32ETH() public {

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice create StrategyModule and stake 32 ETH in the contract
        (address stratModAddr, address podAddr) = _createStratModAndStakeNativeETH(alice, 32 ether);
        assertEq(alice.balance, 8 ether);
        assertEq(address(strategyModuleManager).balance, 0 ether);

        // Verify Alice Strategy Module Balance
        assertEq(stratModAddr.balance, 32 ether);

        // Verify the address of the EigenPod
        assertEq(strategyModuleManager.getPodByStratModAddr(stratModAddr), podAddr);

    }

    function test_RevertWhen_Not32ETHDeposited() public {

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice create StrategyModule and stake 31 ETH in the contract
        vm.expectRevert(bytes("StrategyModuleManager.createStratModAndStakeNativeETH: must initially stake for any validator with 32 ether"));
        _createStratModAndStakeNativeETH(alice, 31 ether);

    }

    function testStakerWithdrawStratModBalance() public {
        // First, verify alice has no ETH
        assertEq(alice.balance, 0 ether);

        // Alice creates a StrategyModule
        address stratModAddr = _createStratMod(alice);

        // Alice's Strategy Module get 64ETH
        vm.deal(stratModAddr, 64 ether);
        assertEq(stratModAddr.balance, 64 ether);

        // Alice withdraw the Strategy Module balance
        vm.prank(alice);
        IStrategyModule(stratModAddr).withdrawContractBalance();
        assertEq(alice.balance, 64 ether);
        assertEq(stratModAddr.balance, 0 ether);
    }

    function testSetTrustedDVPubKey() public {

        bytes memory pubkey = 
            _getTrustedPubKey(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));

        // Alice create StrategyModule and deposit 32 ETH in the contract
        address stratModAddr = _createStratMod(alice);

        // Verify nobody has initialized the trusted DV pubKey
        assertEq(IStrategyModule(stratModAddr).getTrustedDVPubKey().length, 0);

        // Bob, a hacker, try to set the DV pubKey of Alice's StrategyModule
        vm.prank(bob);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        strategyModuleManager.setTrustedDVPubKey(stratModAddr, pubkey);

        // Byzantine admin set the correct DV pubKey of Alice's StrategyModule
        strategyModuleManager.setTrustedDVPubKey(stratModAddr, pubkey);
        assertEq(IStrategyModule(stratModAddr).getTrustedDVPubKey(), pubkey);

    }

    function testClusterDetailsIntegrity() public {
        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice create StrategyModule and stake 32 ETH in the contract
        (address stratModAddr,) = _createStratModAndStakeNativeETH(alice, 32 ether);

        // An auction is triggered and fill the cluster details of StrategyModule
        _simulateAuction(stratModAddr);

        // Verify the cluster details of the StrategyModule
        address[] memory clusterDetailsNodesAddr = IStrategyModule(stratModAddr).getDVNodesAddr();
        address[4] memory selectedNodes = _getDVNodesAddr(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));
        assertEq(clusterDetailsNodesAddr.length, selectedNodes.length);
        for (uint i = 0; i < selectedNodes.length; i++) {
            assertEq(selectedNodes[i], clusterDetailsNodesAddr[i]);
        }
        assertEq(selectedNodes[0], IStrategyModule(stratModAddr).getClusterManager());

        // Verify the status of the DV
        IStrategyModule.DVStatus dvStatus = IStrategyModule(stratModAddr).getDVStatus();
        assertEq(uint(dvStatus), uint(IStrategyModule.DVStatus.WAITING_ACTIVATION));
    }

    function testBeaconChainDeposit() public {

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice create StrategyModule and stake 32 ETH in the contract
        (address stratModAddr,) = _createStratModAndStakeNativeETH(alice, 32 ether);

        // An auction is triggered and fill the cluster details of StrategyModule
        _simulateAuction(stratModAddr);

        // Get the DV deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
        // Get the trusted pubKey
        bytes memory trustedPubkey = 
            _getTrustedPubKey(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));
        // Get the cluster manager address
        address clusterManager = IStrategyModule(stratModAddr).getClusterManager();

        // The cluster manager deposits the 32ETH on the Beacon Chain before the trusted pubKey has been set
        vm.prank(clusterManager);
        vm.expectRevert(bytes("StrategyModule.beaconChainDeposit: Trusted pubkey not initialized"));
        IStrategyModule(stratModAddr).beaconChainDeposit(pubkey, signature, depositDataRoot);

        // Alice set the trusted pubKey of the DV
        vm.prank(alice);
        IStrategyModule(stratModAddr).setTrustedDVPubKey(trustedPubkey);

        // The cluster manager tries again to deposit the 32ETH on the Beacon Chain
        vm.prank(clusterManager);
        IStrategyModule(stratModAddr).beaconChainDeposit(pubkey, signature, depositDataRoot);

        // Verify the balance of the StrategyModule
        assertEq(stratModAddr.balance, 0 ether);

        // Verify the status of the DV
        IStrategyModule.DVStatus dvStatus = IStrategyModule(stratModAddr).getDVStatus();
        assertEq(uint(dvStatus), uint(IStrategyModule.DVStatus.DEPOSITED_NOT_VERIFIED));
    }

    function test_RevertWhen_NotValidPubKey() public {
        // Get the DV deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
        // We assume the trusted pubKey is this one
        bytes memory trustedPubkey = hex"a81a7517846c800845e31dc03dcd9e0cdca5bdf367116d90f5cc339b6b588ab7f824e36bd9b71749aae94341b86083aa";

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice creates a Strategy Module and stake ETH
        (address stratModAddr,) = _createStratModAndStakeNativeETH(alice, 32 ether);

        // An auction is triggered and fill the cluster details of StrategyModule
        _simulateAuction(stratModAddr);

        // Byzantine admin set the trusted DV pubKey
        strategyModuleManager.setTrustedDVPubKey(stratModAddr, trustedPubkey);

        // Cluster Manager deposits the 32ETH on the Beacon Chain
        vm.prank(IStrategyModule(stratModAddr).getClusterManager());
        vm.expectRevert(bytes("StrategyModule.beaconChainDeposit: Invalid DV pubkey"));
        IStrategyModule(stratModAddr).beaconChainDeposit(pubkey, signature, depositDataRoot);
    }

    // That test reverts because the `withdrawal_credential_proof` file generated with the Byzantine API
    // doesn't point to the correct EigenPod (alice's EigenPod which is locally deployed)
    function test_RevertWhen_WrongWithdrawalCredentials() public {

        // Read required data from example files

        // Get the DV deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
        // Get the trusted pubKey
        bytes memory trustedPubkey = 
            _getTrustedPubKey(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));
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

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice creates a Strategy Module and stake ETH
        (address stratModAddr,) = _createStratModAndStakeNativeETH(alice, 32 ether);

        // An auction is triggered and fill the cluster details of StrategyModule
        _simulateAuction(stratModAddr);

        // Byzantine admin set the trusted DV pubKey
        strategyModuleManager.setTrustedDVPubKey(stratModAddr, trustedPubkey);

        // Cluster Manager deposits the 32ETH on the Beacon Chain
        vm.prank(IStrategyModule(stratModAddr).getClusterManager());
        IStrategyModule(stratModAddr).beaconChainDeposit(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

        // Verify the proof
        vm.prank(alice);
        cheats.expectRevert(
            bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod")
        );
        IStrategyModule(stratModAddr).verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

    }

    // TODO: Test the `VerifyWithdrawalCredential` function when the proof is correct

    // This test revert because we are trying to update the balance of a Pod whose validator
    // hasn't been activated by calling `verifyWithdrawalCredentials`
    function test_RevertWhen_UpdatePodBalanceForInactiveValidator() public {

        // Read required data from example files

        // Get the DV deposit data
        (bytes memory pubkey, bytes memory signature, bytes32 depositDataRoot) = 
            _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
        // Get the trusted pubKey
        bytes memory trustedPubkey = 
            _getTrustedPubKey(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));
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

        // Alice get 40ETH
        vm.deal(alice, 40 ether);

        // Alice creates a Strategy Module and stake ETH
        (address stratModAddr,) = _createStratModAndStakeNativeETH(alice, 32 ether);

        // An auction is triggered and fill the cluster details of StrategyModule
        _simulateAuction(stratModAddr);

        // Byzantine admin set the trusted DV pubKey
        strategyModuleManager.setTrustedDVPubKey(stratModAddr, trustedPubkey);

        // Cluster Manager deposits the 32ETH on the Beacon Chain
        vm.prank(IStrategyModule(stratModAddr).getClusterManager());
        IStrategyModule(stratModAddr).beaconChainDeposit(pubkey, signature, depositDataRoot);

        // Deposit received on the Beacon Chain
        cheats.warp(timestamp += 16 hours);

        //set the oracle block root
        _setOracleBlockRoot(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

        // Verify the proof
        cheats.expectRevert(
            bytes("EigenPod.verifyBalanceUpdate: Validator not active")
        );
        IStrategyModule(stratModAddr).verifyBalanceUpdates(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

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

        (address stratModAddr,) = strategyModuleManager.createStratModAndStakeNativeETH{value: 32 ether}();
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

    function _createStratModAndStakeNativeETH(address _staker, uint256 _stake) internal returns (address, address) {
        vm.prank(_staker);
        return strategyModuleManager.createStratModAndStakeNativeETH{value: _stake}();
    }

    function _getByzNftContract() internal view returns (ByzNft) {
        return ByzNft(address(strategyModuleManager.byzNft()));
    }

    function _approveNftTransferByStratModManager(address approver, uint256 nftId) internal {
        ByzNft byzNftContract = _getByzNftContract();
        vm.prank(approver);
        byzNftContract.approve(address(strategyModuleManager), nftId);
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

        pubkey = getDVPubKeyDeposit();
        signature = getDVSignature();
        depositDataRoot = getDVDepositDataRoot();
        //console.logBytes(pubkey);
        //console.logBytes(signature);
        //console.logBytes32(depositDataRoot);
    }

    function _getTrustedPubKey(bytes memory lockFilePath) internal returns (bytes memory pubkey) {
        setJSON(string(lockFilePath));
        pubkey = getDVPubKeyLock();
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

    function _getDVNodesAddr(bytes memory lockFilePath) internal returns (address[4] memory) {
        setJSON(string(lockFilePath));
        return getDVNodesAddr();
    }

    function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    }

    function _setOracleBlockRoot(bytes memory proofFilePath) internal {
        setJSON(string(proofFilePath));
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

    function _simulateAuction(
        address stratModAddrNeedingDV
    ) internal {
        // Get the 4 winners of the auction (no auction takes place as it's a simulation)
        address[4] memory nodesAddr = _getDVNodesAddr(abi.encodePacked("./test/test-data/cluster-lock-DV0-noPod.json"));

        IStrategyModule.Node[] memory nodes = new IStrategyModule.Node[](4);
        for (uint256 i = 0; i < 4; i++) {
            nodes[i] = IStrategyModule.Node(
                365, // We assume all the nodes have 365 Validation Credits
                100, // We assume all the nodes have 100 reputation score
                nodesAddr[i]
            );
        }

        // Define nodesAddr[0] as the cluster manager
        address clusterManager = nodesAddr[0];

        // Bob try to update Alice's cluster details
        vm.prank(bob);
        vm.expectRevert(IStrategyModule.OnlyAuctionContract.selector);
        IStrategyModule(stratModAddrNeedingDV).updateClusterDetails(nodes, clusterManager);

        Auction auctionContract = Auction(address(strategyModuleManager.auction()));
        vm.prank(address(auctionContract));
        IStrategyModule(stratModAddrNeedingDV).updateClusterDetails(nodes, clusterManager);
    }

}