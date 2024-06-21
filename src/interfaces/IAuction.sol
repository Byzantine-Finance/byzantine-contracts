// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IStrategyModule.sol";

interface IAuction {

    /// @notice Stores auction details of node operators
    struct AuctionDetails {
        uint128 numBids;
        uint128 reputationScore;
        mapping(uint256 => uint256[]) auctionScoreToBidPrices;
        mapping(uint256 => uint256[]) auctionScoreToVcNumbers;
    }

    event BidPlaced(
        address indexed nodeOpAddr,
        uint256 reputationScore,
        uint256 discountRate,
        uint256 duration,
        uint256 bidPrice,
        uint256 auctionScore
    );
    
    event BidUpdated(
        address indexed nodeOpAddr,
        uint256 reputationScore,
        uint256 oldAuctionScore,
        uint256 newDuration,
        uint256 newDiscountRate,
        uint256 newBidPrice,
        uint256 newAuctionScore
    );

    event BidWithdrawn(address indexed nodeOpAddr, uint256 auctionScore); 

    event WinnerJoinedDV(address indexed nodeOpAddr, uint256 auctionScore);

    /// @notice Getter of the state variable `numNodeOpsInAuction`
    function numNodeOpsInAuction() external view returns (uint64);

    /// @notice Get the daily rewards of Ethereum Pos (in WEI)
    function expectedDailyReturnWei() external view returns (uint256);

    /// @notice Get the maximum discount rate (i.e the max profit margin of node op) in percentage (upscale 1e2)
    function maxDiscountRate() external view returns (uint16);

    /// @notice Get the minimum duration to be part of a DV (in days)
    function minDuration() external view returns (uint160);

    /// @notice Get the cluster size of a DV (i.e the number of nodes in a DV)
    function clusterSize() external view returns (uint8);

    /**
     * @notice Add a node operator to the the whitelist to not make him pay the bond.
     * @param _nodeOpAddr: the node operator to whitelist.
     * @dev Revert if the node operator is already whitelisted.
     */
    function addNodeOpToWhitelist(address _nodeOpAddr) external;

    /**
     * @notice Remove a node operator to the the whitelist.
     * @param _nodeOpAddr: the node operator to remove from whitelist.
     * @dev Revert if the node operator is not whitelisted.
     */
    function removeNodeOpFromWhitelist(address _nodeOpAddr) external;

    /**
     * @notice Function triggered by the StrategyModuleManager every time a staker deposit 32ETH and ask for a DV.
     * It allows the pre-creation of a new DV for the next staker.
     * It finds the `clusterSize` node operators with the highest auction scores and put them in a DV.
     * @dev Reverts if not enough node operators are available.
     */
    function getAuctionWinners() external returns(IStrategyModule.Node[] memory);

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
    ) 
        external view returns (uint256);

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
    ) 
        external payable returns (uint256[] memory);

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
    ) 
        external view returns (uint256);

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
    ) 
        external payable returns (uint256);

    /**
     * @notice Allow a node operator to withdraw a specific bid (through its auction score).
     * The withdrawer will be refund its bid price plus (the bond of he paid it).
     * @param _auctionScore: auction score of the bid to withdraw. Will withdraw the last bid with this score.
     */
    function withdrawBid(uint256 _auctionScore) external;

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
    )
        external;

    /**
     * @notice Update the cluster size (i.e the number of node operators in a DV)
     * @param _clusterSize: the new cluster size
     */
    function updateClusterSize(uint8 _clusterSize) external;

    /// @notice Return true if the `_nodeOpAddr` is whitelisted, false otherwise.
    function isWhitelisted(address _nodeOpAddr) external view returns (bool);

    /// @notice Return the pending bid number of the `_nodeOpAddr`.
    function getNodeOpBidNumber(address _nodeOpAddr) external view returns (uint256);

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
    ) 
        external view returns (uint256[] memory);

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
    )
        external view returns (uint256[] memory);

    /// @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
    error OnlyStrategyModuleManager();

    /// @dev Error when address already whitelisted
    error AlreadyWhitelisted();

    /// @dev Error when trying to remove from whitelist a non-whitelisted address
    error NotWhitelisted();

    /// @dev Returned when node operator's discount rate is too high compared to the Byzantine's max discount rate.
    error DiscountRateTooHigh();

    /// @dev Returned when node operator's duration is too short compared to the Byzantine's min duration.
    error DurationTooShort();

    /// @dev Returned when bidder didn't pay its entire bid
    error NotEnoughEtherSent();

    /// @dev Returned when the deposit to the Escrow contract failed
    error EscrowTransferFailed();
}