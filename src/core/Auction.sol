// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "ds-math/math.sol";

import "../libraries/HitchensOrderStatisticsTreeLib.sol";

import "./AuctionStorage.sol";

/// TODO: Calculation of the reputation score of node operators

contract Auction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AuctionStorage,
    DSMath
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
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        address _initialOwner,
        uint256 _expectedDailyReturnWei,
        uint16 _maxDiscountRate,
        uint160 _minDuration,
        uint8 _clusterSize
    ) external initializer {
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
        expectedDailyReturnWei = _expectedDailyReturnWei;
        maxDiscountRate = _maxDiscountRate;
        minDuration = _minDuration;
        clusterSize = _clusterSize;
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
     * It allows the pre-creation of a new DV for the next staker.
     * It finds the `clusterSize` node operators with the highest auction scores and put them in a DV.
     * @dev Reverts if not enough node operators are available.
     */
    function getAuctionWinners()
        external
        onlyStategyModuleManager
        nonReentrant
        returns(IStrategyModule.Node[] memory)
    {
        // Check if enough node ops in the auction to create a DV
        require(numNodeOpsInAuction >= clusterSize, "Not enough node ops in auction");
        
        // Returns the auction winners
        return _getAuctionWinners();
    }

    /**
     * @notice Fonction to determine the auction price for a validator according to its bids parameters
     * @param _nodeOpAddr: address of the node operator who wants to bid
     * @param _discountRates: array of discount rates (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timesInDays: array of duration of being a validator, in days
     * @dev Revert if the two entry arrays `_discountRates` and `_timesInDays` have different length
     * @dev Revert if `_discountRates` or `_timesInDays` don't respect the values set by the byzantine.
     */
    function getPriceToPay(
        address _nodeOpAddr,
        uint256[] calldata _discountRates,
        uint256[] calldata _timesInDays
    ) public view returns (uint256) {
        // Verify the two entry arrays have the same length
        require(_discountRates.length == _timesInDays.length, "_discountRates and _timesInDays must have the same length");

        uint256 dailyVcPrice;
        uint256 totalBidPrice;

        for (uint256 i = 0; i < _discountRates.length;) {
            // Verify the standing bid parameters
            if (_discountRates[i] > maxDiscountRate) revert DiscountRateTooHigh();
            if (_timesInDays[i] < minDuration) revert DurationTooShort();

            // Calculate operator's bid price and add it to the total price
            dailyVcPrice = _calculateDailyVcPrice(_discountRates[i]);
            totalBidPrice += _calculateBidPrice(_timesInDays[i], dailyVcPrice);

            unchecked {
                ++i;
            }
        }

        // Return the price to pay according to the whitelist
        if (isWhitelisted(_nodeOpAddr)) {
            return totalBidPrice;
        }
        return totalBidPrice + (_discountRates.length * _BOND);
    }

    /**
     * @notice Operators set their standing bid(s) parameters and pay their bid(s) to an escrow smart contract.
     * If a node op doesn't win the auction, its bids stays in the escrow contract for the next auction.
     * An node op who hasn't won an auction can ask the escrow contract to refund its bid(s) if he wants to leave the protocol.
     * If a node op wants to update its bid parameters, call `updateBid` function.
     * @notice Non-whitelisted operators will have to pay the 1ETH bond as well.
     * @param _discountRates: array of discount rates (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timesInDays: array of duration of being a validator, in days
     * @dev By calling this function, the node op insert data in the auction Binary Search Tree (sorted by auction score).
     * @dev Revert if `_discountRates` or `_timesInDays` don't respect the values set by the byzantine or if they don't have the same length.
     * @dev Revert if the ethers sent by the node op are not enough to pay for the bid(s) (and the bond).
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     * @dev If too many ethers has been sent the function give back the excess to the sender.
     * @return The array of each bid auction score.
     */
    function bid(
        uint256[] calldata _discountRates,
        uint256[] calldata _timesInDays
    ) external payable nonReentrant returns (uint256[] memory) {

        // Verify the two entry arrays have the same length
        require(_discountRates.length == _timesInDays.length, "_discountRates and _timesInDays must have the same length");

        // Update `numNodeOpsInAuction` if necessary
        if (_nodeOpsInfo[msg.sender].numBids == 0) {
            numNodeOpsInAuction += 1;
        }

        // Convert msg.sender address in bytes32
        bytes32 bidder = bytes32(uint256(uint160(msg.sender)));

        /// TODO: Get the reputation score of msg.sender
        uint128 reputationScore = 1;
        _nodeOpsInfo[msg.sender].reputationScore = reputationScore;

        uint256 dailyVcPrice;
        uint256 bidPrice;
        uint256 totalBidPrice;
        uint256[] memory auctionScores = new uint256[](_discountRates.length);

        // Iterate over the number of bids
        for (uint256 i = 0; i < _discountRates.length;) {
            // Verify the standing bid parameters
            if (_discountRates[i] > maxDiscountRate) revert DiscountRateTooHigh();
            if (_timesInDays[i] < minDuration) revert DurationTooShort();

            /// @notice Calculate operator's bid details
            dailyVcPrice = _calculateDailyVcPrice(_discountRates[i]);
            bidPrice = _calculateBidPrice(_timesInDays[i], dailyVcPrice);
            totalBidPrice += bidPrice;
            auctionScores[i] = _calculateAuctionScore(dailyVcPrice, _timesInDays[i], reputationScore);

            // Update auction tree if necessary
            if (!_auctionTree.keyExists(bidder, auctionScores[i])) {
                _auctionTree.insert(bidder, auctionScores[i]);
            }
            // Update node op auction details
            _nodeOpsInfo[msg.sender].numBids += 1;
            _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[auctionScores[i]].push(bidPrice);
            _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[auctionScores[i]].push(_timesInDays[i]);

            /// TODO: Emit event to associate an auction score to a bid price in the front

            unchecked {
                ++i;
            }
        }

        uint256 priceToPay;
        // If msg.sender is whitelisted, he only pays the totalBidPrice
        if (isWhitelisted(msg.sender)) {
            priceToPay = totalBidPrice;
        } else {
            priceToPay = totalBidPrice + (_discountRates.length * _BOND);
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

        return auctionScores;
    }

    /**
     * @notice Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decreases its bid.
     * @notice The bid which will be updated will be the last bid with `_auctionScore`
     * @param _nodeOpAddr: address of the node operator updating its bid
     * @param _auctionScore: auction score of the bid to update
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _timeInDays: duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_auctionScore`.
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function getUpdateOneBidPrice(
        address _nodeOpAddr,
        uint256 _auctionScore,
        uint256 _discountRate,
        uint256 _timeInDays
    ) public view returns (uint256) {
        // Verify if `_nodeOpAddr` has at least a bid with `_auctionScore`
        require (getNodeOpAuctionScoreBidPrices(_nodeOpAddr, _auctionScore).length > 0, "Wrong node op auctionScore");

        // Verify the standing bid parameters
        if (_discountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_timeInDays < minDuration) revert DurationTooShort();

        // Get the number of bids with this `_auctionScore`
        uint256 numSameBids = getNodeOpAuctionScoreBidPrices(_nodeOpAddr, _auctionScore).length;

        // Get what the node op has already paid
        uint256 lastBidPrice = _nodeOpsInfo[_nodeOpAddr].auctionScoreToBidPrices[_auctionScore][numSameBids - 1];

        // Calculate operator's new bid price
        uint256 newDailyVcPrice = _calculateDailyVcPrice(_discountRate);
        uint256 newBidPrice = _calculateBidPrice(_timeInDays, newDailyVcPrice);

        if (newBidPrice > lastBidPrice) {
            unchecked {
                return newBidPrice - lastBidPrice;
            }
        }
        return 0;
    }

    /**
     * @notice  Update a bid of a node operator associated to `_auctionScore`. The node op will have to pay more if he outbids. 
     *          If he decreases his bid, the escrow contract will send him back the difference.
     * @notice  The bid which will be updated will be the last bid with `_auctionScore`
     * @param _auctionScore: auction score of the bid to update
     * @param _newDiscountRate: new discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @param _newTimeInDays: new duration of being a validator, in days
     * @dev Reverts if the node op doesn't have a bid with `_auctionScore`.
     * @dev Reverts if the transfer of the funds to the Escrow contract failed.
     * @dev Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.
     */
    function updateOneBid(
        uint256 _auctionScore,
        uint256 _newDiscountRate,
        uint256 _newTimeInDays
    ) external payable nonReentrant returns (uint256){
        // Verify if the sender has at least a bid with `_auctionScore`
        require (getNodeOpAuctionScoreBidPrices(msg.sender, _auctionScore).length > 0, "Wrong node op auctionScore");

        // Verify the standing bid parameters
        if (_newDiscountRate > maxDiscountRate) revert DiscountRateTooHigh();
        if (_newTimeInDays < minDuration) revert DurationTooShort();

        // Convert msg.sender address in bytes32
        bytes32 bidder = bytes32(uint256(uint160(msg.sender)));

        // Get the number of bids with this `_auctionScore`
        uint256 numSameBids = getNodeOpAuctionScoreBidPrices(msg.sender, _auctionScore).length;

        // Get last bid price associated to `_auctionScore`. That bid will be updated
        uint256 lastBidPrice = _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore][numSameBids - 1];

        // Update auction tree (if necessary) and node ops details mappings
        if (numSameBids == 1) {
            _auctionTree.remove(bidder, _auctionScore);
            delete _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore];
            delete _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_auctionScore];
        } else {
            _nodeOpsInfo[msg.sender].auctionScoreToBidPrices[_auctionScore].pop();
            _nodeOpsInfo[msg.sender].auctionScoreToVcNumbers[_auctionScore].pop();
        }

        /// TODO: Get the reputation score of msg.sender
        uint128 reputationScore = 1;

        /// @notice Calculate operator's new bid price and new auction score
        uint256 newDailyVcPrice = _calculateDailyVcPrice(_newDiscountRate);
        uint256 newBidPrice = _calculateBidPrice(_newTimeInDays, newDailyVcPrice);
        uint256 newAuctionScore = _calculateAuctionScore(newDailyVcPrice, _newTimeInDays, reputationScore);

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

        return newAuctionScore;

    }

    /**
     * @notice Allow a node operator to withdraw a specific bid (through its auction score).
     * The withdrawer will be refund its bid price plus (the bond of he paid it).
     * @param _auctionScore: auction score of the bid to withdraw. Will withdraw the last bid with this score.
     */
    function withdrawBid(uint256 _auctionScore) external {
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
        
    }

    /**
     * @notice Update the auction configuration except cluster size
     * @param _expectedDailyReturnWei: the new expected daily return of Ethereum staking (in wei)
     * @param _maxDiscountRate: the new maximum discount rate (i.e the max profit margin of node op) (from 0 to 10000 -> 100%)
     * @param _minDuration: the new minimum duration of beeing a validator in a DV (in days)
     */
    function updateAuctionConfig(
        uint256 _expectedDailyReturnWei,
        uint16 _maxDiscountRate,
        uint160 _minDuration
    ) external onlyOwner {
        expectedDailyReturnWei = _expectedDailyReturnWei;
        maxDiscountRate = _maxDiscountRate;
        minDuration = _minDuration;
    }

    /**
     * @notice Update the cluster size (i.e the number of node operators in a DV)
     * @param _clusterSize: the new cluster size
     */
    function updateClusterSize(uint8 _clusterSize) external onlyOwner {
        require(_clusterSize >= 4, "Cluster size must be at least 4.");
        clusterSize = _clusterSize;
    }

    /* ===================== GETTER FUNCTIONS ===================== */

    
    /// @notice Return true if the `_nodeOpAddr` is whitelisted, false otherwise.
    function isWhitelisted(address _nodeOpAddr) public view returns (bool) {
        return _nodeOpsWhitelist[_nodeOpAddr];
    }

    
    /// @notice Return the pending bid number of the `_nodeOpAddr`.
    function getNodeOpBidNumber(address _nodeOpAddr) public view returns (uint256) {
        return _nodeOpsInfo[_nodeOpAddr].numBids;
    }

    /**
     * @notice Return the pending bid(s) price of the `_nodeOpAddr` corresponding to `_auctionScore`.
     * @param _auctionScore The auction score of the node operator you want to get the corresponding bid(s) price.
     * @return (uint256[] memory) An array of all the bid price for that specific auctionScore
     * @dev If `_nodeOpAddr` doesn't have `_auctionScore` in his mapping, return an empty array.
     * @dev A same `_auctionScore` can have different bid prices depending on the reputationScore variations.
     */
    function getNodeOpAuctionScoreBidPrices(
        address _nodeOpAddr,
        uint256 _auctionScore
    ) public view returns (uint256[] memory) {
        return _nodeOpsInfo[_nodeOpAddr].auctionScoreToBidPrices[_auctionScore];
    }

    /**
     * @notice Return the pending VCs number of the `_nodeOpAddr` corresponding to `_auctionScore`.
     * @param _auctionScore The auction score of the node operator you want to get the corresponding VCs numbers.
     * @return (uint256[] memory) An array of all the VC numbers for that specific auctionScore
     * @dev If `_nodeOpAddr` doesn't have `_auctionScore` in his mapping, return an empty array.
     * @dev A same `_auctionScore` can have different VCs numbers depending on the reputationScore variations.
     */
    function getNodeOpAuctionScoreVcs(
        address _nodeOpAddr,
        uint256 _auctionScore
    ) public view returns (uint256[] memory) {
        return _nodeOpsInfo[_nodeOpAddr].auctionScoreToVcNumbers[_auctionScore];
    }

    /* ===================== INTERNAL FUNCTIONS ===================== */

    /**
     * @notice Calculate and returns the daily Validation Credit price (in WEI)
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to 10000)
     * @dev vc_price = Re*(1 - D)/cluster_size
     * @dev The `expectedDailyReturnWei` is set by Byzantine and corresponds to the Ethereum daily staking return.
     */
    function _calculateDailyVcPrice(uint256 _discountRate) internal view returns (uint256) {
        return (expectedDailyReturnWei * (10000 - _discountRate)) / (clusterSize * 10000);
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
     * @notice Function to get the auction winners. It returns the node operators addresses with the highest auction score.
     * @dev We assume the winners directly accept to join the DV, therefore this function cleans the auction tree and releases the bid price locked in the escrow.
     * @dev A same Eth address can not figure more than one time a same cluster.  
     */
    function _getAuctionWinners() internal returns (IStrategyModule.Node[] memory) {

        // Create the Node structure array for the Strategy Module
        IStrategyModule.Node[] memory auctionWinners = new IStrategyModule.Node[](clusterSize);

        // Create the best auctionScores array
        uint256[] memory bestAuctionScores = new uint256[](clusterSize);

        // Variables usefull for the algorithm
        uint256 i;
        uint256 count;
        bytes32 winnerKey;
        address winnerAddr;
        bool winnerExists;
        uint256 numSameBids;

        /* ===================== BEST AUCTION SCORE WINNER(S) ===================== */

        // Get the `clusterSize` biggest AuctionScores (can be 0 if not enough different auction scores)
        bestAuctionScores[0] = _auctionTree.last();
        for (i = 1; i < clusterSize;) {
            bestAuctionScores[i] = _auctionTree.prev(bestAuctionScores[i - 1]);
            unchecked {
                ++i;
            }
        }

        for (i = 0; i < clusterSize;) {
            // Get all the node ops with this auctionScore
            (,,,,uint256 _keyCount,) = _auctionTree.getNode(bestAuctionScores[i]);

            uint256 l; // To find the index of the key to select
            // Loop through all the node ops with this auctionScore
            for (uint256 j = 0; j < _keyCount;) {
                winnerKey = _auctionTree.valueKeyAtIndex(bestAuctionScores[i], l);
                winnerAddr = address(uint160(uint256(winnerKey)));
                numSameBids = _nodeOpsInfo[winnerAddr].auctionScoreToBidPrices[bestAuctionScores[i]].length;

                // Verify if the `winnerAddr` isn't already in the array
                winnerExists = false;
                for (uint256 k = 0; k < count;) {
                    if (auctionWinners[k].eth1Addr == winnerAddr) {
                        winnerExists = true;
                        break;
                    }
                    unchecked {
                        ++k;
                    }
                }

                if (!winnerExists) {
                    // Unlock the winner's bid price from the escrow
                    escrow.releaseFunds(_nodeOpsInfo[winnerAddr].auctionScoreToBidPrices[bestAuctionScores[i]][numSameBids - 1]);

                    // Create Node structure for the Strategy Module
                    auctionWinners[count] = IStrategyModule.Node(
                        _nodeOpsInfo[winnerAddr].auctionScoreToVcNumbers[bestAuctionScores[i]][numSameBids - 1], // Validation Credits number associated to the auction score
                        _nodeOpsInfo[winnerAddr].reputationScore, // Reputation score of the node
                        winnerAddr // Winner address
                    );
                    ++count;

                    // Update auction tree (if necessary) and node ops details mappings
                    if (numSameBids == 1) {
                        _auctionTree.remove(winnerKey, bestAuctionScores[i]);
                        delete _nodeOpsInfo[winnerAddr].auctionScoreToBidPrices[bestAuctionScores[i]];
                        delete _nodeOpsInfo[winnerAddr].auctionScoreToVcNumbers[bestAuctionScores[i]];
                    } else {
                        _nodeOpsInfo[winnerAddr].auctionScoreToBidPrices[bestAuctionScores[i]].pop();
                        _nodeOpsInfo[winnerAddr].auctionScoreToVcNumbers[bestAuctionScores[i]].pop();
                        ++l;
                    }
                    _nodeOpsInfo[winnerAddr].numBids -= 1;

                    // Decrease the number of node ops in the auction if the winner has no more bids
                    if (_nodeOpsInfo[winnerAddr].numBids == 0) --numNodeOpsInAuction;

                    // End function if enough winners
                    if (count == clusterSize) return auctionWinners;
                }

                unchecked {
                    ++j;
                }
            }
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
