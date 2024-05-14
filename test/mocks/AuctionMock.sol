// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract AuctionMock {
    address payable public byzantineFinance;

    constructor(address payable _byzantineFinance) {
        byzantineFinance = _byzantineFinance;
    }

    function sendFundsToByzantine() external onlyOwner {
        _sendFunds(byzantineFinance, address(this).balance);
    }

    function _sendFunds(address _receiver, uint256 _amount) internal {
        (bool success, ) = _receiver.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    modifier onlyOwner() {
        require(msg.sender == byzantineFinance, "Not the owner.");
        _;
    }
}
