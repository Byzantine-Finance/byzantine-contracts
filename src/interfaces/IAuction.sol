// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IStrategyModule.sol";

interface IAuction {

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
     * It finds the `_clusterSize` node operators with the highest auction scores and put them in a DV.
     * @param _stratModNeedingDV: the strategy module asking for a DV.
     * @dev The status of the winners is updated to `inDV`.
     * @dev Reverts if not enough node operators are available.
     */
    function createDV(
        IStrategyModule _stratModNeedingDV
    ) 
        external;

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
    ) 
        external view returns (uint256);

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
    ) 
        external payable;

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
    ) 
        external view returns (uint256);

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
    ) 
        external payable;

    /**
     * @notice Allow a node operator to abandon the auction and withdraw the bid he paid.
     * It's not possible to withdraw if the node operator is actively validating.
     * @dev Status is set to inactive and auction details to 0 unless the reputation which is unmodified
     */
    function withdrawBid() external;

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
    )
        external;

    /**
     * @notice Update the cluster size (i.e the number of node operators in a DV)
     * @param __clusterSize: the new cluster size
     */
    function updateClusterSize(uint256 __clusterSize) external;

    /**
     * @notice Return true if the `_nodeOpAddr` is whitelisted, false otherwise.
     * @param _nodeOpAddr: operator address you want to know if whitelisted
     */
    function isWhitelisted(address _nodeOpAddr) external view returns (bool);

    /**
     * @notice Returns the auction details of a node operator
     * @param _nodeOpAddr The node operator address to get the details
     * @return (vcNumber, bidPrice, auctionScore, reputationScore, nodeStatus)
     */
    function getNodeOpDetails(
        address _nodeOpAddr
    ) 
        external view returns (uint256, uint256, uint256, uint256, NodeOpStatus);


    /**
     * @notice Returns the node operator who have the `_auctionScore`
     * @param _auctionScore The auction score to get the node operator
     */
    function getAuctionScoreToNodeOp(
        uint256 _auctionScore
    ) 
        external view returns (address);

    /**
     * @notice Returns the auction configuration values.
     * @dev Function callable only by the owner.
     * @return (_expectedDailyReturnWei, _maxDiscountRate, _minDuration, _clusterSize)
     */
    function getAuctionConfigValues() external view returns (uint256, uint256, uint256, uint256);

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

    /// @dev Returned when a node operator is already in auction and therefore not allowed to bid again
    error AlreadyInAuction();

    /// @dev Returned when a node operator is not in auction and therefore cannot update its bid
    error NotInAuction();

    /// @dev Error when two node operators have the same auction score
    error BidAlreadyExists();

    /// @dev Returned when bidder didn't pay its entire bid
    error NotEnoughEtherSent();

    /// @dev Returned when trying to create a DV but not enough node operators are in auction
    error NotEnoughNodeOps();

    /// @dev Returned when the deposit to the Escrow contract failed
    error EscrowTransferFailed();
}