// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "./ByzantineDeployer.t.sol";
import "../src/interfaces/IAuction.sol";
import "../src/interfaces/IStrategyModule.sol";

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

    function test_getPriceToPayCluster4() external {
        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.getPriceToPayCluster4(nodeOps[0], 25e2, 200);
        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.getPriceToPayCluster4(nodeOps[0], 10e2, 20);

        // Test price to pay for a whitelisted nodeOp
        uint256 priceToPayWhitelisted = auction.getPriceToPayCluster4(nodeOps[0], 10e2, 100);
        assertEq(priceToPayWhitelisted, bidPrice_10e2_100);

        // Test price to pay for a non-whitelisted nodeOp
        uint256 priceToPayNotWhitelisted = auction.getPriceToPayCluster4(alice, 10e2, 100);
        assertEq(priceToPayNotWhitelisted, bidPrice_10e2_100 + BOND);
    }

    function testBid_RevertCorrectly() external {
        // Should revert if non-whitelisted
        vm.expectRevert(IAuction.NotWhitelisted.selector);
        vm.prank(alice);
        auction.bidCluster4(10e2, 100);

        // Should revert if discountRate too high
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        vm.prank(nodeOps[0]);
        auction.bidCluster4(25e2, 200);

        // Should revert if duration too short
        vm.expectRevert(IAuction.DurationTooShort.selector);
        vm.prank(nodeOps[0]);
        auction.bidCluster4(10e2, 20);

        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        vm.prank(nodeOps[0]);
        auction.bidCluster4{value: 0 ether}(10e2, 100);
    }

    function testBid_RefundTheSkimmingEthers() external {
        // nodeOps[0] bids
        uint256 priceToPay = auction.getPriceToPayCluster4(nodeOps[0], 11e2, 99);
        vm.prank(nodeOps[0]);
        auction.bidCluster4{value: (priceToPay + 1 ether)}(11e2, 99);

        // Verify the balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE - priceToPay);
        // Verify the balance of the Escrow contract
        assertEq(address(escrow).balance, priceToPay);
    }

    function test_BidDetails() external {
        // First bid parameters: 10%, 100 days
        bytes32 bid0Id = _bidCluster4(nodeOps[0], 10e2, 100);
        IAuction.BidDetails memory bid0Details = auction.getBidDetails(bid0Id);

        assertEq(bid0Details.auctionScore, auctionScore_10e2_100);
        assertEq(bid0Details.bidPrice, bidPrice_10e2_100);
        assertEq(bid0Details.nodeOp, nodeOps[0]);
        assertEq(bid0Details.vcNumbers, 100);
        assertEq(bid0Details.discountRate, 10e2);
        assertEq(uint256(bid0Details.auctionType), uint256(IAuction.AuctionType.JOIN_CLUSTER_4));

        // Second bid parameter: 13.75%, 129 days
        bytes32 bid1Id = _bidCluster4(nodeOps[1], 1375, 129);
        IAuction.BidDetails memory bid1Details = auction.getBidDetails(bid1Id);

        assertEq(bid1Details.auctionScore, auctionScore_1375_129);
        assertEq(bid1Details.bidPrice, bidPrice_1375_129);
        assertEq(bid1Details.nodeOp, nodeOps[1]);
        assertEq(bid1Details.vcNumbers, 129);
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

        // Verify the `ClsuterDetails` struct
        IAuction.ClusterDetails memory winningClusterDetails = auction.getClusterDetails(winningClusterId);
        assertEq(winningClusterDetails.averageAuctionScore, highestAvgAuctionScore);
        assertEq(winningClusterDetails.nodes[0].pendingBidId, bidId1);
        assertEq(winningClusterDetails.nodes[1].pendingBidId, bidId3);
        assertEq(winningClusterDetails.nodes[2].pendingBidId, bidId5);
        assertEq(winningClusterDetails.nodes[3].pendingBidId, bidId9);

        // Verify latestWonBidId is null
        assertEq(winningClusterDetails.nodes[3].latestWonBidId, bytes32(0));

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

    // function testUpdateBid_RevertWhen_WrongAuctionScore_And_WrongBidParameters() external {
    //     // nodeOps[0] bids
    //     (uint16[] memory discountRate, uint32[] memory time) = _createOneBidParamArray(11e2, 200);
    //     uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[0], discountRate, time));

    //     vm.startPrank(nodeOps[0]);
    //     // nodeOps[0] updates its bid with wrong discountRate
    //     vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
    //     auction.updateOneBid{value: 8 ether}(auctionScore[0], 25e2, 200);

    //     // nodeOps[0] updates its bid with wrong time
    //     vm.expectRevert(IAuction.DurationTooShort.selector);
    //     auction.updateOneBid{value: 8 ether}(auctionScore[0], 11e2, 10);

    //     // nodeOps[0] updates its bid with wrong auctionScore
    //     vm.expectRevert(bytes("Wrong node op auctionScore"));
    //     auction.updateOneBid{value: 8 ether}(++auctionScore[0], 12e2, 200);

    //     vm.stopPrank();
    // }

    // function testUpdateBid_Outbid_RevertWhen_NotEnoughEthSent() external {
    //     // nodeOps[9] bids
    //     (uint16[] memory discountRate, uint32[] memory time) = _createOneBidParamArray(11e2, 200);
    //     uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[9], discountRate, time));

    //     // nodeOps[9] updates its bid
    //     uint256 amountToAdd = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 5e2, 200);
    //     vm.prank(nodeOps[9]);
    //     vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
    //     auction.updateOneBid{value: (amountToAdd - 0.001 ether)}(auctionScore[0], 5e2, 200);
    // }

    // function testUpdateBid_Outbid_RefundTheSkimmingEthers() external {
    //     // Verify the initial balance of nodeOps[9]
    //     assertEq(nodeOps[9].balance, STARTING_BALANCE);

    //     // nodeOps[9] bids
    //     uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));

    //     // Verify the balance of nodeOps[9] after bidding
    //     assertEq(nodeOps[9].balance, STARTING_BALANCE - bidPrice_one_Bid[0]);
    //     // Verify the balance of escrow contract after nodeOps[9] bid
    //     assertEq(address(escrow).balance, bidPrice_one_Bid[0]);

    //     // nodeOps[9] updates its bid (outbids)
    //     uint256 amountToAdd = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 10e2, 200);
    //     vm.prank(nodeOps[9]);
    //     auctionScore[0] = auction.updateOneBid{value: (amountToAdd + 2 ether)}(auctionScore[0], 10e2, 200);

    //     // Verify the balance of nodeOps[9] after updating its bid
    //     assertEq(nodeOps[9].balance, STARTING_BALANCE - (bidPrice_one_Bid[0] + amountToAdd));
    //     // Verify the balance of escrow contract after nodeOps[9] updates its bid
    //     assertEq(address(escrow).balance, bidPrice_one_Bid[0] + amountToAdd);

    //     // nodeOps[9] decreases its bid
    //     uint256 amountToAdd2 = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 10e2, 35); // 0 ether
    //     vm.prank(nodeOps[9]);
    //     auction.updateOneBid{value: amountToAdd2 + 0.001 ether}(auctionScore[0], 10e2, 35);
    //     // Verify if nodeOps[9] has been refunded
    //     (uint16[] memory discountRate, uint32[] memory time) = _createOneBidParamArray(10e2, 35);
    //     uint256 refundAmount = (bidPrice_one_Bid[0] + amountToAdd) - auction.getPriceToPay(nodeOps[9], discountRate, time); // nodeOps[9] is whitelisted
    //     assertEq(nodeOps[9].balance, STARTING_BALANCE - (bidPrice_one_Bid[0] + amountToAdd + amountToAdd2) + refundAmount);
    //     // Verify the balance of escrow contract after nodeOps[9] updates its bid
    //     assertEq(address(escrow).balance, bidPrice_one_Bid[0] + amountToAdd - refundAmount);
    // }

    // function testUpdateBid_NodeOpAuctionDetails() external {
    //     // nodeOps[9] bids
    //     uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));

    //     // nodeOps[9] updates its bid
    //     uint256 newAuctionScoreNodeOp9 = _nodeOpUpdateBid(nodeOps[9], auctionScoreNodeOp9[0], 10e2, 60);

    //     // Verify number of bids of nodeOps[9]
    //     assertEq(auction.numNodeOpsInAuction(), 1);
    //     assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 1);

    //     // Verify auctionScoreNodeOp9[0] is not in nodeOps[9] mapping
    //     assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);
    //     assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);

    //     // Verify newAuctionScoreNodeOp9 in nodeOps[9] mapping
    //     uint256[] memory newBidPrice = auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], newAuctionScoreNodeOp9);
    //     assertEq(newBidPrice.length, 1);
    //     assertEq(newBidPrice[0], 43791780821917800);
    //     uint32[] memory newVc = auction.getNodeOpAuctionScoreVcs(nodeOps[9], newAuctionScoreNodeOp9);
    //     assertEq(newVc.length, 1);
    //     assertEq(newVc[0], 60);

    //     // nodeOps[5] bids five times
    //     uint256[] memory auctionScoreNodeOp5 = _nodeOpBid(NodeOpBid(nodeOps[5], five_SameDiffDiscountRates, five_SameDiffTimesInDays));

    //     // nodeOps[5] updates its first bid
    //     uint256 newAuctionScoreNodeOp5 = _nodeOpUpdateBid(nodeOps[5], auctionScoreNodeOp5[0], 10e2, 60);

    //     // Verify number of bids of nodeOps[5]
    //     assertEq(auction.numNodeOpsInAuction(), 2);
    //     assertEq(auction.getNodeOpBidNumber(nodeOps[5]), 5);

    //     // Verify auctionScoreNodeOp5[0] mappings
    //     assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);
    //     assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);

    //     // Verify newAuctionScoreNodeOp5 in nodeOps[5] mapping
    //     uint256[] memory newBidPriceNodeOp5 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], newAuctionScoreNodeOp5);
    //     assertEq(newBidPriceNodeOp5.length, 1);
    //     assertEq(newBidPriceNodeOp5[0], 43791780821917800);
    //     uint32[] memory newVcNodeOp5 = auction.getNodeOpAuctionScoreVcs(nodeOps[5], newAuctionScoreNodeOp5);
    //     assertEq(newVcNodeOp5.length, 1);
    //     assertEq(newVcNodeOp5[0], 60);

    //     // nodeOps[5] updates its last bid
    //     _nodeOpUpdateBid(nodeOps[5], auctionScoreNodeOp5[4], 5e2, 30);

    //     // Verify auctionScoreNodeOp5[0] mappings
    //     assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 3);
    //     assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 3);
    // }

    // function testWithdrawBid_RevertWhen_WrongAuctionScore() external {
    //     // nodeOps[9] bids
    //     uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));
    //     vm.expectRevert(bytes("Wrong node op auctionScore"));
    //     vm.prank(nodeOps[9]);
    //     auction.withdrawBid(++auctionScoreNodeOp9[0]);
    // }

    // function testWithdrawBid() external {
    //     // nodeOps[9] bids
    //     uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));
    //     // nodeOps[9] withdraw its bid
    //     vm.prank(nodeOps[9]);
    //     auction.withdrawBid(auctionScoreNodeOp9[0]);

    //     // Verify number of bids of nodeOps[9]
    //     assertEq(auction.numNodeOpsInAuction(), 0);
    //     assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 0);

    //     // Verify auctionScoreNodeOp9[0] is not in nodeOps[9] mapping
    //     assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);
    //     assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);

    //     // Verify nodeOps[9] balance
    //     assertEq(nodeOps[9].balance, STARTING_BALANCE);

    //     // nodeOps[5] bids five times
    //     uint256[] memory auctionScoreNodeOp5 = _nodeOpBid(NodeOpBid(nodeOps[5], five_SameDiffDiscountRates, five_SameDiffTimesInDays));
    //     // nodeOps[5] withdraw its bid
    //     vm.prank(nodeOps[5]);
    //     auction.withdrawBid(auctionScoreNodeOp5[0]);

    //     // Verify number of bids of nodeOps[5]
    //     assertEq(auction.numNodeOpsInAuction(), 1);
    //     assertEq(auction.getNodeOpBidNumber(nodeOps[5]), 4);

    //     // Verify auctionScoreNodeOp5[0] is not in nodeOps[5] mapping
    //     assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);
    //     assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);

    //     // Verify nodeOps[5] balance
    //     uint256 remainingBidPrice = 2 * (bidPrices_five_SameDiffBids[2] + bidPrices_five_SameDiffBids[3]);
    //     assertEq(nodeOps[5].balance, STARTING_BALANCE - (remainingBidPrice + 4 * BOND));
    // }

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

    // function test_updateClusterSize() external {
    //     // Update cluster size to 7
    //     auction.updateClusterSize(7);
    //     assertEq(auction.clusterSize(), 7);
    // }

    // function test_getAuctionWinners_FourDiffBids() external {
    //     // 4 node ops bid
    //     uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBidDiff();

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 4);
        
    //     // Get the total bids price
    //     uint256 totalBidsPrice;
    //     uint256 totalBonds = 3 * BOND; // Only 1 node op is whitelisted
    //     for (uint i = 0; i < nodeOpsAuctionScore.length - 1; i++) {
    //        totalBidsPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0])[0];
    //     }
    //     totalBidsPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], nodeOpsAuctionScore[3][0])[0];

    //     // Verify escrow received bids price + bonds
    //     assertEq(address(escrow).balance, totalBidsPrice + totalBonds);

    //     // Revert if not SrategyModuleManager calls createDV
    //     vm.expectRevert(IAuction.OnlyStrategyModuleManager.selector);
    //     auction.getAuctionWinners();

    //     // DV: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[9]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV = auction.getAuctionWinners();

    //     // Verify Escrow contract has been drained
    //     assertEq(address(escrow).balance, totalBonds);
        
    //     // Verify the DV composition
    //     for (uint i = 0; i < winnersDV.length - 1; i++) {
    //        assertEq(winnersDV[i].eth1Addr, nodeOps[i]);
    //     }
    //     assertEq(winnersDV[3].eth1Addr, nodeOps[9]);

    //     // Verify the node ops details has been updated correctly
    //     for (uint256 i = 0; i < winnersDV.length - 1; i++) {
    //         assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 0);
    //         uint256[] memory nodeOpBid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //         uint32[] memory nodeOpVc = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //         assertEq(nodeOpBid.length, 0);
    //         assertEq(nodeOpVc.length, 0);
    //     }
    //     assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 0);
    //     uint256[] memory nodeOp9Bid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], nodeOpsAuctionScore[3][0]);
    //     uint32[] memory nodeOp9Vc = auction.getNodeOpAuctionScoreVcs(nodeOps[9], nodeOpsAuctionScore[3][0]);
    //     assertEq(nodeOp9Bid.length, 0);
    //     assertEq(nodeOp9Vc.length, 0);

    //     // Revert when not enough nodeOps in Auction
    //     assertEq(auction.numNodeOpsInAuction(), 0);
    //     vm.prank(address(strategyModuleManager));
    //     vm.expectRevert(bytes("Not enough node ops in auction"));
    //     auction.getAuctionWinners();

    // }

    // function test_getAuctionWinners_EightSameBids() external {
    //     // 4 node ops bids 2 times (all of them have the same bids)
    //     uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBidSame();

    //     // Calculate the price paid by node ops
    //     uint256 totalBonds = 8 * BOND; // Every node op has 2 bonds
    //     uint256 totalFirstBidPrice;
    //     for (uint i = 0; i < nodeOpsAuctionScore.length; i++) {
    //         totalFirstBidPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0])[0];
    //     }
    //     uint256 totalSecondBidPrice;
    //     for (uint i = 0; i < nodeOpsAuctionScore.length; i++) {
    //         totalSecondBidPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][1])[0];
    //     }
    //     // Verify escrow received bids price + bonds
    //     assertEq(address(escrow).balance, totalFirstBidPrice + totalSecondBidPrice + totalBonds);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 4);

    //     /* ============= 1st DV ============= */

    //     // DV1: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV1 = auction.getAuctionWinners();

    //     // Verify the DV composition
    //     assertEq(winnersDV1[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV1[1].eth1Addr, nodeOps[1]);
    //     assertEq(winnersDV1[2].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV1[3].eth1Addr, nodeOps[3]);

    //     // Verify escrow received bids price + bonds
    //     assertEq(address(escrow).balance, totalSecondBidPrice + totalBonds);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 4);

    //     /* ============= 2nd DV ============= */

    //     // DV2: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV2 = auction.getAuctionWinners();

    //     // Verify the DV composition
    //     assertEq(winnersDV2[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV2[1].eth1Addr, nodeOps[3]);
    //     assertEq(winnersDV2[2].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV2[3].eth1Addr, nodeOps[1]);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 0);

    //     // Verify escrow has been drained
    //     assertEq(address(escrow).balance, totalBonds);

    // }

    // function test_getAuctionWinners_ThreeSameBids_WinnerAlreadyExists() external {
    //     // 4 node ops bid (three bids are similar)
    //     uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBid_ThreeSame_WinnerAlreadyExists();

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 4);

    //     // DV: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV = auction.getAuctionWinners();
        
    //     // Verify the DV composition
    //     assertEq(winnersDV[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV[1].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV[2].eth1Addr, nodeOps[1]);
    //     assertEq(winnersDV[3].eth1Addr, nodeOps[3]);

    //     // Verify the node ops details has been updated correctly
    //     for (uint256 i = 0; i < winnersDV.length; i++) {
    //         if (i != 2) {
    //             assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 0);
    //             uint256[] memory nodeOpBid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //             uint32[] memory nodeOpVc = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //             assertEq(nodeOpBid.length, 0);
    //             assertEq(nodeOpVc.length, 0);
    //         } else {
    //             assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 1);
    //             uint256[] memory nodeOp2Bid1 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //             uint32[] memory nodeOp2Vc1 = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
    //             assertEq(nodeOp2Bid1.length, 0);
    //             assertEq(nodeOp2Vc1.length, 0);
    //             uint256[] memory nodeOp2Bid2 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][1]);
    //             uint32[] memory nodeOp2Vc2 = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][1]);
    //             assertEq(nodeOp2Bid2.length, 1);
    //             assertEq(nodeOp2Vc2.length, 1);
    //             assertEq(nodeOp2Bid2[0], bidPrice_one_Bid[0]);
    //             assertEq(nodeOp2Vc2[0], 100);
    //         }
    //     }

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 1);
    // }

    // function test_CreateMultipleDVs() external {
    //     // 10 node ops bid (real life example)
    //     uint256[][] memory nodeOpsAuctionScore = _10NodeOpsBid();

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 10);

    //     /* ===================== FIRST DV ===================== */

    //     // DV1: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[4]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV1 = auction.getAuctionWinners();
        
    //     // Verify the DV1 composition
    //     assertEq(winnersDV1[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV1[1].eth1Addr, nodeOps[6]);
    //     assertEq(winnersDV1[2].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV1[3].eth1Addr, nodeOps[4]);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 9);

    //     /* ===================== SECOND DV ===================== */

    //     // DV2: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[5]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV2 = auction.getAuctionWinners();
        
    //     // Verify the DV2 composition
    //     assertEq(winnersDV2[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV2[1].eth1Addr, nodeOps[6]);
    //     assertEq(winnersDV2[2].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV2[3].eth1Addr, nodeOps[5]);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 8);

    //     /* ===================== THIRD DV ===================== */

    //     // DV2: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[1]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV3 = auction.getAuctionWinners();
        
    //     // Verify the DV3 composition
    //     assertEq(winnersDV3[0].eth1Addr, nodeOps[0]);
    //     assertEq(winnersDV3[1].eth1Addr, nodeOps[6]);
    //     assertEq(winnersDV3[2].eth1Addr, nodeOps[2]);
    //     assertEq(winnersDV3[3].eth1Addr, nodeOps[1]);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 5);

    //     /* ===================== FOURTH DV ===================== */

    //     // DV2: nodeOps[1], nodeOps[3], nodeOps[7], nodeOps[9]
    //     vm.prank(address(strategyModuleManager));
    //     IStrategyModule.Node[] memory winnersDV4 = auction.getAuctionWinners();
        
    //     // Verify the DV4 composition
    //     assertEq(winnersDV4[0].eth1Addr, nodeOps[1]);
    //     assertEq(winnersDV4[1].eth1Addr, nodeOps[3]);
    //     assertEq(winnersDV4[2].eth1Addr, nodeOps[7]);
    //     assertEq(winnersDV4[3].eth1Addr, nodeOps[9]);

    //     // Verify the number of node ops in the auction
    //     assertEq(auction.numNodeOpsInAuction(), 3);

    //     /* ===================== NOT ENOUGH NODE OPS IN AUCTION ===================== */
    //     vm.prank(address(strategyModuleManager));
    //     vm.expectRevert(bytes("Not enough node ops in auction"));
    //     auction.getAuctionWinners();

    //     // Verify remaining bids of nodeOps[3]
    //     uint256[] memory nodeOp3Bid1 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[3], nodeOpsAuctionScore[3][1]);
    //     uint32[] memory nodeOp3Vc1 = auction.getNodeOpAuctionScoreVcs(nodeOps[3], nodeOpsAuctionScore[3][1]);
    //     assertEq(nodeOp3Bid1.length, 2);
    //     assertEq(nodeOp3Vc1.length, 2);
    //     assertEq(nodeOp3Bid1[0], bidPrices_five_SameDiffBids[0]);
    //     assertEq(nodeOp3Bid1[1], bidPrices_five_SameDiffBids[1]);
    //     assertEq(nodeOp3Vc1[0], 30);
    //     assertEq(nodeOp3Vc1[1], 30);
    //     uint256[] memory nodeOp3Bid2 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[3], nodeOpsAuctionScore[3][4]);
    //     uint32[] memory nodeOp3Vc2 = auction.getNodeOpAuctionScoreVcs(nodeOps[3], nodeOpsAuctionScore[3][4]);
    //     assertEq(nodeOp3Bid2.length, 2);
    //     assertEq(nodeOp3Vc2.length, 2);
    //     assertEq(nodeOp3Bid2[0], bidPrices_five_SameDiffBids[4]);
    //     assertEq(nodeOp3Bid2[1], bidPrices_five_SameDiffBids[4]);
    //     assertEq(nodeOp3Vc2[0], 30);
    //     assertEq(nodeOp3Vc2[1], 30);

    // }

    // /* ===================== HELPER FUNCTIONS ===================== */

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

    function _getBidIdAuctionScore(bytes32 _bidId) internal view returns (uint256) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.auctionScore;
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

    // function _nodeOpUpdateBid(
    //     address _nodeOp,
    //     uint256 _auctionScore,
    //     uint16 _newDiscountRate,
    //     uint32 _newTimeInDays
    // ) internal returns (uint256) {
    //     // Get price to pay
    //     uint256 priceToPay = auction.getUpdateOneBidPrice(_nodeOp, _auctionScore, _newDiscountRate, _newTimeInDays);
    //     vm.prank(_nodeOp);
    //     return auction.updateOneBid{value: priceToPay}(_auctionScore, _newDiscountRate, _newTimeInDays);
    // }

    // function _nodeOpWithdrawBid(address _nodeOp) internal {
    //     vm.prank(_nodeOp);
    //     auction.withdrawBid();
    // }

    // function _4NodeOpsBidDiff() internal returns (uint256[][] memory) {
    //     (uint16[] memory first_DR, uint32[] memory first_time) = _createOneBidParamArray(11e2, 400);
    //     (uint16[] memory second_DR, uint32[] memory second_time) = _createOneBidParamArray(11e2, 300);
    //     (uint16[] memory third_DR, uint32[] memory third_time) = _createOneBidParamArray(11e2, 200);
    //     (uint16[] memory fourth_DR, uint32[] memory fourth_time) = _createOneBidParamArray(11e2, 100);

    //     NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
    //     nodeOpsBid[0] = NodeOpBid(nodeOps[0], first_DR, first_time); // 1st
    //     nodeOpsBid[1] = NodeOpBid(nodeOps[1], second_DR, second_time); // 2nd
    //     nodeOpsBid[2] = NodeOpBid(nodeOps[2], third_DR, third_time); // 3rd
    //     nodeOpsBid[3] = NodeOpBid(nodeOps[9], fourth_DR, fourth_time); // 4th
        
    //     return _nodeOpsBid(nodeOpsBid);
    // }

    // function _4NodeOpsBidSame() internal returns (uint256[][] memory) {
    //     (uint16[] memory discounts, uint32[] memory times) = _createTwoBidsParamArray(11e2, 100, 11e2, 100);

    //     NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
    //     nodeOpsBid[0] = NodeOpBid(nodeOps[0], discounts, times); // 1st // 2nd
    //     nodeOpsBid[1] = NodeOpBid(nodeOps[1], discounts, times); // 1st // 2nd
    //     nodeOpsBid[2] = NodeOpBid(nodeOps[2], discounts, times); // 1st // 2nd
    //     nodeOpsBid[3] = NodeOpBid(nodeOps[3], discounts, times); // 1st // 2nd

    //     return _nodeOpsBid(nodeOpsBid);
    // }

    // function _4NodeOpsBid_ThreeSame_WinnerAlreadyExists() internal returns (uint256[][] memory) {
    //     (uint16[] memory first_DR, uint32[] memory first_time) = _createOneBidParamArray(11e2, 400);
    //     (uint16[] memory second_DR, uint32[] memory second_time) = _createTwoBidsParamArray(11e2, 400, 10e2, 100);
    //     (uint16[] memory third_DR, uint32[] memory third_time) = _createOneBidParamArray(11e2, 100);

    //     NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
    //     nodeOpsBid[0] = NodeOpBid(nodeOps[0], first_DR, first_time); // 1st
    //     nodeOpsBid[1] = NodeOpBid(nodeOps[1], first_DR, first_time); // 1st
    //     nodeOpsBid[2] = NodeOpBid(nodeOps[2], second_DR, second_time); // 1st // 2nd -> not taken cause node op already exists
    //     nodeOpsBid[3] = NodeOpBid(nodeOps[3], third_DR, third_time); // 4th
        
    //     return _nodeOpsBid(nodeOpsBid);
    // }

    // function _10NodeOpsBid() internal returns (uint256[][] memory) {
    //     (uint16[] memory small_DR, uint32[] memory small_time) = _createOneBidParamArray(15e2, 30);

    //     NodeOpBid[] memory nodeOpBids = new NodeOpBid[](10);
    //     nodeOpBids[0] = NodeOpBid(nodeOps[0], three_DiffDiscountRates, three_DiffTimesInDays); // 1st // 5th // 9th --
    //     nodeOpBids[1] = NodeOpBid(nodeOps[1], five_SameDiffDiscountRates, five_SameDiffTimesInDays); // 12th // 13th
    //     nodeOpBids[2] = NodeOpBid(nodeOps[2], three_DiffDiscountRates, three_DiffTimesInDays); // 3rd // 7th // 11th --
    //     nodeOpBids[3] = NodeOpBid(nodeOps[3], five_SameDiffDiscountRates, five_SameDiffTimesInDays); // 14th 
    //     nodeOpBids[4] = NodeOpBid(nodeOps[4], one_DiscountRates, one_TimesInDays);  // 4th --
    //     nodeOpBids[5] = NodeOpBid(nodeOps[5], one_DiscountRates, one_TimesInDays);  // 8th --
    //     nodeOpBids[6] = NodeOpBid(nodeOps[6], three_DiffDiscountRates, three_DiffTimesInDays);  // 2nd // 6th // 10th --
    //     nodeOpBids[7] = NodeOpBid(nodeOps[7], small_DR, small_time);  // 15th --
    //     nodeOpBids[8] = NodeOpBid(nodeOps[8], small_DR, small_time);  
    //     nodeOpBids[9] = NodeOpBid(nodeOps[9], small_DR, small_time);  // 16th --
        
    //     return _nodeOpsBid(nodeOpBids);
    // }

}
