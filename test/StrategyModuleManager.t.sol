// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
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

    /// @notice Random validator deposit data to be able to call `createStratModAndStakeNativeETH` function
    bytes pubkey;
    bytes signature;
    bytes32 depositDataRoot;

    /// @notice Initial balance of all the node operators
    uint256 constant STARTING_BALANCE = 100 ether;

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Fill the node ops' balance
        for (uint i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        // Fill protagonists' balance
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // For the context of these tests, we assume 8 node operators has pending bids
        _8NodeOpsBid();

        // Get deposit data of a random validator
        _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
    }

    function testStratModManagerOwner() public view {
        assertEq(strategyModuleManager.owner(), address(this));
    }

    function testByzNftContractOwner() public view {
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.owner(), address(strategyModuleManager));
    }

    function testPreCreateDVs() public {
        // Alice would like to create a StrategyModule but no pending clusters
        vm.expectRevert(bytes("StrategyModuleManager.createStratModAndStakeNativeETH: no pending DVs"));
        _createStratModAndStakeNativeETH(alice, 32 ether);

        // Alice tries to pre-create 2 DVs but she is not allowed
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        strategyModuleManager.preCreateDVs(2);

        // Byzantine pre-create the first 2 DVs
        strategyModuleManager.preCreateDVs(2);

        // Verify number of pre-created DVs
        assertEq(strategyModuleManager.numPreCreatedClusters(), 2);
        assertEq(strategyModuleManager.getNumPendingClusters(), 2);

        // Verify the nodes details of the pre-created DVs
        IStrategyModule.Node[4] memory nodesDV1 = strategyModuleManager.getPendingClusterNodeDetails(0);
        IStrategyModule.Node[4] memory nodesDV2 = strategyModuleManager.getPendingClusterNodeDetails(1);
        // Verify the nodes details of the pre-created DV1
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV1[i].eth1Addr, nodeOps[i]);
        }
        assertEq(nodesDV1[0].vcNumber, 999);
        assertEq(nodesDV1[1].vcNumber, 900);
        assertEq(nodesDV1[2].vcNumber, 800);
        assertEq(nodesDV1[3].vcNumber, 700);
        // Verify the nodes details of the pre-created DV1
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV2[i].eth1Addr, nodeOps[i + 4]);
        }
        assertEq(nodesDV2[0].vcNumber, 600);
        assertEq(nodesDV2[1].vcNumber, 500);
        assertEq(nodesDV2[2].vcNumber, 400);
        assertEq(nodesDV2[3].vcNumber, 300);

        // Alice creates a StrategyModule and activates the first DV
        _createStratModAndStakeNativeETH(alice, 32 ether);
        assertEq(alice.balance, STARTING_BALANCE - 32 ether);

        // Verify the first pending DV has been deleted from the pending container
        nodesDV1 = strategyModuleManager.getPendingClusterNodeDetails(0);
        // Verify the nodes details of the pre-created DV1 has been deleted
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV1[i].eth1Addr, address(0));
        }
        assertEq(nodesDV1[0].vcNumber, 0);
        assertEq(nodesDV1[1].vcNumber, 0);
        assertEq(nodesDV1[2].vcNumber, 0);
        assertEq(nodesDV1[3].vcNumber, 0);

        // Verify number of pending DVs
        assertEq(strategyModuleManager.numPreCreatedClusters(), 2);
        assertEq(strategyModuleManager.getNumPendingClusters(), 1);
    }

    function testCreateStratMods() public preCreateClusters(2) {

        // Node ops bids again
        _8NodeOpsBid();

        // First, verify if Alice and Bob have StrategyModules
        assertFalse(strategyModuleManager.hasStratMods(alice));
        assertFalse(strategyModuleManager.hasStratMods(bob));

        // Alice creates a StrategyModule
        address aliceStratModAddr1 = _createStratModAndStakeNativeETH(alice, 32 ether);
        uint256 nft1 = IStrategyModule(aliceStratModAddr1).stratModNftId();
        assertTrue(strategyModuleManager.hasStratMods(alice));
        assertEq(strategyModuleManager.numStratMods(), 1);
        assertEq(strategyModuleManager.getStratModNumber(alice), 1);
        assertEq(IStrategyModule(aliceStratModAddr1).stratModOwner(), alice);
        assertEq(strategyModuleManager.getStratModByNftId(nft1), aliceStratModAddr1);

        // Verify alice strat mod 1 DV details
        IStrategyModule.Node[4] memory nodesDV1Alice = IStrategyModule(aliceStratModAddr1).getDVNodesDetails();
        IStrategyModule.DVStatus dvStatusDV1Alice = IStrategyModule(aliceStratModAddr1).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV1Alice[i].eth1Addr, nodeOps[i]);
        }
        assertEq(nodesDV1Alice[0].vcNumber, 999);
        assertEq(nodesDV1Alice[1].vcNumber, 900);
        assertEq(nodesDV1Alice[2].vcNumber, 800);
        assertEq(nodesDV1Alice[3].vcNumber, 700);
        // Verify the DV status
        assertEq(uint(dvStatusDV1Alice), uint(IStrategyModule.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyModuleManager.numPreCreatedClusters(), 3);
        assertEq(strategyModuleManager.getNumPendingClusters(), 2);

        // Bob creates a StrategyModule
        address bobStratModAddr1 = _createStratModAndStakeNativeETH(bob, 32 ether);
        uint256 nft2 = IStrategyModule(bobStratModAddr1).stratModNftId();
        assertTrue(strategyModuleManager.hasStratMods(bob));
        assertEq(strategyModuleManager.numStratMods(), 2);
        assertEq(strategyModuleManager.getStratModNumber(bob), 1);
        assertEq(IStrategyModule(bobStratModAddr1).stratModOwner(), bob);
        assertEq(strategyModuleManager.getStratModByNftId(nft2), bobStratModAddr1);

        // Verify bob strat mod 1 DV details
        IStrategyModule.Node[4] memory nodesDV1Bob = IStrategyModule(bobStratModAddr1).getDVNodesDetails();
        IStrategyModule.DVStatus dvStatusDV1Bob = IStrategyModule(bobStratModAddr1).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
           assertEq(nodesDV1Bob[i].eth1Addr, nodeOps[i + 4]);
        }
        assertEq(nodesDV1Bob[0].vcNumber, 600);
        assertEq(nodesDV1Bob[1].vcNumber, 500);
        assertEq(nodesDV1Bob[2].vcNumber, 400);
        assertEq(nodesDV1Bob[3].vcNumber, 300);
        // Verify the DV status
        assertEq(uint(dvStatusDV1Bob), uint(IStrategyModule.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyModuleManager.numPreCreatedClusters(), 4);
        assertEq(strategyModuleManager.getNumPendingClusters(), 2);

        // Alice creates a second StrategyModule
        address aliceStratModAddr2 = _createStratModAndStakeNativeETH(alice, 32 ether);
        uint256 nft3 = IStrategyModule(aliceStratModAddr2).stratModNftId();
        assertEq(strategyModuleManager.numStratMods(), 3);
        assertEq(strategyModuleManager.getStratModNumber(alice), 2);
        assertEq(IStrategyModule(aliceStratModAddr2).stratModOwner(), alice);
        assertEq(strategyModuleManager.getStratModByNftId(nft3), aliceStratModAddr2);

        // Verify alice strat mod 2 DV details
        IStrategyModule.Node[4] memory nodesDV2Alice = IStrategyModule(aliceStratModAddr2).getDVNodesDetails();
        IStrategyModule.DVStatus dvStatusDV2Alice = IStrategyModule(aliceStratModAddr2).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV2Alice[i].eth1Addr, nodeOps[i]);
        }
        assertEq(nodesDV2Alice[0].vcNumber, 999);
        assertEq(nodesDV2Alice[1].vcNumber, 900);
        assertEq(nodesDV2Alice[2].vcNumber, 800);
        assertEq(nodesDV2Alice[3].vcNumber, 700);
        // Verify the DV status
        assertEq(uint(dvStatusDV2Alice), uint(IStrategyModule.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyModuleManager.numPreCreatedClusters(), 4);
        assertEq(strategyModuleManager.getNumPendingClusters(), 1);

    }

    function testpreCalculatePodAddress() public preCreateClusters(2) {
        // Pre-calculate pod address of DV1, DV2 and DV3
        address podAddressDV1 = strategyModuleManager.preCalculatePodAddress(0);
        address podAddressDV2 = strategyModuleManager.preCalculatePodAddress(1);
        address podAddressDV3 = strategyModuleManager.preCalculatePodAddress(2);

        // Node ops bids again
        _8NodeOpsBid();

        // Alice creates two StrategyModules
        address aliceStratModAddr1 = _createStratModAndStakeNativeETH(alice, 32 ether);
        address aliceStratModAddr2 = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Bob creates a StrategyModule
        address bobStratModAddr1 = _createStratModAndStakeNativeETH(bob, 32 ether);

        // Verify pod addresses of DV1, DV2 and DV3
        assertEq(strategyModuleManager.getPodByStratModAddr(aliceStratModAddr1), podAddressDV1);
        assertEq(strategyModuleManager.getPodByStratModAddr(aliceStratModAddr2), podAddressDV2);
        assertEq(strategyModuleManager.getPodByStratModAddr(bobStratModAddr1), podAddressDV3);
    }

    // Within foundry, resulting address of a contract deployed with CREATE2 differs according to the msg.sender.
    // Why??
    function testFrontRunStratModDeployment() public preCreateClusters(2) {
        // Bob a hacker, front run the deployment of the first StrategyModule
        vm.startPrank(bob);
        uint256 firstNftId = uint256(keccak256(abi.encode(0)));
        address stratModAddr = Create2.deploy(
            0,
            bytes32(firstNftId),
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(strategyModuleBeacon, ""))
        );
        // Bob wants to initialize the StrategyModule but can't because he doesn't own the nft
        vm.expectRevert(bytes("Cannot initialize StrategyModule: ERC721: invalid token ID"));
        IStrategyModule(stratModAddr).initialize(firstNftId, bob);
        vm.stopPrank();
    }

    function testStratModTransfer() public preCreateClusters(2) {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratModAndStakeNativeETH(alice, 32 ether);
        uint256 nftId = IStrategyModule(stratModAddrAlice).stratModNftId();

        // Verify Alice owns the nft
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.ownerOf(nftId), alice);

        // Alice tries to transfer the StrategyModule by call the ERC721 `safeTransferFrom` function
        // It's forbidden because the nft owner will change but the mapping `stakerToStratMods` won't be updated
        vm.startPrank(alice);
        vm.expectRevert(bytes("ByzNft._transfer: Token transfer can only be initiated by the StrategyModuleManager, call StrategyModuleManager.transferStratModOwnership"));
        byzNftContract.safeTransferFrom(alice, bob, nftId);
        vm.stopPrank();

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

    function test_RevertWhen_NonStratModOwnerTransfersStratMod() public preCreateClusters(2) {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Alice approves the StrategyModuleManager to transfer to Bob
        _approveNftTransferByStratModManager(alice, IStrategyModule(stratModAddrAlice).stratModNftId());

        // This smart contract transfers the StrategyModule to Bob
        vm.expectRevert(IStrategyModuleManager.NotStratModOwner.selector);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, bob);
    }

    function test_RevertWhen_TransferStratModToItself() public preCreateClusters(2) {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Alice approves the StrategyModule to transfer to herself
        _approveNftTransferByStratModManager(alice, IStrategyModule(stratModAddrAlice).stratModNftId());     

        vm.expectRevert(bytes("StrategyModuleManager.transferStratModOwnership: cannot transfer ownership to the same address"));
        vm.prank(alice);
        strategyModuleManager.transferStratModOwnership(stratModAddrAlice, alice);
    }

    function test_HasPod() public preCreateClusters(2) {
        // Alice creates a StrategyModule
        address stratModAddrAlice = _createStratModAndStakeNativeETH(alice, 32 ether);
        assertTrue(strategyModuleManager.hasPod(stratModAddrAlice));
    }

    function test_callEigenPodManager() public preCreateClusters(2) {
        // Alice creates a StrategyModule
        address stratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Alice wants to call EigenPodManager directly
        bytes memory functionToCall = abi.encodeWithSignature("ownerToPod(address)", stratModAddr);
        vm.prank(alice);
        bytes memory ret = IStrategyModule(stratModAddr).callEigenPodManager(functionToCall);
        IEigenPod pod = abi.decode(ret, (IEigenPod));

        assertEq(address(pod), strategyModuleManager.getPodByStratModAddr(stratModAddr));
    }

    function test_RevertWhen_Not32ETHDeposited() public preCreateClusters(2) {

        // Alice create StrategyModule and stake 31 ETH in the contract
        vm.expectRevert(bytes("StrategyModuleManager.createStratModAndStakeNativeETH: must initially stake for any validator with 32 ether"));
        _createStratModAndStakeNativeETH(alice, 31 ether);

    }

    function testStakerWithdrawStratModBalance() public preCreateClusters(2) {

        // Alice creates a StrategyModule
        address stratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Alice's Strategy Module get 64ETH
        vm.deal(stratModAddr, 64 ether);
        assertEq(stratModAddr.balance, 64 ether);

        // Alice withdraw the Strategy Module balance
        vm.prank(alice);
        IStrategyModule(stratModAddr).withdrawContractBalance();
        assertEq(alice.balance, STARTING_BALANCE - 32 ether + 64 ether);
        assertEq(stratModAddr.balance, 0 ether);
    }

    // That test reverts because the `withdrawal_credential_proof` file generated with the Byzantine API
    // doesn't point to the correct EigenPod (alice's EigenPod which is locally deployed)
    function test_RevertWhen_WrongWithdrawalCredentials() public preCreateClusters(2) {
        // Get the validator fields proof
        (
            BeaconChainProofs.StateRootProof memory stateRootProofStruct,
            uint40[] memory validatorIndices,
            bytes[] memory proofsArray,
            bytes32[][] memory validatorFieldsArray
        ) = 
            _getValidatorFieldsProof(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

        // Start the test

        // Alice creates a Strategy Module and stake ETH
        address stratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);

        // Deposit received on the Beacon Chain
        uint64 timestamp = uint64(block.timestamp + 16 hours);
        cheats.warp(timestamp);

        //set the oracle block root
        _setOracleBlockRoot(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

        // Verify the proof
        vm.prank(alice);
        cheats.expectRevert(
            bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod")
        );
        /// TODO: Update API to to have the exact timestamp where the proof was generated
        IStrategyModule(stratModAddr).verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

    }

    // TODO: Test the `VerifyWithdrawalCredential` function when the proof is correct

    // The operator shares for the beacon chain strategy hasn't been updated because alice didn't verify the withdrawal credentials
    // of its validator (DV)
    function testDelegateTo() public preCreateClusters(2) {

        // Create the operator details for the operator to delegate to
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: ELOperator1,
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        _registerAsELOperator(ELOperator1, operatorDetails);

        // Create a restaking strategy: only beacon chain ETH Strategy
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        // Get the operator shares before delegation
        uint256[] memory operatorSharesBefore = delegation.getOperatorShares(ELOperator1, strategies);
        assertEq(operatorSharesBefore[0], 0);
        
        // Alice stake 32 ETH
        address stratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);
        // Alice delegate its staked ETH to the ELOperator1
        vm.prank(alice);
        IStrategyModule(stratModAddr).delegateTo(ELOperator1);

        // Verify if alice's strategy module is registered as a delegator
        bool[] memory stratModsDelegated = strategyModuleManager.isDelegated(alice);
        assertTrue(stratModsDelegated[0], "testDelegateTo: Alice's Strategy Module  didn't delegate to ELOperator1 correctly");
        // Verify if Alice delegated to the correct operator
        address[] memory stratModsDelegateTo = strategyModuleManager.hasDelegatedTo(alice);
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

    function _createStratModAndStakeNativeETH(address _staker, uint256 _stake) internal returns (address) {
        vm.prank(_staker);
        strategyModuleManager.createStratModAndStakeNativeETH{value: _stake}(pubkey, signature, depositDataRoot);
        uint256 stratModNumber = strategyModuleManager.getStratModNumber(_staker);
        if (stratModNumber == 0) {
            return address(0);
        }
        return strategyModuleManager.getStratMods(_staker)[stratModNumber - 1];
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
    ) internal {
        // File generated with the Obol LaunchPad
        setJSON(string(depositFilePath));

        pubkey = getDVPubKeyDeposit();
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

    function _registerAsELOperator(
        address operator,
        IDelegationManager.OperatorDetails memory operatorDetails
    ) internal {
        string memory emptyStringForMetadataURI;

        vm.startPrank(operator);
        delegation.registerAsOperator(operatorDetails, emptyStringForMetadataURI);
        vm.stopPrank();

        assertTrue(delegation.isOperator(operator), "_registerAsELOperator: failed to resgister `operator` as an EL operator");
        assertTrue(
            keccak256(abi.encode(delegation.operatorDetails(operator))) == keccak256(abi.encode(operatorDetails)),
            "_registerAsELOperator: operatorDetails not set appropriately"
        );
        assertTrue(delegation.isDelegated(operator), "_registerAsELOperator: operator doesn't delegate itself");
    }

    function _createOneBidParamArray(
        uint256 _discountRate,
        uint256 _timeInDays
    ) internal pure returns (uint256[] memory, uint256[] memory) {
        uint256[] memory discountRateArray = new uint256[](1);
        discountRateArray[0] = _discountRate;

        uint256[] memory timeInDaysArray = new uint256[](1);
        timeInDaysArray[0] = _timeInDays;
        
        return (discountRateArray, timeInDaysArray);
    }

    function _nodeOpBid(
        NodeOpBid memory nodeOpBid
    ) internal returns (uint256[] memory) {
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(nodeOpBid.nodeOp, nodeOpBid.discountRates, nodeOpBid.timesInDays);
        vm.prank(nodeOpBid.nodeOp);
        return auction.bid{value: priceToPay}(nodeOpBid.discountRates, nodeOpBid.timesInDays);
    }

    function _nodeOpsBid(
        NodeOpBid[] memory nodeOpsBids
    ) internal returns (uint256[][] memory) {
        uint256[][] memory nodeOpsAuctionScores = new uint256[][](nodeOpsBids.length);
        for (uint i = 0; i < nodeOpsBids.length; i++) {
            nodeOpsAuctionScores[i] = _nodeOpBid(nodeOpsBids[i]);
        }
        return nodeOpsAuctionScores;
    }

    function _8NodeOpsBid() internal {
        (uint256[] memory DR0, uint256[] memory time0) = _createOneBidParamArray(13e2, 999);  // 1st
        (, uint256[] memory time1) = _createOneBidParamArray(13e2, 900);  // 2nd
        (, uint256[] memory time2) = _createOneBidParamArray(13e2, 800);  // 3rd
        (, uint256[] memory time3) = _createOneBidParamArray(13e2, 700);  // 4th
        (, uint256[] memory time4) = _createOneBidParamArray(13e2, 600);  // 5th
        (, uint256[] memory time5) = _createOneBidParamArray(13e2, 500);  // 6th
        (, uint256[] memory time6) = _createOneBidParamArray(13e2, 400);  // 7th
        (, uint256[] memory time7) = _createOneBidParamArray(13e2, 300);  // 8th

        NodeOpBid[] memory nodeOpBids = new NodeOpBid[](8);
        nodeOpBids[0] = NodeOpBid(nodeOps[0], DR0, time0);
        nodeOpBids[1] = NodeOpBid(nodeOps[1], DR0, time1); 
        nodeOpBids[2] = NodeOpBid(nodeOps[2], DR0, time2); 
        nodeOpBids[3] = NodeOpBid(nodeOps[3], DR0, time3);
        nodeOpBids[4] = NodeOpBid(nodeOps[4], DR0, time4);
        nodeOpBids[5] = NodeOpBid(nodeOps[5], DR0, time5);
        nodeOpBids[6] = NodeOpBid(nodeOps[6], DR0, time6);
        nodeOpBids[7] = NodeOpBid(nodeOps[7], DR0, time7);
        _nodeOpsBid(nodeOpBids);
    }

    /* ===================== MODIFIERS ===================== */

    modifier preCreateClusters(uint8 _numDVsToPreCreate) {
        strategyModuleManager.preCreateDVs(_numDVsToPreCreate);
        _;
    }

}