// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {Test, console} from "forge-std/Test.sol";
import {Auction} from "../src/core/Auction.sol";
import {AuctionMock} from "./mocks/AuctionMock.sol";

contract AuctionTest is Test {
    Auction auction;
    AuctionMock mock;

    uint256 constant BOND = 1 ether;
    uint256 constant STARTING_BALANCE = 10 ether;

    address ESCROW = makeAddr("escrow");
    uint256 EXPECTED_DAILY_RETURN = (uint256(32 ether) * 37) / 1000 / 365; //3243835616438356
    uint256 MAX_DISCOUNT_RATE = 15e2;
    uint256 MIN_DURATION = 30;

    address[] public nodeOps = [
        makeAddr("node_operator_0"),
        makeAddr("node_operator_1"),
        makeAddr("node_operator_2"),
        makeAddr("node_operator_3"),
        makeAddr("node_operator_4"),
        makeAddr("node_operator_5"),
        makeAddr("node_operator_6"),
        makeAddr("node_operator_7"),
        makeAddr("node_operator_8"),
        makeAddr("node_operator_9")
    ];
    address RANDOM_ADDRESS = makeAddr("random_address");

    function setUp() external {
        auction = new Auction(
            ESCROW,
            EXPECTED_DAILY_RETURN,
            MAX_DISCOUNT_RATE,
            MIN_DURATION
        );

        mock = new AuctionMock(payable(msg.sender));

        for (uint i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }

        // nodeOps[9] is whitelisted
        auction.addNodeOpToWhitelist(nodeOps[9]);
    }

    function test_AddToWhitelist() external {
        // First, nodeOps[0] wants to add himself to the whitelist
        vm.prank(nodeOps[0]);
        vm.expectRevert(bytes("Not the owner."));
        auction.addNodeOpToWhitelist(nodeOps[0]);

        // Byzantine adds nodeOps[0] to the whitelist
        auction.addNodeOpToWhitelist(nodeOps[0]);
        assertTrue(auction.isWhitelisted(nodeOps[0]));

        // Should revert if Byzantine add a second time nodeOps[0] to the whitelist
        vm.expectRevert(bytes("Address already whitelisted"));
        auction.addNodeOpToWhitelist(nodeOps[0]);
    }

    function test_RemoveFromWhitelist() external {
        // Byzantine add nodeOps[0] to the whitelist
        auction.addNodeOpToWhitelist(nodeOps[0]);

        // Should revert if Byzantine remove a non-whitelisted address
        vm.expectRevert(bytes("Address is not whitelisted"));
        auction.removeNodeOpFromWhitelist(nodeOps[1]);

        // Byzantine removes nodeOps[0] from the whitelist
        auction.removeNodeOpFromWhitelist(nodeOps[0]);
        assertFalse(auction.isWhitelisted(nodeOps[0]));
    }

    function testBid_RevertWhen_NodeOpAlreadyInAuction() external {
        // nodeOps[0] bids (10%, 30 days)
        _nodeOpBid(nodeOps[0], 10e2, 30);

        // nodeOps[0] does a second bid (15%, 45 days)
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 15e2, 45);
        vm.prank(nodeOps[0]);
        vm.expectRevert(bytes("Already in auction, call updateBid function"));
        auction.bid{value: priceToPay}(15e2, 45);
    }

    function testBid_RevertWhen_WrongBidParameters() external {
        // nodeOps[0] bids with invalid duration (15%, 10 days)
        vm.startPrank(nodeOps[0]);
        vm.expectRevert(bytes("Validating duration too short"));
        auction.getPriceToPay(nodeOps[0], 15e2, 10);
        vm.expectRevert(bytes("Validating duration too short"));
        auction.bid{value: 9 ether}(15e2, 10);
        vm.stopPrank();

        // nodeOps[1] bids with invalid discount rate (16%, 30 days)
        vm.startPrank(nodeOps[1]);
        vm.expectRevert(bytes("Discount rate too high"));
        auction.getPriceToPay(nodeOps[1], 16e2, 30);
        vm.expectRevert(bytes("Discount rate too high"));
        auction.bid{value: 9 ether}(16e2, 30);
        vm.stopPrank();
    }

    function testBid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[0] bids (15%, 45 days)
        uint256 priceToPay = auction.getPriceToPay(nodeOps[0], 15e2, 45);
        vm.prank(nodeOps[0]);
        vm.expectRevert(bytes("Not enough ethers sent"));
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
        _nodeOpBid(nodeOps[0], 10e2, 30);
        (,,uint256 auctionScore_0,,) = auction.getNodeOpDetails(nodeOps[0]);
        address auctionScoreToNodeOp = auction.getAuctionScoreToNodeOp(auctionScore_0);
        assertEq(auctionScoreToNodeOp, nodeOps[0]);

        // nodeOps[1] bids (11%, 30 days)
        _nodeOpBid(nodeOps[1], 11e2, 30);
        (,,uint256 auctionScore_1,,) = auction.getNodeOpDetails(nodeOps[1]);
        auctionScoreToNodeOp = auction.getAuctionScoreToNodeOp(auctionScore_1);
        assertEq(auctionScoreToNodeOp, nodeOps[1]);

        // Revert if nodeOps[2] bids the same as nodeOps[1]
        uint256 priceToPay = auction.getPriceToPay(nodeOps[2], 11e2, 30);
        vm.prank(nodeOps[2]);
        vm.expectRevert(bytes("Auction Score already exists"));
        auction.bid{value: priceToPay}(11e2, 30);
    }

    function testUpdateBid_RevertWhen_NodeOpNotInAuction() external {
        // nodeOps[0] updates its bid but hasn't bid
        vm.expectRevert(bytes("Not in auction, call bid function"));
        auction.updateBid{value: 8 ether}(15e2, 45);
    }

    function testUpdateBid_Outbid_RevertWhen_NotEnoughEthSent() external {
        // nodeOps[9] bids (15%, 30 days)
        _nodeOpBid(nodeOps[9], 15e2, 30);

        // nodeOps[9] updates its bid (5%, 3 days)
        uint256 amountToAdd = auction.getUpdateBidPrice(nodeOps[9], 5e2, 30);
        vm.prank(nodeOps[9]);
        vm.expectRevert(bytes("Not enough ethers sent to outbid"));
        auction.updateBid{value: (amountToAdd - 0.001 ether)}(5e2, 30);
    }

    function testUpdateBid_Outbid_RefundTheSkimmingEthers() external {
        // Verify the initial balance of nodeOps[9]
        assertEq(nodeOps[9].balance, STARTING_BALANCE);

        // nodeOps[9] bids (5%, 30 days)
        uint256 bidPrice = auction.getPriceToPay(nodeOps[9], 5e2, 30);
        _nodeOpBid(nodeOps[9], 5e2, 30);

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
        _nodeOpBid(nodeOps[9], 5e2, 90);
        (,,uint256 FirstAuctionScore,,) = auction.getNodeOpDetails(nodeOps[9]);

        // nodeOps[8] bids (5%, 120 days)
        _nodeOpBid(nodeOps[8], 5e2, 120);

        // nodeOps[9] updates its bid (14%, 90 days)
        _nodeOpUpdateBid(nodeOps[9], 14e2, 90);
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
        vm.expectRevert(bytes("Auction Score already exists"));
        auction.updateBid{value: priceToPay}(14e2, 90);
    }

    function testUpdateBid_NodeOpStruct() external {
        // nodeOps[9] bids (5%, 90 days)
        _nodeOpBid(nodeOps[9], 5e2, 90);

        // nodeOps[9] updates its bid (10%, 60 days)
        _nodeOpUpdateBid(nodeOps[9], 10e2, 60);
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
        assertEq(_expectedDailyReturnWei, EXPECTED_DAILY_RETURN);
        assertEq(_maxDiscountRate, MAX_DISCOUNT_RATE);
        assertEq(_minDuration, MIN_DURATION);
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
        _nodeOpBid(nodeOps[0], 5e2, 30);
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
        _nodeOpBid(nodeOps[1], 10e2, 60);
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
        // nodeOps[0] withdraw its bid but hasn't had bid
        vm.expectRevert(bytes("Not in auction, cannot withdraw"));
        auction.withdrawBid();
    }

    function testWithdrawBid() external {
        // nodeOps[0] bid with discountRate = 13% and timeInDays = 100
        _nodeOpBid(nodeOps[0], 13e2, 100);
        (,,uint256 auctionScoreBeforeWithdrawal,,) = auction.getNodeOpDetails(nodeOps[0]);

        // nodeOps[0] withdraw its bid
        vm.prank(nodeOps[0]);
        auction.withdrawBid();

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
        _nodeOpBid(nodeOps[0], 13e2, 100);
    }

    /*function test_TopFourWinnersAreSelectedIfClusterSizeIsFour() external {
        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();

        // Sort and get top winners
        address[] memory topWinners = auction.sortAndGetTopWinners();
        // Cluster size is 4, so only top 4 winners should be returned
        assertEq(topWinners.length, 4);

        // Check if the top winners are the correct operators. The order doesn't matter.
        assertEq(topWinners[0], OPERATOR_8);
        assertEq(topWinners[1], OPERATOR_7);
        assertEq(topWinners[2], OPERATOR_5);
        assertEq(topWinners[3], OPERATOR_10);
    }*/

    /*function test_TopSevenWinnersAreSelectedIfClusterSizeIsSeven() external {
        // Update cluster size to 7
        auction.updateClusterSize(7);

        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();

        // Sort and get top winners
        address[] memory topWinners = auction.sortAndGetTopWinners();
        // Cluster size is 7, so only top 4 winners should be returned
        assertEq(topWinners.length, 7);

        // Check if the top winners are the correct operators. The order doesn't matter.
        assertEq(topWinners[0], OPERATOR_1);
        assertEq(topWinners[1], OPERATOR_9);
        assertEq(topWinners[2], OPERATOR_8);
        assertEq(topWinners[3], OPERATOR_4);
        assertEq(topWinners[4], OPERATOR_5);
        assertEq(topWinners[5], OPERATOR_10);
        assertEq(topWinners[6], OPERATOR_7);
    }*/

    /*function test_OnlyOperatorsWithInProtocolStatusAreSubjectToAuctionSort()
        external
    {
        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();

        // First auction runs and top winners are selected
        auction.sortAndGetTopWinners();
        // Noted that the winners are OPERATOR_5, OPERATOR_7, OPERATOR_8, OPERATOR_10
        assertEq(uint(getOperatorStatus(OPERATOR_10)), 1); // auctionWinner status

        // Operators with auctionWinner status are not subject to new auction sort

        // Second auction runs and top winners are selected
        // Check if the top winners are the correct operators
        address[] memory topWinners = auction.sortAndGetTopWinners();
        assertEq(topWinners[0], OPERATOR_1);
        assertEq(topWinners[1], OPERATOR_9);
        assertEq(topWinners[2], OPERATOR_6);
        assertEq(topWinners[3], OPERATOR_4);
    }*/

    /*function test_RevertWhen_NumberOfOperatorsIsLessThanClusterSize() external {
        // Update cluster size to 11
        auction.updateClusterSize(11);

        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();

        // Sort and get top winners
        vm.expectRevert(bytes("No enough operators for the cluser."));
        auction.sortAndGetTopWinners();
    }*/

    /*function test_WinnerOperatorCanAcceptAndPayBid() external {
        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();
        // Sort and get top winners
        auction.sortAndGetTopWinners();

        // Noted that the winners are OPERATOR_5, OPERATOR_7, OPERATOR_8, OPERATOR_10
        // Check winner status, all should be 1, auctionWinner
        assertEq(uint(getOperatorStatus(OPERATOR_5)), 1);
        assertEq(uint(getOperatorStatus(OPERATOR_10)), 1);

        // OPERATOR_5 accepts and pays the bid
        vm.prank(OPERATOR_5);
        console.log(OPERATOR_5.balance);
        auction.acceptAndPayBid();
        console.log(OPERATOR_5.balance);
        // Operator_5 status should be updated to 2, pendingForDvt
        assertEq(uint(getOperatorStatus(OPERATOR_5)), 2);
        // Calculate the bid price for OPERATOR_5
        (uint256 bidPrice_5, , , ) = auction.getNodeOpStruct(OPERATOR_5);

        // Check the balance of the vault
        assertEq(address(VAULT).balance, bidPrice_5);

        // OPERATOR_10 accepts and pays the bid
        vm.prank(OPERATOR_10);
        auction.acceptAndPayBid();
        // Calculate the bid price for OPERATOR_10
        (uint256 bidPrice_10, , , ) = auction.getNodeOpStruct(OPERATOR_10);

        // Check the balance of the vault
        assertEq(address(VAULT).balance, bidPrice_5 + bidPrice_10);
    }*/

    /* ===================== HELPER FUNCTIONS ===================== */

    function _nodeOpBid(
        address _nodeOp,
        uint256 _discountRate,
        uint256 _timeInDays
    ) internal {
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(_nodeOp, _discountRate, _timeInDays);
        vm.prank(_nodeOp);
        auction.bid{value: priceToPay}(_discountRate, _timeInDays);
    }

    function _nodeOpUpdateBid(
        address _nodeOp,
        uint256 _newDiscountRate,
        uint256 _newTimeInDays
    ) internal {
        // Get price to pay
        uint256 priceToAdd = auction.getUpdateBidPrice(_nodeOp, _newDiscountRate, _newTimeInDays);
        vm.prank(_nodeOp);
        auction.updateBid{value: priceToAdd}(_newDiscountRate, _newTimeInDays);
    }

    /*function leaveProtocol(address operator) internal {
        vm.prank(operator);
        auction.leaveProtocol();
    }

    function getAuctionScoreOfTheOperator(
        address operator
    ) internal view returns (uint256) {
        (, uint256 auctionScore, , ) = auction.getNodeOpStruct(operator);
        return auctionScore;
    }

    function getOperatorStatus(
        address operator
    ) internal view returns (Auction.NodeOpStatus) {
        (, , , Auction.NodeOpStatus opStatus) = auction.getNodeOpStruct(
            operator
        );
        return opStatus;
    }

    function letTenOperatorsJoinProtocol() internal {
        // Operator_1 joins the protocol with discountRate = 2% and timeInDays = 30
        operatorJoinsProtocol(OPERATOR_1, 2e2, 30);
        console.log("Operator_1: ", OPERATOR_1);
        console.log(
            "Operator_1 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_1)
        );

        // Operator_2 joins the protocol with discountRate = 10% and timeInDays = 60
        operatorJoinsProtocol(OPERATOR_2, 10e2, 60);
        console.log("Operator_2: ", OPERATOR_2);
        console.log(
            "Operator_2 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_2)
        );

        // Operator_3 joins the protocol with discountRate = 15% and timeInDays = 30
        operatorJoinsProtocol(OPERATOR_3, 15e2, 30);
        console.log("Operator_3: ", OPERATOR_3);
        console.log(
            "Operator_3 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_3)
        );

        // Operator_4 joins the protocol with discountRate = 14% and timeInDays = 180
        operatorJoinsProtocol(OPERATOR_4, 14e2, 180);
        console.log("Operator_4: ", OPERATOR_4);
        console.log(
            "Operator_4 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_4)
        );

        // Operator_5 joins the protocol with discountRate = 8% and timeInDays = 365
        operatorJoinsProtocol(OPERATOR_5, 8e2, 365);
        console.log("Operator_5: ", OPERATOR_5);
        console.log(
            "Operator_5 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_5)
        );

        // Operator_6 joins the protocol with discountRate = 3% and timeInDays = 30
        operatorJoinsProtocol(OPERATOR_6, 3e2, 30);
        console.log("Operator_6: ", OPERATOR_6);
        console.log(
            "Operator_6 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_6)
        );

        // Operator_7 joins the protocol with discountRate = 5% and timeInDays = 180
        operatorJoinsProtocol(OPERATOR_7, 5e2, 180);
        console.log("Operator_7: ", OPERATOR_7);
        console.log(
            "Operator_7 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_7)
        );

        // Operator_8 joins the protocol with discountRate = 2% and timeInDays = 365
        operatorJoinsProtocol(OPERATOR_8, 2e2, 365);
        console.log("Operator_8: ", OPERATOR_8);
        console.log(
            "Operator_8 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_8)
        );

        // Operator_9 joins the protocol with discountRate = 7% and timeInDays = 90
        operatorJoinsProtocol(OPERATOR_9, 7e2, 90);
        console.log("Operator_9: ", OPERATOR_9);
        console.log(
            "Operator_9 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_9)
        );

        // Operator_10 joins the protocol with discountRate = 15% and timeInDays = 365
        operatorJoinsProtocol(OPERATOR_10, 15e2, 365);
        console.log("Operator_10: ", OPERATOR_10);
        console.log(
            "Operator_10 auction score: ",
            getAuctionScoreOfTheOperator(OPERATOR_10)
        );
    }*/
}
