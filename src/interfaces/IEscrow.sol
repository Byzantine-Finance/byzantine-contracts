// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrow {
    event FundsLocked(uint256 _amount);

    /**
     * @notice Function to be called once the contract is deployed to grant AUCTION_ROLE to the auction contract
     * @param _auctionAddr Address of the auction contract
     */
    function grantRoleToAuction(address _auctionAddr) external;

    /**
     * @notice Function to approve the pid price of the winner operator to be released to the final bid price receiver
     * @param _bidPrice Bid price of the node operator
     */
    function releaseFunds(uint256 _bidPrice) external;

    /**
     * @notice Function to refund the overpaid amount to the node operator after updating the bid or
     * refund the total amount to the node operator if the operator leaves the protocol
     * @param _amountToRefund Funds to be refunded to the node operator if the newBidPrice < oldBidPrice
     */
    function refund(address _nodeOpAddr, uint256 _amountToRefund) external;
}