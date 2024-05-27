// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "ds-math/math.sol";

import "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

import "./AuctionStorage.sol";

/// TODO: Calculation of the reputation score of node operators

contract Auction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AuctionStorage,
    DSMath
{
    using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;  

    /* ===================== CONSTRUCTOR & INITIALIZER ===================== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IEscrow _escrow,
        IStrategyModuleManager _strategyModuleManager
    ) AuctionStorage(_escrow, _strategyModuleManager) {
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        address _initialOwner,
        uint256 __expectedDailyReturnWei,
        uint256 __maxDiscountRate,
        uint256 __minDuration,
        uint256 __clusterSize
    ) external initializer {
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
        _expectedDailyReturnWei = __expectedDailyReturnWei;
        _maxDiscountRate = __maxDiscountRate;
        _minDuration = __minDuration;
        _clusterSize = __clusterSize;
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Add a node operator to the the whitelist to not make him pay the bond.
     * @param _nodeOpAddr: the node operator to whitelist.
     * @dev Revert if the node operator is already whitelisted.
     */
    function addNodeOpToWhitelist(address _nodeOpAddr) external onlyOwner {
        if (isWhitelisted(_nodeOpAddr)) revert AlreadyWhitelisted();
        _nodeOpsWhitelist[_nodeOpAddr] = true;
    }

    /**
     * @notice Remove a node operator to the the whitelist.
     * @param _nodeOpAddr: the node operator to remove from whitelist.
     * @dev Revert if the node operator is not whitelisted.
     */
    function removeNodeOpFromWhitelist(address _nodeOpAddr) external onlyOwner {
        if (!isWhitelisted(_nodeOpAddr)) revert NotWhitelisted();
        _nodeOpsWhitelist[_nodeOpAddr] = false;
    }

    /**
     * @notice Function triggered by the StrategyModuleManager every time a staker deposit 32ETH and ask for a DV.
     * It finds the `_clusterSize` node operators with the highest auction scores and put them in a DV.
     * @param _stratModNeedingDV: the strategy module asking for a DV.
     * @dev The status of the winners is updated to `inDV`.
     * @dev Reverts if not enough node operators are available.
     */
    function createDV(
        IStrategyModule _stratModNeedingDV
    ) external onlyStategyModuleManager nonReentrant {
        
        address[] memory auctionWinners = _getAuctionWinners();

        // BUG If node op payments fail, auction tree and auction score mapping already updated....

        // Create the Node structure and updates the details of the winners
        IStrategyModule.Node[] memory nodes = new IStrategyModule.Node[](_clusterSize);
        for (uint256 i = 0; i < _clusterSize;) {
            escrow.releaseFunds(_nodeOpsInfo[auctionWinners[i]].bidPrice);
            nodes[i] = IStrategyModule.Node(
                _nodeOpsInfo[auctionWinners[i]].vcNumber, // Validation Credits number of the node
                _nodeOpsInfo[auctionWinners[i]].reputationScore, // Reputation score of the node
                auctionWinners[i] // Winner address
            );
            _nodeOpsInfo[auctionWinners[i]].nodeStatus = NodeOpStatus.inDV;
            _nodeOpsInfo[auctionWinners[i]].bidPrice = 0;
            _nodeOpsInfo[auctionWinners[i]].auctionScore = 0;
            unchecked {
                ++i;
            }
        }
        // The cluster manager is the last node among the winners
        address clusterManager = auctionWinners[_clusterSize - 1];

        // update `ClusterDetails` of the StrategyModule
        _stratModNeedingDV.updateClusterDetails(nodes, clusterManager);

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
        if (_discountRate > _maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < _minDuration) revert DurationTooShort();

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
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     * @dev If too many ethers has been sent the function give back the excess to the sender.
     */
    function bid(
        uint256 _discountRate,
        uint256 _timeInDays
    ) external payable nonReentrant {
        // Verify if the sender is not already in auction
        if (_nodeOpsInfo[msg.sender].nodeStatus == NodeOpStatus.inAuction) revert AlreadyInAuction();

        // Verify the standing bid parameters
        if (_discountRate > _maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < _minDuration) revert DurationTooShort();

        /// TODO: Get the reputation score of msg.sender
        uint256 reputationScore = 1;

        /// @notice Calculate operator's bid price and auction score
        uint256 dailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 bidPrice = _calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = _calculateAuctionScore(dailyVcPrice, _timeInDays, reputationScore);

        if (_auctionTree.exists(auctionScore)) revert BidAlreadyExists();

        uint256 priceToPay;
        // If msg.sender is whitelisted, he only pays the bid
        if (isWhitelisted(msg.sender)) {
            priceToPay = bidPrice;
        } else {
            priceToPay = bidPrice + _BOND;
        }

        // Verify if the sender has sent enough ethers
        if (msg.value < priceToPay) revert NotEnoughEtherSent();

        // If to many ethers has been sent, refund the sender
        uint256 amountToRefund = msg.value - priceToPay;
        if (amountToRefund > 0) {
            payable(msg.sender).transfer(amountToRefund);
        }

        // Transfer the ethers in the escrow contract
        (bool success,) = address(escrow).call{value: priceToPay}("");
        if (!success) revert EscrowTransferFailed();

        // Add auction score in the tree
        _auctionTree.insert(auctionScore);
        // Update auctionScore mapping
        _auctionScoreToNodeOp[auctionScore] = msg.sender;

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
        if (_discountRate > _maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < _minDuration) revert DurationTooShort();

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
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function updateBid(
        uint256 _newDiscountRate,
        uint256 _newTimeInDays
    ) external payable nonReentrant {
        // Verify if the sender is in the auction
        if (_nodeOpsInfo[msg.sender].nodeStatus != NodeOpStatus.inAuction) revert NotInAuction();

        // Verify the standing bid parameters
        if (_newDiscountRate > _maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < _minDuration) revert DurationTooShort();

        // Get the previous bid price and auction score of msg.sender
        (,uint256 previousBidPrice,uint256 previousAuctionScore,,) = getNodeOpDetails(msg.sender);

        /// TODO: Get the reputation score of msg.sender
        uint256 reputationScore = 1;

        /// @notice Calculate operator's new bid price and new auction score
        uint256 newDailyVcPrice = _calculateDailyVcPrice(_newDiscountRate);
        uint256 newBidPrice = _calculateBidPrice(_newTimeInDays, newDailyVcPrice);
        uint256 newAuctionScore = _calculateAuctionScore(newDailyVcPrice, _newTimeInDays, reputationScore);

        // Verify if new Auction score doesn't already exist
        if (_auctionTree.exists(newAuctionScore)) revert BidAlreadyExists();

        if (newBidPrice > previousBidPrice) {
            // TODO: gas optimization with unchecked
            uint256 ethersToAdd = newBidPrice - previousBidPrice;
            // Verify if the sender has sent the difference
            if (msg.value < ethersToAdd) revert NotEnoughEtherSent();
            // If to many ethers has been sent, refund the sender
            uint256 amountToRefund = msg.value - ethersToAdd;
            if (amountToRefund > 0) {
                payable(msg.sender).transfer(amountToRefund);
            }
            // Transfer the ethers in the escrow contract
            (bool success,) = address(escrow).call{value: ethersToAdd}("");
            if (!success) revert EscrowTransferFailed();
        } else {
            // Knowing that the node op doesn't have to pay more, send him back all the ethers he has sent
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
            // TODO: gas optimization with unchecked
            uint256 ethersToSendBack = previousBidPrice - newBidPrice;
            // Ask the Escrow to send back the ethers
            escrow.refund(msg.sender, ethersToSendBack);
        }

        // Verify auctionScore of msg.sender and remove it from the tree and the mapping
        require(_auctionScoreToNodeOp[previousAuctionScore] == msg.sender);
        _auctionTree.remove(previousAuctionScore);
        delete _auctionScoreToNodeOp[previousAuctionScore];

        // Add new auction score in the tree
        _auctionTree.insert(newAuctionScore);
        // Update auctionScore mapping
        _auctionScoreToNodeOp[newAuctionScore] = msg.sender;

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
        // BUG: Possibility to withdraw bid when a node op has won an auction
        // Verify if the sender is in the auction
        if (_nodeOpsInfo[msg.sender].nodeStatus != NodeOpStatus.inAuction) revert NotInAuction();

        // Get the paid bid and auction score of msg.sender
        (,uint256 bidToRefund,uint256 auctionScore,,) = getNodeOpDetails(msg.sender);

        // Verify auctionScore of msg.sender and remove it from the tree and the mapping
        require(_auctionScoreToNodeOp[auctionScore] == msg.sender);
        _auctionTree.remove(auctionScore);
        delete _auctionScoreToNodeOp[auctionScore];

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

        // Ask the Escrow contract to refund the node op
        if (isWhitelisted(msg.sender)) {
            escrow.refund(msg.sender, bidToRefund);
        } else {
            escrow.refund(msg.sender, bidToRefund + _BOND);
        }
        
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
     * @notice Returns the node operator who have the `_auctionScore`
     * @param _auctionScore The auction score to get the node operator
     */
    function getAuctionScoreToNodeOp(
        uint256 _auctionScore
    ) public view returns (address) {
        return _auctionScoreToNodeOp[_auctionScore];
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

    /**
     * @notice Function to get the auction winners. It returns the node operators with the highest auction score.
     * @dev Reverts if not enough node operators in the auction to create a DV.
     * @dev Reverts if a winner address is null.
     * @dev We assume the winners directly accept to join the DV, therefore this function cleans the auction tree and auctionScore mapping.
     */
    function _getAuctionWinners() internal returns (address[] memory) {
        uint256 empty = BokkyPooBahsRedBlackTreeLibrary.getEmpty();

        uint256[] memory topAuctionScores = new uint256[](_clusterSize);
        address[] memory auctionWinners = new address[](_clusterSize);

        // Get the first `_clusterSize` biggest score and winners.
        // Reverts if not enough node operators in the auction.
        topAuctionScores[0] = _auctionTree.last();
        if (topAuctionScores[0] == empty) revert NotEnoughNodeOps();
        auctionWinners[0] = _auctionScoreToNodeOp[topAuctionScores[0]];
        require(auctionWinners[0] != address(0), "Invalid winner address");
        for (uint256 i = 1; i < _clusterSize;) {
            topAuctionScores[i] = _auctionTree.prev(topAuctionScores[i - 1]);
            if (topAuctionScores[i] == empty) revert NotEnoughNodeOps();
            auctionWinners[i] = _auctionScoreToNodeOp[topAuctionScores[i]];
            require(auctionWinners[i] != address(0), "Invalid winner address");
            unchecked {
                ++i;
            }
        }

        // If function didn't revert, we can clean the auction tree and auctionScore mapping.
        for (uint256 i = 0; i < _clusterSize;) {
            _auctionTree.remove(topAuctionScores[i]);
            delete _auctionScoreToNodeOp[topAuctionScores[i]];
            unchecked {
                ++i;
            }
        }

        return auctionWinners;
    }

    /* ===================== MODIFIERS ===================== */

    modifier onlyStategyModuleManager() {
        if (msg.sender != address(strategyModuleManager)) revert OnlyStrategyModuleManager();
        _;
    }
}
