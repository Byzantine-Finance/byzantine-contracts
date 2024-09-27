// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {IAuction} from "../src/interfaces/IAuction.sol";
import {IEscrow} from "../src/interfaces/IEscrow.sol";
import {Escrow} from "../src/vault/Escrow.sol";

import {Test, console} from "forge-std/Test.sol";

contract EscrowTest is Test {
    IEscrow escrow;

    address auctionContractAddr = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address BID_PRICE_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address someone = makeAddr("someone");

    function setUp() external {
        escrow = new Escrow(BID_PRICE_RECEIVER, IAuction(auctionContractAddr));

        vm.deal(auctionContractAddr, 1000 ether);
        vm.deal(someone, 1000 ether);
    }

    function testReceiveFunds() external {
        vm.prank(auctionContractAddr);
        (bool success, ) = address(escrow).call{value: 200}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 200);
    }

    function test_ReceiveFunds_AnyoneCanSendFundsToEscrow() external {
        vm.prank(someone);
        (bool success, ) = address(escrow).call{value: 100}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 100);
    }

    function test_ReleaseFunds() external {
        vm.startPrank(auctionContractAddr);
        (bool success, ) = address(escrow).call{value: 500}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 500);
        vm.expectRevert(IEscrow.InsufficientFundsInEscrow.selector);
        escrow.releaseFunds(1000);
        escrow.releaseFunds(100);
        assertEq(address(escrow).balance, 400);
        assertEq(BID_PRICE_RECEIVER.balance, 100);
        vm.stopPrank();
    }

    function testReleaseFunds_RevertWhen_calledByNonAuctionRoleAddress() external {
        vm.startPrank(someone);
        (bool success, ) = address(escrow).call{value: 500}("");
        require(success, "Failed to send Ether");

        vm.expectRevert(IEscrow.OnlyAuction.selector);
        escrow.releaseFunds(500);
        assertEq(address(escrow).balance, 500);
        vm.stopPrank();
    }

    function test_Refund() external {
        vm.startPrank(auctionContractAddr);
        (bool success, ) = address(escrow).call{value: 1000}("");
        require(success, "Failed to send Ether");

        vm.expectRevert(IEscrow.InsufficientFundsInEscrow.selector);
        escrow.refund(payable(someone), 2000);

        escrow.refund(payable(someone), 400);
        assertEq(address(escrow).balance, 600);
        assertEq(address(someone).balance, 1000 ether + 400);
        vm.stopPrank();
    }
}
