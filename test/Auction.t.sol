// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "./ByzantineDeployer.t.sol";
import "../src/interfaces/IAuction.sol";
import "../src/interfaces/IStrategyModule.sol";

contract AuctionTest is ByzantineDeployer {

    uint256 constant STARTING_BALANCE = 10 ether;

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

    function testBid_RevertWhen_NodeOpAlreadyInAuction() external {
        // nodeOps[0] bids (10%, 30 days)
        _nodeOpBid(NodeOpBid(nodeOps[0], 10e2, 30));

        // nodeOps[0] does a second bid (15%, 45 days)
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 15e2, 45);
        vm.prank(nodeOps[0]);
        vm.expectRevert(IAuction.AlreadyInAuction.selector);
        auction.bid{value: priceToPay}(15e2, 45);
    }

    function testBid_RevertWhen_WrongBidParameters() external {
        // nodeOps[0] bids with invalid duration (15%, 10 days)
        vm.startPrank(nodeOps[0]);
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.getPriceToPay(nodeOps[0], 15e2, 10);
        vm.expectRevert(IAuction.DurationTooShort.selector);
        auction.bid{value: 9 ether}(15e2, 10);
        vm.stopPrank();

        // nodeOps[1] bids with invalid discount rate (16%, 30 days)
        vm.startPrank(nodeOps[1]);
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.getPriceToPay(nodeOps[1], 16e2, 30);
        vm.expectRevert(IAuction.DiscountRateTooHigh.selector);
        auction.bid{value: 9 ether}(16e2, 30);
        vm.stopPrank();
    }

    function testBid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[0] bids (15%, 45 days)
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 15e2, 45);
        vm.prank(nodeOps[0]);
        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        auction.bid{value: (priceToPay - 0.1 ether)}(15e2, 45);
    }

    function testBid_RefundTheSkimmingEthers() external {
        // Verify the initial balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE);
        // nodeOps[0] bids (15%, 45 days)
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 15e2, 45);
        vm.prank(nodeOps[0]);
        auction.bid{value: (priceToPay + 1 ether)}(15e2, 45);

        // Verify the balance of nodeOps[0]
        assertEq(nodeOps[0].balance, STARTING_BALANCE - priceToPay);
        // Verify the balance of the auction contract
        assertEq(address(auction).balance, priceToPay);
    }

    function testBid_AuctionScoreMapping() external {
        // nodeOps[0] bids (10%, 30 days)
        _nodeOpBid(NodeOpBid(nodeOps[0], 10e2, 30));
        (,,uint256 auctionScore_0,,) = auction.getNodeOpDetails(nodeOps[0]);
        address auctionScoreToNodeOp = auction.getAuctionScoreToNodeOp(auctionScore_0);
        assertEq(auctionScoreToNodeOp, nodeOps[0]);

        // nodeOps[1] bids (11%, 30 days)
        _nodeOpBid(NodeOpBid(nodeOps[1], 11e2, 30));
        (,,uint256 auctionScore_1,,) = auction.getNodeOpDetails(nodeOps[1]);
        auctionScoreToNodeOp = auction.getAuctionScoreToNodeOp(auctionScore_1);
        assertEq(auctionScoreToNodeOp, nodeOps[1]);

        // Revert if nodeOps[2] bids the same as nodeOps[1]
        uint256 priceToPay = auction.getPriceToPay(nodeOps[2], 11e2, 30);
        vm.prank(nodeOps[2]);
        vm.expectRevert(IAuction.BidAlreadyExists.selector);
        auction.bid{value: priceToPay}(11e2, 30);
    }

    function testUpdateBid_RevertWhen_NodeOpNotInAuction() external {
        // nodeOps[0] updates its bid but hasn't bid
        vm.expectRevert(IAuction.NotInAuction.selector);
        auction.updateBid{value: 8 ether}(15e2, 45);
    }

    function testUpdateBid_Outbid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[9] bids (15%, 30 days)
        _nodeOpBid(NodeOpBid(nodeOps[9], 15e2, 30));

        // nodeOps[9] updates its bid (5%, 3 days)
        uint256 amountToAdd = auction.getUpdateBidPrice(nodeOps[9], 5e2, 30);
        vm.prank(nodeOps[9]);
        vm.expectRevert(IAuction.NotEnoughEtherSent.selector);
        auction.updateBid{value: (amountToAdd - 0.001 ether)}(5e2, 30);
    }

    function testUpdateBid_Outbid_RefundTheSkimmingEthers() external {
        // Verify the initial balance of nodeOps[9]
        assertEq(nodeOps[9].balance, STARTING_BALANCE);

        // nodeOps[9] bids (5%, 30 days)
        uint256 bidPrice = auction.getPriceToPay(nodeOps[9], 5e2, 30);
        _nodeOpBid(NodeOpBid(nodeOps[9], 5e2, 30));

        // Verify the balance of nodeOps[9] after bidding
        assertEq(nodeOps[9].balance, STARTING_BALANCE - bidPrice);
        // Verify the balance of auction contract after nodeOps[9] bid
        assertEq(address(auction).balance, bidPrice);

        // nodeOps[9] updates its bid (14%, 3 days)
        uint256 amountToAdd = auction.getUpdateBidPrice(nodeOps[9], 14e2, 45);
        vm.prank(nodeOps[9]);
        auction.updateBid{value: (amountToAdd + 2 ether)}(14e2, 45);

        // Verify the balance of nodeOps[9] after updating its bid
        assertEq(nodeOps[9].balance, STARTING_BALANCE - (bidPrice + amountToAdd));
        // Verify the balance of auction contract after nodeOps[9] updates its bid
        assertEq(address(auction).balance, bidPrice + amountToAdd);
    }

    function testUpdateBid_DecreaseBid() external {
        // TODO: Wait for Escrow contract to refund the bidder
    }

    function testUpdateBid_AuctionScoreMapping() external {
        // nodeOps[9] bids (5%, 90 days)
        _nodeOpBid(NodeOpBid(nodeOps[9], 5e2, 90));
        (,,uint256 FirstAuctionScore,,) = auction.getNodeOpDetails(nodeOps[9]);

        // nodeOps[8] bids (5%, 120 days)
        _nodeOpBid(NodeOpBid(nodeOps[8], 5e2, 120));

        // nodeOps[9] updates its bid (14%, 90 days)
        _nodeOpUpdateBid(NodeOpBid(nodeOps[9], 14e2, 90));
        (,,uint256 SecondAuctionScore,,) = auction.getNodeOpDetails(nodeOps[9]);

        // Verify if nodeOps[9] has been removed from FirstAuctionScore
        address auctionScore1ToNodeOp = auction.getAuctionScoreToNodeOp(FirstAuctionScore);
        assertEq(auctionScore1ToNodeOp, address(0));

        // Verify if nodeOps[9] has been added to the SecondAuctionScore
        address auctionScore2ToNodeOp = auction.getAuctionScoreToNodeOp(SecondAuctionScore);
        assertEq(auctionScore2ToNodeOp, nodeOps[9]);

        // nodeOps[8] updates its bid to the same as nodeOps[9] (14%, 90 days)
        uint256 priceToPay = auction.getUpdateBidPrice(nodeOps[8], 14e2, 90);
        vm.prank(nodeOps[8]);
        vm.expectRevert(IAuction.BidAlreadyExists.selector);
        auction.updateBid{value: priceToPay}(14e2, 90);
    }

    function testUpdateBid_NodeOpStruct() external {
        // nodeOps[9] bids (5%, 90 days)
        _nodeOpBid(NodeOpBid(nodeOps[9], 5e2, 90));

        // nodeOps[9] updates its bid (10%, 60 days)
        _nodeOpUpdateBid(NodeOpBid(nodeOps[9], 10e2, 60));
        (
            uint256 vcNumber_9,
            uint256 bidPrice_9,
            uint256 auctionScore_9,
            uint256 reputationScore_9,
            Auction.NodeOpStatus opStatus_9
        ) = auction.getNodeOpDetails(nodeOps[9]);

        // Check if the value of vcNumber for nodeOps[9] is correct
        assertEq(vcNumber_9, 60);
        // Check if the value of bidPrice for nodeOps[9] is calculated correctly
        assertEq(bidPrice_9, 43791780821917800);
        // Check if the value of auctionScore for nodeOps[9] is calculated correctly
        assertEq(auctionScore_9, 774971987896852);
        assertEq(reputationScore_9, 1);
        assertEq(uint(opStatus_9), 1);


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

    function test_AuctionCalculations_And_NodeOpDetails() external {
        // nodeOps[0] bid with discountRate = 5% and timeInDays = 30
        _nodeOpBid(NodeOpBid(nodeOps[0], 5e2, 30));
        (
            uint256 vcNumber_0,
            uint256 bidPrice_0,
            uint256 auctionScore_0,
            uint256 reputationScore_0,
            Auction.NodeOpStatus opStatus_0
        ) = auction.getNodeOpDetails(nodeOps[0]);

        // Check if the value of vcNumber for nodeOps[0] is correct
        assertEq(vcNumber_0, 30);
        // Check if the value of bidPrice for nodeOps[0] is calculated correctly
        assertEq(bidPrice_0, 23112328767123270);
        // Check if the value of auctionScore for nodeOps[0] is calculated correctly
        assertEq(auctionScore_0, 793861565530208);
        // Check other values in the node op Struct
        assertEq(reputationScore_0, 1);
        assertEq(uint(opStatus_0), 1);

        // nodeOps[1] bid with discountRate = 10% and timeInDays = 60
        _nodeOpBid(NodeOpBid(nodeOps[1], 10e2, 60));
        (
            uint256 vcNumber_1,
            uint256 bidPrice_1,
            uint256 auctionScore_1,
            uint256 reputationScore_1,
            Auction.NodeOpStatus opStatus_1
        ) = auction.getNodeOpDetails(nodeOps[1]);

        // Check if the value of vcNumber for nodeOps[1] is correct
        assertEq(vcNumber_1, 60);
        // Check if the value of bidPrice for nodeOps[1] is calculated correctly
        assertEq(bidPrice_1, 43791780821917800);
        // Check if the value of auctionScore for nodeOps[1] is calculated correctly
        assertEq(auctionScore_1, 774971987896852);
        assertEq(reputationScore_1, 1);
        assertEq(uint(opStatus_1), 1);
    }

    function testWithdrawBid_RevertWhen_NotInAuction() external {
        // nodeOps[0] withdraws its bid but hasn't had bid
        vm.expectRevert(IAuction.NotInAuction.selector);
        auction.withdrawBid();
    }

    function testWithdrawBid() external {
        // nodeOps[0] bids with discountRate = 13% and timeInDays = 100
        _nodeOpBid(NodeOpBid(nodeOps[0], 13e2, 100));
        (,,uint256 auctionScoreBeforeWithdrawal,,) = auction.getNodeOpDetails(nodeOps[0]);

        // nodeOps[0] withdraw its bid
        _nodeOpWithdrawBid(nodeOps[0]);

        // Verify auctionScore mapping
        address auctionScoreMapping = auction.getAuctionScoreToNodeOp(auctionScoreBeforeWithdrawal);
        assertEq(auctionScoreMapping, address(0));

        // Verify nodeOps[0] auction details
        (
            uint256 vcNumber_0,
            uint256 bidPrice_0,
            uint256 auctionScore_0,
            uint256 reputationScore_0,
            Auction.NodeOpStatus opStatus_0
        ) = auction.getNodeOpDetails(nodeOps[0]);
        assertEq(vcNumber_0, 0);
        assertEq(bidPrice_0, 0);
        assertEq(auctionScore_0, 0);
        assertEq(reputationScore_0, 1);
        assertEq(uint(opStatus_0), 0);

        // TODO: Verify nodeOps[0] balance once Escrow contract is implemented

        // Verify if nodeOps[1] can bid with the same parameters after withdrawal
        _nodeOpBid(NodeOpBid(nodeOps[0], 13e2, 100));
    }

    function testCreateDVs() external {
        // Alice creates a StrategyModule
        vm.prank(alice);
        IStrategyModule aliceStratMod = IStrategyModule(strategyModuleManager.createStratMod());

        // 10 node ops bids
        _10NodeOpsBid();
        // Get nodeOPs[0] auction score
        (,,uint256 auctionScore0,,) = auction.getNodeOpDetails(nodeOps[0]);
        assertEq(auction.getAuctionScoreToNodeOp(auctionScore0), nodeOps[0]);

        // Revert if not SrategyModuleManager calls createDV
        vm.expectRevert(IAuction.OnlyStrategyModuleManager.selector);
        auction.createDV(aliceStratMod);

        // First DV: nodeOps[0], nodeOps[2], nodeOps[4], nodeOps[6]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);
        address [] memory winnersDV1 = aliceStratMod.getDVNodesAddr();
        for (uint i = 0; i < winnersDV1.length; i++) {
            assertEq(winnersDV1[i], nodeOps[2 * i]);
        }
        // Verify if auctionScore mapping is updated correctly
        assertEq(auction.getAuctionScoreToNodeOp(auctionScore0), address(0));

        // Second DV: nodeOps[1], nodeOps[3], nodeOps[5], nodeOps[7]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);
        address [] memory winnersDV2 = aliceStratMod.getDVNodesAddr();
        for (uint i = 0; i < winnersDV2.length; i++) {
            assertEq(winnersDV2[i], nodeOps[(2 * i) + 1]);
        }

        // Alice bids like nodeOps[0] (verify if tree leaf has been deleted)
        _nodeOpBid(NodeOpBid(alice, 13e2, 1000));
        
        vm.prank(address(strategyModuleManager));
        vm.expectRevert(IAuction.NotEnoughNodeOps.selector);
        auction.createDV(aliceStratMod);

        // Bob bids just under Alice's bid
        _nodeOpBid(NodeOpBid(bob, 13e2, 999));

        // Third DV: alice, bob, nodeOps[8], nodeOps[9]
        vm.prank(address(strategyModuleManager));
        auction.createDV(aliceStratMod);
        address [] memory winnersDV3 = aliceStratMod.getDVNodesAddr();
        assertEq(winnersDV3[0], alice);
        assertEq(winnersDV3[1], bob);
        assertEq(winnersDV3[2], nodeOps[8]);
        assertEq(winnersDV3[3], nodeOps[9]);

        // Verify node ops alice details
        (
            uint256 vcNumberAlice,
            uint256 bidPriceAlice,
            uint256 auctionScoreAlice,
            uint256 reputationScoreAlice,
            Auction.NodeOpStatus opStatusAlice
        ) = auction.getNodeOpDetails(alice);
        assertEq(vcNumberAlice, 1000);
        assertEq(bidPriceAlice, 0);
        assertEq(auctionScoreAlice, 0);
        assertEq(reputationScoreAlice, 1);
        assertEq(uint(opStatusAlice), 2);

    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _nodeOpBid(
        NodeOpBid memory nodeOpBid
    ) internal {
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(nodeOpBid.nodeOp, nodeOpBid.discountRate, nodeOpBid.timeInDays);
        vm.prank(nodeOpBid.nodeOp);
        auction.bid{value: priceToPay}(nodeOpBid.discountRate, nodeOpBid.timeInDays);
    }

    function _nodeOpUpdateBid(
        NodeOpBid memory nodeOpBid
    ) internal {
        // Get price to pay
        uint256 priceToPay = auction.getUpdateBidPrice(nodeOpBid.nodeOp, nodeOpBid.discountRate, nodeOpBid.timeInDays);
        vm.prank(nodeOpBid.nodeOp);
        auction.updateBid{value: priceToPay}(nodeOpBid.discountRate, nodeOpBid.timeInDays);
    }

    function _nodeOpWithdrawBid(address _nodeOp) internal {
        vm.prank(_nodeOp);
        auction.withdrawBid();
    }

    function _nodeOpsBid(
        NodeOpBid[] memory nodeOpBids
    ) internal {
        for (uint i = 0; i < nodeOpBids.length; i++) {
            _nodeOpBid(nodeOpBids[i]);
        }
    }

    function _10NodeOpsBid() internal {
        NodeOpBid[] memory nodeOpBids = new NodeOpBid[](10);
        nodeOpBids[0] = NodeOpBid(nodeOps[0], 13e2, 1000); // 1st
        nodeOpBids[1] = NodeOpBid(nodeOps[1], 13e2, 600);  // 5th
        nodeOpBids[2] = NodeOpBid(nodeOps[2], 13e2, 900);  // 2nd
        nodeOpBids[3] = NodeOpBid(nodeOps[3], 13e2, 500);  // 6th
        nodeOpBids[4] = NodeOpBid(nodeOps[4], 13e2, 800);  // 3rd
        nodeOpBids[5] = NodeOpBid(nodeOps[5], 13e2, 400);  // 7th
        nodeOpBids[6] = NodeOpBid(nodeOps[6], 13e2, 700);  // 4th
        nodeOpBids[7] = NodeOpBid(nodeOps[7], 13e2, 300);  // 8th
        nodeOpBids[8] = NodeOpBid(nodeOps[8], 13e2, 200);  // 9th
        nodeOpBids[9] = NodeOpBid(nodeOps[9], 13e2, 100);  // 10th
        _nodeOpsBid(nodeOpBids);
    }

}
