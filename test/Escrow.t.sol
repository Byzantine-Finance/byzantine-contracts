// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {Test, console} from "forge-std/Test.sol";
import {Escrow} from "../src/vault/Escrow.sol";

contract EscrowTest is Test {
    Escrow escrow;

    address auctionContract = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address bidPriceReceiver = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address someone = makeAddr("someone");

    function setUp() external {
        escrow = new Escrow(auctionContract, bidPriceReceiver);

        vm.deal(auctionContract, 1000);
        vm.deal(someone, 1000);
    }

    function test_LockFunds() external {
        vm.prank(auctionContract);
        escrow.lockFunds{value: 1000}();
        assertEq(address(escrow).balance, 1000);
    }

    function testLockFunds_RevertWhen_CalledByNonAuctionContract() external {
        console.log("msg sender: ", msg.sender);
        vm.prank(someone);
        vm.expectRevert(bytes("Caller is not the Auction contract."));
        escrow.lockFunds{value: 1}();
    }

    function test_ReleaseFunds() external {
        vm.startPrank(auctionContract);
        escrow.lockFunds{value: 1000}();
        assertEq(address(escrow).balance, 1000);
        escrow.releaseFunds(1000);
        assertEq(address(escrow).balance, 0);
        vm.stopPrank();
    }

    function test_Refund() external {
        vm.startPrank(auctionContract);
        escrow.lockFunds{value: 1000}();
        assertEq(address(escrow).balance, 1000);
        uint256 balanceBeforeRefund = address(someone).balance;
        escrow.refund(payable(someone), 1000);
        assertEq(address(escrow).balance, 0);
        assertEq(address(someone).balance, balanceBeforeRefund + 1000);
        vm.stopPrank();
    }
}
