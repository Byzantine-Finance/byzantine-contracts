// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "./AuctionStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "ds-math/math.sol";
import "../libraries/ProcessDataLib.sol";

contract Auction is ReentrancyGuard, DSMath {
    using ProcessDataLib for ProcessDataLib.Set;
    ProcessDataLib.Set _opSet;

    uint constant _WAD = 1e18;
    uint public expectedReturn;
    uint public maxDiscountRate;
    uint public minDuration;
    uint public operatorBond;
    uint public clusterSize;

    address payable public vault;
    address public byzantineFinance;

    /// The current status of the operator
    enum OperatorStatus {
        inProtocol, //meaning also seeking for work
        pendingForDvt,
        activeInDvt
    }
    /// Operator details
    struct OperatorStruct {
        uint reputationScore;
        OperatorStatus opStatus;
    }
    /// Maps operator address => operator struct
    mapping(address => OperatorStruct) _operatorStructs;

    /// Auction details for each auction(ID)
    struct AuctionStruct {
        bool started;
        bool ended;
        uint[] topScores;
        address[] topWinners;
        uint[] topBidPrices;
        mapping(address => uint) bids; // winner address => bid price
    }
    uint public _nextAuctionId;
    mapping(uint => AuctionStruct) public auctions;

    event OperatorJoined(address operatorAddress);
    event OperatorLeft(address operatorAddress);
    event ReadyForBid(uint auctionId);
    event End(uint auctionId);
    event BidPaid(uint auctionId, address operatorAddress, uint bidPrice);

    constructor(
        address _vault,
        uint _expectedReturn,
        uint _maxDiscountRate,
        uint _minDuration,
        uint _operatorBond
    ) {
        byzantineFinance = msg.sender;
        vault = payable(_vault);
        expectedReturn = _expectedReturn;
        maxDiscountRate = _maxDiscountRate;
        minDuration = _minDuration;
        operatorBond = _operatorBond;
    }

    /********************************************************************/
    /***************************   AUCTIONS   ****************************/
    /********************************************************************/

    /// Call by Byzantine to allow operators to bid for the auction with ID _auctionId
    function setupAuction(
        uint _clusterSize
    ) external onlyOwner returns (uint _auctionId) {
        _auctionId = nextAuctionId++;
        auctions[_auctionId].started = true;
        /// Determine the cluster size before the operator starts bidding
        _updateClusterSize(_clusterSize, _auctionId);

        emit ReadyForBid(_auctionId);
    }

    /// @dev Called by the operator when ready to bid for the upcoming acution with ID _auctionId
    /// Pre-calculate the bid price and store the top winners depending on the cluster size
    function readyForBid(
        uint _auctionId,
        uint _discountRate,
        uint _timeInDays
    ) external nonReentrant {
        AuctionStruct storage auction = auctions[_auctionId];
        require(
            auction.started && !auction.ended,
            "Auction not started or alread ended."
        );
        require(_opSet.exists(msg.sender), "Operator not in protocol.");
        require(
            _discountRate <= maxDiscountRate,
            "Discount rate exceeds the maximum."
        );
        require(
            _timeInDays >= minDuration,
            "Duration is less than the minimum."
        );

        OperatorStruct storage op = _operatorStructs[msg.sender];
        uint dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint auctionScore = _calculateAuctionScore(
            dailyVcPrice,
            _timeInDays,
            op.reputationScore
        );

        // Find the lowest of the top four scores and its index i
        uint lowestIndex = 0;
        uint lowestScore = auction.topScores[0];
        for (uint i = 1; i < clusterSize; i++) {
            if (auction.topScores[i] < lowestScore) {
                lowestScore = auction.topScores[i];
                lowestIndex = i;
            }
        }

        // Replace the lowest score at index i if the new score is higher
        if (auctionScore > lowestScore) {
            auction.topScores[lowestIndex] = auctionScore;
            auction.topWinners[lowestIndex] = msg.sender;
            auction.topBidPrices[lowestIndex] = bidPrice;
            auction.bids[msg.sender] = bidPrice;
        }
    }

    /// End the auction
    function endAuction(uint _auctionId) external onlyOwner {
        AuctionStruct storage auction = auctions[_auctionId];
        require(auction.started, "Auction not started.");
        require(!auction.ended, "Auction already ended.");

        auction.ended = true;
        emit End(_auctionId);
    }

    /// Called by each operator bidder to accept and pay the bid price
    function acceptAndPayBid(uint _auctionId) external {
        AuctionStruct storage auction = auctions[_auctionId];
        require(auction.started, "Auction not started.");
        require(auction.ended, "Auction not yet ended.");

        uint bidPrice = auction.bids[msg.sender];
        if (auction.topWinners.length != 0) {
            _sendFunds(vault, bidPrice);
        }
        OperatorStruct storage op = _operatorStructs[msg.sender];
        op.opStatus = OperatorStatus.pendingForDvt;

        emit BidPaid(_auctionId, msg.sender, bidPrice);
    }

    /// Update the auction configuration except cluster size
    function updateAuctionConfig(
        uint _expectedReturn,
        uint _maxDiscountRate,
        uint _minDuration,
        uint _operatorBond
    ) external {
        expectedReturn = _expectedReturn;
        maxDiscountRate = _maxDiscountRate;
        minDuration = _minDuration;
        operatorBond = _operatorBond;
    }

    /********************************************************************/
    /**********************   NODE OPERATOR MANAGEMENT   ****************/
    /********************************************************************/

    /// Add an operator to the protocol by paying the bond to the contract
    function joinProtocol() external payable {
        require(msg.value == operatorBond, "Bond value must be 1 ETH.");
        _opSet.insert(msg.sender);
        OperatorStruct storage op = _operatorStructs[msg.sender];
        op.opStatus = OperatorStatus.inProtocol;

        emit OperatorJoined(msg.sender);
    }

    /// Remove an operator from the protocol and return the bond
    function leaveProtocol() external {
        OperatorStatus status = _operatorStructs[msg.sender].opStatus;
        require(
            status == OperatorStatus.inProtocol &&
                status != OperatorStatus.activeInDvt,
            "Operator is not in protocol or is active in a DVT."
        );
        _opSet.remove(msg.sender);
        _sendFunds(msg.sender, operatorBond);

        emit OperatorLeft(msg.sender);
    }

    function getOperatorStruct(
        address _opAddr
    ) external view returns (uint, OperatorStatus) {
        require(_opSet.exists(_opAddr), "Not a member.");
        OperatorStruct storage op = _operatorStructs[_opAddr];
        return (op.reputationScore, op.opStatus);
    }

    /********************************************************************/
    /**********************   OTHER FUNCTIONS  ***********************/
    /********************************************************************/

    function getFundsToByzantine() external onlyOwner {
        _sendFunds(byzantineFinance, address(this).balance);
    }

    /********************************************************************/
    /**********************   INTERNAL FUNCTIONS  ***********************/
    /********************************************************************/

    /// Internal function to update the cluster size, called by setupForBid function
    function _updateClusterSize(uint _clusterSize, uint _id) internal {
        require(_clusterSize >= 4, "Cluster size must be at least 4.");
        clusterSize = _clusterSize;
        auctions[_id].topScores = new uint[](_clusterSize);
        auctions[_id].topWinners = new address[](_clusterSize);
        auctions[_id].topBidPrices = new uint[](_clusterSize);
    }

    /// Calculate the daily Vc price: Re*(1 - D)/cluster_size
    /// @notice expectedReturn is in percentage, upscaled to 1e18
    /// @param _discountRate: discount rate in percentage, upscaled to 1e18
    /// @return dailyVcPrice in ETH
    function _calculateDailyVcPrice(
        uint _discountRate
    ) internal view returns (uint) {
        return
            (expectedReturn * (expectedReturn - _discountRate)) /
            clusterSize /
            (_WAD * 100);
    }

    /// calculate Bid price
    function _calculateBidPrice(
        uint _timeInDays,
        uint _dailyVcPrice
    ) internal pure returns (uint) {
        return _timeInDays * _dailyVcPrice;
    }

    /// calculate auction Score: P_vc * 1.001^td * r_reputation (td being timeInDays)
    /// @notice powerValue is 1.001^td.
    function _calculateAuctionScore(
        uint _pvc,
        uint _timeInDays,
        uint _reputation
    ) internal pure returns (uint) {
        uint powerValue = _pow(_timeInDays);
        return _pvc * powerValue * _reputation;
    }

    /// Calculate the power value of 1.001^td, 1.001 becomes 1001
    function _pow(uint _timeIndays) internal pure returns (uint) {
        return DSMath.rpow(1001, _timeIndays);
    }

    function _sendFunds(address _receiver, uint _amount) internal {
        (bool success, ) = _receiver.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    modifier onlyOwner() {
        require(msg.sender == byzantineFinance);
        _;
    }
}
