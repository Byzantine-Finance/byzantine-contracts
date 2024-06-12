// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "./ByzantineDeployer.t.sol";
import "../src/interfaces/IAuction.sol";
import "../src/interfaces/IStrategyModule.sol";

contract AuctionTest is ByzantineDeployer {

    uint256 constant STARTING_BALANCE = 100 ether;
    uint256 constant BOND = 1 ether;

    uint256[] one_DiscountRates = new uint256[](1);
    uint256[] one_TimesInDays = new uint256[](1);
    uint256[1] bidPrice_one_Bid;

    uint256[] three_DiffDiscountRates = new uint256[](3);
    uint256[] three_DiffTimesInDays = new uint256[](3);
    uint256[3] auctionScores_three_DiffBids;
    uint256[3] bidPrices_three_DiffBids;

    uint256[] five_SameDiffDiscountRates = new uint256[](5);
    uint256[] five_SameDiffTimesInDays = new uint256[](5);
    uint256[5] bidPrices_five_SameDiffBids;

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Fill the node operators' balance
        for (uint i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // nodeOps[9] is whitelisted
        auction.addNodeOpToWhitelist(nodeOps[9]);

        // Initialize the discountRates and timesInDays arrays
        one_DiscountRates[0] = 10e2;
        one_TimesInDays[0] = 100;
        // Auction Score one bid: [806583073624143]; // Printed from Auction contract
        bidPrice_one_Bid = [72986301369863000]; // Calculated manually

        three_DiffDiscountRates[0] = 7e2;
        three_DiffDiscountRates[1] = 9e2;
        three_DiffDiscountRates[2] = 12e2;
        three_DiffTimesInDays[0] = 100;
        three_DiffTimesInDays[1] = 150;
        three_DiffTimesInDays[2] = 200;
        auctionScores_three_DiffBids = [833469176078281, 857337580166460, 871559446929509]; // Printed from Auction contract
        bidPrices_three_DiffBids = [75419178082191700, 110695890410958750, 142728767123287600]; // Calculated manually

        five_SameDiffDiscountRates[0] = 5e2;
        five_SameDiffDiscountRates[1] = 5e2;
        five_SameDiffDiscountRates[2] = 5e2;
        five_SameDiffDiscountRates[3] = 13e2;
        five_SameDiffDiscountRates[4] = 13e2;
        five_SameDiffTimesInDays[0] = 30;
        five_SameDiffTimesInDays[1] = 30;
        five_SameDiffTimesInDays[2] = 30;
        five_SameDiffTimesInDays[3] = 30;
        five_SameDiffTimesInDays[4] = 30;
        // Auction Score five same diff bids: [793861565530208, 793861565530208, 793861565530208, 727010065275032, 727010065275032];
        bidPrices_five_SameDiffBids = [23112328767123270, 23112328767123270, 23112328767123270, 21166027397260260, 21166027397260260]; // Calculated manually
    }

    function test_AddToWhitelist() external {
        // First, nodeOps[0] wants to add himself to the whitelist
        vm.prank(nodeOps[0]);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        auction.addNodeOpToWhitelist(nodeOps[0]);

        // Byzantine adds nodeOps[0] to the whitelist
        auction.addNodeOpToWhitelist(nodeOps[0]);
        assertTrue(auction.isWhitelisted(nodeOps[0]));

        // Should revert if Byzantine add a second time nodeOps[0] to the whitelist
        vm.expectRevert(IAuction.AlreadyWhitelisted.selector);
        auction.addNodeOpToWhitelist(nodeOps[0]);
    }

    function test_RemoveFromWhitelist() external {
        // Byzantine add nodeOps[0] to the whitelist
        auction.addNodeOpToWhitelist(nodeOps[0]);

        // Should revert if Byzantine remove a non-whitelisted address
        vm.expectRevert(IAuction.NotWhitelisted.selector);
        auction.removeNodeOpFromWhitelist(nodeOps[1]);

        // Byzantine removes nodeOps[0] from the whitelist
        auction.removeNodeOpFromWhitelist(nodeOps[0]);
        assertFalse(auction.isWhitelisted(nodeOps[0]));
    }

    function test_getPriceToPay() external {
        // Should revert if not same entries length
        vm.expectRevert(bytes("_discountRates and _timesInDays must have the same length"));
        auction.getPriceToPay(nodeOps[0], five_SameDiffDiscountRates, one_TimesInDays);

        // Test price to pay for a whitelisted nodeOp and a non-whitelisted one
        uint256 priceToPayWhitelisted = auction.getPriceToPay(nodeOps[9], five_SameDiffDiscountRates, five_SameDiffTimesInDays);
        uint256 expectedPriceToPayWhitelisted;
        for (uint i = 0; i < five_SameDiffDiscountRates.length; i++) {
            expectedPriceToPayWhitelisted += bidPrices_five_SameDiffBids[i];
        }
        assertEq(priceToPayWhitelisted, expectedPriceToPayWhitelisted);
        uint256 priceToPayNotWhitelisted = auction.getPriceToPay(nodeOps[1], five_SameDiffDiscountRates, five_SameDiffTimesInDays);
        assertEq(priceToPayNotWhitelisted, expectedPriceToPayWhitelisted + (5 * BOND));
    }

    function testBid_RevertWhen_WrongBidParameters() external {
        uint256[] memory one_WrongDiscountRates = new uint256[](1);
        one_WrongDiscountRates[0] = 16e2;
        uint256[] memory one_WrongTimesInDays = new uint256[](1);
        one_WrongTimesInDays[0] = 10;

        // nodeOps[0] bids with invalid duration
        vm.startPrank(nodeOps[0]);
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.getPriceToPay(msg.sender, one_DiscountRates, one_WrongTimesInDays);
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.bid{value: 9 ether}(one_DiscountRates, one_WrongTimesInDays);
        vm.stopPrank();

        // nodeOps[1] bids with invalid discount rateS
        vm.startPrank(nodeOps[1]);
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.getPriceToPay(msg.sender, one_WrongDiscountRates, one_TimesInDays);
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.bid{value: 9 ether}(one_WrongDiscountRates, one_TimesInDays);
        vm.stopPrank();
    }

    function testBid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[0] bids
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], three_DiffDiscountRates, three_DiffTimesInDays);
        vm.prank(nodeOps[0]);
        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        auction.bid{value: (priceToPay - 0.1 ether)}(three_DiffDiscountRates, three_DiffTimesInDays);

        // Verify node op auction details hasn't been updated
        assertEq(auction.getNodeOpBidNumber(nodeOps[0]), 0);
        for (uint i = 0; i < three_DiffDiscountRates.length; i++) {
            assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[0], auctionScores_three_DiffBids[i]).length, 0);
            assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[0], auctionScores_three_DiffBids[i]).length, 0);
        }
    }

    function testBid_RefundTheSkimmingEthers() external {
        // Verify the initial balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE);
        // nodeOps[0] bids
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], three_DiffDiscountRates, three_DiffTimesInDays);
        vm.prank(nodeOps[0]);
        auction.bid{value: (priceToPay + 1 ether)}(three_DiffDiscountRates, three_DiffTimesInDays);

        // Verify the balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE - priceToPay);
        // Verify the balance of the Escrow contract
        assertEq(address(escrow).balance, priceToPay);
    }

    function testBid_AuctionScoreMapping() external {

        // Should revert if not same entries length
        vm.expectRevert(bytes("_discountRates and _timesInDays must have the same length"));
        auction.getPriceToPay(nodeOps[8], five_SameDiffDiscountRates, three_DiffTimesInDays);

        // nodeOps[5] bids for 1 Auction Score
        uint256[] memory auctionScoreNodeOp5 = _nodeOpBid(NodeOpBid(nodeOps[5], one_DiscountRates, one_TimesInDays));
        assertEq(auction.getNodeOpBidNumber(nodeOps[5]), 1);
        uint256[] memory nodeOp5Bid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]);
        uint256[] memory nodeOp5Vc = auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]);
        assertEq(nodeOp5Bid.length, 1);
        assertEq(nodeOp5Vc.length, 1);
        assertEq(nodeOp5Bid[0], bidPrice_one_Bid[0]);
        assertEq(nodeOp5Vc[0], one_TimesInDays[0]);
        assertEq(auction.numNodeOpsInAuction(), 1);

        // nodeOps[0] bids for 3 differents Auction Score 
        uint256[] memory auctionScoreNodeOp0 = _nodeOpBid(NodeOpBid(nodeOps[0], three_DiffDiscountRates, three_DiffTimesInDays));
        assertEq(auction.getNodeOpBidNumber(nodeOps[0]), 3);
        for (uint256 i = 0; i < auctionScoreNodeOp0.length; i++) {
            uint256[] memory nodeOp0Bid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[0], auctionScoreNodeOp0[i]);
            uint256[] memory nodeOp0Vc = auction.getNodeOpAuctionScoreVcs(nodeOps[0], auctionScoreNodeOp0[i]);
            assertEq(nodeOp0Bid.length, 1);
            assertEq(nodeOp0Vc.length, 1);
            assertEq(nodeOp0Bid[0], bidPrices_three_DiffBids[i]);
            assertEq(nodeOp0Vc[0], three_DiffTimesInDays[i]);
        }
        assertEq(auction.numNodeOpsInAuction(), 2);

        // nodeOps[9] bids five times for 2 differents Auction Score (2 and 3 bids are the same)
        uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], five_SameDiffDiscountRates, five_SameDiffTimesInDays));
        assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 5);
        for (uint256 i = 0; i < auctionScoreNodeOp9.length; i++) {
            uint256[] memory nodeOp0Bid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], auctionScoreNodeOp9[i]);
            uint256[] memory nodeOp0Vc = auction.getNodeOpAuctionScoreVcs(nodeOps[9], auctionScoreNodeOp9[i]);
            if (i == 0 || i == 1 || i == 2) {
                assertEq(nodeOp0Bid.length, 3);
                assertEq(nodeOp0Vc.length, 3);
            } 
            if (i == 3 || i == 4) {
                assertEq(nodeOp0Bid.length, 2);
                assertEq(nodeOp0Vc.length, 2);
            }
            for (uint256 j = 0; j < nodeOp0Bid.length; j++) {
               assertEq(nodeOp0Bid[j], bidPrices_five_SameDiffBids[i]);
               assertEq(nodeOp0Vc[j], five_SameDiffTimesInDays[i]);
            }
        }
        assertEq(auction.numNodeOpsInAuction(), 3);
    }

    function testUpdateBid_RevertWhen_WrongAuctionScore_And_WrongBidParameters() external {
        // nodeOps[0] bids
        (uint256[] memory discountRate, uint256[] memory time) = _createOneBidParamArray(11e2, 200);
        uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[0], discountRate, time));

        vm.startPrank(nodeOps[0]);
        // nodeOps[0] updates its bid with wrong discountRate
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.updateOneBid{value: 8 ether}(auctionScore[0], 25e2, 200);

        // nodeOps[0] updates its bid with wrong time
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.updateOneBid{value: 8 ether}(auctionScore[0], 11e2, 10);

        // nodeOps[0] updates its bid with wrong auctionScore
        vm.expectRevert(bytes("Wrong node op auctionScore"));
        auction.updateOneBid{value: 8 ether}(++auctionScore[0], 12e2, 200);

        vm.stopPrank();
    }

    function testUpdateBid_Outbid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[9] bids
        (uint256[] memory discountRate, uint256[] memory time) = _createOneBidParamArray(11e2, 200);
        uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[9], discountRate, time));

        // nodeOps[9] updates its bid
        uint256 amountToAdd = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 5e2, 200);
        vm.prank(nodeOps[9]);
        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        auction.updateOneBid{value: (amountToAdd - 0.001 ether)}(auctionScore[0], 5e2, 200);
    }

    function testUpdateBid_Outbid_RefundTheSkimmingEthers() external {
        // Verify the initial balance of nodeOps[9]
        assertEq(nodeOps[9].balance, STARTING_BALANCE);

        // nodeOps[9] bids
        uint256[] memory auctionScore = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));

        // Verify the balance of nodeOps[9] after bidding
        assertEq(nodeOps[9].balance, STARTING_BALANCE - bidPrice_one_Bid[0]);
        // Verify the balance of escrow contract after nodeOps[9] bid
        assertEq(address(escrow).balance, bidPrice_one_Bid[0]);

        // nodeOps[9] updates its bid (outbids)
        uint256 amountToAdd = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 10e2, 200);
        vm.prank(nodeOps[9]);
        auctionScore[0] = auction.updateOneBid{value: (amountToAdd + 2 ether)}(auctionScore[0], 10e2, 200);

        // Verify the balance of nodeOps[9] after updating its bid
        assertEq(nodeOps[9].balance, STARTING_BALANCE - (bidPrice_one_Bid[0] + amountToAdd));
        // Verify the balance of escrow contract after nodeOps[9] updates its bid
        assertEq(address(escrow).balance, bidPrice_one_Bid[0] + amountToAdd);

        // nodeOps[9] decreases its bid
        uint256 amountToAdd2 = auction.getUpdateOneBidPrice(nodeOps[9], auctionScore[0], 10e2, 35); // 0 ether
        vm.prank(nodeOps[9]);
        auction.updateOneBid{value: amountToAdd2 + 0.001 ether}(auctionScore[0], 10e2, 35);
        // Verify if nodeOps[9] has been refunded
        (uint256[] memory discountRate, uint256[] memory time) = _createOneBidParamArray(10e2, 35);
        uint256 refundAmount = (bidPrice_one_Bid[0] + amountToAdd) - auction.getPriceToPay(nodeOps[9], discountRate, time); // nodeOps[9] is whitelisted
        assertEq(nodeOps[9].balance, STARTING_BALANCE - (bidPrice_one_Bid[0] + amountToAdd + amountToAdd2) + refundAmount);
        // Verify the balance of escrow contract after nodeOps[9] updates its bid
        assertEq(address(escrow).balance, bidPrice_one_Bid[0] + amountToAdd - refundAmount);
    }

    function testUpdateBid_NodeOpAuctionDetails() external {
        // nodeOps[9] bids
        uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));

        // nodeOps[9] updates its bid
        uint256 newAuctionScoreNodeOp9 = _nodeOpUpdateBid(nodeOps[9], auctionScoreNodeOp9[0], 10e2, 60);

        // Verify number of bids of nodeOps[9]
        assertEq(auction.numNodeOpsInAuction(), 1);
        assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 1);

        // Verify auctionScoreNodeOp9[0] is not in nodeOps[9] mapping
        assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);
        assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);

        // Verify newAuctionScoreNodeOp9 in nodeOps[9] mapping
        uint256[] memory newBidPrice = auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], newAuctionScoreNodeOp9);
        assertEq(newBidPrice.length, 1);
        assertEq(newBidPrice[0], 43791780821917800);
        uint256[] memory newVc = auction.getNodeOpAuctionScoreVcs(nodeOps[9], newAuctionScoreNodeOp9);
        assertEq(newVc.length, 1);
        assertEq(newVc[0], 60);

        // nodeOps[5] bids five times
        uint256[] memory auctionScoreNodeOp5 = _nodeOpBid(NodeOpBid(nodeOps[5], five_SameDiffDiscountRates, five_SameDiffTimesInDays));

        // nodeOps[5] updates its first bid
        uint256 newAuctionScoreNodeOp5 = _nodeOpUpdateBid(nodeOps[5], auctionScoreNodeOp5[0], 10e2, 60);

        // Verify number of bids of nodeOps[5]
        assertEq(auction.numNodeOpsInAuction(), 2);
        assertEq(auction.getNodeOpBidNumber(nodeOps[5]), 5);

        // Verify auctionScoreNodeOp5[0] mappings
        assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);
        assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);

        // Verify newAuctionScoreNodeOp5 in nodeOps[5] mapping
        uint256[] memory newBidPriceNodeOp5 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], newAuctionScoreNodeOp5);
        assertEq(newBidPriceNodeOp5.length, 1);
        assertEq(newBidPriceNodeOp5[0], 43791780821917800);
        uint256[] memory newVcNodeOp5 = auction.getNodeOpAuctionScoreVcs(nodeOps[5], newAuctionScoreNodeOp5);
        assertEq(newVcNodeOp5.length, 1);
        assertEq(newVcNodeOp5[0], 60);

        // nodeOps[5] updates its last bid
        _nodeOpUpdateBid(nodeOps[5], auctionScoreNodeOp5[4], 5e2, 30);

        // Verify auctionScoreNodeOp5[0] mappings
        assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 3);
        assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 3);
    }

    function testWithdrawBid_RevertWhen_WrongAuctionScore() external {
        // nodeOps[9] bids
        uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));
        vm.expectRevert(bytes("Wrong node op auctionScore"));
        vm.prank(nodeOps[9]);
        auction.withdrawBid(++auctionScoreNodeOp9[0]);
    }

    function testWithdrawBid() external {
        // nodeOps[9] bids
        uint256[] memory auctionScoreNodeOp9 = _nodeOpBid(NodeOpBid(nodeOps[9], one_DiscountRates, one_TimesInDays));
        // nodeOps[9] withdraw its bid
        vm.prank(nodeOps[9]);
        auction.withdrawBid(auctionScoreNodeOp9[0]);

        // Verify number of bids of nodeOps[9]
        assertEq(auction.numNodeOpsInAuction(), 0);
        assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 0);

        // Verify auctionScoreNodeOp9[0] is not in nodeOps[9] mapping
        assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);
        assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[9], auctionScoreNodeOp9[0]).length, 0);

        // Verify nodeOps[9] balance
        assertEq(nodeOps[9].balance, STARTING_BALANCE);

        // nodeOps[5] bids five times
        uint256[] memory auctionScoreNodeOp5 = _nodeOpBid(NodeOpBid(nodeOps[5], five_SameDiffDiscountRates, five_SameDiffTimesInDays));
        // nodeOps[5] withdraw its bid
        vm.prank(nodeOps[5]);
        auction.withdrawBid(auctionScoreNodeOp5[0]);

        // Verify number of bids of nodeOps[5]
        assertEq(auction.numNodeOpsInAuction(), 1);
        assertEq(auction.getNodeOpBidNumber(nodeOps[5]), 4);

        // Verify auctionScoreNodeOp5[0] is not in nodeOps[5] mapping
        assertEq(auction.getNodeOpAuctionScoreBidPrices(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);
        assertEq(auction.getNodeOpAuctionScoreVcs(nodeOps[5], auctionScoreNodeOp5[0]).length, 2);

        // Verify nodeOps[5] balance
        uint256 remainingBidPrice = 2 * (bidPrices_five_SameDiffBids[2] + bidPrices_five_SameDiffBids[3]);
        assertEq(nodeOps[5].balance, STARTING_BALANCE - (remainingBidPrice + 4 * BOND));


        // // nodeOps[0] bids with discountRate = 13% and timeInDays = 100
        // _nodeOpBid(NodeOpBid(nodeOps[0], 13e2, 100));
        // uint256 bidPrice = auction.getPriceToPay(nodeOps[0], 13e2, 100);
        // (,,uint256 auctionScoreBeforeWithdrawal,,) = auction.getNodeOpDetails(nodeOps[0]);
        // assertEq(nodeOps[0].balance, STARTING_BALANCE - bidPrice);

        // // nodeOps[0] withdraw its bid
        // _nodeOpWithdrawBid(nodeOps[0]);

        // // Verify auctionScore mapping
        // address auctionScoreMapping = auction.getAuctionScoreToNodeOp(auctionScoreBeforeWithdrawal);
        // assertEq(auctionScoreMapping, address(0));

        // // Verify nodeOps[0] auction details
        // (
        //     uint256 vcNumber_0,
        //     uint256 bidPrice_0,
        //     uint256 auctionScore_0,
        //     uint256 reputationScore_0,
        //     Auction.NodeOpStatus opStatus_0
        // ) = auction.getNodeOpDetails(nodeOps[0]);
        // assertEq(vcNumber_0, 0);
        // assertEq(bidPrice_0, 0);
        // assertEq(auctionScore_0, 0);
        // assertEq(reputationScore_0, 1);
        // assertEq(uint(opStatus_0), 0);

        // // Verify nodeOps[0] balance once node ops has withdrawn its bid
        // assertEq(nodeOps[0].balance, STARTING_BALANCE);

        // // Verify if nodeOps[1] can bid with the same parameters after withdrawal
        // _nodeOpBid(NodeOpBid(nodeOps[0], 13e2, 100));
    }

    function test_UpdateAuctionConfig() external {
        (
            uint256 _expectedDailyReturnWei,
            uint256 _maxDiscountRate,
            uint256 _minDuration,
            uint256 _clusterSize
        ) = auction.getAuctionConfigValues();

        // Check if the initial values are correct
        assertEq(_expectedDailyReturnWei, currentPoSDailyReturnWei);
        assertEq(_maxDiscountRate, maxDiscountRate);
        assertEq(_minDuration, minValidationDuration);
        assertEq(_clusterSize, 4);

        // Update auction configuration
        uint256 newExpectedDailyReturnWei = 0.0003 ether;
        uint256 newMaxDiscountRate = 10e2;
        uint256 newMinDuration = 60;
        auction.updateAuctionConfig(newExpectedDailyReturnWei, newMaxDiscountRate, newMinDuration);

        (
            uint256 _newExpectedDailyReturnWei,
            uint256 _newMaxDiscountRate,
            uint256 _newMinDuration,
            uint256 _newClusterSize
        ) = auction.getAuctionConfigValues();

        // Check if the auction configuration is updated correctly
        assertEq(_newExpectedDailyReturnWei, newExpectedDailyReturnWei);
        assertEq(_newMaxDiscountRate, newMaxDiscountRate);
        assertEq(_newMinDuration, newMinDuration);
        assertEq(_newClusterSize, 4);
    }

    function test_updateClusterSize() external {
        // Update cluster size to 7
        auction.updateClusterSize(7);

        (,,,uint256 _newClusterSize) = auction.getAuctionConfigValues();
        assertEq(_newClusterSize, 7);
    }

    function test_createDV_FourDiffBids() external {
        // Alice creates a StrategyModule
        vm.prank(alice);
        IStrategyModule aliceStratMod = IStrategyModule(strategyModuleManager.createStratMod());

        // 4 node ops bid
        uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBidDiff();

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 4);
        
        // Get the total bids price
        uint256 totalBidsPrice;
        uint256 totalBonds = 3 * BOND; // Only 1 node op is whitelisted
        for (uint i = 0; i < nodeOpsAuctionScore.length - 1; i++) {
           totalBidsPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0])[0];
        }
        totalBidsPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], nodeOpsAuctionScore[3][0])[0];

        // Verify escrow received bids price + bonds
        assertEq(address(escrow).balance, totalBidsPrice + totalBonds);

        // Revert if not SrategyModuleManager calls createDV
        vm.expectRevert(IAuction.OnlyStrategyModuleManager.selector);
        auction.createDV(aliceStratMod);

        // DV: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[9]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);

        // Verify Escrow contract has been drained
        assertEq(address(escrow).balance, totalBonds);
        
        // Verify the DV composition
        address [] memory winnersDV = aliceStratMod.getDVNodesAddr();
        for (uint i = 0; i < winnersDV.length - 1; i++) {
           assertEq(winnersDV[i], nodeOps[i]);
        }
        assertEq(winnersDV[3], nodeOps[9]);

        // Verify the node ops details has been updated correctly
        for (uint256 i = 0; i < winnersDV.length - 1; i++) {
            assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 0);
            uint256[] memory nodeOpBid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
            uint256[] memory nodeOpVc = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
            assertEq(nodeOpBid.length, 0);
            assertEq(nodeOpVc.length, 0);
        }
        assertEq(auction.getNodeOpBidNumber(nodeOps[9]), 0);
        uint256[] memory nodeOp9Bid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[9], nodeOpsAuctionScore[3][0]);
        uint256[] memory nodeOp9Vc = auction.getNodeOpAuctionScoreVcs(nodeOps[9], nodeOpsAuctionScore[3][0]);
        assertEq(nodeOp9Bid.length, 0);
        assertEq(nodeOp9Vc.length, 0);

        // Revert when not enough nodeOps in Auction
        assertEq(auction.numNodeOpsInAuction(), 0);
        vm.prank(address(strategyModuleManager));
        vm.expectRevert(IAuction.NotEnoughNodeOps.selector);
        auction.createDV(aliceStratMod);

    }

    function test_createDV_EightSameBids() external {
        // Alice creates a StrategyModule
        vm.prank(alice);
        IStrategyModule aliceStratMod = IStrategyModule(strategyModuleManager.createStratMod());

        // 4 node ops bids 2 times (all of them have the same bids)
        uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBidSame();

        // Calculate the price paid by node ops
        uint256 totalBonds = 8 * BOND; // Every node op has 2 bonds
        uint256 totalFirstBidPrice;
        for (uint i = 0; i < nodeOpsAuctionScore.length; i++) {
            totalFirstBidPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0])[0];
        }
        uint256 totalSecondBidPrice;
        for (uint i = 0; i < nodeOpsAuctionScore.length; i++) {
            totalSecondBidPrice += auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][1])[0];
        }
        // Verify escrow received bids price + bonds
        assertEq(address(escrow).balance, totalFirstBidPrice + totalSecondBidPrice + totalBonds);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 4);

        // DV1: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);

        // Verify the DV composition
        address [] memory winnersDV1 = aliceStratMod.getDVNodesAddr();
        assertEq(winnersDV1[0], nodeOps[0]);
        assertEq(winnersDV1[1], nodeOps[1]);
        assertEq(winnersDV1[2], nodeOps[2]);
        assertEq(winnersDV1[3], nodeOps[3]);

        // Verify escrow received bids price + bonds
        assertEq(address(escrow).balance, totalSecondBidPrice + totalBonds);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 4);

        // Bob creates a StrategyModule
        vm.prank(bob);
        IStrategyModule bobStratMod = IStrategyModule(strategyModuleManager.createStratMod());

        // DV2: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
        vm.prank(address(strategyModuleManager));
        auction.createDV(bobStratMod);

        // Verify the DV composition
        address [] memory winnersDV2 = bobStratMod.getDVNodesAddr();
        assertEq(winnersDV2[0], nodeOps[0]);
        assertEq(winnersDV2[1], nodeOps[3]);
        assertEq(winnersDV2[2], nodeOps[2]);
        assertEq(winnersDV2[3], nodeOps[1]);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 0);

        // Verify escrow has been drained
        assertEq(address(escrow).balance, totalBonds);

    }

    function test_createDV_ThreeSameBids_WinnerAlreadyExists() external {
        // Alice creates a StrategyModule
        vm.prank(alice);
        IStrategyModule aliceStratMod = IStrategyModule(strategyModuleManager.createStratMod());

        // 4 node ops bid (three bids are similar)
        uint256[][] memory nodeOpsAuctionScore = _4NodeOpsBid_ThreeSame_WinnerAlreadyExists();

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 4);

        // DV: nodeOps[0], nodeOps[1], nodeOps[2], nodeOps[3]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);
        
        // Verify the DV composition
        address [] memory winnersDV = aliceStratMod.getDVNodesAddr();
        assertEq(winnersDV[0], nodeOps[0]);
        assertEq(winnersDV[1], nodeOps[2]);
        assertEq(winnersDV[2], nodeOps[1]);
        assertEq(winnersDV[3], nodeOps[3]);

        // Verify the node ops details has been updated correctly
        for (uint256 i = 0; i < winnersDV.length; i++) {
            if (i != 2) {
                assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 0);
                uint256[] memory nodeOpBid = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
                uint256[] memory nodeOpVc = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
                assertEq(nodeOpBid.length, 0);
                assertEq(nodeOpVc.length, 0);
            } else {
                assertEq(auction.getNodeOpBidNumber(nodeOps[i]), 1);
                uint256[] memory nodeOp2Bid1 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][0]);
                uint256[] memory nodeOp2Vc1 = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][0]);
                assertEq(nodeOp2Bid1.length, 0);
                assertEq(nodeOp2Vc1.length, 0);
                uint256[] memory nodeOp2Bid2 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[i], nodeOpsAuctionScore[i][1]);
                uint256[] memory nodeOp2Vc2 = auction.getNodeOpAuctionScoreVcs(nodeOps[i], nodeOpsAuctionScore[i][1]);
                assertEq(nodeOp2Bid2.length, 1);
                assertEq(nodeOp2Vc2.length, 1);
                assertEq(nodeOp2Bid2[0], bidPrice_one_Bid[0]);
                assertEq(nodeOp2Vc2[0], 100);
            }
        }

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 1);
    }

    function test_CreateMultipleDVs() external {
        // Alice creates 3 StrategyModules
        vm.startPrank(alice);
        IStrategyModule aliceStratMod1 = IStrategyModule(strategyModuleManager.createStratMod());
        IStrategyModule aliceStratMod2 = IStrategyModule(strategyModuleManager.createStratMod());
        IStrategyModule aliceStratMod3 = IStrategyModule(strategyModuleManager.createStratMod());
        vm.stopPrank();

        // Bob creates 2 StrategyModules
        vm.startPrank(alice);
        IStrategyModule bobStratMod1 = IStrategyModule(strategyModuleManager.createStratMod());
        IStrategyModule bobStratMod2 = IStrategyModule(strategyModuleManager.createStratMod());
        vm.stopPrank();

        // 10 node ops bid (real life example)
        uint256[][] memory nodeOpsAuctionScore = _10NodeOpsBid();

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 10);

        /* ===================== FIRST DV ===================== */

        // DV1: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[4]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod1);
        
        // Verify the DV1 composition
        address [] memory winnersDV1 = aliceStratMod1.getDVNodesAddr();
        assertEq(winnersDV1[0], nodeOps[0]);
        assertEq(winnersDV1[1], nodeOps[6]);
        assertEq(winnersDV1[2], nodeOps[2]);
        assertEq(winnersDV1[3], nodeOps[4]);

        // Verify cluster manager DV1
        assertEq(aliceStratMod1.getClusterManager(), nodeOps[4]);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 9);

        /* ===================== SECOND DV ===================== */

        // DV2: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[5]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod2);
        
        // Verify the DV1 composition
        address [] memory winnersDV2 = aliceStratMod2.getDVNodesAddr();
        assertEq(winnersDV2[0], nodeOps[0]);
        assertEq(winnersDV2[1], nodeOps[6]);
        assertEq(winnersDV2[2], nodeOps[2]);
        assertEq(winnersDV2[3], nodeOps[5]);

        // Verify cluster manager DV1
        assertEq(aliceStratMod2.getClusterManager(), nodeOps[5]);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 8);

        /* ===================== THIRD DV ===================== */

        // DV2: nodeOps[0], nodeOps[6], nodeOps[2], nodeOps[1]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod3);
        
        // Verify the DV1 composition
        address [] memory winnersDV3 = aliceStratMod3.getDVNodesAddr();
        assertEq(winnersDV3[0], nodeOps[0]);
        assertEq(winnersDV3[1], nodeOps[6]);
        assertEq(winnersDV3[2], nodeOps[2]);
        assertEq(winnersDV3[3], nodeOps[1]);

        // Verify cluster manager DV1
        assertEq(aliceStratMod3.getClusterManager(), nodeOps[1]);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 5);

        /* ===================== FOURTH DV ===================== */

        // DV2: nodeOps[1], nodeOps[3], nodeOps[7], nodeOps[9]
        vm.prank(address(strategyModuleManager));
        auction.createDV(bobStratMod1);
        
        // Verify the DV1 composition
        address [] memory winnersDV4 = bobStratMod1.getDVNodesAddr();
        assertEq(winnersDV4[0], nodeOps[1]);
        assertEq(winnersDV4[1], nodeOps[3]);
        assertEq(winnersDV4[2], nodeOps[7]);
        assertEq(winnersDV4[3], nodeOps[9]);

        // Verify cluster manager DV1
        assertEq(bobStratMod1.getClusterManager(), nodeOps[9]);

        // Verify the number of node ops in the auction
        assertEq(auction.numNodeOpsInAuction(), 3);

        /* ===================== NOT ENOUGH NODE OPS IN AUCTION ===================== */
        vm.prank(address(strategyModuleManager));
        vm.expectRevert(IAuction.NotEnoughNodeOps.selector);
        auction.createDV(bobStratMod2);

        // Verify remaining bids of nodeOps[3]
        uint256[] memory nodeOp3Bid1 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[3], nodeOpsAuctionScore[3][1]);
        uint256[] memory nodeOp3Vc1 = auction.getNodeOpAuctionScoreVcs(nodeOps[3], nodeOpsAuctionScore[3][1]);
        assertEq(nodeOp3Bid1.length, 2);
        assertEq(nodeOp3Vc1.length, 2);
        assertEq(nodeOp3Bid1[0], bidPrices_five_SameDiffBids[0]);
        assertEq(nodeOp3Bid1[1], bidPrices_five_SameDiffBids[1]);
        assertEq(nodeOp3Vc1[0], 30);
        assertEq(nodeOp3Vc1[1], 30);
        uint256[] memory nodeOp3Bid2 = auction.getNodeOpAuctionScoreBidPrices(nodeOps[3], nodeOpsAuctionScore[3][4]);
        uint256[] memory nodeOp3Vc2 = auction.getNodeOpAuctionScoreVcs(nodeOps[3], nodeOpsAuctionScore[3][4]);
        assertEq(nodeOp3Bid2.length, 2);
        assertEq(nodeOp3Vc2.length, 2);
        assertEq(nodeOp3Bid2[0], bidPrices_five_SameDiffBids[4]);
        assertEq(nodeOp3Bid2[1], bidPrices_five_SameDiffBids[4]);
        assertEq(nodeOp3Vc2[0], 30);
        assertEq(nodeOp3Vc2[1], 30);

    }

    /* ===================== HELPER FUNCTIONS ===================== */

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

    function _createTwoBidsParamArray(
        uint256 _discountRate1,
        uint256 _timeInDays1,
        uint256 _discountRate2,
        uint256 _timeInDays2
    ) internal pure returns (uint256[] memory, uint256[] memory) {
        uint256[] memory discountRatesArray = new uint256[](2);
        discountRatesArray[0] = _discountRate1;
        discountRatesArray[1] = _discountRate2;

        uint256[] memory timesInDaysArray = new uint256[](2);
        timesInDaysArray[0] = _timeInDays1;
        timesInDaysArray[1] = _timeInDays2;
        
        return (discountRatesArray, timesInDaysArray);
    }

    function _nodeOpBid(
        NodeOpBid memory nodeOpBid
    ) internal returns (uint256[] memory) {
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(nodeOpBid.nodeOp, nodeOpBid.discountRates, nodeOpBid.timesInDays);
        vm.prank(nodeOpBid.nodeOp);
        return auction.bid{value: priceToPay}(nodeOpBid.discountRates, nodeOpBid.timesInDays);
    }

    function _nodeOpUpdateBid(
        address _nodeOp,
        uint256 _auctionScore,
        uint256 _newDiscountRate,
        uint256 _newTimeInDays
    ) internal returns (uint256) {
        // Get price to pay
        uint256 priceToPay = auction.getUpdateOneBidPrice(_nodeOp, _auctionScore, _newDiscountRate, _newTimeInDays);
        vm.prank(_nodeOp);
        return auction.updateOneBid{value: priceToPay}(_auctionScore, _newDiscountRate, _newTimeInDays);
    }

    // function _nodeOpWithdrawBid(address _nodeOp) internal {
    //     vm.prank(_nodeOp);
    //     auction.withdrawBid();
    // }

    function _nodeOpsBid(
        NodeOpBid[] memory nodeOpsBids
    ) internal returns (uint256[][] memory) {
        uint256[][] memory nodeOpsAuctionScores = new uint256[][](nodeOpsBids.length);
        for (uint i = 0; i < nodeOpsBids.length; i++) {
            nodeOpsAuctionScores[i] = _nodeOpBid(nodeOpsBids[i]);
        }
        return nodeOpsAuctionScores;
    }

    function _4NodeOpsBidDiff() internal returns (uint256[][] memory) {
        (uint256[] memory first_DR, uint256[] memory first_time) = _createOneBidParamArray(11e2, 400);
        (uint256[] memory second_DR, uint256[] memory second_time) = _createOneBidParamArray(11e2, 300);
        (uint256[] memory third_DR, uint256[] memory third_time) = _createOneBidParamArray(11e2, 200);
        (uint256[] memory fourth_DR, uint256[] memory fourth_time) = _createOneBidParamArray(11e2, 100);

        NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
        nodeOpsBid[0] = NodeOpBid(nodeOps[0], first_DR, first_time); // 1st
        nodeOpsBid[1] = NodeOpBid(nodeOps[1], second_DR, second_time); // 2nd
        nodeOpsBid[2] = NodeOpBid(nodeOps[2], third_DR, third_time); // 3rd
        nodeOpsBid[3] = NodeOpBid(nodeOps[9], fourth_DR, fourth_time); // 4th
        
        return _nodeOpsBid(nodeOpsBid);
    }

    function _4NodeOpsBidSame() internal returns (uint256[][] memory) {
        (uint256[] memory discounts, uint256[] memory times) = _createTwoBidsParamArray(11e2, 100, 11e2, 100);

        NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
        nodeOpsBid[0] = NodeOpBid(nodeOps[0], discounts, times); // 1st // 2nd
        nodeOpsBid[1] = NodeOpBid(nodeOps[1], discounts, times); // 1st // 2nd
        nodeOpsBid[2] = NodeOpBid(nodeOps[2], discounts, times); // 1st // 2nd
        nodeOpsBid[3] = NodeOpBid(nodeOps[3], discounts, times); // 1st // 2nd

        return _nodeOpsBid(nodeOpsBid);
    }

    function _4NodeOpsBid_ThreeSame_WinnerAlreadyExists() internal returns (uint256[][] memory) {
        (uint256[] memory first_DR, uint256[] memory first_time) = _createOneBidParamArray(11e2, 400);
        (uint256[] memory second_DR, uint256[] memory second_time) = _createTwoBidsParamArray(11e2, 400, 10e2, 100);
        (uint256[] memory third_DR, uint256[] memory third_time) = _createOneBidParamArray(11e2, 100);

        NodeOpBid[] memory nodeOpsBid = new NodeOpBid[](4);
        nodeOpsBid[0] = NodeOpBid(nodeOps[0], first_DR, first_time); // 1st
        nodeOpsBid[1] = NodeOpBid(nodeOps[1], first_DR, first_time); // 1st
        nodeOpsBid[2] = NodeOpBid(nodeOps[2], second_DR, second_time); // 1st // 2nd -> not taken cause node op already exists
        nodeOpsBid[3] = NodeOpBid(nodeOps[3], third_DR, third_time); // 4th
        
        return _nodeOpsBid(nodeOpsBid);
    }

    function _10NodeOpsBid() internal returns (uint256[][] memory) {
        (uint256[] memory small_DR, uint256[] memory small_time) = _createOneBidParamArray(15e2, 30);

        NodeOpBid[] memory nodeOpBids = new NodeOpBid[](10);
        nodeOpBids[0] = NodeOpBid(nodeOps[0], three_DiffDiscountRates, three_DiffTimesInDays); // 1st // 5th // 9th --
        nodeOpBids[1] = NodeOpBid(nodeOps[1], five_SameDiffDiscountRates, five_SameDiffTimesInDays); // 12th // 13th
        nodeOpBids[2] = NodeOpBid(nodeOps[2], three_DiffDiscountRates, three_DiffTimesInDays); // 3rd // 7th // 11th --
        nodeOpBids[3] = NodeOpBid(nodeOps[3], five_SameDiffDiscountRates, five_SameDiffTimesInDays); // 14th 
        nodeOpBids[4] = NodeOpBid(nodeOps[4], one_DiscountRates, one_TimesInDays);  // 4th --
        nodeOpBids[5] = NodeOpBid(nodeOps[5], one_DiscountRates, one_TimesInDays);  // 8th --
        nodeOpBids[6] = NodeOpBid(nodeOps[6], three_DiffDiscountRates, three_DiffTimesInDays);  // 2nd // 6th // 10th --
        nodeOpBids[7] = NodeOpBid(nodeOps[7], small_DR, small_time);  // 15th --
        nodeOpBids[8] = NodeOpBid(nodeOps[8], small_DR, small_time);  
        nodeOpBids[9] = NodeOpBid(nodeOps[9], small_DR, small_time);  // 16th --
        
        return _nodeOpsBid(nodeOpBids);
    }

}
