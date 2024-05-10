// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore

import {Test, console} from "forge-std/Test.sol";
import {Auction} from "../src/core/Auction.sol";

contract AuctionTest is Test {
    Auction auction;
    function setUp() external {
        auction = new Auction(
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            (uint256(32 ether) * 37) / 1000 / 365,
            15e18,
            30,
            1 ether
        );
    }

    function testVariables() external view {
        assertEq(
            auction.expectedReturn(),
            (uint256(32 ether) * 37) / 1000 / 365
        );
        assertEq(auction.maxDiscountRate(), 15e18);
        assertEq(auction.minDuration(), 30);
        assertEq(auction.operatorBond(), 1 ether);
        assertEq(auction.vault(), 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    }


}
