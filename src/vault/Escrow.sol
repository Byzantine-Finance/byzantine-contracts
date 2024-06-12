// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEscrow} from "../interfaces/IEscrow.sol";
import {IAuction} from "../interfaces/IAuction.sol";

contract Escrow is IEscrow {

    /**
     * @notice Address which receives the bid of the auction winners
     * @dev This will be updated to a smart contract vault in the future to distribute the stakers rewards
     */
    address public immutable bidPriceReceiver;

    /// @notice Auction contract
    IAuction public immutable auction;

    /**
     * @notice Constructor to set the bidPriceReceiver address and the auction contract
     * @param _bidPriceReceiver Address which receives the bid of the winners and distribute it to the stakers
     * @param _auction The auction proxy contract
     */
    constructor(address _bidPriceReceiver, IAuction _auction) {
        bidPriceReceiver = _bidPriceReceiver;
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
        (bool success, ) = payable(bidPriceReceiver).call{value: _bidPrice}("");
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
