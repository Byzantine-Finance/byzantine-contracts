// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";
import "./utils/ProofParsing.sol";

import "./ByzantineDeployer.t.sol";

import "../src/tokens/ByzNft.sol";
import "../src/core/Auction.sol";

import "../src/interfaces/IStrategyVaultETH.sol";
import "../src/interfaces/IStrategyVaultManager.sol";

contract StrategyVaultManagerTest is ProofParsing, ByzantineDeployer {
    using BeaconChainProofs for *;

    /// @notice Canonical, virtual beacon chain ETH strategy
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    /// @notice Random validator deposit data to be able to call `createStratVaultAndStakeNativeETH` function
    bytes pubkey;
    bytes signature;
    bytes32 depositDataRoot;

    /// @notice address of the native token in the Split contract
    address public constant SPLIT_NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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

    function testStratVaultManagerOwner() public view {
        assertEq(strategyVaultManager.owner(), address(this));
    }

    function testByzNftContractOwner() public view {
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.owner(), address(strategyVaultManager));
    }

    function testPreCreateDVs() public {
        // Alice would like to create a StrategyVault but no pending clusters
        vm.expectRevert(bytes("StrategyVaultManager.createStratVaultAndStakeNativeETH: no pending DVs"));
        _createStratVaultAndStakeNativeETH(alice, 32 ether);

        // Alice tries to pre-create 2 DVs but she is not allowed
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        strategyVaultManager.preCreateDVs(2);

        // Byzantine pre-create the first 2 DVs
        strategyVaultManager.preCreateDVs(2);

        // Verify number of pre-created DVs
        assertEq(strategyVaultManager.numPreCreatedClusters(), 2);
        assertEq(strategyVaultManager.getNumPendingClusters(), 2);

        // Verify the nodes details of the pre-created DVs
        IStrategyVaultETH.Node[4] memory nodesDV1 = strategyVaultManager.getPendingClusterNodeDetails(0);
        IStrategyVaultETH.Node[4] memory nodesDV2 = strategyVaultManager.getPendingClusterNodeDetails(1);
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

        // Alice creates a StrategyVault and activates the first DV
        _createStratVaultAndStakeNativeETH(alice, 32 ether);
        assertEq(alice.balance, STARTING_BALANCE - 32 ether);

        // Verify the first pending DV has been deleted from the pending container
        nodesDV1 = strategyVaultManager.getPendingClusterNodeDetails(0);
        // Verify the nodes details of the pre-created DV1 has been deleted
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV1[i].eth1Addr, address(0));
        }
        assertEq(nodesDV1[0].vcNumber, 0);
        assertEq(nodesDV1[1].vcNumber, 0);
        assertEq(nodesDV1[2].vcNumber, 0);
        assertEq(nodesDV1[3].vcNumber, 0);

        // Verify number of pending DVs
        assertEq(strategyVaultManager.numPreCreatedClusters(), 2);
        assertEq(strategyVaultManager.getNumPendingClusters(), 1);
    }

    function testCreateStratVaults() public preCreateClusters(2) {

        // Node ops bids again
        _8NodeOpsBid();

        // First, verify if Alice and Bob have StrategyVaults
        assertFalse(strategyVaultManager.hasStratVaults(alice));
        assertFalse(strategyVaultManager.hasStratVaults(bob));

        // Alice creates a StrategyVault
        address aliceStratVaultAddr1 = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        uint256 nft1 = IStrategyVaultETH(aliceStratVaultAddr1).stratVaultNftId();
        assertTrue(strategyVaultManager.hasStratVaults(alice));
        assertEq(strategyVaultManager.numStratVaults(), 1);
        assertEq(strategyVaultManager.getStratVaultNumber(alice), 1);
        assertEq(IStrategyVaultETH(aliceStratVaultAddr1).stratVaultOwner(), alice);
        assertEq(strategyVaultManager.getStratVaultByNftId(nft1), aliceStratVaultAddr1);

        // Verify alice strat vault 1 DV details
        IStrategyVaultETH.Node[4] memory nodesDV1Alice = IStrategyVaultETH(aliceStratVaultAddr1).getDVNodesDetails();
        IStrategyVaultETH.DVStatus dvStatusDV1Alice = IStrategyVaultETH(aliceStratVaultAddr1).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV1Alice[i].eth1Addr, nodeOps[i]);
        }
        assertEq(nodesDV1Alice[0].vcNumber, 999);
        assertEq(nodesDV1Alice[1].vcNumber, 900);
        assertEq(nodesDV1Alice[2].vcNumber, 800);
        assertEq(nodesDV1Alice[3].vcNumber, 700);
        // Verify the DV status
        assertEq(uint(dvStatusDV1Alice), uint(IStrategyVaultETH.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyVaultManager.numPreCreatedClusters(), 3);
        assertEq(strategyVaultManager.getNumPendingClusters(), 2);

        // Bob creates a StrategyVault
        address bobStratVaultAddr1 = _createStratVaultAndStakeNativeETH(bob, 32 ether);
        uint256 nft2 = IStrategyVaultETH(bobStratVaultAddr1).stratVaultNftId();
        assertTrue(strategyVaultManager.hasStratVaults(bob));
        assertEq(strategyVaultManager.numStratVaults(), 2);
        assertEq(strategyVaultManager.getStratVaultNumber(bob), 1);
        assertEq(IStrategyVaultETH(bobStratVaultAddr1).stratVaultOwner(), bob);
        assertEq(strategyVaultManager.getStratVaultByNftId(nft2), bobStratVaultAddr1);

        // Verify bob strat vault 1 DV details
        IStrategyVaultETH.Node[4] memory nodesDV1Bob = IStrategyVaultETH(bobStratVaultAddr1).getDVNodesDetails();
        IStrategyVaultETH.DVStatus dvStatusDV1Bob = IStrategyVaultETH(bobStratVaultAddr1).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
           assertEq(nodesDV1Bob[i].eth1Addr, nodeOps[i + 4]);
        }
        assertEq(nodesDV1Bob[0].vcNumber, 600);
        assertEq(nodesDV1Bob[1].vcNumber, 500);
        assertEq(nodesDV1Bob[2].vcNumber, 400);
        assertEq(nodesDV1Bob[3].vcNumber, 300);
        // Verify the DV status
        assertEq(uint(dvStatusDV1Bob), uint(IStrategyVaultETH.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyVaultManager.numPreCreatedClusters(), 4);
        assertEq(strategyVaultManager.getNumPendingClusters(), 2);

        // Alice creates a second StrategyVault
        address aliceStratVaultAddr2 = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        uint256 nft3 = IStrategyVaultETH(aliceStratVaultAddr2).stratVaultNftId();
        assertEq(strategyVaultManager.numStratVaults(), 3);
        assertEq(strategyVaultManager.getStratVaultNumber(alice), 2);
        assertEq(IStrategyVaultETH(aliceStratVaultAddr2).stratVaultOwner(), alice);
        assertEq(strategyVaultManager.getStratVaultByNftId(nft3), aliceStratVaultAddr2);

        // Verify alice strat vault 2 DV details
        IStrategyVaultETH.Node[4] memory nodesDV2Alice = IStrategyVaultETH(aliceStratVaultAddr2).getDVNodesDetails();
        IStrategyVaultETH.DVStatus dvStatusDV2Alice = IStrategyVaultETH(aliceStratVaultAddr2).getDVStatus();
        // Verify the nodes details
        for (uint i = 0; i < clusterSize; i++) {
            assertEq(nodesDV2Alice[i].eth1Addr, nodeOps[i]);
        }
        assertEq(nodesDV2Alice[0].vcNumber, 999);
        assertEq(nodesDV2Alice[1].vcNumber, 900);
        assertEq(nodesDV2Alice[2].vcNumber, 800);
        assertEq(nodesDV2Alice[3].vcNumber, 700);
        // Verify the DV status
        assertEq(uint(dvStatusDV2Alice), uint(IStrategyVaultETH.DVStatus.DEPOSITED_NOT_VERIFIED));

        // Verify number of pending DVs
        assertEq(strategyVaultManager.numPreCreatedClusters(), 4);
        assertEq(strategyVaultManager.getNumPendingClusters(), 1);

    }

    function testpreCalculatePodAndSplitAddress() public preCreateClusters(2) {

        // Pre-calculate pod and split address of DV1 and DV2
        (address podAddressDV1, address splitAddressDV1) = strategyVaultManager.preCalculatePodAndSplitAddr(0);
        (address podAddressDV2, address splitAddressDV2) = strategyVaultManager.preCalculatePodAndSplitAddr(1);

        // Sould revert because DV3 is not in the precreated clusters range
        vm.expectRevert(bytes("StrategyVaultManager.preCalculatePodAndSplitAddr: invalid nounce. Should be in the precreated clusters range"));
        (address podAddressDV3, address splitAddressDV3) = strategyVaultManager.preCalculatePodAndSplitAddr(2);

        // Node ops bids again
        _8NodeOpsBid();

        // Alice creates two StrategyVaults
        address aliceStratVaultAddr1 = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        address aliceStratVaultAddr2 = _createStratVaultAndStakeNativeETH(alice, 32 ether);

        // Should revert because DV1 is already created
        vm.expectRevert(bytes("StrategyVaultManager.preCalculatePodAndSplitAddr: invalid nounce. Should be in the precreated clusters range"));
        strategyVaultManager.preCalculatePodAndSplitAddr(0);

        (podAddressDV3, splitAddressDV3) = strategyVaultManager.preCalculatePodAndSplitAddr(2);

        // Bob creates a StrategyVault
        address bobStratVaultAddr1 = _createStratVaultAndStakeNativeETH(bob, 32 ether);

        // Verify pod addresses of DV1, DV2 and DV3
        assertEq(strategyVaultManager.getPodByStratVaultAddr(aliceStratVaultAddr1), podAddressDV1);
        assertEq(strategyVaultManager.getPodByStratVaultAddr(aliceStratVaultAddr2), podAddressDV2);
        assertEq(strategyVaultManager.getPodByStratVaultAddr(bobStratVaultAddr1), podAddressDV3);

        // Verify split addresses of DV1, DV2 and DV3
        assertEq(IStrategyVaultETH(aliceStratVaultAddr1).getSplitAddress(), splitAddressDV1);
        assertEq(IStrategyVaultETH(aliceStratVaultAddr2).getSplitAddress(), splitAddressDV2);
        assertEq(IStrategyVaultETH(bobStratVaultAddr1).getSplitAddress(), splitAddressDV3);
    }

    // Within foundry, resulting address of a contract deployed with CREATE2 differs according to the msg.sender.
    // Why??
    function testFrontRunStratVaultDeployment() public preCreateClusters(2) {
        // Bob a hacker, front run the deployment of the first StrategyVault
        vm.startPrank(bob);
        uint256 firstNftId = uint256(keccak256(abi.encode(0)));
        address stratVaultAddr = Create2.deploy(
            0,
            bytes32(firstNftId),
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(strategyVaultBeacon, ""))
        );
        // Bob wants to initialize the StrategyVault but can't because he doesn't own the nft
        vm.expectRevert(bytes("Cannot initialize StrategyVault: ERC721: invalid token ID"));
        IStrategyVaultETH(stratVaultAddr).initialize(firstNftId, bob);
        vm.stopPrank();
    }

    function testSplitDistribution() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        IStrategyVaultETH stratVaultAlice = IStrategyVaultETH(_createStratVaultAndStakeNativeETH(alice, 32 ether));
        address stratVaultAliceSplit = stratVaultAlice.getSplitAddress();

        // Create the recipients array
        IStrategyVaultETH.Node[4] memory nodesDVAlice = stratVaultAlice.getDVNodesDetails();
        address[] memory recipients = new address[](nodesDVAlice.length);
        for (uint i = 0; i < nodesDVAlice.length; i++) {
            recipients[i] = nodesDVAlice[i].eth1Addr;
        }

        // Get DV's node ops' balances
        uint256[] memory nodeOpsInitialBalances = new uint256[](nodesDVAlice.length);
        for (uint i = 0; i < nodesDVAlice.length; i++) {
            nodeOpsInitialBalances[i] = recipients[i].balance;
        }
        // Get distributor's balance
        uint256 distributorBalance = bob.balance;

        // Fake the PoS rewards and add 100ETH in stratVaultAliceSplit contract
        vm.deal(stratVaultAliceSplit, 100 ether);
        assertEq(stratVaultAliceSplit.balance, 100 ether);

        SplitV2Lib.Split memory split = _createSplit(recipients);
        // Bob distributes the Split balance to DV's node ops
        vm.prank(bob);
        stratVaultAlice.distributeSplitBalance(split, SPLIT_NATIVE_TOKEN_ADDR);

        // Verify the Split contract balance has been drained
        assertEq(stratVaultAliceSplit.balance, 1); // 0xSplits decided to left 1 wei to save gas. Only impact the distributor rewards

        // Verify the new balances of the DV's node ops
        for (uint i = 0; i < nodesDVAlice.length; i++) {
            assertEq(recipients[i].balance, nodeOpsInitialBalances[i] + 24.5 ether);
        }

        // Verify the distributor balance
        assertEq(bob.balance, distributorBalance + 2 ether - 1);
    }

    function testStratVaultTransfer() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        address stratVaultAddrAlice = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        uint256 nftId = IStrategyVaultETH(stratVaultAddrAlice).stratVaultNftId();

        // Verify Alice owns the nft
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.ownerOf(nftId), alice);

        // Alice tries to transfer the StrategyVault by call the ERC721 `safeTransferFrom` function
        // It's forbidden because the nft owner will change but the mapping `stakerToStratVaults` won't be updated
        vm.startPrank(alice);
        vm.expectRevert(bytes("ByzNft._transfer: Token transfer can only be initiated by the StrategyVaultManager, call StrategyVaultManager.transferStratVaultOwnership"));
        byzNftContract.safeTransferFrom(alice, bob, nftId);
        vm.stopPrank();

        // Alice approves the StrategyVaultManager to transfer to Bob
        _approveNftTransferByStratVaultManager(alice, IStrategyVaultETH(stratVaultAddrAlice).stratVaultNftId());

        // Alice transfers the StrategyVault to Bob
        vm.prank(alice);
        strategyVaultManager.transferStratVaultOwnership(stratVaultAddrAlice, bob);
        assertEq(strategyVaultManager.getStratVaultNumber(alice), 0);

        // Verify if Bob is the new owner
        assertEq(bob, IStrategyVaultETH(stratVaultAddrAlice).stratVaultOwner());
        assertEq(strategyVaultManager.getStratVaultNumber(bob), 1);

        // Verify if the mappings has been correctly updated
        address[] memory aliceStratVaults = strategyVaultManager.getStratVaults(alice);
        assertEq(aliceStratVaults.length, 0);
        assertEq(aliceStratVaults, new address[](0));
        address[] memory bobStratVaults = strategyVaultManager.getStratVaults(bob);
        assertEq(bobStratVaults.length, 1);
        assertEq(bobStratVaults[0], stratVaultAddrAlice);
    }

    function test_RevertWhen_NonStratVaultOwnerTransfersStratVault() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        address stratVaultAddrAlice = _createStratVaultAndStakeNativeETH(alice, 32 ether);

        // Alice approves the StrategyVaultManager to transfer to Bob
        _approveNftTransferByStratVaultManager(alice, IStrategyVaultETH(stratVaultAddrAlice).stratVaultNftId());

        // This smart contract transfers the StrategyVault to Bob
        vm.expectRevert(IStrategyVaultManager.NotStratVaultOwner.selector);
        strategyVaultManager.transferStratVaultOwnership(stratVaultAddrAlice, bob);
    }

    function test_RevertWhen_TransferStratVaultToItself() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        address stratVaultAddrAlice = _createStratVaultAndStakeNativeETH(alice, 32 ether);

        // Alice approves the StrategyVault to transfer to herself
        _approveNftTransferByStratVaultManager(alice, IStrategyVaultETH(stratVaultAddrAlice).stratVaultNftId());     

        vm.expectRevert(bytes("StrategyVaultManager.transferStratVaultOwnership: cannot transfer ownership to the same address"));
        vm.prank(alice);
        strategyVaultManager.transferStratVaultOwnership(stratVaultAddrAlice, alice);
    }

    function test_HasPod() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        address stratVaultAddrAlice = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        assertTrue(strategyVaultManager.hasPod(stratVaultAddrAlice));
    }

    function test_callEigenPodManager() public preCreateClusters(2) {
        // Alice creates a StrategyVault
        address stratVaultAddr = _createStratVaultAndStakeNativeETH(alice, 32 ether);

        // Alice wants to call EigenPodManager directly
        bytes memory functionToCall = abi.encodeWithSignature("ownerToPod(address)", stratVaultAddr);
        vm.prank(alice);
        bytes memory ret = IStrategyVaultETH(stratVaultAddr).callEigenPodManager(functionToCall);
        IEigenPod pod = abi.decode(ret, (IEigenPod));

        assertEq(address(pod), strategyVaultManager.getPodByStratVaultAddr(stratVaultAddr));
    }

    function test_RevertWhen_Not32ETHDeposited() public preCreateClusters(2) {

        // Alice create StrategyVault and stake 31 ETH in the contract
        vm.expectRevert(bytes("StrategyVaultManager.createStratVaultAndStakeNativeETH: must initially stake for any validator with 32 ether"));
        _createStratVaultAndStakeNativeETH(alice, 31 ether);

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

        // Alice creates a Strategy Vault and stake ETH
        address stratVaultAddr = _createStratVaultAndStakeNativeETH(alice, 32 ether);

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
        IStrategyVaultETH(stratVaultAddr).verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

    }

    // TODO: Test the `VerifyWithdrawalCredential` function when the proof is correct

    // The operator shares for the beacon chain strategy hasn't been updated because alice didn't verify the withdrawal credentials
    // of its validator (DV)
    function testDelegateTo() public preCreateClusters(2) {

        // Create the operator details for the operator to delegate to
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            __deprecated_earningsReceiver: ELOperator1,
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
        address stratVaultAddr = _createStratVaultAndStakeNativeETH(alice, 32 ether);
        // Alice delegate its staked ETH to the ELOperator1
        vm.prank(alice);
        IStrategyVaultETH(stratVaultAddr).delegateTo(ELOperator1);

        // Verify if alice's strategy vault is registered as a delegator
        bool[] memory stratVaultsDelegated = strategyVaultManager.isDelegated(alice);
        assertTrue(stratVaultsDelegated[0], "testDelegateTo: Alice's Strategy Vault  didn't delegate to ELOperator1 correctly");
        // Verify if Alice delegated to the correct operator
        address[] memory stratVaultsDelegateTo = strategyVaultManager.hasDelegatedTo(alice);
        assertEq(stratVaultsDelegateTo[0], ELOperator1);

        // Operator shares didn't increase because alice didn't verify its withdrawal credentials -> podOwnerShares[stratVaultAddr] = 0
        uint256[] memory operatorSharesAfter = delegation.getOperatorShares(ELOperator1, strategies);
        //console.log("operatorSharesAfter", operatorSharesAfter[0]);
        //assertEq(operatorSharesBefore[0], 0);

    }

    // TODO: Verify the operator shares increase correctly when staker has verified correctly its withdrawal credentials
    // TODO: Delegate to differents operators by creating new strategy vaults -> necessary to not put the 32ETH in the same DV

    //--------------------------------------------------------------------------------------
    //------------------------------  INTERNAL FUNCTIONS  ----------------------------------
    //--------------------------------------------------------------------------------------

    function _createStratVaultAndStakeNativeETH(address _staker, uint256 _stake) internal returns (address) {
        vm.prank(_staker);
        strategyVaultManager.createStratVaultAndStakeNativeETH{value: _stake}(pubkey, signature, depositDataRoot);
        uint256 stratVaultNumber = strategyVaultManager.getStratVaultNumber(_staker);
        if (stratVaultNumber == 0) {
            return address(0);
        }
        return strategyVaultManager.getStratVaults(_staker)[stratVaultNumber - 1];
    }

    function _getByzNftContract() internal view returns (ByzNft) {
        return ByzNft(address(strategyVaultManager.byzNft()));
    }

    function _approveNftTransferByStratVaultManager(address approver, uint256 nftId) internal {
        ByzNft byzNftContract = _getByzNftContract();
        vm.prank(approver);
        byzNftContract.approve(address(strategyVaultManager), nftId);
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

    function _createSplit(
        address[] memory recipients
    ) internal view returns (SplitV2Lib.Split memory split) {

        uint256[] memory allocations = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            allocations[i] = strategyVaultManager.NODE_OP_SPLIT_ALLOCATION();
        }

        split = SplitV2Lib.Split({
            recipients: recipients,
            allocations: allocations,
            totalAllocation: strategyVaultManager.SPLIT_TOTAL_ALLOCATION(),
            distributionIncentive: strategyVaultManager.SPLIT_DISTRIBUTION_INCENTIVE()
        });
    }

    function _createOneBidParamArray(
        uint16 _discountRate,
        uint32 _timeInDays
    ) internal pure returns (uint16[] memory, uint32[] memory) {
        uint16[] memory discountRateArray = new uint16[](1);
        discountRateArray[0] = _discountRate;

        uint32[] memory timeInDaysArray = new uint32[](1);
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
        (uint16[] memory DR0, uint32[] memory time0) = _createOneBidParamArray(13e2, 999);  // 1st
        (, uint32[] memory time1) = _createOneBidParamArray(13e2, 900);  // 2nd
        (, uint32[] memory time2) = _createOneBidParamArray(13e2, 800);  // 3rd
        (, uint32[] memory time3) = _createOneBidParamArray(13e2, 700);  // 4th
        (, uint32[] memory time4) = _createOneBidParamArray(13e2, 600);  // 5th
        (, uint32[] memory time5) = _createOneBidParamArray(13e2, 500);  // 6th
        (, uint32[] memory time6) = _createOneBidParamArray(13e2, 400);  // 7th
        (, uint32[] memory time7) = _createOneBidParamArray(13e2, 300);  // 8th

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
        strategyVaultManager.preCreateDVs(_numDVsToPreCreate);
        _;
    }

}