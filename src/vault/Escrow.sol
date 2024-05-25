// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract Escrow {
    /// @notice address of the auction contract
    address public auctionContract;
    /// @notice Address which receives the final bid prices
    address payable public bidPriceReceiver;

    /// @notice Constructor to set the auction contract and bidPriceReceiver addresses
    constructor(address _auctionContract, address _bidPriceReceiver) {
        auctionContract = _auctionContract;
        bidPriceReceiver = payable(_bidPriceReceiver);
    }

    event FundsLocked(uint256 _amount);

    /**
     * @notice Function to receive funds of the node operator at the time of joining the protocol
     * Same function to receive new funds after a node operator updates the bid
     * @dev The funds are locked in the escrow
     */
    function lockFunds() public payable onlyAuction {
        emit FundsLocked(msg.value);
    }

    /**
     * @notice Function to approve the pid price of the winner operator to be released to the final bid price receiver
     * @param _bidPrice Bid price of the node operator
     */
    function releaseFunds(uint256 _bidPrice) public onlyAuction {
        require(
            address(this).balance >= _bidPrice,
            "Insufficient funds in escrow"
        );
        (bool success, ) = bidPriceReceiver.call{value: _bidPrice}("");
        require(success, "Failed to send Ether");
    }

    /**
     * @notice Function to refund the overpaid amount to the node operator after updating the bid or
     * refund the total amount to the node operator if the operator leaves the protocol
     * @param _fundToRefund Funds to be refunded to the node operator if the newBidPrice < oldBidPrice
     */
    function refund(
        address payable _nodeOpAddr,
        uint256 _fundToRefund
    ) public onlyAuction {
        require(
            address(this).balance >= _fundToRefund,
            "Insufficient funds in escrow"
        );
        (bool success, ) = _nodeOpAddr.call{value: _fundToRefund}("");
        require(success, "Failed to send Ether");
    }

    modifier onlyAuction() {
        require(
            msg.sender == auctionContract,
            "Caller is not the Auction contract."
        );
        _;
    }
}
