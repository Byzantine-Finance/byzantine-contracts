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
        assertEq(bid0Details.vcNumber, 100);
        assertEq(bid0Details.discountRate, 10e2);
        assertEq(uint256(bid0Details.auctionType), uint256(IAuction.AuctionType.JOIN_CLUSTER_4));

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

    function test_TriggerMainAuctions() external {

        // 6 nodeOps bid, 11 bids in total
        bytes32[] memory bidIds = _createMultipleBids();

        // Verify the number of node ops and DV
        assertEq(auction.dv4AuctionNumNodeOps(), 6);
        assertEq(auction.getNumDVInAuction(), 1);

        /* ===================== FIRST DV CREATION ===================== */

        // Revert if the caller is not the StrategyModuleManager
        vm.expectRevert(IAuction.OnlyStratVaultManagerOrStratVaultETH.selector);
        auction.triggerAuction();

        // A main auction is triggered
        vm.prank(address(strategyModuleManager));
        bytes32 firstClusterId = auction.triggerAuction();

        // Get the winning cluster details
        IAuction.ClusterDetails memory winningClusterDetails = auction.getClusterDetails(firstClusterId);

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

        /* ===================== SECOND DV CREATION ===================== */

        // A main auction is triggered
        vm.prank(address(strategyModuleManager));
        bytes32 secondClusterId = auction.triggerAuction();

        // Get the second winning cluster details
        winningClusterDetails = auction.getClusterDetails(secondClusterId);

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
        vm.prank(address(strategyModuleManager));
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
        uint256 priceToPay = auction.getPriceToPayCluster4(_nodeOp, _discountRate, _timeInDays);
        vm.prank(_nodeOp);
        return   auction.bidCluster4{value: priceToPay}(_discountRate, _timeInDays);
    }

    function _getBidIdAuctionScore(bytes32 _bidId) internal view returns (uint256) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.auctionScore;
    }

    function _getBidIdNodeAddr(bytes32 _bidId) internal view returns (address) {
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        return bidDetails.nodeOp;
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

}
