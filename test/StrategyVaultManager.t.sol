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

import "./mocks/MockOracle.sol";

contract StrategyVaultManagerTest is ProofParsing, ByzantineDeployer {
    // using BeaconChainProofs for *;

    /// @notice Canonical, virtual beacon chain ETH strategy
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    /// @notice Mock oracle to simulate the price of ETH
    MockOracle public oracle;

    /// @notice Random validator deposit data (simulates a Byzantine DV)
    bytes private pubkey;
    bytes private signature;
    bytes32 private depositDataRoot;

    /// @notice address of the native token in the Split contract
    address public constant SPLIT_NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Initial balance of all the node operators
    uint256 internal constant STARTING_BALANCE = 500 ether;

    /// @notice Array of all the bid ids
    bytes32[] internal bidId;

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Deploy the mock oracle
        oracle = new MockOracle();

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
        _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
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
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(true, true, ELOperator1, address(oracle)));

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
        IStrategyVaultETH aliceStratVault2 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(false, false, ELOperator1, address(oracle)));

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
        strategyVaultManager.createStratVaultAndStakeNativeETH{value: 58 ether}(true, true, ELOperator1, address(oracle), alice);

        /* ===================== STRATVAULTETH CREATION FAILS BECAUSE NOT NODE OPS IN AUCTION ===================== */
        vm.prank(alice);
        vm.expectRevert(IAuction.MainAuctionEmpty.selector);
        strategyVaultManager.createStratVaultAndStakeNativeETH{value: 320 ether}(true, true, ELOperator1, address(oracle), alice);

        /* ===================== ALICE CREATES A STRATVAULTETH AND STAKES 64ETH ===================== */
        // whitelistedDeposit = true, upgradeable = true, EL Operator = ELOperator1, oracle = 0x0
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: 64 ether}(true, true, ELOperator1, address(oracle), alice));

        // Verify the StratVaultETH has received the 64 ETH
        assertEq(address(aliceStratVault1).balance, 64 ether);

        // Verify the StratVaultETH clusters
        assertEq(aliceStratVault1.getVaultDVNumber(), 2);
        bytes32[] memory clusterIds = aliceStratVault1.getAllDVIds();
        assertEq(clusterIds.length, 2);
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

        /* ===================== BOB TRIES TO STAKE IN ALICE'S STRATVAULTETH ===================== */
        vm.prank(bob);
        vm.expectRevert(IStrategyVault.OnlyWhitelistedDeposit.selector);
        aliceStratVault1.deposit{value: 32 ether}(32 ether, bob);

        // alice whitelists bob
        vm.prank(alice);
        aliceStratVault1.whitelistStaker(bob);

        // bob stakes in alice's stratvault
        vm.prank(bob);
        aliceStratVault1.deposit{value: 32 ether}(32 ether, bob);

        // Verify the StratVaultETH has received the 32 ETH
        assertEq(address(aliceStratVault1).balance, 64 ether + 32 ether);

        // Verify the StratVaultETH clusters
        assertEq(aliceStratVault1.getVaultDVNumber(), 3);
        clusterIds = aliceStratVault1.getAllDVIds();
        assertEq(clusterIds.length, 3);
        // Verify DV3 node ops addresses
        address[] memory nodeOpsDV3 = _getClusterIdNodeOp(clusterIds[2]);
        assertEq(nodeOpsDV3.length, 4);
        assertEq(nodeOpsDV3[0], nodeOps[2]);
        assertEq(nodeOpsDV3[1], nodeOps[5]);
        assertEq(nodeOpsDV3[2], nodeOps[6]);
        assertEq(nodeOpsDV3[3], nodeOps[7]);

        // /* ===================== BOB STAKES AGAIN IN ALICE'S STRATVAULTETH ===================== */

        /// TODO: Test function mint

        // vm.prank(bob);
        // aliceStratVault1.mint{value: 32 ether}(32 ether, bob);

        // // Verify the StratVaultETH has received the 32 ETH
        // assertEq(address(aliceStratVault1).balance, 64 ether + 32 ether + 32 ether);

        // // Verify the StratVaultETH clusters
        // assertEq(aliceStratVault1.getVaultDVNumber(), 4);
        // clusterIds = aliceStratVault1.getAllDVIds();
        // assertEq(clusterIds.length, 4);
        // // Verify DV4 node ops addresses
        // address[] memory nodeOpsDV4 = _getClusterIdNodeOp(clusterIds[3]);
        // assertEq(nodeOpsDV4.length, 4);
        // assertEq(nodeOpsDV4[0], nodeOps[2]);
        // assertEq(nodeOpsDV4[1], nodeOps[6]);
        // assertEq(nodeOpsDV4[2], nodeOps[7]);
        // assertEq(nodeOpsDV4[3], nodeOps[8]);

    }

    function test_RevertWhen_TransferByzNft() public {

        // Alice creates a StratVaultETH
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultETH(true, true, ELOperator1, address(oracle)));
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
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: 32 ether}(true, true, ELOperator1, address(oracle), alice));

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

    function test_activateCluster() public {

        // Alice creates a StrategyVault and stakes 32 ETH in it
        vm.prank(alice);
        IStrategyVaultETH aliceStratVault1 = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: 32 ether}(true, true, ELOperator1, address(oracle), alice));

        // Get the DV cluster ID
        bytes32[] memory clusterIds = aliceStratVault1.getAllDVIds();

        // Verify the DV status
        assertEq(uint256(auction.getClusterDetails(clusterIds[0]).status), uint256(IAuction.ClusterStatus.IN_CREATION));

        // The node operators create the DV off-chain
        // As soon as the DV is created and its deposit data available, it possible to activate it

        // DV activation fails because Alice is not the BeaconChainAdmin
        vm.prank(alice);
        vm.expectRevert(IStrategyVaultETH.OnlyBeaconChainAdmin.selector);
        aliceStratVault1.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // DV activation fails because the cluster is not in the vault
        vm.prank(beaconChainAdmin);
        vm.expectRevert(IStrategyVaultETH.ClusterNotInVault.selector);
        aliceStratVault1.activateCluster(pubkey, signature, depositDataRoot, bytes32(0));

        // BeaconChainAdmin activates the DV
        vm.prank(beaconChainAdmin);
        aliceStratVault1.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // Verify the DV status has been updated
        assertEq(uint256(auction.getClusterDetails(clusterIds[0]).status), uint256(IAuction.ClusterStatus.DEPOSITED));
        // Verify the pubkey hash has been set
        assertEq(auction.getClusterDetails(clusterIds[0]).clusterPubKeyHash, sha256(abi.encodePacked(pubkey, bytes16(0))));

        // Verify the balance of the StratVaultETH
        assertEq(address(aliceStratVault1).balance, 0 ether);

    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _bidCluster4(
        address _nodeOp,
        uint16 _discountRate,
        uint32 _timeInDays
    ) internal returns (bytes32) {
        vm.warp(block.timestamp + 1);
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(_nodeOp, _discountRate, _timeInDays, IAuction.AuctionType.JOIN_CLUSTER_4);
        vm.prank(_nodeOp);
        return   auction.bid{value: priceToPay}(_discountRate, _timeInDays, IAuction.AuctionType.JOIN_CLUSTER_4);
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

}