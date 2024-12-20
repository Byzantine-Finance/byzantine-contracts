// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";

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
        IStrategyVaultManager _strategyVaultManager,
        PushSplitFactory _pushSplitFactory,
        IStakerRewards _stakerRewards
    ) AuctionStorage(_escrow, _strategyVaultManager, _pushSplitFactory, _stakerRewards) {
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
     * @notice Function triggered by the StrategyVaultManager or a StrategyVaultETH every time a staker deposits ETH
     * @dev It triggers the DV Auction, returns the winning cluster ID and triggers a new sub-auction
     * @dev Reverts if not enough node operators in the protocol
     * @dev Reverts if the caller is not a StrategyVaultETH contract or the StrategyVaultManager
     * @return The id of the winning cluster
     */
    function triggerAuction() external onlyStratVaultETH nonReentrant returns (bytes32) {

        // Check if at least one DV is ready in the main auction 
        if (_mainAuctionTree.count() < 1) revert MainAuctionEmpty();

        // Get the winning cluster details
        (bytes32 winningClusterId, uint256 winningAvgAuctionScore) = getWinningCluster();
        _clusterDetails[winningClusterId].status = ClusterStatus.IN_CREATION;
        ClusterDetails memory winningClusterDetails = getClusterDetails(winningClusterId);

        // Remove the winning cluster from the main auction tree
        _mainAuctionTree.remove(winningClusterId, winningAvgAuctionScore);

        // Create the split struct of the winning cluster
        SplitV2Lib.Split memory splitParams = _createSplitParams(winningClusterDetails.nodes);

        // deploy the Split contract and update ClusterDetails
        address splitAddr = pushSplitFactory.createSplit(splitParams, owner(), owner());
        address eigenPodAddr = strategyVaultManager.getPodByStratVaultAddr(msg.sender);
        _clusterDetails[winningClusterId].splitAddr = splitAddr;

        // Update the corresponding sub-auction tree
        _mainUdateSubAuction(winningClusterDetails.nodes, winningClusterId, _bidDetails[winningClusterDetails.nodes[0].bidId].auctionType);

        emit ClusterCreated(winningClusterId, winningAvgAuctionScore, msg.sender, splitAddr, eigenPodAddr);

        return winningClusterId;
    }

    /**
     * @notice Function to determine the bid price a node operator will have to pay
     * @param _nodeOpAddr: address of the node operator who will bid
     * @param _discountRate: The desired profit margin in percentage of the operator (scale from 0 to 10000)
     * @param _timeInDays: duration of being part of a DV, in days
     * @param _auctionType: cluster type the node operator wants to join (dv4, dv7, private dv, ...)
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the minimum values set by Byzantine.
     * @dev Reverts if the auction type is unknown
     */
    function getPriceToPay(
        address _nodeOpAddr,
        uint16 _discountRate,
        uint32 _timeInDays,
        AuctionType _auctionType
    ) external view returns (uint256) {

        // Verify the standing bid parameters
        if (_discountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < minDuration) revert DurationTooShort();

        // Calculate operator's bid price according to the auction type
        uint256 dailyVcPrice;
        uint256 bidPrice;   
        if (_auctionType == AuctionType.JOIN_CLUSTER_4) {
            dailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _discountRate, _CLUSTER_SIZE_4);
            bidPrice = ByzantineAuctionMath.calculateBidPrice(_timeInDays, dailyVcPrice);
        } else {
            revert InvalidAuctionType();
        }

        // Calculate the total price to pay
        if (isWhitelisted(_nodeOpAddr)) {
            return bidPrice;
        }
        return bidPrice + _BOND;
    }

    /**
     * @notice Bid function to join a cluster type specified by `_auctionType`. A call to that function will search the sub-auctions winners, calculate their average score, and put the virtual DV in the main auction.
     * Every time a new bid modify the sub-auctions winners, it update the main auction by removing the previous virtual DV and adding the new one.
     * @param _discountRate The desired profit margin in percentage of the operator (scale from 0 to 10000)
     * @param _timeInDays Duration of being part of a DV, in days
     * @param _auctionType cluster type the node operator wants to join (dv4, dv7, private dv, ...)
     * @return bidId The id of the bid
     * @dev The bid price is sent to an escrow smart contract. As long as the node operator doesn't win the auction, its bids stays in the escrow contract.
     * It is possible to ask the escrow contract to refund the bid if the operator wants to leave the protocol (call `withdrawBid`)
     * It is possible to update an existing bid parameters (call `updateBid`).
     * @dev Reverts if the bidder is not whitelisted (permissionless DV will arrive later)
     * @dev Reverts if the discount rate is too high or the duration is too short
     * @dev Reverts if the ethers sent by the node op are not enough to pay for the bid(s) (and the bond). If too many ethers has been sent the function returns the excess to the sender.
     * @dev Reverts if the auction type is unknown
     */
    function bid(
        uint16 _discountRate,
        uint32 _timeInDays,
        AuctionType _auctionType
    ) external payable nonReentrant returns (bytes32 bidId) {

        // Only whitelisted node operators can bid
        if (!isWhitelisted(msg.sender)) revert NotWhitelisted();

        // Verify the standing bid parameters
        if (_discountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < minDuration) revert DurationTooShort();

        /// TODO: Get the reputation score of msg.sender
        uint32 reputationScore = 1;

        // Bid the corresponding sub-auction
        uint256 dailyVcPrice;
        uint256 bidPrice;
        uint256 auctionScore;

        if (_auctionType == AuctionType.JOIN_CLUSTER_4) {
            // Update `dv4AuctionNumNodeOps` if necessary
            if (_nodeOpsDetails[msg.sender].numBidsCluster4 == 0) {
                dv4AuctionNumNodeOps += 1;
            }

            // Calculate operator's bid price and score
            dailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _discountRate, _CLUSTER_SIZE_4);
            bidPrice = ByzantineAuctionMath.calculateBidPrice(_timeInDays, dailyVcPrice);
            auctionScore = ByzantineAuctionMath.calculateAuctionScore(dailyVcPrice, _timeInDays, reputationScore);

            // Calculate the bid ID (hash(msg.sender, timestamp, bidType))
            bidId = keccak256(abi.encodePacked(msg.sender, block.timestamp, _CLUSTER_SIZE_4));

            // Insert the auction score in the cluster 4 sub-auction tree
            _dv4AuctionTree.insert(bidId, auctionScore);

            // Increment the bid number of the node op
            _nodeOpsDetails[msg.sender].numBidsCluster4 += 1;

            // Add bid to the bids mapping
            _bidDetails[bidId] = BidDetails({
                auctionScore: auctionScore,
                bidPrice: bidPrice,
                nodeOp: msg.sender,
                vcNumber: _timeInDays,
                discountRate: _discountRate,
                auctionType: AuctionType.JOIN_CLUSTER_4
            });

            // Update main auction if necessary
            if (auctionScore > _dv4LatestWinningInfo.lastestWinningScore && dv4AuctionNumNodeOps >= _CLUSTER_SIZE_4) {
                _dv4UpdateMainAuction();
            }

            emit BidPlaced(msg.sender, bidId, _discountRate, _timeInDays, bidPrice, auctionScore, AuctionType.JOIN_CLUSTER_4);

        } else {
            revert InvalidAuctionType();
        }

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
     * @notice Fonction to determine the price to add if the node operator outbids. Returns 0 if he downbids.
     * @param _nodeOpAddr: address of the node operator updating its bid
     * @param _bidId: bidId to update
     * @param _newDiscountRate: the new discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: the new duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_bidId`.
     * @dev Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.
     */
    function getUpdateBidPrice(
        address _nodeOpAddr,
        bytes32 _bidId,
        uint16 _newDiscountRate,
        uint32 _newTimeInDays
    ) external view returns (uint256) {
        // Verify if `_nodeOpAddr` is the owner of `_bidId`
        if (_bidDetails[_bidId].nodeOp != _nodeOpAddr) revert SenderNotBidder();

        // Verify the standing bid parameters
        if (_newDiscountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < minDuration) revert DurationTooShort();

        // Get what the node op has already paid
        uint256 priceAlreadyPaid = _bidDetails[_bidId].bidPrice;

        // Calculate operator's new bid price according to the auction type
        uint256 newDailyVcPrice;
        uint256 newBidPrice;
        if (_bidDetails[_bidId].auctionType == AuctionType.JOIN_CLUSTER_4) {
            newDailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _newDiscountRate, _CLUSTER_SIZE_4);
            newBidPrice = ByzantineAuctionMath.calculateBidPrice(_newTimeInDays, newDailyVcPrice);
        } else {
            revert InvalidAuctionType();
        }

        if (newBidPrice > priceAlreadyPaid) {
            unchecked {
                return newBidPrice - priceAlreadyPaid;
            }
        }
        return 0;
    }

    /**
     * @notice  Update a bid of a node operator's `_bidId`. The node op will have to pay more if he outbids. 
     *          If he decreases his bid, the escrow contract will send him back the price difference.
     * @param _bidId: bidId to update
     * @param _newDiscountRate: the new discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: the new duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_bidId`.
     * @dev Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     */
    function updateBid(
        bytes32 _bidId,
        uint16 _newDiscountRate,
        uint32 _newTimeInDays
    ) external payable nonReentrant {
        // Verify if the sender update one of its bids
        if (_bidDetails[_bidId].nodeOp != msg.sender) revert SenderNotBidder();

        // Verify the standing bid parameters
        if (_newDiscountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < minDuration) revert DurationTooShort();

        // Get the bid to update details
        BidDetails memory bidToUpdate = _bidDetails[_bidId];

        /// TODO: Get the reputation score of msg.sender
        uint32 reputationScore = 1;

        // Update the bid according to its auction type
        uint256 newDailyVcPrice;
        uint256 newBidPrice;
        uint256 newAuctionScore;
        if (bidToUpdate.auctionType == AuctionType.JOIN_CLUSTER_4) {
            // Calculate operator's new bid price and new score
            newDailyVcPrice = ByzantineAuctionMath.calculateVCPrice(expectedDailyReturnWei, _newDiscountRate, _CLUSTER_SIZE_4);
            newBidPrice = ByzantineAuctionMath.calculateBidPrice(_newTimeInDays, newDailyVcPrice);
            newAuctionScore = ByzantineAuctionMath.calculateAuctionScore(newDailyVcPrice, _newTimeInDays, reputationScore);

            // Update the cluster 4 sub-auction tree
            _dv4AuctionTree.remove(_bidId, bidToUpdate.auctionScore);
            _dv4AuctionTree.insert(_bidId, newAuctionScore);

            // Update the bids mapping
            _bidDetails[_bidId].auctionScore = newAuctionScore;
            _bidDetails[_bidId].bidPrice = newBidPrice;
            _bidDetails[_bidId].vcNumber = _newTimeInDays;
            _bidDetails[_bidId].discountRate = _newDiscountRate;

            // Update main auction if:
            //      1. The new bid auction score is higher than the current sub-auction latest winning score
            //      2. The updated auction score was among the sub-auction winning bids
            if ((newAuctionScore > _dv4LatestWinningInfo.lastestWinningScore || bidToUpdate.auctionScore >= _dv4LatestWinningInfo.lastestWinningScore) && dv4AuctionNumNodeOps >= _CLUSTER_SIZE_4) {
                _dv4UpdateMainAuction();
            }

        } else {

            revert InvalidAuctionType();
        }

        // Verify the price difference between the old and new bid
        uint256 priceDiff;
        if (newBidPrice > bidToUpdate.bidPrice) { // node op outbids
            unchecked { priceDiff = newBidPrice - bidToUpdate.bidPrice; }
            _verifyEthSent(msg.value, priceDiff);
            _transferToEscrow(priceDiff);
        } else { // node op downbids
            if (msg.value > 0) {
                (bool success, ) = msg.sender.call{value: msg.value}("");
                if (!success) revert RefundFailed();
            }
            unchecked { priceDiff = bidToUpdate.bidPrice - newBidPrice; }
            // Ask the Escrow to send back the ethers
            escrow.refund(msg.sender, priceDiff);
        }

        emit BidUpdated(msg.sender, _bidId, _newDiscountRate, _newTimeInDays, newBidPrice, newAuctionScore);

    }

    /**
     * @notice Allow a node operator to withdraw a specific bid (through its bidId).
     * The withdrawer will be refund its bid price plus (the bond of he paid it).
     * @param _bidId: bidId of the bid to withdraw.
     * @dev Reverts if the node op doesn't have a bid with `_bidId`.
     */
    function withdrawBid(bytes32 _bidId) external {
        // Verify if the sender withdraw one of its bids
        if (_bidDetails[_bidId].nodeOp != msg.sender) revert SenderNotBidder();

        // Get the bid to withdraw details
        BidDetails memory bidToWithdraw = _bidDetails[_bidId];

        // Find the bid's sub-auction tree
        if (bidToWithdraw.auctionType == AuctionType.JOIN_CLUSTER_4) {
            // Decrement the bid number of the node op
            _nodeOpsDetails[msg.sender].numBidsCluster4 -= 1;
            // Update `dv4AuctionNumNodeOps` if necessary
            if (_nodeOpsDetails[msg.sender].numBidsCluster4 == 0) --dv4AuctionNumNodeOps;

            // Remove the bid from the sub-auction tree
            _dv4AuctionTree.remove(_bidId, bidToWithdraw.auctionScore);

            // delete the bid from the bids mapping
            delete _bidDetails[_bidId];

            // Update main auction if necessary
            if (bidToWithdraw.auctionScore >= _dv4LatestWinningInfo.lastestWinningScore && dv4AuctionNumNodeOps >= _CLUSTER_SIZE_4) {
                _dv4UpdateMainAuction();
            }

        } else {

            revert InvalidAuctionType();
        }

        // Ask the Escrow contract to refund the node op
        if (isWhitelisted(msg.sender)) {
            escrow.refund(msg.sender, bidToWithdraw.bidPrice);
        } else if (_nodeOpsDetails[msg.sender].numBonds > 0) {
            _nodeOpsDetails[msg.sender].numBonds -= 1;
            escrow.refund(msg.sender, bidToWithdraw.bidPrice + _BOND);
        } else {
            escrow.refund(msg.sender, bidToWithdraw.bidPrice);
        }

        emit BidWithdrawn(msg.sender, _bidId);
    }

    /** 
     * @notice Update the VC number of a node and the cluster status
     * @param _clusterId: ID of the cluster
     * @param _consumedVCs: number of VC to subtract
     * @dev This function is callable only by the StakerRewards contract
     * TODO: add a try catch to handle the case where consumedVCs is greater than currentVCs
     */
    function updateNodeVCNumber(bytes32 _clusterId, uint32 _consumedVCs) external onlyStakerRewards {
        ClusterDetails storage clusterDetails = _clusterDetails[_clusterId];
        for (uint8 i; i < clusterDetails.nodes.length; ) {
            clusterDetails.nodes[i].currentVCNumber -= _consumedVCs;

            if (clusterDetails.nodes[i].currentVCNumber == 0) {
                clusterDetails.status = ClusterStatus.EXITED;
            }

            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @notice Update the status of a cluster
     * @param _clusterId The id of the cluster to update the status
     * @param _newStatus The new status
     * @dev Callable only by a StrategyVaultETH contract
     * @dev The check to know if the cluster is in the calling vault is done in the StrategyVaultETH contract
     */
    function updateClusterStatus(bytes32 _clusterId, IAuction.ClusterStatus _newStatus) external onlyStratVaultETH {
        _clusterDetails[_clusterId].status = _newStatus;
    }

    /**
     * @notice Set the pubkey hash of a cluster
     * @param _clusterId The id of the cluster to set the pubkey hash
     * @param _clusterPubkey The pubkey of the cluster
     * @dev Callable only by a StrategyVaultETH contract
     * @dev The check to know if the cluster is in the calling vault is done in the StrategyVaultETH contract
     */
    function setClusterPubKey(bytes32 _clusterId, bytes calldata _clusterPubkey) external onlyStratVaultETH {
        _clusterDetails[_clusterId].clusterPubKeyHash = sha256(abi.encodePacked(_clusterPubkey, bytes16(0)));
    }

    /* ===================== VIEW FUNCTIONS ===================== */

    /// @notice Returns true if `_nodeOpAddr` is whitelisted, false otherwise.
    function isWhitelisted(address _nodeOpAddr) public view returns (bool) {
        return _nodeOpsDetails[_nodeOpAddr].isWhitelisted;
    }

    /// @notice Returns the globaldetails of a specific node operator
    function getNodeOpDetails(address _nodeOpAddr) public view returns (NodeOpGlobalDetails memory) {
        return _nodeOpsDetails[_nodeOpAddr];
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
                    dv4Winners[winnerCount].bidId = bidId;
                    dv4Winners[winnerCount].currentVCNumber = _bidDetails[bidId].vcNumber;
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
        _updateMainAuctionTree(clusterId, averageAuctionScore, AuctionType.JOIN_CLUSTER_4);

        // Update cluster mapping
        _createClusterDetails(clusterId, averageAuctionScore, dv4Winners);

        // Update the lastest winning info
        _dv4LatestWinningInfo.lastestWinningScore = bestAuctionScores[_CLUSTER_SIZE_4 - 1];
        _dv4LatestWinningInfo.latestWinningClusterId = clusterId;
    }

    /// @notice Called to update the winning cluster's sub-auction tree
    function _mainUdateSubAuction(NodeDetails[] memory _nodesToRemove, bytes32 _winningClusterId, AuctionType _auctionType) private {

        // Update sub auction tree dv4
        if (_auctionType == AuctionType.JOIN_CLUSTER_4) {
            // Reset the latest winning info
            _dv4LatestWinningInfo.lastestWinningScore = 0;
            _dv4LatestWinningInfo.latestWinningClusterId = bytes32(0);

            for (uint256 i = 0; i < _nodesToRemove.length;) {
                // Bidder address and bidPrice
                address nodeOpAddr = _bidDetails[_nodesToRemove[i].bidId].nodeOp;
                uint256 bidPrice = _bidDetails[_nodesToRemove[i].bidId].bidPrice;
                // Transfer the bid price to the StakerRewards contract
                escrow.releaseFunds(bidPrice);
                // Remove the winning node operator bid from the dv4 sub-auction tree
                _dv4AuctionTree.remove(_nodesToRemove[i].bidId, _bidDetails[_nodesToRemove[i].bidId].auctionScore);
                // Update the bids number of the node op in dv4 sub-auction
                _nodeOpsDetails[nodeOpAddr].numBidsCluster4 -= 1;
                // Update the number of node ops in dv4 sub-auction if necessary
                if (_nodeOpsDetails[nodeOpAddr].numBidsCluster4 == 0) dv4AuctionNumNodeOps -= 1;

                emit WinnerJoinedCluster(nodeOpAddr, _winningClusterId, _nodesToRemove[i].bidId);

                unchecked {
                    ++i;
                }
            }
            
            // If enough operators in dv4 sub-auction, update main tree
            if (dv4AuctionNumNodeOps >= _CLUSTER_SIZE_4) _dv4UpdateMainAuction();
        } else {
            revert InvalidAuctionType();
        }

    }

    /// @notice Update the main auction tree by adding a new virtual cluster and removing the old one
    function _updateMainAuctionTree(bytes32 _newClusterId, uint256 _newAvgAuctionScore, AuctionType _auctionType) private {
        if (_auctionType == AuctionType.JOIN_CLUSTER_4 && _dv4LatestWinningInfo.latestWinningClusterId != bytes32(0)) {
            uint256 lastAverageAuctionScore = _clusterDetails[_dv4LatestWinningInfo.latestWinningClusterId].averageAuctionScore;
            _mainAuctionTree.remove(_dv4LatestWinningInfo.latestWinningClusterId, lastAverageAuctionScore);
            delete _clusterDetails[_dv4LatestWinningInfo.latestWinningClusterId];
        }
        _mainAuctionTree.insert(_newClusterId, _newAvgAuctionScore);
    }

    /// @notice Create a new entry in the `_clusterDetails` mapping
    function _createClusterDetails(bytes32 _clusterId, uint256 _averageAuctionScore, NodeDetails[] memory _nodes) private {
        _clusterDetails[_clusterId].averageAuctionScore = _averageAuctionScore;
        for (uint256 i = 0; i < _nodes.length;) {
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

    /// @notice Create the split parameters depending on the winning nodes
    function _createSplitParams(NodeDetails[] memory _nodes) internal view returns (SplitV2Lib.Split memory) {

        address[] memory recipients = new address[](_nodes.length);
        uint256[] memory allocations = new uint256[](_nodes.length);

        // Retrieve the addresses of all the _nodes and create the Split allocation
        for (uint256 i = 0; i < _nodes.length;) {
            recipients[i] = _bidDetails[_nodes[i].bidId].nodeOp;
            allocations[i] = NODE_OP_SPLIT_ALLOCATION;
            unchecked {
                ++i;
            }
        }

        return SplitV2Lib.Split({
            recipients: recipients,
            allocations: allocations,
            totalAllocation: SPLIT_TOTAL_ALLOCATION,
            distributionIncentive: SPLIT_DISTRIBUTION_INCENTIVE
        });

    }

    /* ===================== MODIFIERS ===================== */

    modifier onlyStratVaultETH() {
        if (!strategyVaultManager.isStratVaultETH(msg.sender)) revert OnlyStratVaultETH();
        _;
    }

    modifier onlyStakerRewards() {
        if (msg.sender != address(stakerRewards)) revert OnlyStakerRewards();
        _;
    }
}
