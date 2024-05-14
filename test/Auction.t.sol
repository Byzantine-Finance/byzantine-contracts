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

    address VAULT = makeAddr("vault");
    uint256 EXPECTED_RETURN = (uint256(32 ether) * 37) / 1000 / 365; //3243835616438356
    uint112 MAX_DISCOUNT_RATE = 15e2;
    uint MIN_DURATION = 30;
    uint256 OPERATOR_BOND = 1 ether;

    address OPERATOR_1 = makeAddr("operator_1");
    address OPERATOR_2 = makeAddr("operator_2");
    address OPERATOR_3 = makeAddr("operator_3");
    address OPERATOR_4 = makeAddr("operator_4");
    address OPERATOR_5 = makeAddr("operator_5");
    address OPERATOR_6 = makeAddr("operator_6");
    address OPERATOR_7 = makeAddr("operator_7");
    address OPERATOR_8 = makeAddr("operator_8");
    address OPERATOR_9 = makeAddr("operator_9");
    address OPERATOR_10 = makeAddr("operator_10");
    address RANDOM_ADDRESS = makeAddr("random_address");
    uint256 constant BOND_VALUE = 1 ether;
    uint256 constant STARTING_BALANCE = 10 ether;

    function setUp() external {
        auction = new Auction(
            VAULT,
            EXPECTED_RETURN,
            MAX_DISCOUNT_RATE,
            MIN_DURATION,
            OPERATOR_BOND
        );

        mock = new AuctionMock(payable(msg.sender));

        vm.deal(OPERATOR_1, STARTING_BALANCE);
        vm.deal(OPERATOR_2, STARTING_BALANCE);
        vm.deal(OPERATOR_3, STARTING_BALANCE);
        vm.deal(OPERATOR_4, STARTING_BALANCE);
        vm.deal(OPERATOR_5, STARTING_BALANCE);
        vm.deal(OPERATOR_6, STARTING_BALANCE);
        vm.deal(OPERATOR_7, STARTING_BALANCE);
        vm.deal(OPERATOR_8, STARTING_BALANCE);
        vm.deal(OPERATOR_9, STARTING_BALANCE);
        vm.deal(OPERATOR_10, STARTING_BALANCE);
    }

    function test_OperatorsCorrectlyJoinedAndLeftProtocol() external {
        // Operator_1 joins the protocol
        operatorJoinsProtocol(OPERATOR_1, 5e2, 30);
        assertEq(auction.getNumberOfNodeOps(), 1);

        // Operator_2 joins the protocol
        operatorJoinsProtocol(OPERATOR_2, 10e2, 60);

        // Check the balance of the auction contract with two operators joined
        assertEq(address(auction).balance, 2 ether);

        // Check the list of operators in the protocol
        address[] memory expectedOperators = new address[](2);
        expectedOperators[0] = OPERATOR_1;
        expectedOperators[1] = OPERATOR_2;
        assertEq(auction.getListOfNodeOps(), expectedOperators);

        // Operator_1 leaves the protocol
        vm.startPrank(OPERATOR_1);
        auction.leaveProtocol();
        // Check the balance of the auction contract
        assertEq(address(auction).balance, 1 ether);
        vm.stopPrank();

        // Check number of operators in the protocol
        assertEq(auction.getNumberOfNodeOps(), 1);
        // Check if operator is in the protocol
        assertEq(auction.operatorInProtocol(OPERATOR_1), false);
    }

    function test_RevertWhen_OperatorJoinsProtocolWithInvalidValues() external {
        // Operator_1 joins the protocol with lower bond value
        vm.prank(OPERATOR_1);
        vm.expectRevert(bytes("Bond value must be 1 ETH."));
        auction.joinProtocol{value: 0.5 ether}(5e2, 30);
        vm.stopPrank();

        // Operator_1 joins the protocol with invalid discount rate
        vm.prank(OPERATOR_1);
        vm.expectRevert(bytes("Discount rate exceeds the maximum."));
        auction.joinProtocol{value: BOND_VALUE}(16e2, 29);
        vm.stopPrank();

        // Operator_1 joins the protocol with invalid time duration
        vm.prank(OPERATOR_1);
        vm.expectRevert(bytes("Time in days must be >= 30."));
        auction.joinProtocol{value: BOND_VALUE}(10e2, 29);
        vm.stopPrank();
    }

    function test_RevertWhen_NotMemberOperatorsCallAnyFunction() external {
        // Operator_1 joins and then leaves the protocol
        operatorJoinsProtocol(OPERATOR_1, 5e2, 30);
        leaveProtocol(OPERATOR_1);

        // Left operator tries to update bid without joining the protocol
        vm.startPrank(OPERATOR_1);
        vm.expectRevert(bytes("Operator not in protocol."));
        auction.updateBid(300, 40);

        // Left operator is no longer in the protocol, so cannot call getNodeOpStruct
        vm.expectRevert();
        auction.getNodeOpStruct(OPERATOR_1);
        vm.stopPrank();

        // Operators who are not in the protocol cannot leave the protocol or update bid
        vm.startPrank(OPERATOR_3);
        vm.expectRevert();
        auction.leaveProtocol();
        vm.expectRevert(bytes("Operator not in protocol."));
        auction.updateBid(300, 40);
        vm.stopPrank();
    }

    function test_RevertWhen_AnyAddressExceptByzantineCallsOnlyOwnerFunctions()
        external
    {
        // Operator_1 joins the protocol
        operatorJoinsProtocol(OPERATOR_1, 5e2, 30);

        vm.startPrank(OPERATOR_1);
        vm.expectRevert();
        auction.sortAndGetTopWinners();
        vm.expectRevert();
        auction.updateAuctionConfig(0.003 ether, 10e2, 60, 1 ether);
        vm.expectRevert();
        auction.updateClusterSize(6);
        vm.expectRevert();
        auction.sendFundsToByzantine();
        vm.expectRevert();
        auction.operatorInProtocol(OPERATOR_1);
        vm.expectRevert();
        auction.getNumberOfNodeOps();
        vm.expectRevert();
        auction.getListOfNodeOps();
        vm.stopPrank();
    }

    function test_UpdateAuctionConfigWorksCorrectly() external {
        (
            uint256 _expectedReturnWei,
            uint256 _maxDiscountRate,
            uint256 _minDuration,
            uint256 _operatorBond,
            uint256 _clusterSize
        ) = auction.getAuctionConfigValues();

        // Check if the initial values are correct
        assertEq(_expectedReturnWei, EXPECTED_RETURN);
        assertEq(_maxDiscountRate, MAX_DISCOUNT_RATE);
        assertEq(_minDuration, MIN_DURATION);
        assertEq(_operatorBond, BOND_VALUE);
        assertEq(_clusterSize, 4);

        // Update auction configuration
        auction.updateAuctionConfig(0.003 ether, 10e2, 60, 1.5 ether);

        // After update
        (
            uint256 _newExpectedReturnWei,
            uint256 _newMaxDiscountRate,
            uint256 _newMinDuration,
            uint256 _newOperatorBond,
            uint256 _newClusterSize
        ) = auction.getAuctionConfigValues();

        // Check if the auction configuration is updated correctly
        assertEq(_newExpectedReturnWei, 0.003 ether);
        assertEq(_newMaxDiscountRate, 10e2);
        assertEq(_newMinDuration, 60);
        assertEq(_newOperatorBond, 1.5 ether);
        assertEq(_newClusterSize, 4);
    }

    function test_OperatorUpdatesBidCorrectly() external {
        // Operator_1 joins the protocol
        operatorJoinsProtocol(OPERATOR_1, 5e2, 30);

        // Update bid for Operator_1
        vm.startPrank(OPERATOR_1);
        auction.updateBid(14e2, 365);

        // Check if the bid is updated correctly
        (
            uint256 bidPrice,
            uint256 auctionScore,
            uint256 reputationScore,
            Auction.NodeOpStatus opStatus
        ) = auction.getNodeOpStruct(OPERATOR_1);

        assertEq(bidPrice, 254559999999999790);
        assertEq(auctionScore, 1004466779031871);
        assertEq(reputationScore, 1);
        assertEq(uint(opStatus), 0);

        vm.stopPrank();
    }

    function test_CalculationsWorkCorrectly() external {
        // Operator_2 joins the protocol with discountRate = 5% and timeInDays = 30
        operatorJoinsProtocol(OPERATOR_1, 5e2, 30);
        assertEq(auction.getNumberOfNodeOps(), 1);

        (
            uint256 bidPrice_1,
            uint256 auctionScore_1,
            uint256 reputationScore_1,
            Auction.NodeOpStatus opStatus_1
        ) = auction.getNodeOpStruct(OPERATOR_1);

        // Check if the value of bidPrice for Operator_1 is calculated correctly
        assertEq(bidPrice_1, 23112328767123270);
        // Check if the value of auctionScore for Operator_1 is calculated correctly
        assertEq(auctionScore_1, 793861565530208);
        // Check other values in the operatorStruct
        assertEq(reputationScore_1, 1);
        assertEq(uint(opStatus_1), 0);

        // Operator_2 joins the protocol with discountRate = 10% and timeInDays = 60
        operatorJoinsProtocol(OPERATOR_2, 10e2, 60);
        assertEq(auction.getNumberOfNodeOps(), 2);
        (
            uint256 bidPrice_2,
            uint256 auctionScore_2,
            uint256 reputationScore_2,
            Auction.NodeOpStatus opStatus_2
        ) = auction.getNodeOpStruct(OPERATOR_2);

        // Check if the value of bidPrice for Operator_2 is calculated correctly
        assertEq(bidPrice_2, 43791780821917800);
        // Check if the value of auctionScore for Operator_2 is calculated correctly
        assertEq(auctionScore_2, 774971987896852);
        assertEq(reputationScore_2, 1);
        assertEq(uint(opStatus_2), 0);
    }

    function test_TopFourWinnersAreSelectedIfClusterSizeIsFour() external {
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
    }

    function test_TopSevenWinnersAreSelectedIfClusterSizeIsSeven() external {
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
    }

    function test_OnlyOperatorsWithInProtocolStatusAreSubjectToAuctionSort()
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
    }

    function test_RevertWhen_NumberOfOperatorsIsLessThanClusterSize() external {
        // Update cluster size to 11
        auction.updateClusterSize(11);

        // Supposing that 10 operators have joined the protocol
        letTenOperatorsJoinProtocol();

        // Sort and get top winners
        vm.expectRevert(bytes("No enough operators for the cluser."));
        auction.sortAndGetTopWinners();
    }

    function test_WinnerOperatorCanAcceptAndPayBid() external {
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
        auction.acceptAndPayBid();
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
    }

    function test_SendFundsFromVaultToByzantine() external {
        // Use AuctionMock to simulate the scenario where funds are sent to Byzantine
        vm.deal(address(mock), 10 ether);
        assertEq(address(mock).balance, 10 ether);

        vm.prank(msg.sender);
        // Test the sendFundsToByzantine function in Auction contract
        mock.sendFundsToByzantine();

        // After sending funds to Byzantine
        assertEq(address(mock).balance, 0);
    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function operatorJoinsProtocol(
        address operator,
        uint256 _discountRate,
        uint256 _timeInDays
    ) internal {
        vm.prank(operator);
        auction.joinProtocol{value: BOND_VALUE}(_discountRate, _timeInDays);
    }

    function leaveProtocol(address operator) internal {
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
    }
}
