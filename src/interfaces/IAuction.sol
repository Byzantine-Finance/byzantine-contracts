// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IStrategyModule.sol";

interface IAuction {

    /* ===================== ENUMS ===================== */

    /// @notice Defines the types of auctions available
    enum AuctionType {
        JOIN_CLUSTER_4,
        JOIN_CLUSTER_7,
        ALREADY_EXISTING_CLUSTER
    }

    /* ===================== STRUCTS ===================== */

    /// @notice Stores the details of a specific bid
    struct BidDetails {
        // Necessary to remove the bids from the BSTs
        uint256 auctionScore;
        // Price paid (excluding the bond)
        uint256 bidPrice;
        // Address of the node operator who placed the bid
        address nodeOp;
        // Number of VCs the node operator wishes to buy
        uint32 vcNumbers;
        // Discount rate of the bid
        uint16 discountRate;
        // Auction type to know if we must update a sub-auction tree
        AuctionType auctionType;
    }

    /// @notice Stores the node operators global auction's details
    struct NodeOpGlobalDetails {
        // Current reputation score of the node operator
        uint32 reputationScore;
        // Number of bonds paid by the node operator
        uint16 numBonds;
        // Number of pending bids in the DV4 sub-auction
        uint8 numBidsCluster4;
        // Number of pending bids in the DV7 sub-auction
        uint8 numBidsCluster7;
        // Whether the node operator is whitelisted
        bool isWhitelisted;
    }

    /// @notice Stores the threshold above which a virtual cluster changes plus the id of the lastest winning cluster 
    struct LatestWinningInfo {
        // The auction score of the latest winning node operator of its sub-auction.
        // If a new bidder exceeds that score, the last winning node operator will be kicked off from the virtual cluster in favor of the new bidder.
        uint256 lastestWinningScore;
        // The cluster ID of the current winning virtual cluster
        bytes32 latestWinningClusterId;
    }

    /// @notice Stores the nodes details of a Distributed Validator
    struct ClusterDetails {
        uint256 averageAuctionScore;
        NodeDetails[] nodes;
    }

    /// @notice Stores a node operator DV details
    /// @dev Only store the latest won bidId and a potential new pending bidId as the bids stores all the necessary details
    /// @dev When rebuying VCs, take the discount rate of the latest won bid
    struct NodeDetails {
        // Bid Id which allows the node op to join that DV
        bytes32 latestWonBidId;
        // Bid id of the node to add additional validators in its DV 
        bytes32 pendingBidId;
    }

    /* ===================== EVENTS ===================== */

    event BidPlaced(
        address indexed nodeOpAddr,
        uint32 reputationScore,
        uint16 discountRate,
        uint32 duration,
        uint256 bidPrice,
        uint256 auctionScore
    );
    
    event BidUpdated(
        address indexed nodeOpAddr,
        uint32 reputationScore,
        uint256 oldAuctionScore,
        uint32 newDuration,
        uint16 newDiscountRate,
        uint256 newBidPrice,
        uint256 newAuctionScore
    );

    event BidWithdrawn(address indexed nodeOpAddr, uint256 auctionScore); 

    event WinnerJoinedDV(address indexed nodeOpAddr, uint256 auctionScore);

    /* ====================== GETTERS ====================== */

    /// @notice Returns the daily rewards of Ethereum PoS (in WEI)
    /// @dev Used for the Validation Credit's price calculation
    function expectedDailyReturnWei() external view returns (uint256);

    /// @notice Returns the minimum duration to be part of a DV (in days)
    function minDuration() external view returns (uint32);

    /// @notice Returns the maximum discount rate (i.e the max profit margin of node op) in percentage (0 to 10_000 -> 100%)
    function maxDiscountRate() external view returns (uint16);

    /* ===================== VIEW FUNCTIONS ===================== */

    /// @notice Returns true if `_nodeOpAddr` is whitelisted, false otherwise.
    function isWhitelisted(address _nodeOpAddr) external view returns (bool);

    /// @notice Returns the number of DVs in the main auction
    function getNumDVInAuction() external view returns (uint256);

    /**
     * @notice Returns the details of a specific bid
     * @param _bidId The unique identifier of the bid
     * @return BidDetails struct containing the bid details
     */
    function getBidDetails(bytes32 _bidId) external view returns (BidDetails memory);

    /**
     * @notice Returns the details of a specific cluster
     * @param _clusterId The unique identifier of the cluster
     * @return ClusterDetails struct containing the cluster details
     */
    function getClusterDetails(bytes32 _clusterId) external view returns (ClusterDetails memory);

    /**
     * @notice Returns the id of the cluster with the highest average auction score
     * @dev Returns 0 if main tree is empty
     */
    function getWinningCluster() external view returns (bytes32, uint256);

    /* ===================== EXTERNAL FUNCTIONS ===================== */

    /**
     * @notice Function triggered by the StrategyModuleManager every time a staker deposit 32ETH and ask for a DV.
     * It allows the pre-creation of a new DV for the next staker.
     * It finds the `clusterSize` node operators with the highest auction scores and put them in a DV.
     * @dev Reverts if not enough node operators are available.
     */
    // function getAuctionWinners() external returns(IStrategyModule.Node[] memory);

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
    ) external view returns (uint256);

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
    ) external payable returns (bytes32);

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
    ) 
        external view returns (uint256);*/

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
    ) 
        external payable returns (uint256);*/

    /**
     * @notice Allow a node operator to withdraw a specific bid (through its auction score).
     * The withdrawer will be refund its bid price plus (the bond of he paid it).
     * @param _auctionScore: auction score of the bid to withdraw. Will withdraw the last bid with this score.
     */
    // function withdrawBid(uint256 _auctionScore) external;

    /* ===================== OWNER FUNCTIONS ===================== */

    /**
     * @notice Add node operators to the whitelist
     * @param _nodeOpAddrs: A dynamique array of the addresses to whitelist
     */
    function whitelistNodeOps(address[] calldata _nodeOpAddrs) external;

    /**
     * @notice Update the expected daily PoS rewards variable (in Wei)
     * @dev This function is callable only by the Auction contract's owner
     * @param _newExpectedDailyReturnWei: the new expected daily return of Ethereum staking (in wei)
     */
    function updateExpectedDailyReturnWei(uint256 _newExpectedDailyReturnWei) external;

    /**
     * @notice Update the minimum validation duration
     * @dev This function is callable only by the Auction contract's owner
     * @param _newMinDuration: the new minimum duration of being a validator in a DV (in days)
     */
    function updateMinDuration(uint32 _newMinDuration) external;

    /**
     * @notice Update the maximum discount rate
     * @dev This function is callable only by the Auction contract's owner
     * @param _newMaxDiscountRate: the new maximum discount rate (i.e the max profit margin of node op) (from 0 to 10000 -> 100%)
     */
    function updateMaxDiscountRate(uint16 _newMaxDiscountRate) external;

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

    /// @dev Returned when a bid refund failed
    error RefundFailed();
}