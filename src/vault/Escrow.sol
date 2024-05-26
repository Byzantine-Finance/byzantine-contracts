// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEscrow} from "../interfaces/IEscrow.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Escrow is IEscrow, AccessControl {
    /// @notice Address which receives the final bid prices
    address payable public bidPriceReceiver;

    /// @notice Set an access control role
    bytes32 public constant AUCTION_ROLE = keccak256("AUCTION_ROLE");

    /**
     * @notice Constructor to set the bidPriceReceiver address and set the DEFAULT_ADMIN_ROLE to the deployer
     * @param _bidPriceReceiver Address which receives the final bid prices
     */
    constructor(address _bidPriceReceiver) {
        bidPriceReceiver = payable(_bidPriceReceiver);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Function to be called once the contract is deployed to grant AUCTION_ROLE to the auction contract
     * @param _auctionAddr Address of the auction contract
     */
    function grantRoleToAuction(
        address _auctionAddr
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(AUCTION_ROLE, _auctionAddr);
    }

    /**
     * @notice Function to receive funds of the node operator at the time of joining the protocol
     * Same function to receive new funds after a node operator updates the bid
     * @dev The funds are locked in the escrow
     */
    receive() external payable {
        emit FundsLocked(msg.value);
    }

    /**
     * @notice Function to approve the pid price of the winner operator to be released to the final bid price receiver
     * @param _bidPrice Bid price of the node operator
     */
    function releaseFunds(uint256 _bidPrice) public onlyRole(AUCTION_ROLE) {
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
     * @param _amountToRefund Funds to be refunded to the node operator if the newBidPrice < oldBidPrice
     */
    function refund(
        address _nodeOpAddr,
        uint256 _amountToRefund
    ) public onlyRole(AUCTION_ROLE) {
        require(
            address(this).balance >= _amountToRefund,
            "Insufficient funds in escrow"
        );
        (bool success, ) = payable(_nodeOpAddr).call{value: _amountToRefund}(
            ""
        );
        require(success, "Failed to send Ether");
    }
}
