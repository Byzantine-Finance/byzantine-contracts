// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "ds-math/math.sol";
import "../libraries/ProcessDataLib.sol";

/// TODO: Calculation of the reputation score of node operators
/// TODO: Create a whitelist to avoid our partner to pay the bond
/// TODO: Create escrow contract to pay directly the bid
/// TODO: Sort the array off-chain, verify on-chain (or use ChainLink Functions)

contract Auction is ReentrancyGuard, DSMath {
    using ProcessDataLib for ProcessDataLib.Set;

    /* ===================== STATE VARIABLES ===================== */

    /// @notice Keep state variables private for better gas efficiency
    ProcessDataLib.Set private _nodeOpSet;

    uint256 private constant _WAD = 1e18;
    uint256 private _expectedReturnWei;
    uint256 private _minDuration;
    /// @notice Maximum discount rate in percentage, upscaled to 1e2 (15% => 1500)
    uint256 private _maxDiscountRate;
    uint256 private _clusterSize = 4;
    uint256 private _nodeOpBond;

    address payable public vault;
    address payable public byzantineFinance;

    enum NodeOpStatus {
        inProtocol, // bid set, seeking for work
        auctionWinner, // winner of an auction but bid price not paid yet
        pendingForDvt, // bid price paid and awaiting DVT
        activeInDvt // active in DVT
    }

    /// @notice Stores detail of node operators in the protocol
    struct NodeOpStruct {
        uint256 bidPrice;
        uint256 auctionScore;
        uint256 reputationScore;
        NodeOpStatus nodeStatus;
    }
    /// @notice Node operator address => node operator struct
    mapping(address => NodeOpStruct) private _nodeOpStructs;

    event NodeOpJoined(address nodeOpAddress);
    event NodeOpLeft(address nodeOpAddress);
    event BidUpdated(
        address nodeOpAddress,
        uint256 bidPrice,
        uint256 auctionScore,
        uint256 reputationScore
    );
    event AuctionConfigUpdated(
        uint256 _expectedReturnWei,
        uint256 _maxDiscountRate,
        uint256 _minDuration,
        uint256 _nodeOpBond
    );
    event ClusterSizeUpdated(uint256 _clusterSize);
    event TopWinners(address[] winners);
    event BidPaid(address nodeOpAddress, uint256 bidPrice);
    event ListOfNodeOps(address[] nodeOps);

    /* ===================== CONSTRUCTOR ===================== */

    constructor(
        address _vault,
        uint256 __expectedReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration,
        uint256 __nodeOpBond
    ) {
        byzantineFinance = payable(msg.sender);
        vault = payable(_vault);
        _expectedReturnWei = __expectedReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
        _nodeOpBond = __nodeOpBond;
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Function triggered by the StrategyModuleManeger every time a staker deposit 32ETH.
     * It sorts the node operators by their auction score and returns a new memory array.
     * The status of the node operators in the topWinners array is updated to auctionWinner.
     * @dev The length of return array varies depending on the cluster size.
     * @dev The _nodeOpArray does not alter the storage array _nodeOpSet.addrList.
     */
    function sortAndGetTopWinners()
        external
        onlyOwner
        nonReentrant
        returns (address[] memory)
    {
        address[] memory _nodeOpArray = _nodeOpSet.addrList;

        // BUG: Should compare the length of node op with the status inProtocol
        require(
            _nodeOpArray.length >= _clusterSize,
            "No enough operators for the cluser."
        );

        /// @notice Initialize the topWinners memory array
        address[] memory topWinners = new address[](_clusterSize);

        /// @notice Initialize the new array with the first n elements, no sorting here
        uint256 initializedCount; // = 0
        for (
            uint256 i = 0;
            i < _clusterSize && initializedCount < _clusterSize;
            i++
        ) {
            if (
                _nodeOpStructs[_nodeOpArray[i]].nodeStatus ==
                NodeOpStatus.inProtocol
            ) {
                topWinners[initializedCount++] = _nodeOpArray[i];
            }
        }

        /// @notice Iterate through the operator array to find the n largest numbers
        for (uint256 i = _clusterSize; i < _nodeOpArray.length; i++) {
            NodeOpStruct storage nodeOpStruct = _nodeOpStructs[_nodeOpArray[i]];
            if (
                nodeOpStruct.nodeStatus == NodeOpStatus.auctionWinner ||
                nodeOpStruct.nodeStatus == NodeOpStatus.pendingForDvt ||
                nodeOpStruct.nodeStatus == NodeOpStatus.activeInDvt
            ) continue;

            /// @notice Get the score to compare with the scores in topWinners array
            uint256 scoreToCompare = _nodeOpStructs[_nodeOpArray[i]]
                .auctionScore;

            /// @notice Initialize the lowest score in the topWinners array
            uint256 lowestScoreIndex = 0;
            uint256 lowestScore = _nodeOpStructs[topWinners[0]].auctionScore;

            /// @notice Find the lowest score in the topWinners array
            for (uint256 j = 1; j < _clusterSize; j++) {
                uint256 score = _nodeOpStructs[topWinners[j]].auctionScore;
                if (score < lowestScore) {
                    lowestScoreIndex = j; // 1
                    lowestScore = score;
                }
            }

            /// @notice Replace the lowest score with the current score if it is higher
            if (scoreToCompare > lowestScore) {
                topWinners[lowestScoreIndex] = _nodeOpArray[i];
            }
        }

        for (uint256 i = 0; i < topWinners.length; i++) {
            _nodeOpStructs[topWinners[i]].nodeStatus = NodeOpStatus
                .auctionWinner;
        }
        emit TopWinners(topWinners);

        return topWinners;
    }

    /**
     * @notice Function triggered by the winner operator to accept the bid and pay the bid price.
     * It updates the operator status to pendingForDvt.
     * @dev The operator must be in the top winners to call this function.
     */
    function acceptAndPayBid() external {
        NodeOpStruct storage nodeOp = _nodeOpStructs[msg.sender];
        require(
            nodeOp.nodeStatus == NodeOpStatus.auctionWinner,
            "Operator not in the top winners."
        );

        uint256 bidPrice = nodeOp.bidPrice;
        _sendFunds(vault, bidPrice);

        nodeOp.nodeStatus = NodeOpStatus.pendingForDvt;

        emit BidPaid(msg.sender, bidPrice);
    }

    /**
     * @notice Update the auction configuration except cluster size
     */
    function updateAuctionConfig(
        uint256 __expectedReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration,
        uint256 __nodeOpBond
    ) external onlyOwner {
        _expectedReturnWei = __expectedReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
        _nodeOpBond = __nodeOpBond;

        emit AuctionConfigUpdated(
            __expectedReturnWei,
            __maxDiscountRate,
            __minDuration,
            __nodeOpBond
        );
    }

    /**
     * @notice Update the cluster size
     */
    function updateClusterSize(uint256 __clusterSize) external onlyOwner {
        require(__clusterSize >= 4, "Cluster size must be at least 4.");
        _clusterSize = __clusterSize;

        emit ClusterSizeUpdated(__clusterSize);
    }

    /**
     * @notice Operator joins the protocol by paying the bond and setting the bid parameters.
     * @param _discountRate: discount rate set by the node operator in percentage (from 0 to 10000 -> 100%)
     * @param _timeInDays: duration of being a validator, in days
     * @dev Auction score and bid price are stored in NodeOpStruct
     */
    function joinProtocol(
        uint256 _discountRate,
        uint256 _timeInDays
    ) external payable {
        require(msg.value == _nodeOpBond, "Bond value must be 1 ETH.");
        _nodeOpSet.insert(msg.sender);
        NodeOpStruct storage nodeOp = _nodeOpStructs[msg.sender];
        nodeOp.reputationScore = 1;

        /// @notice Calculate operator's bid price and auction score
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(
            dailyVcPrice,
            _timeInDays,
            nodeOp.reputationScore
        );

        nodeOp.bidPrice = bidPrice;
        nodeOp.auctionScore = auctionScore;
        nodeOp.nodeStatus = NodeOpStatus.inProtocol;

        emit NodeOpJoined(msg.sender);
    }

    /**
     * @notice Operator leaves the protocol and gets the bond back.
     * @dev Operator must not be pending for or active in a DVT.
     */
    function leaveProtocol() external {
        NodeOpStatus status = _nodeOpStructs[msg.sender].nodeStatus;
        require(_nodeOpSet.exists(msg.sender), "Operator not in protocol.");
        require(
            status != NodeOpStatus.pendingForDvt ||
                status != NodeOpStatus.activeInDvt,
            "Operator pending for or active in a DVT cannot leave."
        );
        _nodeOpSet.remove(msg.sender);
        _sendFunds(msg.sender, _nodeOpBond);

        emit NodeOpLeft(msg.sender);
    }

    /**
     * @notice Update the bid of an operator.
     * @param _discountRate: discount rate set by the node operator in percentage, upscaled to 1e3
     * @param _timeInDays: duration of being a validator, in days
     * @dev The auction score is updated.
     */
    function updateBid(uint256 _discountRate, uint256 _timeInDays) external {
        require(_nodeOpSet.exists(msg.sender), "Operator not in protocol.");
        NodeOpStruct storage nodeOp = _nodeOpStructs[msg.sender];
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(
            dailyVcPrice,
            _timeInDays,
            nodeOp.reputationScore
        );
        nodeOp.bidPrice = bidPrice;
        nodeOp.auctionScore = auctionScore;

        emit BidUpdated(
            msg.sender,
            bidPrice,
            auctionScore,
            nodeOp.reputationScore
        );
    }

    /**
     * @notice Send any remaining funds of the present contract to Byzantine.
     */
    function sendFundsToByzantine() external onlyOwner {
        _sendFunds(byzantineFinance, address(this).balance);
    }

    /* ===================== GETTER FUNCTIONS ===================== */

    /**
     * @notice Check if an operator is in the protocol by address
     * @param _opAddr: operator address
     */
    function operatorInProtocol(
        address _opAddr
    ) external view onlyOwner returns (bool) {
        return _nodeOpSet.exists(_opAddr);
    }

    /**
     * @notice Get the detail of an operator by address.
     * @param _opAddr: operator address
     */
    function getNodeOpStruct(
        address _opAddr
    ) external view returns (uint256, uint256, uint256, NodeOpStatus) {
        require(_nodeOpSet.exists(_opAddr), "Not a member.");
        NodeOpStruct storage nodeOp = _nodeOpStructs[_opAddr];
        return (
            nodeOp.bidPrice,
            nodeOp.auctionScore,
            nodeOp.reputationScore,
            nodeOp.nodeStatus
        );
    }

    /**
     * @notice Get the total number of node operators in the protocol.
     */
    function getNumberOfNodeOps() external view onlyOwner returns (uint256) {
        return _nodeOpSet.count();
    }

    /**
     * @notice Get the list of node operators in the protocol.
     */
    function getListOfNodeOps() external onlyOwner returns (address[] memory) {
        emit ListOfNodeOps(_nodeOpSet.addrList);
        return _nodeOpSet.addrList;
    }

    function getAuctionConfigValues()
        external
        view
        onlyOwner
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            _expectedReturnWei,
            _maxDiscountRate,
            _minDuration,
            _nodeOpBond,
            _clusterSize
        );
    }

    /* ===================== INTERNAL FUNCTIONS ===================== */

    /**
     * @notice Calculate the daily validation credit price
     * @param _discountRate: discount rate in percentage, upscaled to 1e3
     * @return _dailyVcPrice: daily validation credit price in WEI
     * @dev price_vc = Re*(1 - D)/cluster_size
     * @dev The expected return is in WEI (1e18), set by Byzantine
     * @dev The discount rate must not exceed the maximum discount rate
     */
    function _calculateDailyVcPrice(
        uint256 _discountRate
    ) internal view returns (uint256) {
        require(
            _discountRate <= _maxDiscountRate,
            "Discount rate exceeds the maximum."
        );
        return
            (_expectedReturnWei * (10000 - _discountRate)) /
            (_clusterSize * 10000);
    }

    /**
     * @notice Calculate the bid price that should be paid by the winner node operator
     * @param _timeInDays: duration of being a validator, in days
     * @param _dailyVcPrice: daily validation credit price in WEI
     * @return _bidPrice: bid price in WEI
     * @dev bid_price = time_in_days * price_vc
     * @dev Time in days must be >= 30
     */
    function _calculateBidPrice(
        uint256 _timeInDays,
        uint256 _dailyVcPrice
    ) internal view returns (uint256) {
        require(_timeInDays >= _minDuration, "Time in days must be >= 30.");
        return _timeInDays * _dailyVcPrice;
    }

    /**
     * @notice Calculate the auction score of an operator
     * @param _dailyVcPrice: daily validation credit price in WEI
     * @param _timeInDays: duration of being a validator, in days
     * @param _reputation: reputation score of the operator
     * @return _auctionScore: auction score of the operator, upscaled to 1e18
     * @dev powerValue = 1.001**_timeInDays, calculated from _pow function
     * @dev The result is divided by 1e18 to downscaled from 1e36 to 1e18
     */
    function _calculateAuctionScore(
        uint256 _dailyVcPrice,
        uint256 _timeInDays,
        uint256 _reputation
    ) internal pure returns (uint256) {
        uint256 powerValue = _pow(_timeInDays);
        return (_dailyVcPrice * powerValue * _reputation) / _WAD;
    }

    /**
     * @notice Calculate the power value of 1.001**_timeInDays
     * @dev 1.001 becomes 1001 * 1e24
     * @dev The result is divided by 1e9 to downscaled to 1e18 as the return value is upscaled to 1e27
     */
    function _pow(uint256 _timeIndays) internal pure returns (uint256) {
        uint256 fixedPoint = 1001 * 1e24;
        return DSMath.rpow(fixedPoint, _timeIndays) / 1e9;
    }

    /**
     * @notice Send funds to a receiver
     * @dev The receiver is vault in the present contract
     */
    function _sendFunds(address _receiver, uint256 _amount) internal {
        (bool success, ) = _receiver.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    /* ===================== MODIFIERS ===================== */

    modifier onlyOwner() {
        require(msg.sender == byzantineFinance, "Not the owner.");
        _;
    }
}
