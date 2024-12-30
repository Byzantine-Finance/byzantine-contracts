// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "./ByzantineDeployer.t.sol";
import {IAuction} from "../src/interfaces/IAuction.sol";
import {IStrategyVaultETH} from "../src/interfaces/IStrategyVaultETH.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

contract AuctionTest is ByzantineDeployer {

    uint256 internal constant STARTING_BALANCE = 100 ether;
    uint256 internal constant BOND = 1 ether;

    // Some references score and bid price for specific bid parameters 
    uint256 internal auctionScore_10e2_100 = 737197890360389;
    uint256 internal bidPrice_10e2_100 = 72986301369863000;
    uint256 internal auctionScore_1375_129 = 708532978296286;
    uint256 internal bidPrice_1375_129 = 90229315068493080;

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Fill the node operators' balance
        for (uint256 i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // whitelist all the node operators
        auction.whitelistNodeOps(nodeOps);
    }

    function test_Whitelist() external view {
        // Verify if all node operators are whitelisted
        for (uint256 i = 0; i < nodeOps.length; i++) {
            assertTrue(auction.isWhitelisted(nodeOps[i]));
        }

        // Verify Alice and Bob are not whitelisted
        assertFalse(auction.isWhitelisted(alice));
        assertFalse(auction.isWhitelisted(bob));
    }

    // function test_RemoveFromWhitelist() external {
    //     // Byzantine add nodeOps[0] to the whitelist
    //     auction.addNodeOpToWhitelist(nodeOps[0]);

    //     // Should revert if Byzantine remove a non-whitelisted address
    //     vm.expectRevert(IAuction.NotWhitelisted.selector);
    //     auction.removeNodeOpFromWhitelist(nodeOps[1]);

    //     // Byzantine removes nodeOps[0] from the whitelist
    //     auction.removeNodeOpFromWhitelist(nodeOps[0]);
    //     assertFalse(auction.isWhitelisted(nodeOps[0]));
    // }

    function test_getPriceToPay() external {
        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.getPriceToPay(nodeOps[0], 25e2, 200, IAuction.AuctionType.JOIN_CLUSTER_4);
        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.getPriceToPay(nodeOps[0], 10e2, 20, IAuction.AuctionType.JOIN_CLUSTER_4);
        // Should revert if auctionType is invalid
        vm.expectRevert(IAuction.InvalidAuctionType.selector);
        auction.getPriceToPay(nodeOps[0], 10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_7);

        // Test price to pay for a whitelisted nodeOp
        uint256 priceToPayWhitelisted = auction.getPriceToPay(nodeOps[0], 10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_4);
        assertEq(priceToPayWhitelisted, bidPrice_10e2_100);

        // Test price to pay for a non-whitelisted nodeOp
        uint256 priceToPayNotWhitelisted = auction.getPriceToPay(alice, 10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_4);
        assertEq(priceToPayNotWhitelisted, bidPrice_10e2_100 + BOND);
    }

    function testBid_RevertCorrectly() external {
        // Should revert if non-whitelisted
        vm.expectRevert(IAuction.NotWhitelisted.selector);
        vm.prank(alice);
        auction.bid(10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_4);

        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        vm.prank(nodeOps[0]);
        auction.bid(25e2, 200, IAuction.AuctionType.JOIN_CLUSTER_4);

        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        vm.prank(nodeOps[0]);
        auction.bid(10e2, 20, IAuction.AuctionType.JOIN_CLUSTER_4);

        // Should revert if not enough ether sent
        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        vm.prank(nodeOps[0]);
        auction.bid{value: 0 ether}(10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_4);

        // Should revert if auctionType is invalid
        vm.expectRevert(IAuction.InvalidAuctionType.selector);
        vm.prank(nodeOps[0]);
        auction.bid{value: 20 ether}(10e2, 100, IAuction.AuctionType.JOIN_CLUSTER_7);
    }

    function testBid_RefundTheSkimmingEthers() external {
        // nodeOps[0] bids
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 11e2, 99, IAuction.AuctionType.JOIN_CLUSTER_4);
        vm.prank(nodeOps[0]);
        auction.bid{value: (priceToPay + 1 ether)}(11e2, 99, IAuction.AuctionType.JOIN_CLUSTER_4);

        // Verify the balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE - priceToPay);
        // Verify the balance of the Escrow contract
        assertEq(address(escrow).balance, priceToPay);
    }

    function test_NodeOpDetails() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Check nodeOps[0] details
        IAuction.NodeOpGlobalDetails memory nodeOpDetails = auction.getNodeOpDetails(nodeOps[0]);
        assertEq(nodeOpDetails.reputationScore, 0);
        assertEq(nodeOpDetails.numBonds, 0);
        assertEq(nodeOpDetails.numBidsCluster4, 2);
        assertEq(nodeOpDetails.numBidsCluster7, 0);
        assertEq(nodeOpDetails.isWhitelisted, true);
    }

    function test_BidDetails() external {
        // First bid parameters: 10%, 100 days
        bytes32 bid0Id = _bidCluster4(nodeOps[0], 10e2, 100);
        IAuction.BidDetails memory bid0Details = auction.getBidDetails(bid0Id);

        assertEq(bid0Details.auctionScore, auctionScore_10e2_100);
        assertEq(bid0Details.bidPrice, bidPrice_10e2_100);
        assertEq(bid0Details.nodeOp, nodeOps[0]);
        assertEq(bid0Details.vcNumber, 100);
        assertEq(bid0Details.discountRate, 10e2);
        assertEq(uint256(bid0Details.auctionType), uint256(IAuction.AuctionType.JOIN_CLUSTER_4));
        assertEq(address(escrow).balance, bid0Details.bidPrice);

        // Second bid parameter: 13.75%, 129 days
        bytes32 bid1Id = _bidCluster4(nodeOps[1], 1375, 129);
        IAuction.BidDetails memory bid1Details = auction.getBidDetails(bid1Id);

        assertEq(bid1Details.auctionScore, auctionScore_1375_129);
        assertEq(bid1Details.bidPrice, bidPrice_1375_129);
        assertEq(bid1Details.nodeOp, nodeOps[1]);
        assertEq(bid1Details.vcNumber, 129);
        assertEq(bid1Details.discountRate, 1375);
        assertEq(uint256(bid1Details.auctionType), uint256(IAuction.AuctionType.JOIN_CLUSTER_4));
    }

    function test_bidCluster4() external {
        // Verify there is no DV in the main auction
        assertEq(auction.getNumDVInAuction(), 0);
        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 0);

        // nodeOps[0] bids 2 times with the same parameters
        bytes32 bidId1 = _bidCluster4(nodeOps[0], 5e2, 200); // 1st
        _bidCluster4(nodeOps[0], 5e2, 200); // 1st
        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 1);

        // nodeOps[1] bids 2 times with the same parameters
        bytes32 bidId3 = _bidCluster4(nodeOps[1], 5e2, 200); // 2nd
        _bidCluster4(nodeOps[1], 5e2, 200); // 2nd

        // nodeOps[2] bids 4 times with different parameters
        bytes32 bidId5 = _bidCluster4(nodeOps[2], 5e2, 150); // 3rd
        _bidCluster4(nodeOps[2], 5e2, 149); // 3rd
        _bidCluster4(nodeOps[2], 5e2, 148); // 3rd
        _bidCluster4(nodeOps[2], 5e2, 147); // 3rd

        // nodeOps[3] bids
        bytes32 bidId9 = _bidCluster4(nodeOps[3], 14e2, 50); // 4th

        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 4);
        // Verify if the main auction tree has been filled
        assertEq(auction.getNumDVInAuction(), 1);
        
        // Store the winning cluster info
        WinningClusterInfo memory winningInfo;
        winningInfo.auctionScores = new uint256[](4);
        winningInfo.winnersAddr = new address[](4);

        // Fill auctionScores and winnersAddr tab
        (winningInfo.auctionScores[0], winningInfo.winnersAddr[0]) = (_getBidIdAuctionScore(bidId1), nodeOps[0]);
        (winningInfo.auctionScores[1], winningInfo.winnersAddr[1]) = (_getBidIdAuctionScore(bidId3), nodeOps[1]);
        (winningInfo.auctionScores[2], winningInfo.winnersAddr[2]) = (_getBidIdAuctionScore(bidId5), nodeOps[2]);
        (winningInfo.auctionScores[3], winningInfo.winnersAddr[3]) = (_getBidIdAuctionScore(bidId9), nodeOps[3]);

        // Calculate the average auction score and the ID of the winning cluster
        winningInfo.averageAuctionScore = _calculateAvgAuctionScore(winningInfo.auctionScores);
        winningInfo.clusterId = _calculateClusterId(block.timestamp, winningInfo.winnersAddr, winningInfo.averageAuctionScore);

        // Verify the winning cluster ID and Average Auction Score
        (bytes32 winningClusterId, uint256 highestAvgAuctionScore) = auction.getWinningCluster();
        assertEq(highestAvgAuctionScore, winningInfo.averageAuctionScore);
        assertEq(winningClusterId, winningInfo.clusterId);

        // Verify the `ClusterDetails` struct
        IAuction.ClusterDetails memory winningClusterDetails = auction.getClusterDetails(winningClusterId);
        assertEq(winningClusterDetails.averageAuctionScore, highestAvgAuctionScore);
        assertEq(winningClusterDetails.splitAddr, address(0));
        assertEq(uint256(winningClusterDetails.status), uint256(IAuction.ClusterStatus.INACTIVE));
        assertEq(winningClusterDetails.nodes[0].bidId, bidId1);
        assertEq(winningClusterDetails.nodes[0].currentVCNumber, 200);
        assertEq(winningClusterDetails.nodes[1].bidId, bidId3);
        assertEq(winningClusterDetails.nodes[1].currentVCNumber, 200);
        assertEq(winningClusterDetails.nodes[2].bidId, bidId5);
        assertEq(winningClusterDetails.nodes[2].currentVCNumber, 150);
        assertEq(winningClusterDetails.nodes[3].bidId, bidId9);
        assertEq(winningClusterDetails.nodes[3].currentVCNumber, 50);

        /* ============= nodeOps[4] update the main auction tree ============= */

        // nodeOps[4] bids and takes the first position
        bytes32 bidId10 = _bidCluster4(nodeOps[4], 5e2, 210); // takes the 1st position

        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 5);
        // Verify if the main auction tree has removed the last virtual cluster and add the new one
        assertEq(auction.getNumDVInAuction(), 1);

        // Update winning cluster info
        (winningInfo.auctionScores[0], winningInfo.winnersAddr[0]) = (_getBidIdAuctionScore(bidId10), nodeOps[4]);
        (winningInfo.auctionScores[1], winningInfo.winnersAddr[1]) = (_getBidIdAuctionScore(bidId1), nodeOps[0]);
        (winningInfo.auctionScores[2], winningInfo.winnersAddr[2]) = (_getBidIdAuctionScore(bidId3), nodeOps[1]);
        (winningInfo.auctionScores[3], winningInfo.winnersAddr[3]) = (_getBidIdAuctionScore(bidId5), nodeOps[2]);

        // Calculate the average auction score and the ID of the winning cluster
        winningInfo.averageAuctionScore = _calculateAvgAuctionScore(winningInfo.auctionScores);
        winningInfo.clusterId = _calculateClusterId(block.timestamp, winningInfo.winnersAddr, winningInfo.averageAuctionScore);

        // Verify the last `ClusterDetails` has been deleted from the mapping
        winningClusterDetails = auction.getClusterDetails(winningClusterId);
        assertEq(winningClusterDetails.averageAuctionScore, 0);

        // Verify the main auction tree has been updated
        (winningClusterId, highestAvgAuctionScore) = auction.getWinningCluster();
        assertEq(highestAvgAuctionScore, winningInfo.averageAuctionScore);
        assertEq(winningClusterId, winningInfo.clusterId);

        /* ============= nodeOps[5] update the main auction tree ============= */

        // nodeOps[5] bids and takes the fourth position
        bytes32 bidId11 = _bidCluster4(nodeOps[5], 5e2, 175); // takes the 4th position

        // Update winning cluster info
        (winningInfo.auctionScores[3], winningInfo.winnersAddr[3]) = (_getBidIdAuctionScore(bidId11), nodeOps[5]);

        // Calculate the average auction score and the ID of the winning cluster
        winningInfo.averageAuctionScore = _calculateAvgAuctionScore(winningInfo.auctionScores);
        winningInfo.clusterId = _calculateClusterId(block.timestamp, winningInfo.winnersAddr, winningInfo.averageAuctionScore);

        // Verify the main auction tree has been updated
        (winningClusterId, highestAvgAuctionScore) = auction.getWinningCluster();
        assertEq(highestAvgAuctionScore, winningInfo.averageAuctionScore);
        assertEq(winningClusterId, winningInfo.clusterId);

    }

    function test_getUpdateBidPrice() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Sould revert if `nodeOp` is not the owner of `bidId`
        vm.expectRevert(IAuction.SenderNotBidder.selector);
        auction.getUpdateBidPrice(nodeOps[2], bidIds[0], 10e2, 100);

        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.getUpdateBidPrice(nodeOps[0], bidIds[0], 30e2, 100);

        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.getUpdateBidPrice(nodeOps[0], bidIds[0], 10e2, 10);

        // Test update bid price when outBidding
        uint256 priceToAdd = auction.getUpdateBidPrice(nodeOps[5], bidIds[10], 10e2, 100);
        assertEq(priceToAdd, bidPrice_10e2_100 - _getBidIdBidPrice(bidIds[10]));

        // Test update bid price when downBidding
        priceToAdd = auction.getUpdateBidPrice(nodeOps[0], bidIds[0], 15e2, 50);
        assertEq(priceToAdd, 0);
    }

    function testUpdateBid_RevertCorrectly() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Sould revert if `nodeOp` is not the owner of `bidId`
        vm.expectRevert(IAuction.SenderNotBidder.selector);
        auction.updateBid(bidIds[0], 10e2, 100);

        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        vm.prank(nodeOps[0]);
        auction.updateBid(bidIds[0], 30e2, 100);

        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        vm.prank(nodeOps[0]);
        auction.updateBid(bidIds[0], 10e2, 10);
    }

    function test_updateBid_RefundSkimmingEthers() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // OutBidding and sending to many ETH
        vm.prank(nodeOps[5]);
        auction.updateBid{value: 50 ether}(bidIds[10], 10e2, 100);
        assertEq(nodeOps[5].balance, STARTING_BALANCE - bidPrice_10e2_100);

        // DownBidding and sending to many ETH
        vm.prank(nodeOps[3]);
        auction.updateBid{value: 50 ether}(bidIds[8], 10e2, 100);
        assertEq(nodeOps[3].balance, STARTING_BALANCE - bidPrice_10e2_100);
    }

    function test_updateBid_BidDetails() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // nodeOps[3] updates its bid
        _nodeOpUpdateBid(nodeOps[3], bidIds[8], 1375, 129);

        // Verify the new bidId has been added to the bidDetails mapping
        IAuction.BidDetails memory newBidDetails = auction.getBidDetails(bidIds[8]);
        assertEq(newBidDetails.auctionScore, auctionScore_1375_129);
        assertEq(newBidDetails.bidPrice, bidPrice_1375_129);
        assertEq(newBidDetails.nodeOp, nodeOps[3]);
        assertEq(newBidDetails.vcNumber, 129);
        assertEq(newBidDetails.discountRate, 1375);
        assertEq(uint256(newBidDetails.auctionType), uint256(IAuction.AuctionType.JOIN_CLUSTER_4));
    }

    function test_updateBid_updateMainAuction() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        /* ============= Number 1 (nodeOps[3]) downbids to exit the winner set ============= */

        _nodeOpUpdateBid(nodeOps[3], bidIds[8], 5e2, 149);

        // Get the winning cluster Id
        (bytes32 winningClusterId,) = auction.getWinningCluster();
        address[] memory nodesAddr = _getClusterIdNodeAddr(winningClusterId);
        assertEq(nodesAddr.length, 4);
        assertEq(nodesAddr[0], nodeOps[0]);
        assertEq(nodesAddr[1], nodeOps[1]);
        assertEq(nodesAddr[2], nodeOps[4]);
        assertEq(nodesAddr[3], nodeOps[2]);

        /* ============= Number last (nodeOps[5]) outbids to be in the winner set ============= */
        _nodeOpUpdateBid(nodeOps[5], bidIds[10], 2e2, 500);

        // Get the winning cluster Id
        (winningClusterId,) = auction.getWinningCluster();
        nodesAddr = _getClusterIdNodeAddr(winningClusterId);
        assertEq(nodesAddr.length, 4);
        assertEq(nodesAddr[0], nodeOps[5]);
        assertEq(nodesAddr[1], nodeOps[0]);
        assertEq(nodesAddr[2], nodeOps[1]);
        assertEq(nodesAddr[3], nodeOps[4]);

    }

    function testWithdrawBid_RevertWhen_SenderNotBidder() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Should revert if nodeOps[8] tries to withdraw nodeOps[0]'s bid
        vm.expectRevert(IAuction.SenderNotBidder.selector);
        vm.prank(nodeOps[8]);
        auction.withdrawBid(bidIds[0]);
    }

    function testWithdrawBid() external {
        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        /* ============= nodeOps[0] withdraw one of its bid ============= */

        vm.prank(nodeOps[0]);
        auction.withdrawBid(bidIds[0]);

        IAuction.NodeOpGlobalDetails memory nodeOpDetails = auction.getNodeOpDetails(nodeOps[0]);
        // Verify number of bids of nodeOps[0]
        assertEq(nodeOpDetails.numBidsCluster4, 1);
        // Verify the number of DV
        assertEq(auction.getNumDVInAuction(), 1);
        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 6);

        // Verify bidIds[0] has been deleted
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(bidIds[0]);
        assertEq(bidDetails.nodeOp, address(0));

        /* ============= nodeOps[0] withdraw its last bid ============= */

        vm.prank(nodeOps[0]);
        auction.withdrawBid(bidIds[1]);

        nodeOpDetails = auction.getNodeOpDetails(nodeOps[0]);
        // Verify number of bids of nodeOps[0]
        assertEq(nodeOpDetails.numBidsCluster4, 0);
        // Verify the number of DV
        assertEq(auction.getNumDVInAuction(), 1);
        // Verify the number of node ops in dv4
        assertEq(auction.dv4AuctionNumNodeOps(), 5);

        // Verify nodeOps[0] balance
        assertEq(nodeOps[0].balance, STARTING_BALANCE);

        /* ============= Verify winning cluster when nodeOps[0] is out ============= */

        // Get the winning cluster Id
        (bytes32 winningClusterId,) = auction.getWinningCluster();
        address[] memory nodesAddr = _getClusterIdNodeAddr(winningClusterId);
        assertEq(nodesAddr[0], nodeOps[3]);
        assertEq(nodesAddr[1], nodeOps[1]);
        assertEq(nodesAddr[2], nodeOps[4]);
        assertEq(nodesAddr[3], nodeOps[2]);

    }

    function testRemoveBid() external {
        // 6 nodeOps bid, 11 bids in total
        _createMultipleBids();
        assertEq(auction.getNumBids(IAuction.AuctionType.JOIN_CLUSTER_4), 11);

        // nodeOps[3] bids again two times: 13.75%, 129 days
        bytes32 bidId1 = _bidCluster4(nodeOps[3], 1375, 129);
        bytes32 bidId2 = _bidCluster4(nodeOps[3], 1375, 129);

        // Verify total number of bids
        assertEq(auction.getNumBids(IAuction.AuctionType.JOIN_CLUSTER_4), 13);

        // Should revert if not called by the Byzantine Admin
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        auction.removeBid(bidId1, auctionScore_1375_129, nodeOps[3], IAuction.AuctionType.JOIN_CLUSTER_4);

        /* ============= Byzantine Admin removes nodeOps[3]'s last bid ============= */

        vm.prank(byzantineAdmin);
        auction.removeBid(bidId2, auctionScore_1375_129, nodeOps[3], IAuction.AuctionType.JOIN_CLUSTER_4);

        // Verify total number of bids
        assertEq(auction.getNumBids(IAuction.AuctionType.JOIN_CLUSTER_4), 12);

        // Verify number of bids of nodeOps[3]
        assertEq(auction.getNodeOpDetails(nodeOps[3]).numBidsCluster4, 2);

        // Verify bidId has been deleted from mapping
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(bidId2);
        assertEq(bidDetails.nodeOp, address(0));

    }

    function test_UpdateAuctionParam() external {
        // Update auction configuration
        uint256 newExpectedDailyReturnWei = (uint256(32 ether) * 32) / (1000 * 365); // 3.2% APY
        uint16 newMaxDiscountRate = 10e2;
        uint32 newMinDuration = 60;

        auction.updateExpectedDailyReturnWei(newExpectedDailyReturnWei);
        auction.updateMinDuration(newMinDuration);
        auction.updateMaxDiscountRate(newMaxDiscountRate);

        // Check if the auction configuration is updated correctly
        assertEq(auction.expectedDailyReturnWei(), newExpectedDailyReturnWei);
        assertEq(auction.maxDiscountRate(), newMaxDiscountRate);
        assertEq(auction.minDuration(), newMinDuration);
    }

    function test_TriggerMainAuctions() external {

        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Create a StratVaultETH
        address stratVaultETH = _createStratVaultETH();

        // Verify the number of node ops and DV
        assertEq(auction.dv4AuctionNumNodeOps(), 6);
        assertEq(auction.getNumDVInAuction(), 1);

        /* ===================== FIRST DV CREATION ===================== */

        // Revert if the caller is not the StrategyModuleManager
        vm.expectRevert(IAuction.OnlyStratVaultETH.selector);
        auction.triggerAuction();

        // A main auction is triggered
        vm.prank(stratVaultETH);
        bytes32 firstClusterId = auction.triggerAuction();

        // Get the winning cluster details
        IAuction.ClusterDetails memory winningClusterDetails = auction.getClusterDetails(firstClusterId);

        // Verify a Split has been deployed
        assertNotEq(winningClusterDetails.splitAddr, address(0));

        // Get the winning bid ids
        bytes32[] memory winningBidIds = new bytes32[](4);
        winningBidIds[0] = winningClusterDetails.nodes[0].bidId;
        winningBidIds[1] = winningClusterDetails.nodes[1].bidId;
        winningBidIds[2] = winningClusterDetails.nodes[2].bidId;
        winningBidIds[3] = winningClusterDetails.nodes[3].bidId;

        // Verify the winning bids
        assertEq(winningBidIds[0], bidIds[8]);
        assertEq(winningBidIds[1], bidIds[0]);
        assertEq(winningBidIds[2], bidIds[2]);
        assertEq(winningBidIds[3], bidIds[9]);
        // Verify the winning node op addresses
        assertEq(_getBidIdNodeAddr(bidIds[8]), nodeOps[3]);
        assertEq(_getBidIdNodeAddr(bidIds[0]), nodeOps[0]);
        assertEq(_getBidIdNodeAddr(bidIds[2]), nodeOps[1]);
        assertEq(_getBidIdNodeAddr(bidIds[9]), nodeOps[4]);
        // Verify the number of VCs of each node op
        assertEq(winningClusterDetails.nodes[0].currentVCNumber, 210);
        assertEq(winningClusterDetails.nodes[1].currentVCNumber, 200);
        assertEq(winningClusterDetails.nodes[2].currentVCNumber, 200);
        assertEq(winningClusterDetails.nodes[3].currentVCNumber, 175);
        // Verify the cluster status
        assertEq(uint256(winningClusterDetails.status), uint256(IAuction.ClusterStatus.IN_CREATION));

        // Verify the number of node ops and DV
        assertEq(auction.dv4AuctionNumNodeOps(), 4);
        assertEq(auction.getNumDVInAuction(), 1);

        // Check if StakerRewards has received the bids prices
        assertEq(address(stakerRewards).balance, _getBidIdBidPrice(winningBidIds[0]) + _getBidIdBidPrice(winningBidIds[1]) + _getBidIdBidPrice(winningBidIds[2]) + _getBidIdBidPrice(winningBidIds[3]));

        /* ===================== SECOND DV CREATION ===================== */

        // A main auction is triggered
        vm.prank(stratVaultETH);
        bytes32 secondClusterId = auction.triggerAuction();

        // Get the second winning cluster details
        winningClusterDetails = auction.getClusterDetails(secondClusterId);

        // Verify a Split has been deployed
        assertNotEq(winningClusterDetails.splitAddr, address(0));

        // Get the second DV winning bid ids
        winningBidIds[0] = winningClusterDetails.nodes[0].bidId;
        winningBidIds[1] = winningClusterDetails.nodes[1].bidId;
        winningBidIds[2] = winningClusterDetails.nodes[2].bidId;
        winningBidIds[3] = winningClusterDetails.nodes[3].bidId;

        // Verify the winning bids
        assertEq(winningBidIds[0], bidIds[3]); // How the RedBlackTreeLib is implemented --> last element overwrites the first one
        assertEq(winningBidIds[1], bidIds[1]);
        assertEq(winningBidIds[2], bidIds[4]);
        assertEq(winningBidIds[3], bidIds[10]);
        // Verify the winning node op addresses
        assertEq(_getBidIdNodeAddr(bidIds[3]), nodeOps[1]);
        assertEq(_getBidIdNodeAddr(bidIds[1]), nodeOps[0]);
        assertEq(_getBidIdNodeAddr(bidIds[4]), nodeOps[2]);
        assertEq(_getBidIdNodeAddr(bidIds[10]), nodeOps[5]);
        // Verify the cluster status
        assertEq(uint256(winningClusterDetails.status), uint256(IAuction.ClusterStatus.IN_CREATION));

        // Verify the number of node ops and DV
        assertEq(auction.dv4AuctionNumNodeOps(), 1);
        assertEq(auction.getNumDVInAuction(), 0);

        /* ===================== THIRD DV CREATION FAILED ===================== */

        // Cannot trigger a new auction if not enough node operators to create a new DV
        vm.expectRevert(IAuction.MainAuctionEmpty.selector);
        vm.prank(stratVaultETH);
        auction.triggerAuction();
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
        return auction.bid{value: priceToPay}(_discountRate, _timeInDays, IAuction.AuctionType.JOIN_CLUSTER_4);
    }

    function _nodeOpUpdateBid(
        address _nodeOp,
        bytes32 _bidId,
        uint16 _newDiscountRate,
        uint32 _newTimeInDays
    ) internal {
        // Get price to pay
        uint256 priceToAdd = auction.getUpdateBidPrice(_nodeOp, _bidId, _newDiscountRate, _newTimeInDays);
        vm.prank(_nodeOp);
        auction.updateBid{value: priceToAdd}(_bidId, _newDiscountRate, _newTimeInDays);
    }

    function _getBidIdAuctionScore(bytes32 _bidId) internal view returns (uint256) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.auctionScore;
    }

    function _getBidIdNodeAddr(bytes32 _bidId) internal view returns (address) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.nodeOp;
    }

    function _getBidIdBidPrice(bytes32 _bidId) internal view returns (uint256) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.bidPrice;
    }

    function _getClusterIdNodeAddr(bytes32 _clusterId) internal view returns (address[] memory) {
        IAuction.NodeDetails[] memory nodes = auction.getClusterDetails(_clusterId).nodes;
        address[] memory nodesAddr = new address[](nodes.length);
        for (uint256 i = 0; i < nodes.length; i++) {
            nodesAddr[i] = _getBidIdNodeAddr(nodes[i].bidId);
        }
        return nodesAddr;
    }

    function _calculateAvgAuctionScore(uint256[] memory _auctionScores) internal pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < _auctionScores.length;) {
            sum += _auctionScores[i];
            unchecked {
                ++i;
            }
        }
        return sum / _auctionScores.length;
    }

    function _calculateClusterId(
        uint256 _timestamp,
        address[] memory _addresses,
        uint256 _averageAuctionScore
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_timestamp, _averageAuctionScore, _addresses));
    }

    function _createMultipleBids() internal returns (bytes32[] memory) {
        bytes32[] memory bidIds = new bytes32[](11);

        // nodeOps[0] bids 2 times with the same parameters
        bidIds[0] = _bidCluster4(nodeOps[0], 5e2, 200); // 2nd
        bidIds[1] = _bidCluster4(nodeOps[0], 5e2, 200); // 2nd

        // nodeOps[1] bids 2 times with the same parameters
        bidIds[2] = _bidCluster4(nodeOps[1], 5e2, 200); // 3rd
        bidIds[3] = _bidCluster4(nodeOps[1], 5e2, 200); // 3rd

        // nodeOps[2] bids 4 times with different parameters
        bidIds[4] = _bidCluster4(nodeOps[2], 5e2, 150); // 5th
        bidIds[5] = _bidCluster4(nodeOps[2], 5e2, 149); // 5th
        bidIds[6] = _bidCluster4(nodeOps[2], 5e2, 148); // 5th
        bidIds[7] = _bidCluster4(nodeOps[2], 5e2, 147); // 5th

        // nodeOps[3] bids and takes the first position
        bidIds[8] = _bidCluster4(nodeOps[3], 5e2, 210); // 1st

        // nodeOps[4] bids and takes the fourth position
        bidIds[9] = _bidCluster4(nodeOps[4], 5e2, 175); // 4th

        // nodeOps[5] bids
        bidIds[10] = _bidCluster4(nodeOps[5], 14e2, 50); // 6th

        return bidIds;
    }

    function _createStratVaultETH() internal returns (address) {
        vm.prank(alice);
        return strategyVaultManager.createStratVaultETH(true, true, ELOperator1, address(0));
    }

}
