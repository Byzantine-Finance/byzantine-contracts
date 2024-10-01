// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";
import "./utils/ProofParsing.sol";

import "./ByzantineDeployer.t.sol";

import "../src/tokens/ByzNft.sol";
import "../src/core/Auction.sol";

import "../src/interfaces/IStrategyVaultERC20.sol";
import "../src/interfaces/IStrategyVaultETH.sol";
import "../src/interfaces/IStrategyVaultManager.sol";
import "../src/interfaces/IAuction.sol";

contract StrategyVaultManagerTest is ProofParsing, ByzantineDeployer {
    // using BeaconChainProofs for *;

    /// @notice Canonical, virtual beacon chain ETH strategy
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    // /// @notice Random validator deposit data to be able to call `createStratVaultAndStakeNativeETH` function
    // bytes pubkey;
    // bytes signature;
    // bytes32 depositDataRoot;

    /// @notice address of the native token in the Split contract
    address public constant SPLIT_NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Initial balance of all the node operators
    uint256 internal constant STARTING_BALANCE = 500 ether;

    /// @notice Array of all the bid ids
    bytes32[] internal bidId;

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Fill the node ops' balance
        for (uint256 i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        // Fill protagonists' balance
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // whitelist all the node operators
        auction.whitelistNodeOps(nodeOps);

        // nodeOps bid to be able to create 4 DVs
        bidId = _createMultipleBids();

        // Get deposit data of a random validator
        // _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
    }

    function test_byzantineContractsOwnership() public view {
        assertEq(strategyVaultManager.owner(), address(this));
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.owner(), address(strategyVaultManager));
    }

    function test_createStratVaultETH() public {

        /* ===================== ALICE CREATES A FIRST STRATVAULTETH ===================== */
        // whitelistedDeposit = true, upgradeable = true, EL Operator = ELOperator1, oracle = 0x0
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(true, true, ELOperator1, address(0)));

        // Verify aliceStratVault1 has been created and has delegated
        assertEq(aliceStratVault1.stratVaultNftId(), uint256(keccak256(abi.encodePacked(block.timestamp, uint64(0), alice))));
        assertEq(strategyVaultManager.getStratVaultByNftId(aliceStratVault1.stratVaultNftId()), address(aliceStratVault1));
        assertEq(aliceStratVault1.stratVaultOwner(), alice);
        assertEq(aliceStratVault1.whitelistedDeposit(), true);
        assertEq(aliceStratVault1.isWhitelisted(alice), true);
        assertEq(aliceStratVault1.upgradeable(), true);
        assertEq(eigenPodManager.hasPod(address(aliceStratVault1)), true);
        assertEq(strategyVaultManager.isStratVaultETH(address(aliceStratVault1)), true);
        assertEq(strategyVaultManager.numStratVaultETHs(), 1);
        assertEq(strategyVaultManager.numStratVaults(), 1);
        assertEq(aliceStratVault1.hasDelegatedTo(), ELOperator1);
        assertEq(aliceStratVault1.getVaultDVNumber(), 0);

        /* ===================== ALICE CREATES A FIRST STRATVAULTETH ===================== */
        // whitelistedDeposit = false, upgradeable = false, EL Operator = ELOperator1, oracle = 0x0
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault2 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(false, false, ELOperator1, address(0)));

        // Verify some variables of aliceStratVault2
        assertEq(aliceStratVault2.whitelistedDeposit(), false);
        assertEq(aliceStratVault2.isWhitelisted(alice), false);
        assertEq(aliceStratVault2.upgradeable(), false);
        assertEq(strategyVaultManager.numStratVaultETHs(), 2);
        assertEq(strategyVaultManager.numStratVaults(), 2);
        assertEq(aliceStratVault2.hasDelegatedTo(), ELOperator1);

        /// Get all the deployed StratVaultETH
        address[] memory stratVaultETHs = strategyVaultManager.getAllStratVaultETHs();
        assertEq(stratVaultETHs.length, 2);
        assertEq(stratVaultETHs[0], address(aliceStratVault1));
        assertEq(stratVaultETHs[1], address(aliceStratVault2));

    }

    function test_createStratVaultETHAndStake() public {

        /* ===================== STRATVAULTETH CREATION FAILS BECAUSE NOT MULTIPLE OF 32ETH STAKED ===================== */
        vm.prank(alice);
        vm.expectRevert(IStrategyVaultETH.CanOnlyDepositMultipleOf32ETH.selector);
        strategyVaultManager.createStratVaultAndStakeNativeETH{value: 58 ether}(true, true, ELOperator1, address(0));

        /* ===================== STRATVAULTETH CREATION FAILS BECAUSE NOT NODE OPS IN AUCTION ===================== */
        vm.prank(alice);
        vm.expectRevert(IAuction.MainAuctionEmpty.selector);
        strategyVaultManager.createStratVaultAndStakeNativeETH{value: 320 ether}(true, true, ELOperator1, address(0));

        /* ===================== ALICE CREATES A STRATVAULTETH AND STAKES 96ETH ===================== */
        // whitelistedDeposit = true, upgradeable = true, EL Operator = ELOperator1, oracle = 0x0
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: 96 ether}(true, true, ELOperator1, address(0)));

        // Verify the StratVaultETH has received the 96 ETH
        assertEq(address(aliceStratVault1).balance, 96 ether);

        // Verify the StratVaultETH clusters
        assertEq(aliceStratVault1.getVaultDVNumber(), 3);
        bytes32[] memory clusterIds = aliceStratVault1.getAllDVIds();
        assertEq(clusterIds.length, 3);
        // Verify DV1 node ops addresses
        address[] memory nodeOpsDV1 = _getClusterIdNodeOp(clusterIds[0]);
        assertEq(nodeOpsDV1.length, 4);
        assertEq(nodeOpsDV1[0], nodeOps[0]);
        assertEq(nodeOpsDV1[1], nodeOps[1]);
        assertEq(nodeOpsDV1[2], nodeOps[2]);
        assertEq(nodeOpsDV1[3], nodeOps[3]);
        // Verify DV2 node ops addresses
        address[] memory nodeOpsDV2 = _getClusterIdNodeOp(clusterIds[1]);
        assertEq(nodeOpsDV2.length, 4);
        assertEq(nodeOpsDV2[0], nodeOps[1]);
        assertEq(nodeOpsDV2[1], nodeOps[0]);
        assertEq(nodeOpsDV2[2], nodeOps[2]);
        assertEq(nodeOpsDV2[3], nodeOps[4]);
        // Verify DV3 node ops addresses
        address[] memory nodeOpsDV3 = _getClusterIdNodeOp(clusterIds[2]);
        assertEq(nodeOpsDV3.length, 4);
        assertEq(nodeOpsDV3[0], nodeOps[2]);
        assertEq(nodeOpsDV3[1], nodeOps[5]);
        assertEq(nodeOpsDV3[2], nodeOps[6]);
        assertEq(nodeOpsDV3[3], nodeOps[7]);

        /* ===================== BOB TRIES TO STAKE IN ALICE'S STRATVAULTETH ===================== */
        vm.prank(bob);
        vm.expectRevert(IStrategyVault.OnlyWhitelistedDeposit.selector);
        aliceStratVault1.stakeNativeETH{value: 32 ether}();

        // alice whitelists bob
        vm.prank(alice);
        aliceStratVault1.whitelistStaker(bob);

        // bob stakes in alice's stratvault
        vm.prank(bob);
        aliceStratVault1.stakeNativeETH{value: 32 ether}();

        // Verify the StratVaultETH has received the 32 ETH
        assertEq(address(aliceStratVault1).balance, 96 ether + 32 ether);

        // Verify the StratVaultETH clusters
        assertEq(aliceStratVault1.getVaultDVNumber(), 4);
        clusterIds = aliceStratVault1.getAllDVIds();
        assertEq(clusterIds.length, 4);
        // Verify DV4 node ops addresses
        address[] memory nodeOpsDV4 = _getClusterIdNodeOp(clusterIds[3]);
        assertEq(nodeOpsDV4.length, 4);
        assertEq(nodeOpsDV4[0], nodeOps[2]);
        assertEq(nodeOpsDV4[1], nodeOps[6]);
        assertEq(nodeOpsDV4[2], nodeOps[7]);
        assertEq(nodeOpsDV4[3], nodeOps[8]);

    }

    function test_RevertWhen_TransferByzNft() public {

        // Alice creates a StratVaultETH
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(true, true, ELOperator1, address(0)));
        uint256 nftId = IStrategyVaultETH(aliceStratVault1).stratVaultNftId();

        // Verify Alice owns the nft
        ByzNft byzNftContract = _getByzNftContract();
        assertEq(byzNftContract.ownerOf(nftId), alice);

        // Alice tries to transfer her ByzNft to Bob by calling the ERC721 `safeTransferFrom` function
        vm.startPrank(alice);
        vm.expectRevert(bytes("ByzNft is non-transferable"));
        byzNftContract.safeTransferFrom(alice, bob, nftId);

    }

    function test_SplitDistribution() public {

        // Alice creates a StrategyVault and stakes 32 ETH in it
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: 32 ether}(true, true, ELOperator1, address(0)));

        // Get the DV cluster ID
        bytes32[] memory clusterIds = aliceStratVault1.getAllDVIds();

        // Get the DV Split address
        address dvSplitAddr = auction.getClusterDetails(clusterIds[0]).splitAddr;

        // Get the DV recipients
        address[] memory recipients = _getClusterIdNodeOp(clusterIds[0]);

        // Get DV recipients' balances
        uint256[] memory recipientsInitialBalances = new uint256[](recipients.length);
        for (uint i = 0; i < recipients.length; i++) {
            recipientsInitialBalances[i] = recipients[i].balance;
        }
        // Get distributor's balance
        uint256 distributorBalance = bob.balance;

        // Fake the PoS rewards and add 100ETH in DV Split contract
        vm.deal(dvSplitAddr, 100 ether);

        SplitV2Lib.Split memory split = _createSplit(recipients);
        // Bob distributes the Split balance to DV's node ops
        vm.prank(bob);
        strategyVaultManager.distributeSplitBalance(clusterIds[0], split, SPLIT_NATIVE_TOKEN_ADDR);

        // Verify the Split contract balance has been drained
        assertEq(dvSplitAddr.balance, 1); // 0xSplits decided to left 1 wei to save gas. Only impact the distributor rewards

        // Verify the new balances of the DV's node ops
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(recipients[i].balance, recipientsInitialBalances[i] + 24.5 ether);
        }

        // Verify the distributor balance
        assertEq(bob.balance, distributorBalance + 2 ether - 1);

        // Bob distributes the Split balance of a non-existing cluster id
        vm.prank(bob);
        vm.expectRevert(IStrategyVaultManager.SplitAddressNotSet.selector);
        strategyVaultManager.distributeSplitBalance(bytes32(0), split, SPLIT_NATIVE_TOKEN_ADDR);
    }

    // // That test reverts because the `withdrawal_credential_proof` file generated with the Byzantine API
    // // doesn't point to the correct EigenPod (alice's EigenPod which is locally deployed)
    // function test_RevertWhen_WrongWithdrawalCredentials() public preCreateClusters(2) {
    //     // Get the validator fields proof
    //     (
    //         BeaconChainProofs.StateRootProof memory stateRootProofStruct,
    //         uint40[] memory validatorIndices,
    //         bytes[] memory proofsArray,
    //         bytes32[][] memory validatorFieldsArray
    //     ) = 
    //         _getValidatorFieldsProof(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

    //     // Start the test

    //     // Alice creates a Strategy Vault and stake ETH
    //     address stratVaultAddr = _createStratVaultAndStakeNativeETH(alice, 32 ether);

    //     // Deposit received on the Beacon Chain
    //     uint64 timestamp = uint64(block.timestamp + 16 hours);
    //     cheats.warp(timestamp);

    //     //set the oracle block root
    //     _setOracleBlockRoot(abi.encodePacked("./test/test-data/withdrawal_credential_proof_1634654.json"));

    //     // Verify the proof
    //     vm.prank(alice);
    //     cheats.expectRevert(
    //         bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod")
    //     );
    //     /// TODO: Update API to to have the exact timestamp where the proof was generated
    //     IStrategyVaultETH(stratVaultAddr).verifyWithdrawalCredentials(timestamp, stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);

    // }

    // // TODO: Test the `VerifyWithdrawalCredential` function when the proof is correct

    // // The operator shares for the beacon chain strategy hasn't been updated because alice didn't verify the withdrawal credentials
    // // of its validator (DV)
    // function testDelegateTo() public preCreateClusters(2) {

    //     // Create the operator details for the operator to delegate to
    //     IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
    //         __deprecated_earningsReceiver: ELOperator1,
    //         delegationApprover: address(0),
    //         stakerOptOutWindowBlocks: 0
    //     });

    //     _registerAsELOperator(ELOperator1, operatorDetails);

    //     // Create a restaking strategy: only beacon chain ETH Strategy
    //     IStrategy[] memory strategies = new IStrategy[](1);
    //     strategies[0] = beaconChainETHStrategy;

    //     // Get the operator shares before delegation
    //     uint256[] memory operatorSharesBefore = delegation.getOperatorShares(ELOperator1, strategies);
    //     assertEq(operatorSharesBefore[0], 0);
        
    //     // Alice stake 32 ETH
    //     address stratVaultAddr = _createStratVaultAndStakeNativeETH(alice, 32 ether);
    //     // Alice delegate its staked ETH to the ELOperator1
    //     vm.prank(alice);
    //     IStrategyVaultETH(stratVaultAddr).delegateTo(ELOperator1);

    //     // Verify if alice's strategy vault is registered as a delegator
    //     bool[] memory stratVaultsDelegated = strategyVaultManager.isDelegated(alice);
    //     assertTrue(stratVaultsDelegated[0], "testDelegateTo: Alice's Strategy Vault  didn't delegate to ELOperator1 correctly");
    //     // Verify if Alice delegated to the correct operator
    //     address[] memory stratVaultsDelegateTo = strategyVaultManager.hasDelegatedTo(alice);
    //     assertEq(stratVaultsDelegateTo[0], ELOperator1);

    //     // Operator shares didn't increase because alice didn't verify its withdrawal credentials -> podOwnerShares[stratVaultAddr] = 0
    //     uint256[] memory operatorSharesAfter = delegation.getOperatorShares(ELOperator1, strategies);
    //     //console.log("operatorSharesAfter", operatorSharesAfter[0]);
    //     //assertEq(operatorSharesBefore[0], 0);

    // }

    // // TODO: Verify the operator shares increase correctly when staker has verified correctly its withdrawal credentials
    // // TODO: Delegate to differents operators by creating new strategy vaults -> necessary to not put the 32ETH in the same DV

    // //--------------------------------------------------------------------------------------
    // //------------------------------  INTERNAL FUNCTIONS  ----------------------------------
    // //--------------------------------------------------------------------------------------

    // function _createStratVaultAndStakeNativeETH(address _staker, uint256 _stake) internal returns (address) {
    //     vm.prank(_staker);
    //     strategyVaultManager.createStratVaultAndStakeNativeETH{value: _stake}(pubkey, signature, depositDataRoot);
    //     uint256 stratVaultNumber = strategyVaultManager.getStratVaultNumber(_staker);
    //     if (stratVaultNumber == 0) {
    //         return address(0);
    //     }
    //     return strategyVaultManager.getStratVaults(_staker)[stratVaultNumber - 1];
    // }

    // function _getDepositData(
    //     bytes memory depositFilePath
    // ) internal {
    //     // File generated with the Obol LaunchPad
    //     setJSON(string(depositFilePath));

    //     pubkey = getDVPubKeyDeposit();
    //     signature = getDVSignature();
    //     depositDataRoot = getDVDepositDataRoot();
    //     //console.logBytes(pubkey);
    //     //console.logBytes(signature);
    //     //console.logBytes32(depositDataRoot);
    // }

    // function _getValidatorFieldsProof(
    //     bytes memory proofFilePath
    // ) internal returns (
    //     BeaconChainProofs.StateRootProof memory,
    //     uint40[] memory,
    //     bytes[] memory,
    //     bytes32[][] memory
    // ) {
    //     // File generated with the Byzantine API
    //     setJSON(string(proofFilePath));

    //     BeaconChainProofs.StateRootProof memory stateRootProofStruct = _getStateRootProof();

    //     uint40[] memory validatorIndices = new uint40[](1);
    //     validatorIndices[0] = uint40(getValidatorIndex());

    //     bytes32[][] memory validatorFieldsArray = new bytes32[][](1);
    //     validatorFieldsArray[0] = getValidatorFields();

    //     bytes[] memory proofsArray = new bytes[](1);
    //     proofsArray[0] = abi.encodePacked(getWithdrawalCredentialProof());

    //     return (stateRootProofStruct, validatorIndices, proofsArray, validatorFieldsArray);
    // }

    // function _getDVNodesAddr(bytes memory lockFilePath) internal returns (address[4] memory) {
    //     setJSON(string(lockFilePath));
    //     return getDVNodesAddr();
    // }

    // function _getStateRootProof() internal returns (BeaconChainProofs.StateRootProof memory) {
    //     return BeaconChainProofs.StateRootProof(getBeaconStateRoot(), abi.encodePacked(getStateRootProof()));
    // }

    // function _setOracleBlockRoot(bytes memory proofFilePath) internal {
    //     setJSON(string(proofFilePath));
    //     bytes32 latestBlockRoot = getLatestBlockRoot();
    //     //set beaconStateRoot
    //     beaconChainOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);
    // }

    // function _nodeOpsBid(
    //     NodeOpBid[] memory nodeOpsBids
    // ) internal returns (uint256[][] memory) {
    //     uint256[][] memory nodeOpsAuctionScores = new uint256[][](nodeOpsBids.length);
    //     for (uint i = 0; i < nodeOpsBids.length; i++) {
    //         nodeOpsAuctionScores[i] = _nodeOpBid(nodeOpsBids[i]);
    //     }
    //     return nodeOpsAuctionScores;
    // }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _bidCluster4(
        address _nodeOp,
        uint16 _discountRate,
        uint32 _timeInDays
    ) internal returns (bytes32) {
        vm.warp(block.timestamp + 1);
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPayCluster4(_nodeOp, _discountRate, _timeInDays);
        vm.prank(_nodeOp);
        return   auction.bidCluster4{value: priceToPay}(_discountRate, _timeInDays);
    }

    function _createMultipleBids() internal returns (bytes32[] memory) {
        bytes32[] memory bidIds = new bytes32[](16);

        // nodeOps[0] bids 2 times with the same parameters
        bidIds[0] = _bidCluster4(nodeOps[0], 5e2, 200); // 1st
        bidIds[1] = _bidCluster4(nodeOps[0], 5e2, 200); // 6th

        // nodeOps[1] bids 2 times with the same parameters
        bidIds[2] = _bidCluster4(nodeOps[1], 5e2, 200); // 2nd
        bidIds[3] = _bidCluster4(nodeOps[1], 5e2, 200); // 5th

        // nodeOps[2] bids 4 times with different parameters
        bidIds[4] = _bidCluster4(nodeOps[2], 5e2, 150); // 3rd
        bidIds[5] = _bidCluster4(nodeOps[2], 5e2, 149); // 7th
        bidIds[6] = _bidCluster4(nodeOps[2], 5e2, 148); // 9th
        bidIds[7] = _bidCluster4(nodeOps[2], 5e2, 147); // 13th

        // nodeOps[3] bids
        bidIds[8] = _bidCluster4(nodeOps[3], 5e2, 150); // 4th

        // nodeOps[4] bids
        bidIds[9] = _bidCluster4(nodeOps[4], 5e2, 149); // 8th

        // nodeOps[5] bids
        bidIds[10] = _bidCluster4(nodeOps[5], 9e2, 100); // 10th

        // nodeOps[6] bids
        bidIds[11] = _bidCluster4(nodeOps[6], 12e2, 50); // 11th
        bidIds[12] = _bidCluster4(nodeOps[6], 14e2, 50); // 14th

        // nodeOps[7] bids
        bidIds[13] = _bidCluster4(nodeOps[7], 14e2, 45); // 12th
        bidIds[14] = _bidCluster4(nodeOps[7], 14e2, 40); // 15th

        // nodeOps[8] bids
        bidIds[15] = _bidCluster4(nodeOps[8], 15e2, 40); // 16th

        return bidIds;
    }
    
    function _getByzNftContract() internal view returns (ByzNft) {
        return ByzNft(address(strategyVaultManager.byzNft()));
    }

    function _getClusterIdNodeOp(bytes32 _clusterId) internal view returns (address[] memory) {
        IAuction.NodeDetails[] memory nodeDetails = auction.getClusterDetails(_clusterId).nodes;

        address[] memory nodeOps = new address[](nodeDetails.length);
        for (uint256 i = 0; i < nodeDetails.length; i++) {
            nodeOps[i] = auction.getBidDetails(nodeDetails[i].bidId).nodeOp;
        }
        return nodeOps;
    }

    function _createSplit(
        address[] memory recipients
    ) internal view returns (SplitV2Lib.Split memory split) {

        uint256[] memory allocations = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            allocations[i] = auction.NODE_OP_SPLIT_ALLOCATION();
        }

        split = SplitV2Lib.Split({
            recipients: recipients,
            allocations: allocations,
            totalAllocation: auction.SPLIT_TOTAL_ALLOCATION(),
            distributionIncentive: auction.SPLIT_DISTRIBUTION_INCENTIVE()
        });
    }

}