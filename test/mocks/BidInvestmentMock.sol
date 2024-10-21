// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BidInvestmentMock {

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives the paid bid prices from the Escrow contract 
     */
    receive() external payable {}

}