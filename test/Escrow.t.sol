// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {IEscrow} from "../src/interfaces/IEscrow.sol";
import "./ByzantineDeployer.t.sol";

contract EscrowTest is ByzantineDeployer {

    address someone = makeAddr("someone");

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        vm.deal(address(auction), 1000 ether);
        vm.deal(someone, 1000 ether);
    }

    function testReceiveFunds() external {
        vm.prank(address(auction));
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
        vm.startPrank(address(auction));
        (bool success, ) = address(escrow).call{value: 500}("");
        require(success, "Failed to send Ether");
        assertEq(address(escrow).balance, 500);
        vm.expectRevert(IEscrow.InsufficientFundsInEscrow.selector);
        escrow.releaseFunds(1000);
        escrow.releaseFunds(100);
        assertEq(address(escrow).balance, 400);
        assertEq(address(stakerRewards).balance, 100);
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
        vm.startPrank(address(auction));
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
