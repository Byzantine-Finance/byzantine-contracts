// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrow {
    event FundsLocked(uint256 _amount);

    /**
     * @notice Function to approve the bid price of the winner operator to be released to the bid price receiver
     * @param _bidPrice Bid price of the node operator
     */
    function releaseFunds(uint256 _bidPrice) external;

    /**
     * @notice Function to refund the overpaid amount to the node operator after bidding or updating its bid.
     * Also used to refund the node operator when he withdraws
     * @param _nodeOpAddr Address of the node operator to refund
     * @param _amountToRefund Funds to be refunded to the node operator if necessary
     */
    function refund(address _nodeOpAddr, uint256 _amountToRefund) external;

    /// @dev Error when unauthorized call to a function callable only by the Auction.
    error OnlyAuction();

    /// @dev Returned when not enough funds in the escrow to refund ops or move funds.
    error InsufficientFundsInEscrow();
}