// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "ds-math/math.sol";
import "../libraries/ProcessDataLib.sol";

/// TODO: Calculation of the reputation score of operators

contract Auction is ReentrancyGuard, DSMath {
    /* ===================== STATE VARIABLES ===================== */

    /// @notice Keep state variables private for better gas efficiency
    using ProcessDataLib for ProcessDataLib.Set;
    ProcessDataLib.Set private _opSet;

    uint256 private constant _WAD = 1e18;
    uint256 private _expectedReturnWei;
    /// @notice Maximum discount rate in percentage, upscaled to 1e2 (15% => 1500)
    uint256 private _maxDiscountRate;
    uint256 private _minDuration;
    uint256 private _operatorBond;
    uint256 private _clusterSize = 4;

    address payable public vault;
    address payable public byzantineFinance;

    enum OperatorStatus {
        inProtocol, // bid set, seeking for work
        auctionWinner, // winner of an auction but bid price not paid yet
        pendingForDvt, // bid price paid and awaiting DVT
        activeInDvt // active in DVT
    }

    /// @notice Stores detail of operator in the protocol
    struct OperatorStruct {
        uint256 bidPrice;
        uint256 auctionScore;
        uint256 reputationScore;
        OperatorStatus opStatus;
    }
    /// @notice Operator address => operator struct
    mapping(address => OperatorStruct) private _operatorStructs;

    event OperatorJoined(address operatorAddress);
    event OperatorLeft(address operatorAddress);
    event BidUpdated(
        address operatorAddress,
        uint256 bidPrice,
        uint256 auctionScore,
        uint256 reputationScore
    );
    event AuctionConfigUpdated(
        uint256 _expectedReturnWei,
        uint256 _maxDiscountRate,
        uint256 _minDuration,
        uint256 _operatorBond
    );
    event ClusterSizeUpdated(uint256 _clusterSize);
    event TopWinners(address[] winners);
    event BidPaid(address operatorAddress, uint256 bidPrice);
    event ListOfOperators(address[] operators);

    /* ===================== CONSTRUCTOR ===================== */

    constructor(
        address _vault,
        uint256 __expectedReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration,
        uint256 __operatorBond
    ) {
        byzantineFinance = payable(msg.sender);
        vault = payable(_vault);
        _expectedReturnWei = __expectedReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
        _operatorBond = __operatorBond;
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Function triggered by Byzantine once 32ETH are gathered from stakers.
     * It sorts the operators by their auction score and returns a new memory array.
     * The status of the operators in the topWinners array is updated to auctionWinner.
     * @dev The length of return array varies depending on the cluster size.
     * @dev The _opArray does not alter the storage array _opSet.addrList.
     */
    function sortAndGetTopWinners()
        external
        onlyOwner
        nonReentrant
        returns (address[] memory)
    {
        address[] memory _opArray = _opSet.addrList;
        require(
            _opArray.length >= _clusterSize,
            "No enough operators for the cluser."
        );

        /// @notice Initialize the topWinners memory array
        address[] memory topWinners = new address[](_clusterSize);

        /// @notice Initialize the new array with the first n elements, no sorting here
        uint256 initializedCount = 0;
        for (
            uint256 i = 0;
            i < _clusterSize && initializedCount < _clusterSize;
            i++
        ) {
            if (
                _operatorStructs[_opArray[i]].opStatus ==
                OperatorStatus.inProtocol
            ) {
                topWinners[initializedCount++] = _opArray[i];
            }
        }

        /// @notice Iterate through the operator array to find the n largest numbers
        for (uint256 i = _clusterSize; i < _opArray.length; i++) {
            OperatorStruct storage opStruct = _operatorStructs[_opArray[i]];
            if (
                opStruct.opStatus == OperatorStatus.auctionWinner ||
                opStruct.opStatus == OperatorStatus.pendingForDvt ||
                opStruct.opStatus == OperatorStatus.activeInDvt
            ) continue;

            /// @notice Get the score to compare with the scores in topWinners array
            uint256 scoreToCompare = _operatorStructs[_opArray[i]].auctionScore;

            /// @notice Initialize the lowest score in the topWinners array
            uint256 lowestScoreIndex = 0;
            uint256 lowestScore = _operatorStructs[topWinners[0]].auctionScore;

            /// @notice Find the lowest score in the topWinners array
            for (uint256 j = 1; j < _clusterSize; j++) {
                uint256 score = _operatorStructs[topWinners[j]].auctionScore;
                if (score < lowestScore) {
                    lowestScoreIndex = j; // 1
                    lowestScore = score;
                }
            }

            /// @notice Replace the lowest score with the current score if it is higher
            if (scoreToCompare > lowestScore) {
                topWinners[lowestScoreIndex] = _opArray[i];
            }
        }

        for (uint256 i = 0; i < topWinners.length; i++) {
            _operatorStructs[topWinners[i]].opStatus = OperatorStatus
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
        OperatorStruct storage op = _operatorStructs[msg.sender];
        require(
            op.opStatus == OperatorStatus.auctionWinner,
            "Operator not in the top winners."
        );

        uint256 bidPrice = op.bidPrice;
        _sendFunds(vault, bidPrice);

        op.opStatus = OperatorStatus.pendingForDvt;

        emit BidPaid(msg.sender, bidPrice);
    }

    /**
     * @notice Update the auction configuration except cluster size
     */
    function updateAuctionConfig(
        uint256 __expectedReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration,
        uint256 __operatorBond
    ) external onlyOwner {
        _expectedReturnWei = __expectedReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
        _operatorBond = __operatorBond;

        emit AuctionConfigUpdated(
            __expectedReturnWei,
            __maxDiscountRate,
            __minDuration,
            __operatorBond
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
     * @notice Operator joins the protocol by paying the bond and setting the bid price.
     * @param _discountRate: discount rate set by the node operator in percentage, upscaled to 1e3
     * @param _timeInDays: duration of being a validator, in days
     * @dev Auction score and bid price are stored in OperatorStruct
     */
    function joinProtocol(
        uint256 _discountRate,
        uint256 _timeInDays
    ) external payable {
        require(msg.value == _operatorBond, "Bond value must be 1 ETH.");
        _opSet.insert(msg.sender);
        OperatorStruct storage op = _operatorStructs[msg.sender];
        op.reputationScore = 1;

        /// @notice Calculate operator's bid price and auction score
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(
            dailyVcPrice,
            _timeInDays,
            op.reputationScore
        );

        op.bidPrice = bidPrice;
        op.auctionScore = auctionScore;
        op.opStatus = OperatorStatus.inProtocol;

        emit OperatorJoined(msg.sender);
    }

    /**
     * @notice Operator leaves the protocol and gets the bond back.
     * @dev Operator must not be pending for or active in a DVT.
     */
    function leaveProtocol() external {
        OperatorStatus status = _operatorStructs[msg.sender].opStatus;
        require(_opSet.exists(msg.sender), "Operator not in protocol.");
        require(
            status != OperatorStatus.pendingForDvt ||
                status != OperatorStatus.activeInDvt,
            "Operator pending for or active in a DVT cannot leave."
        );
        _opSet.remove(msg.sender);
        _sendFunds(msg.sender, _operatorBond);

        emit OperatorLeft(msg.sender);
    }

    /**
     * @notice Update the bid of an operator.
     * @param _discountRate: discount rate set by the node operator in percentage, upscaled to 1e3
     * @param _timeInDays: duration of being a validator, in days
     * @dev The auction score is updated.
     */
    function updateBid(uint256 _discountRate, uint256 _timeInDays) external {
        require(_opSet.exists(msg.sender), "Operator not in protocol.");
        OperatorStruct storage op = _operatorStructs[msg.sender];
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(
            dailyVcPrice,
            _timeInDays,
            op.reputationScore
        );
        op.bidPrice = bidPrice;
        op.auctionScore = auctionScore;

        emit BidUpdated(msg.sender, bidPrice, auctionScore, op.reputationScore);
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
        return _opSet.exists(_opAddr);
    }

    /**
     * @notice Get the detail of an operator by address.
     * @param _opAddr: operator address
     */
    function getOperatorStruct(
        address _opAddr
    ) external view returns (uint256, uint256, uint256, OperatorStatus) {
        require(_opSet.exists(_opAddr), "Not a member.");
        OperatorStruct storage op = _operatorStructs[_opAddr];
        return (op.bidPrice, op.auctionScore, op.reputationScore, op.opStatus);
    }

    /**
     * @notice Get the total number of operators in the protocol.
     */
    function getNumberOfOperators() external view onlyOwner returns (uint256) {
        return _opSet.count();
    }

    /**
     * @notice Get the list of operators in the protocol.
     */
    function getListOfOperators()
        external
        onlyOwner
        returns (address[] memory)
    {
        emit ListOfOperators(_opSet.addrList);
        return _opSet.addrList;
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
            _operatorBond,
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
    ) internal view returns (uint256) {
        require(_timeInDays >= _minDuration, "Time in days must be >= 30.");
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
