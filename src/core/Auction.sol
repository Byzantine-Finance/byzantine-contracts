// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "ds-math/math.sol";

import "../libraries/ProcessDataLib.sol";
import "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

/// TODO: Calculation of the reputation score of node operators
/// TODO: Create escrow contract to pay directly the bid

contract Auction is ReentrancyGuard, DSMath {
    using ProcessDataLib for ProcessDataLib.Set;
    using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;

    /* ================= CONSTANTS + IMMUTABLES ================= */

    uint256 private constant _WAD = 1e18;
    uint256 private constant _BOND = 1 ether;

    /* ===================== STATE VARIABLES ===================== */

    /// @notice Auction scores stored in a Red-Black tree (complexity O(log n))
    BokkyPooBahsRedBlackTreeLibrary.Tree private _auctionTree;

    /// @notice Daily rewards of Ethereum Pos (in WEI)
    uint256 private _expectedDailyReturnWei;
    /// @notice Minimum duration to be part of a DV (in days)
    uint256 private _minDuration;
    /// @notice Maximum discount rate (i.e the max profit margin of node op) in percentage (from 0 to 10000 -> 100%)
    uint256 private _maxDiscountRate;
    /// @notice Number of nodes in a Distributed Validator
    uint256 private _clusterSize = 4;

    /// @notice Escrow contract address where the bids and the bonds are sent and stored
    address payable public escrowAddr;
    /// @notice Smart contract admin
    address public byzantineFinance;

    /// @notice Node operator address => node operator auction details
    mapping(address => NodeOpDetails) private _nodeOpsInfo;

    /// @notice Auction score => node operator array (different node ops can have the same auction score)
    mapping(uint256 => ProcessDataLib.Set) private _auctionScoreToNodeOps;

    /// @notice Mapping for the whitelisted node operators
    mapping(address => bool) private _nodeOpsWhitelist;

    /* ===================== TO PUT IN CONTRACT INTERFACE ===================== */

    enum NodeOpStatus {
        inactive, // has left the auction or has finished his work
        inAuction, // bid set, seeking for work
        inDV // auction won. We assume he has accepted to join the DV
    }

    /// @notice Stores auction details of node operators
    struct NodeOpDetails {
        uint256 vcNumber;
        uint256 bidPrice;
        uint256 auctionScore;
        uint256 reputationScore;
        NodeOpStatus nodeStatus;
    }

    event NodeOpJoined(address nodeOpAddress);
    event NodeOpLeft(address nodeOpAddress);
    event BidUpdated(
        address nodeOpAddress,
        uint256 bidPrice,
        uint256 auctionScore,
        uint256 reputationScore
    );
    event AuctionConfigUpdated(
        uint256 _expectedDailyReturnWei,
        uint256 _maxDiscountRate,
        uint256 _minDuration
    );
    event ClusterSizeUpdated(uint256 _clusterSize);
    event TopWinners(address[] winners);
    event BidPaid(address nodeOpAddress, uint256 bidPrice);
    event ListOfNodeOps(address[] nodeOps);

    /* ===================== CONSTRUCTOR ===================== */

    constructor(
        address _escrowAddr,
        uint256 __expectedDailyReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration
    ) {
        byzantineFinance = msg.sender;
        escrowAddr = payable(_escrowAddr);
        _expectedDailyReturnWei = __expectedDailyReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Add a node operator to the the whitelist to not make him pay the bond.
     * @param _nodeOpAddr: the node operator to whitelist.
     * @dev Revert if the node operator is already whitelisted.
     */
    function addNodeOpToWhitelist(address _nodeOpAddr) external onlyOwner {
        require(!isWhitelisted(_nodeOpAddr), "Address already whitelisted");
        _nodeOpsWhitelist[_nodeOpAddr] = true;
    }

    /**
     * @notice Remove a node operator to the the whitelist.
     * @param _nodeOpAddr: the node operator to remove from whitelist.
     * @dev Revert if the node operator is not whitelisted.
     */
    function removeNodeOpFromWhitelist(address _nodeOpAddr) external onlyOwner {
        require(isWhitelisted(_nodeOpAddr), "Address is not whitelisted");
        _nodeOpsWhitelist[_nodeOpAddr] = false;
    }

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
        /*address[] memory _nodeOpArray = _nodeOpSet.addrList;

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

        return topWinners;*/
    }

    /**
     * @notice Fonction to determine the auction price for a validator according to its bid parameters
     * @param _nodeOpAddr: address of the node operator joining the auction
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timeInDays: duration of being a validator, in days
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function getPriceToPay(
        address _nodeOpAddr,
        uint256 _discountRate,
        uint256 _timeInDays
    ) public view returns (uint256) {
        // Verify the standing bid parameters
        require(_discountRate <= _maxDiscountRate, "Discount rate too high");
        require(_timeInDays >= _minDuration, "Validating duration too short");

        /// @notice Calculate operator's bid price
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);

        // Return the price to pay according to the whitelist
        if (isWhitelisted(_nodeOpAddr)) {
            return bidPrice;
        }
        return bidPrice + _BOND;
    }

    /**
     * @notice Operators set their standing bid parameters and pay their bid to an escrow smart contract.
     * If a node op doesn't win the auction, its bid stays in the escrow contract for the next auction.
     * An node op who hasn't won an auction can ask the escrow contract to refund its bid if he wants to leave the protocol.
     * If a node op wants to update its bid parameters, call `updateBid` function.
     * @notice Non-whitelisted operators will have to pay the 1ETH bond as well.
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timeInDays: duration of being a validator, in days
     * @dev By calling this function, the node op insert a data in the auction Binary Search Tree (sorted by auction score).
     * @dev Revert if the node op is already in auction. Call `updateBid` instead.
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     * @dev Revert if the ethers sent by the node op are not enough to pay for the bid (and the bond).
     * @dev If too many ethers has been sent the function give back the excess to the sender.
     */
    function bid(
        uint256 _discountRate,
        uint256 _timeInDays
    ) external payable nonReentrant {
        // Verify if the sender is not already in auction
        require(_nodeOpsInfo[msg.sender].nodeStatus != NodeOpStatus.inAuction, "Already in auction, call updateBid function");

        // Verify the standing bid parameters
        require(_discountRate <= _maxDiscountRate, "Discount rate too high");
        require(_timeInDays >= _minDuration, "Validating duration too short");

        /// TODO: Get the reputation score of msg.sender
        uint256 reputationScore = 1;

        /// @notice Calculate operator's bid price and auction score
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(dailyVcPrice, _timeInDays, reputationScore);

        uint256 priceToPay;
        // If msg.sender is whitelisted, he only pays the bid
        if (isWhitelisted(msg.sender)) {
            priceToPay = bidPrice;
        } else {
            priceToPay = bidPrice + _BOND;
        }

        // Verify if the sender has sent enough ethers
        require(msg.value >= priceToPay, "Not enough ethers sent");

        // If to many ethers has been sent, refund the sender
        uint256 amountToRefund = msg.value - priceToPay;
        if (amountToRefund > 0) {
            payable(msg.sender).transfer(amountToRefund);
        }

        // TODO: transfer the ethers in the escrow contract

        // Verify if auctionScore is not already in the tree
        if (!_auctionTree.exists(auctionScore)) {
            _auctionTree.insert(auctionScore);
        }

        // Insert the nodeOp in the auctionScore mapping
        _auctionScoreToNodeOps[auctionScore].insert(msg.sender);

        // Fill or update the nodeOpDetails
        _nodeOpsInfo[msg.sender] = NodeOpDetails({
            vcNumber: _timeInDays,
            bidPrice: bidPrice,
            auctionScore: auctionScore,
            reputationScore: reputationScore,
            nodeStatus: NodeOpStatus.inAuction
        });
    }

    /**
     * @notice Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decrease its bid.
     * @param _nodeOpAddr: address of the node operator updating its bid
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timeInDays: duration of being a validator, in days
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function getUpdateBidPrice(
        address _nodeOpAddr,
        uint256 _discountRate,
        uint256 _timeInDays
    ) public view returns (uint256) {
        // Verify the standing bid parameters
        require(_discountRate <= _maxDiscountRate, "Discount rate too high");
        require(_timeInDays >= _minDuration, "Validating duration too short");

        // Get what the node op has already paid
        uint256 previousBidPrice = _nodeOpsInfo[_nodeOpAddr].bidPrice;

        /// @notice Calculate operator's new bid price
        uint256 newDailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 newBidPrice = _calculateBidPrice(_timeInDays, newDailyVcPrice);

        if (newBidPrice > previousBidPrice) {
            return newBidPrice - previousBidPrice;
        }
        return 0;
    }

    /**
     * @notice Update the bid of a node operator. A same address cannot have several bids, so the node op
     * will have to pay more if he outbids. If he decreases his bid, the escrow contract will send him the difference.
     * @param _newDiscountRate: new discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: new duration of being a validator, in days
     * @dev To call that function, the node op has to be inAuction.
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function updateBid(
        uint256 _newDiscountRate,
        uint256 _newTimeInDays
    ) external payable nonReentrant {
        // Verify if the sender is in the auction
        require(_nodeOpsInfo[msg.sender].nodeStatus == NodeOpStatus.inAuction, "Not in auction, call bid function");

        // Verify the standing bid parameters
        require(_newDiscountRate <= _maxDiscountRate, "Discount rate too high");
        require(_newTimeInDays >= _minDuration, "Validating duration too short");

        // Get the previous bid price and auction score of msg.sender
        (,uint256 previousBidPrice,uint256 previousAuctionScore,,) = getNodeOpDetails(msg.sender);

        /// TODO: Get the reputation score of msg.sender
        uint256 reputationScore = 1;

        /// @notice Calculate operator's new bid price and new auction score
        uint256 newDailyVcPrice = _calculateDailyVcPrice(_newDiscountRate);
        uint256 newBidPrice = _calculateBidPrice(_newTimeInDays, newDailyVcPrice);
        uint256 newAuctionScore = _calculateAuctionScore(newDailyVcPrice, _newTimeInDays, reputationScore);

        if (newBidPrice > previousBidPrice) {
            // TODO: gas optimization with unchecked
            uint256 ethersToAdd = newBidPrice - previousBidPrice;
            // Verify if the sender has sent the difference
            require(msg.value >= ethersToAdd, "Not enough ethers sent to outbid");
            // If to many ethers has been sent, refund the sender
            uint256 amountToRefund = msg.value - ethersToAdd;
            if (amountToRefund > 0) {
                payable(msg.sender).transfer(amountToRefund);
            }
            // TODO: transfer the ethers in the escrow contract
        } else {
            // TODO: gas optimization with unchecked
            uint256 ethersToSendBack = previousBidPrice - newBidPrice;
            // TODO: Ask the escrow to send back the ethers
        }

        // If msg.sender is the only one with that Auction score, remove it from the tree and the mapping
        if (_auctionScoreToNodeOps[previousAuctionScore].count() == 1) {
            _auctionTree.remove(previousAuctionScore);
            delete _auctionScoreToNodeOps[previousAuctionScore];
        } else {
            // remove node op from the auction score mapping
            _auctionScoreToNodeOps[previousAuctionScore].remove(msg.sender);
        }

        // Add node op to new auction score mapping
        _auctionScoreToNodeOps[newAuctionScore].insert(msg.sender);

        // Update the nodeOpDetails
        _nodeOpsInfo[msg.sender] = NodeOpDetails({
            vcNumber: _newTimeInDays,
            bidPrice: newBidPrice,
            auctionScore: newAuctionScore,
            reputationScore: reputationScore,
            nodeStatus: NodeOpStatus.inAuction
        });
    }

    /**
     * @notice Allow a node operator to abandon the auction and withdraw the bid he paid.
     * It's not possible to withdraw if the node operator is actively validating.
     * @dev Status is set to inactive and auction details to 0 unless the reputation which is unmodified
     */
    function withdrawBid() external {
        // Verify if the sender is in the auction
        require(_nodeOpsInfo[msg.sender].nodeStatus == NodeOpStatus.inAuction, "Not in auction, cannot withdraw");

        // Get the paid bid and auction score of msg.sender
        (,uint256 bidToRefund,uint256 auctionScore,,) = getNodeOpDetails(msg.sender);

        // Check if other node ops doesn't have the same auction score
        if (_auctionScoreToNodeOps[auctionScore].count() == 1) {
            // Remove auction score from the tree and the mapping
            _auctionTree.remove(auctionScore);
            delete _auctionScoreToNodeOps[auctionScore];
        } else {
            // remove node op from the auction score mapping
            _auctionScoreToNodeOps[auctionScore].remove(msg.sender);
        }

        // TODO: Get the reputation score of msg.sender
        uint256 reputationScore = 1;

        // Update the nodeOpDetails
        _nodeOpsInfo[msg.sender] = NodeOpDetails({
            vcNumber: 0,
            bidPrice: 0,
            auctionScore: 0,
            reputationScore: reputationScore,
            nodeStatus: NodeOpStatus.inactive
        });

        // TODO: Ask the Escrow contract to refund the node op
    }

    /**
     * @notice Update the auction configuration except cluster size
     * @param __expectedDailyReturnWei: the new expected daily return of Ethereum staking (in wei)
     * @param __maxDiscountRate: the new maximum discount rate (i.e the max profit margin of node op) (from 0 to 10000 -> 100%)
     * @param __minDuration: the new minimum duration of beeing a validator in a DV (in days)
     */
    function updateAuctionConfig(
        uint256 __expectedDailyReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration
    ) external onlyOwner {
        _expectedDailyReturnWei = __expectedDailyReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
    }

    /**
     * @notice Update the cluster size (i.e the number of node operators in a DV)
     * @param __clusterSize: the new cluster size
     */
    function updateClusterSize(uint256 __clusterSize) external onlyOwner {
        require(__clusterSize >= 4, "Cluster size must be at least 4.");
        _clusterSize = __clusterSize;
    }

    /* ===================== GETTER FUNCTIONS ===================== */

    /**
     * @notice Return true if the `_nodeOpAddr` is whitelisted, false otherwise.
     * @param _nodeOpAddr: operator address you want to know if whitelisted
     */
    function isWhitelisted(address _nodeOpAddr) public view returns (bool) {
        return _nodeOpsWhitelist[_nodeOpAddr];
    }

    /**
     * @notice Returns the auction details of a node operator
     * @param _nodeOpAddr The node operator address to get the details
     * @return (vcNumber, bidPrice, auctionScore, reputationScore, nodeStatus)
     */
    function getNodeOpDetails(
        address _nodeOpAddr
    ) public view returns (uint256, uint256, uint256, uint256, NodeOpStatus) {
        NodeOpDetails memory nodeOp = _nodeOpsInfo[_nodeOpAddr];
        return (
            nodeOp.vcNumber,
            nodeOp.bidPrice,
            nodeOp.auctionScore,
            nodeOp.reputationScore,
            nodeOp.nodeStatus
        );
    }

    /**
     * @notice Returns the array of node operators who have the `_auctionScore`
     * @param _auctionScore The auction score to get the node operators array
     */
    function getAuctionScoreToNodeOps(
        uint256 _auctionScore
    ) public view returns (address[] memory) {
        return _auctionScoreToNodeOps[_auctionScore].addrList;
    }

    /**
     * @notice Returns the auction configuration values.
     * @dev Function callable only by the owner.
     * @return (_expectedDailyReturnWei, _maxDiscountRate, _minDuration, _clusterSize)
     */
    function getAuctionConfigValues() external view onlyOwner returns (uint256, uint256, uint256, uint256) {
        return (
            _expectedDailyReturnWei,
            _maxDiscountRate,
            _minDuration,
            _clusterSize
        );
    }

    /* ===================== INTERNAL FUNCTIONS ===================== */

    /**
     * @notice Calculate and returns the daily Validation Credit price (in WEI)
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @dev vc_price = Re*(1 - D)/cluster_size
     * @dev The `_expectedDailyReturnWei` is set by Byzantine and corresponds to the Ethereum daily staking return.
     */
    function _calculateDailyVcPrice(uint256 _discountRate) internal view returns (uint256) {
        return (_expectedDailyReturnWei * (10000 - _discountRate)) / (_clusterSize * 10000);
    }

    /**
     * @notice Calculate and returns the bid price that should be paid by the node operator (in WEI)
     * @param _timeInDays: duration of being a validator, in days
     * @param _dailyVcPrice: daily Validation Credit price (in WEI)
     * @dev bid_price = time_in_days * vc_price
     */
    function _calculateBidPrice(
        uint256 _timeInDays,
        uint256 _dailyVcPrice
    ) internal pure returns (uint256) {
        return _timeInDays * _dailyVcPrice;
    }

    /**
     * @notice Calculate and returns the auction score of a node operator
     * @param _dailyVcPrice: daily Validation Credit price in WEI
     * @param _timeInDays: duration of being a validator, in days
     * @param _reputation: reputation score of the operator
     * @dev powerValue = 1.001**_timeInDays, calculated from `_pow` function
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
     * @dev The result is divided by 1e9 to downscaled to 1e18 as the return value of `rpow` is upscaled to 1e27
     */
    function _pow(uint256 _timeIndays) internal pure returns (uint256) {
        uint256 fixedPoint = 1001 * 1e24;
        return DSMath.rpow(fixedPoint, _timeIndays) / 1e9;
    }

    /* ===================== MODIFIERS ===================== */

    modifier onlyOwner() {
        require(msg.sender == byzantineFinance, "Not the owner.");
        _;
    }
}
