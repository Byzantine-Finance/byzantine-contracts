// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {BidInvestmentMock} from "../../test/mocks/BidInvestmentMock.sol";

contract Escrow is IEscrow {

    /**
     * @notice Address which receives the bid of the auction winners
     */
    BidInvestmentMock public immutable bidInvestment;

    /// @notice Auction contract
    IAuction public immutable auction;

    /**
    * @dev This empty reserved space is put in place to allow future versions to add new
    * variables without shifting down storage in the inheritance chain.
    * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
    */
    uint256[44] private __gap;

    /**
     * @notice Constructor to set the bidInvestment and the auction contracts
     * @param _bidInvestment Address which receives the bid of the winners
     * @param _auction The auction proxy contract
     */
    constructor(BidInvestmentMock _bidInvestment, IAuction _auction) {
        bidInvestment = _bidInvestment;
        auction = _auction;
    }

    /**
     * @notice Fallback function which receives funds of the node operator when they bid
     * Also receives new funds after a node operator updates its bid
     * @dev The funds are locked in the escrow
     */
    receive() external payable {
        emit FundsLocked(msg.value);
    }

    /**
     * @notice Function to approve the bid price of the winner operator to be released to the bid price receiver
     * @param _bidPrice Bid price of the node operator
     */
    function releaseFunds(uint256 _bidPrice) public onlyAuction {
        if (address(this).balance < _bidPrice) revert InsufficientFundsInEscrow();
        (bool success, ) = address(bidInvestment).call{value: _bidPrice}("");
        if (!success) revert FailedToSendEther();
    }

    /**
     * @notice Function to refund the overpaid amount to the node operator after bidding or updating its bid.
     * Also used to refund the node operator when he withdraws
     * @param _nodeOpAddr Address of the node operator to refund
     * @param _amountToRefund Funds to be refunded to the node operator if necessary
     */
    function refund(
        address _nodeOpAddr,
        uint256 _amountToRefund
    ) public onlyAuction {
        if (address(this).balance < _amountToRefund) revert InsufficientFundsInEscrow();
        (bool success, ) = payable(_nodeOpAddr).call{value: _amountToRefund}("");
        if (!success) revert FailedToSendEther();
    }

    modifier onlyAuction() {
        if (msg.sender != address(auction)) revert OnlyAuction();
        _;
    }
}
