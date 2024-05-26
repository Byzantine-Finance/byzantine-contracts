// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {Escrow} from "../src/vault/Escrow.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import {Test, console} from "forge-std/Test.sol";

contract EscrowTest is Test {
    Escrow escrow;

    address auctionContract = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address BID_PRICE_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address someone = makeAddr("someone");

    function setUp() external {
        escrow = new Escrow(BID_PRICE_RECEIVER);

        vm.deal(auctionContract, 1000);
        vm.deal(someone, 1000);
    }

    function testGrantRoleToAuction_RevertWhen_calledByNonAdminRoleAddress()
        external
    {
        vm.prank(someone);
        vm.expectRevert();
        escrow.grantRoleToAuction(auctionContract);
    }

    function test_GrantRoleToAuction() external {
        escrow.grantRoleToAuction(auctionContract);
    }

    function testReceiveFunds() external {
        escrow.grantRoleToAuction(auctionContract);
        vm.prank(auctionContract);
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
        escrow.grantRoleToAuction(auctionContract);
        vm.startPrank(auctionContract);
        (bool success, ) = address(escrow).call{value: 500}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 500);
        escrow.releaseFunds(100);
        assertEq(address(escrow).balance, 400);
        vm.stopPrank();
    }

    function testReleaseFunds_RevertWhen_calledByNonAuctionRoleAddress()
        external
    {
        vm.startPrank(someone);
        (bool success, ) = address(escrow).call{value: 500}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 500);

        vm.expectRevert();
        escrow.releaseFunds(500);
        assertEq(address(escrow).balance, 500);
    }

    function test_Refund() external {
        escrow.grantRoleToAuction(auctionContract);
        vm.startPrank(auctionContract);
        (bool success, ) = address(escrow).call{value: 1000}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 1000);

        escrow.refund(payable(someone), 400);
        assertEq(address(escrow).balance, 600);
        assertEq(address(someone).balance, 1400);
        vm.stopPrank();
    }
}
