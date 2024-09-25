// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

import { HitchensOrderStatisticsTreeLib } from "../libraries/HitchensOrderStatisticsTreeLib.sol";
import { ByzantineAuctionMath } from "../libraries/ByzantineAuctionMath.sol";

import "./AuctionStorage.sol";

/// TODO: Calculation of the reputation score of node operators

contract Auction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AuctionStorage
{
    using HitchensOrderStatisticsTreeLib for HitchensOrderStatisticsTreeLib.Tree;

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
     * @dev Initializes the address of the initial owner plus the auction parameters
     */
    function initialize(
        address _initialOwner,
        uint256 _expectedDailyReturnWei,
        uint16 _maxDiscountRate,
        uint32 _minDuration
    ) external initializer {
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
        expectedDailyReturnWei = _expectedDailyReturnWei;
        maxDiscountRate = _maxDiscountRate;
        minDuration = _minDuration;
    }

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Function triggered by the StrategyModuleManager every time a staker deposit 32ETH and ask for a DV.
     * It allows the pre-creation of a new DV for the next staker.
     * It finds the `clusterSize` node operators with the highest auction scores and put them in a DV.
     * @dev Reverts if not enough node operators are available.
     */
    /*function getAuctionWinners()
        external
        onlyStategyModuleManager
        nonReentrant
        returns(IStrategyModule.Node[] memory)
    {
        // Check if enough node ops in the auction to create a DV
        require(numNodeOpsInAuction >= clusterSize, "Not enough node ops in auction");
        
        // Returns the auction winners
        return _getAuctionWinners();
    }*/

    /**
     * @notice Function to determine the bid price a node operator will have to pay
     * @param _nodeOpAddr: address of the node operator who will bid
     * @param _discountRate: The desired profit margin in percentage of the operator (scale from 0 to 10000)
     * @param _timeInDays: duration of being part of a DV, in days
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the minimum values set by Byzantine.
     */
    function getPriceToPayCluster4(
        address _nodeOpAddr,
        uint16 _discountRate,
        uint32 _timeInDays
    ) external view returns (uint256) {

        // Verify the standing bid parameters
        if (_discountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < minDuration) revert DurationTooShort();

        // Calculate operator's bid price
        uint256 dailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _discountRate, _CLUSTER_SIZE_4);
        uint256 bidPrice = ByzantineAuctionMath.calculateBidPrice(_timeInDays, dailyVcPrice);

        // Calculate the total price to pay
        if (isWhitelisted(_nodeOpAddr)) {
            return bidPrice;
        }
        return bidPrice + _BOND;
    }

    /**
     * @notice Bid function to join a cluster of size 4. A call to that function will search the first 4 winners, calculate their average score, and put the virtual DV in the main auction.
     * Every time a new bid modify the first 4 winners, it update the main auction by removing the previous virtual DV and adding the new one.
     * @param _discountRate The desired profit margin in percentage of the operator (scale from 0 to 10000)
     * @param _timeInDays Duration of being part of a DV, in days
     * @return bidId The id of the bid
     * @dev The bid price is sent to an escrow smart contract. As long as the node operator doesn't win the auction, its bids stays in the escrow contract.
     * It is possible to ask the escrow contract to refund the bid if the operator wants to leave the protocol (call `withdrawBid`)
     * It is possible to update an existing bid parameters (call `updateBid`).
     * @dev Reverts if the bidder is not whitelisted (permissionless DV will arrive later)
     * @dev Reverts if the discount rate is too high or the duration is too short
     * @dev Reverts if the ethers sent by the node op are not enough to pay for the bid(s) (and the bond). If too many ethers has been sent the function returns the excess to the sender.
     */
    function bidCluster4(
        uint16 _discountRate,
        uint32 _timeInDays
    ) external payable nonReentrant returns (bytes32 bidId) {

        // Only whitelisted node operators can bid
        if (!isWhitelisted(msg.sender)) revert NotWhitelisted();

        // Verify the standing bid parameters
        if (_discountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < minDuration) revert DurationTooShort();

        // Update `dv4AuctionNumNodeOps` if necessary
        if (_nodeOpsDetails[msg.sender].numBidsCluster4 == 0) {
            dv4AuctionNumNodeOps += 1;
        }

        /// TODO: Get the reputation score of msg.sender
        uint32 reputationScore = 1;

        // Calculate operator's bid price and score
        uint256 dailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _discountRate, _CLUSTER_SIZE_4);
        uint256 bidPrice = ByzantineAuctionMath.calculateBidPrice(_timeInDays, dailyVcPrice);
        uint256 auctionScore = ByzantineAuctionMath.calculateAuctionScore(dailyVcPrice, _timeInDays, reputationScore);

        // Calculate the bid ID (hash(msg.sender, timestamp, bidType))
        bidId = keccak256(abi.encodePacked(msg.sender, block.timestamp, _CLUSTER_SIZE_4));

        // Insert the auction score in the cluster 4 sub-auction tree
        _dv4AuctionTree.insert(bidId, auctionScore);

        // Add bid to the bids mapping
        _bidDetails[bidId] = BidDetails({
            auctionScore: auctionScore,
            bidPrice: bidPrice,
            nodeOp: msg.sender,
            vcNumbers: _timeInDays, /// TODO: Split the VC among the different validators (or do it in another contract)
            discountRate: _discountRate,
            auctionType: AuctionType.JOIN_CLUSTER_4
        });
        // Increment the bid number of the node op
        _nodeOpsDetails[msg.sender].numBidsCluster4 += 1;

        // Update main auction if necessary
        if (auctionScore > _dv4LatestWinningInfo.lastestWinningScore && dv4AuctionNumNodeOps >= _CLUSTER_SIZE_4) {
            _dv4UpdateMainAuction();
        }
        
        /// TODO Events
        /// emit BidPlaced(msg.sender, reputationScore, _discountRate[i], _timeInDays[i], bidPrice, auctionScores[i]);

        // Calculate the total price to pay, verify it and send it to the escrow contract
        uint256 priceToPay;
        if (isWhitelisted(msg.sender)) {
            priceToPay = bidPrice;
        } else {
            priceToPay = bidPrice + _BOND;
            _nodeOpsDetails[msg.sender].numBonds += 1;
        }
        _verifyEthSent(msg.value, priceToPay);
        _transferToEscrow(priceToPay);
    }

    /**
     * @notice Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decreases its bid.
     * @notice The bid which will be updated will be the last bid with `_oldAuctionScore`
     * @param _nodeOpAddr: address of the node operator updating its bid
     * @param _oldAuctionScore: auction score of the bid to update
     * @param _newDiscountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_oldAuctionScore`.
     * @dev Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.
     */
    /*function getUpdateOneBidPrice(
        address _nodeOpAddr,
        uint256 _oldAuctionScore,
        uint16 _newDiscountRate,
        uint32 _newTimeInDays
    ) public view returns (uint256) {
        // Verify if `_nodeOpAddr` has at least a bid with `_oldAuctionScore`
        require (getNodeOpAuctionScoreBidPrices(_nodeOpAddr, _oldAuctionScore).length > 0, "Wrong node op auctionScore");

        // Verify the standing bid parameters
        if (_newDiscountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < minDuration) revert DurationTooShort();

        // Get the number of bids with this `_oldAuctionScore`
        uint256 numSameBids = getNodeOpAuctionScoreBidPrices(_nodeOpAddr, _oldAuctionScore).length;

        // Get what the node op has already paid
        uint256 lastBidPrice = _nodeOpsInfo[_nodeOpAddr].auctionScoreToBidPrices[_oldAuctionScore][numSameBids - 1];

        // Calculate operator's new bid price
        uint256 newDailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _newDiscountRate, clusterSize);
        uint256 newBidPrice = ByzantineAuctionMath.calculateBidPrice(_newTimeInDays, newDailyVcPrice);

        if (newBidPrice > lastBidPrice) {
            unchecked {
                return newBidPrice - lastBidPrice;
            }
        }
        return 0;
    }*/

    /**
     * @notice  Update a bid of a node operator associated to `_oldAuctionScore`. The node op will have to pay more if he outbids. 
     *          If he decreases his bid, the escrow contract will send him back the difference.
     * @notice  The bid which will be updated will be the last bid with `_oldAuctionScore`
     * @param _oldAuctionScore: auction score of the bid to update
     * @param _newDiscountRate: new discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: new duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_oldAuctionScore`.
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     * @dev Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.
     */
    /*function updateOneBid(
        uint256 _oldAuctionScore,
        uint16 _newDiscountRate,
        uint32 _newTimeInDays
    ) external payable nonReentrant returns (uint256){
        // Verify if the sender has at least a bid with `_oldAuctionScore`
        require (getNodeOpAuctionScoreBidPrices(msg.sender, _oldAuctionScore).length > 0, "Wrong node op auctionScore");

        // Verify the standing bid parameters
        if (_newDiscountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < minDuration) revert DurationTooShort();

        // Convert msg.sender address in bytes32
        bytes32 bidder = bytes32(uint256(uint160(msg.sender)));

        // Get the number of bids with this `_oldAuctionScore`
        uint256 numSameBids = getNodeOpAuctionScoreBidPrices(msg.sender, _oldAuctionScore).length;

        // Get last bid price associated to `_oldAuctionScore`. That bid will be updated
        uint256 lastBidPrice = _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_oldAuctionScore][numSameBids - 1];

        // Update auction tree (if necessary) and node ops details mappings
        if (numSameBids == 1) {
            _auctionTree.remove(bidder, _oldAuctionScore);
            delete _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_oldAuctionScore];
            delete _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_oldAuctionScore];
        } else {
            _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_oldAuctionScore].pop();
            _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_oldAuctionScore].pop();
        }

        /// TODO: Get the reputation score of msg.sender
        uint32 reputationScore = 1;

        /// @notice Calculate operator's new bid price and new auction score
        uint256 newDailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _newDiscountRate, clusterSize);
        uint256 newBidPrice = ByzantineAuctionMath.calculateBidPrice(_newTimeInDays, newDailyVcPrice);
        uint256 newAuctionScore = ByzantineAuctionMath.calculateAuctionScore(newDailyVcPrice, _newTimeInDays, reputationScore);

        // Verify if new Auction score doesn't already exist
        if (!_auctionTree.keyExists(bidder, newAuctionScore)) {
            _auctionTree.insert(bidder, newAuctionScore);
        }
        _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[newAuctionScore].push(newBidPrice);
        _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[newAuctionScore].push(_newTimeInDays);      

        // Verify the price to pay for the new bid
        if (newBidPrice > lastBidPrice) {
            uint256 ethersToAdd;
            unchecked { ethersToAdd = newBidPrice - lastBidPrice; }
            // Verify if the sender has sent the difference
            if (msg.value < ethersToAdd) revert NotEnoughEtherSent();
            // If to many ethers has been sent, refund the sender
            uint256 amountToRefund;
            unchecked { amountToRefund = msg.value - ethersToAdd; }
            if (amountToRefund > 0) {
                payable(msg.sender).transfer(amountToRefund);
            }
            // Transfer the ethers in the escrow contract
            (bool success,) = address(escrow).call{value: ethersToAdd}("");
            if (!success) revert EscrowTransferFailed();
        } else {
            // Knowing that the node op doesn't have to pay more, send him back the diffence
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
            uint256 ethersToSendBack;
            unchecked {
                ethersToSendBack = lastBidPrice - newBidPrice;
            }
            // Ask the Escrow to send back the ethers
            escrow.refund(msg.sender, ethersToSendBack);
        }

        emit BidUpdated(msg.sender, reputationScore, _oldAuctionScore, _newTimeInDays, _newDiscountRate, newBidPrice, newAuctionScore);

        return newAuctionScore;

    }*/

    /**
     * @notice Allow a node operator to withdraw a specific bid (through its auction score).
     * The withdrawer will be refund its bid price plus (the bond of he paid it).
     * @param _auctionScore: auction score of the bid to withdraw. Will withdraw the last bid with this score.
     */
    /*function withdrawBid(uint256 _auctionScore) external {
        // Verify if the sender has at least a bid with `_auctionScore`
        require (getNodeOpAuctionScoreBidPrices(msg.sender, _auctionScore).length > 0, "Wrong node op auctionScore");

        // Convert msg.sender address in bytes32
        bytes32 bidder = bytes32(uint256(uint160(msg.sender)));

        // Get the number of bids with this `_auctionScore`
        uint256 numSameBids = getNodeOpAuctionScoreBidPrices(msg.sender, _auctionScore).length;

        // Get last bid price associated to `_auctionScore`. That bid will be updated
        uint256 bidToRefund = _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore][numSameBids - 1];

        // Update auction tree (if necessary) and node ops details mappings
        if (numSameBids == 1) {
            _auctionTree.remove(bidder, _auctionScore);
            delete _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore];
            delete _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_auctionScore];
        } else {
            _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore].pop();
            _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_auctionScore].pop();
        }
        _nodeOpsInfo[msg.sender].numBids -= 1;
        // Decrease the number of node ops in the auction if the winner has no more bids
        if (_nodeOpsInfo[msg.sender].numBids == 0) --numNodeOpsInAuction;

        // Ask the Escrow contract to refund the node op
        if (isWhitelisted(msg.sender)) {
            escrow.refund(msg.sender, bidToRefund);
        } else {
            escrow.refund(msg.sender, bidToRefund + _BOND);
        }

        emit BidWithdrawn(msg.sender, _auctionScore);
    }*/

    /* ===================== VIEW FUNCTIONS ===================== */

    /// @notice Returns true if `_nodeOpAddr` is whitelisted, false otherwise.
    function isWhitelisted(address _nodeOpAddr) public view returns (bool) {
        return _nodeOpsDetails[_nodeOpAddr].isWhitelisted;
    }

    /// @notice Returns the number of DVs in the main auction
    function getNumDVInAuction() public view returns (uint256) {
        return _mainAuctionTree.count();
    }

    /**
     * @notice Returns the details of a specific bid
     * @param _bidId The unique identifier of the bid
     * @return BidDetails struct containing the bid details
     */
    function getBidDetails(bytes32 _bidId) public view returns (BidDetails memory) {
        return _bidDetails[_bidId];
    }

    /**
     * @notice Returns the details of a specific cluster
     * @param _clusterId The unique identifier of the cluster
     * @return ClusterDetails struct containing the cluster details
     */
    function getClusterDetails(bytes32 _clusterId) public view returns (ClusterDetails memory) {
        return _clusterDetails[_clusterId];
    }

    /**
     * @notice Returns the id of the cluster with the highest average auction score
     * @dev Returns (bytes32(0), 0) if main tree is empty
     */
    function getWinningCluster() public view returns (bytes32 winningClusterId, uint256 highestAvgAuctionScore) {
        highestAvgAuctionScore = _mainAuctionTree.last();
        if (highestAvgAuctionScore == 0) {
            winningClusterId = bytes32(0);
        } else {
            winningClusterId = _mainAuctionTree.valueKeyAtIndex(highestAvgAuctionScore, 0);
        }
    }

    /* ======================= OWNER FUNCTIONS ======================= */

    /**
     * @notice Add node operators to the whitelist
     * @param _nodeOpAddrs: A dynamique array of the addresses to whitelist
     */
    function whitelistNodeOps(address[] calldata _nodeOpAddrs) external onlyOwner {
        for (uint256 i = 0; i < _nodeOpAddrs.length;) {
            _nodeOpsDetails[_nodeOpAddrs[i]].isWhitelisted = true;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove a node operator to the the whitelist.
     * @param _nodeOpAddr: the node operator to remove from whitelist.
     * @dev Revert if the node operator is not whitelisted.
     */
    /*function removeNodeOpFromWhitelist(address _nodeOpAddr) external onlyOwner {
        if (!isWhitelisted(_nodeOpAddr)) revert NotWhitelisted();
        _nodeOpsWhitelist[_nodeOpAddr] = false;
    }*/

    /**
     * @notice Update the expected daily PoS rewards variable (in Wei)
     * @dev This function is callable only by the Auction contract's owner
     * @param _newExpectedDailyReturnWei: the new expected daily return of Ethereum staking (in wei)
     */
    function updateExpectedDailyReturnWei(uint256 _newExpectedDailyReturnWei) external onlyOwner {
        expectedDailyReturnWei = _newExpectedDailyReturnWei;
    }

    /**
     * @notice Update the minimum validation duration
     * @dev This function is callable only by the Auction contract's owner
     * @param _newMinDuration: the new minimum duration of being a validator in a DV (in days)
     */
    function updateMinDuration(uint32 _newMinDuration) external onlyOwner {
        minDuration = _newMinDuration;
    }

    /**
     * @notice Update the maximum discount rate
     * @dev This function is callable only by the Auction contract's owner
     * @param _newMaxDiscountRate: the new maximum discount rate (i.e the max profit margin of node op) (from 0 to 10000 -> 100%)
     */
    function updateMaxDiscountRate(uint16 _newMaxDiscountRate) external onlyOwner {
        maxDiscountRate = _newMaxDiscountRate;
    }

    /* ======================= PRIVATE FUNCTIONS ======================= */

    function _dv4UpdateMainAuction() private {

        // Create the Node structure array for the Strategy Module
        NodeDetails[] memory dv4Winners = new NodeDetails[](_CLUSTER_SIZE_4);

        // 4 best auctionScores array
        uint256[] memory bestAuctionScores = new uint256[](_CLUSTER_SIZE_4);

        // 4 winners address array
        address[] memory winnersAddr = new address[](_CLUSTER_SIZE_4);

        uint256 winnerCount;
        bytes32 bidId;
        uint256 frozenAuctionScore;
        bool winnerExists;

        // Find the sub-auction 4 winners
        while (winnerCount < _CLUSTER_SIZE_4) {
            // Fill bestAuctionScores array
            if (winnerCount == 0) {
                bestAuctionScores[winnerCount] = _dv4AuctionTree.last();
            } else {
                bestAuctionScores[winnerCount] = _dv4AuctionTree.prev(frozenAuctionScore);
            }

            (,,,,uint256 numSameBids,) = _dv4AuctionTree.getNode(bestAuctionScores[winnerCount]);

            frozenAuctionScore = bestAuctionScores[winnerCount];
            for (uint256 i = 0; i < numSameBids && winnerCount < _CLUSTER_SIZE_4;) {
                bidId = _dv4AuctionTree.valueKeyAtIndex(frozenAuctionScore, i);

                // Verify if the `winnerAddr` isn't already in the array
                winnerExists = false;
                for (uint256 j = 0; j < winnerCount;) {
                    if (_bidDetails[bidId].nodeOp == winnersAddr[j]) {
                        winnerExists = true;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }

                // Save winner's details
                if (!winnerExists) {
                    winnersAddr[winnerCount] = _bidDetails[bidId].nodeOp;
                    dv4Winners[winnerCount].pendingBidId = bidId;
                    if (i > 0) bestAuctionScores[winnerCount] = bestAuctionScores[winnerCount - 1];
                    ++winnerCount;
                }

                unchecked {
                    ++i;
                }
            }
        }

        // Calculate the average auction score and cluster ID
        uint256 averageAuctionScore = ByzantineAuctionMath.calculateAverageAuctionScore(bestAuctionScores);
        bytes32 clusterId = ByzantineAuctionMath.generateClusterId(block.timestamp, winnersAddr, averageAuctionScore);        

        // Update main auction
        _updateMainAuctionTree(clusterId, averageAuctionScore);

        // Update cluster mapping
        _createClusterDetails(clusterId, averageAuctionScore, dv4Winners);

        // Update the lastest winning info
        _dv4LatestWinningInfo.lastestWinningScore = bestAuctionScores[_CLUSTER_SIZE_4 - 1];
        _dv4LatestWinningInfo.latestWinningClusterId = clusterId;
    }

    /// @notice Update the main auction tree by adding a new virtual cluster and removing the old one
    function _updateMainAuctionTree(bytes32 _newClusterId, uint256 _newAvgAuctionScore) private {
        if (_dv4LatestWinningInfo.latestWinningClusterId != bytes32(0)) {
            uint256 lastAverageAuctionScore = _clusterDetails[_dv4LatestWinningInfo.latestWinningClusterId].averageAuctionScore;
            _mainAuctionTree.remove(_dv4LatestWinningInfo.latestWinningClusterId, lastAverageAuctionScore);
            delete _clusterDetails[_dv4LatestWinningInfo.latestWinningClusterId];
        }
        _mainAuctionTree.insert(_newClusterId, _newAvgAuctionScore);
    }

    /// @notice Create a new entry in the `_clusterDetails` mapping
    function _createClusterDetails(bytes32 _clusterId, uint256 _averageAuctionScore, NodeDetails[] memory _nodes) private {
        _clusterDetails[_clusterId].averageAuctionScore = _averageAuctionScore;
        for (uint256 i = 0; i < _CLUSTER_SIZE_4;) {
            _clusterDetails[_clusterId].nodes.push(_nodes[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Verify if the bidder has sent enough ethers. Refund the excess if it's the case.
    function _verifyEthSent(uint256 _ethSent, uint256 _priceToPay) private {
        if (_ethSent < _priceToPay) revert NotEnoughEtherSent();

        // If too many ethers have been sent, refund the sender
        uint256 amountToRefund = _ethSent - _priceToPay;
        if (amountToRefund > 0) {
            (bool success, ) = msg.sender.call{value: amountToRefund}("");
            if (!success) revert RefundFailed();
        }
    }

    /// @notice Transfer `_priceToPay` to the Escrow contract
    function _transferToEscrow(uint256 _priceToPay) private {
        (bool success,) = address(escrow).call{value: _priceToPay}("");
        if (!success) revert EscrowTransferFailed();
    }

    /* ===================== MODIFIERS ===================== */

    modifier onlyStategyModuleManager() {
        if (msg.sender != address(strategyModuleManager)) revert OnlyStrategyModuleManager();
        _;
    }

}
