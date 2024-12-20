// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PushSplitFactory} from "splits-v2/splitters/push/PushSplitFactory.sol";

import { IAuction } from "../interfaces/IAuction.sol";
import { IStrategyVaultManager } from "../interfaces/IStrategyVaultManager.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";
import { IStakerRewards } from "../interfaces/IStakerRewards.sol";

import {HitchensOrderStatisticsTreeLib } from "../libraries/HitchensOrderStatisticsTreeLib.sol";

abstract contract AuctionStorage is IAuction {
    /* ================= CONSTANTS + IMMUTABLES ================= */

    /// @notice The split operators allocation
    uint256 public constant NODE_OP_SPLIT_ALLOCATION = 250_000; // 25%

    /// @notice The split total allocation
    uint256 public constant SPLIT_TOTAL_ALLOCATION = 1_000_000; // 100% is 1_000_000

    /// @notice Bond to pay for the non whitelisted node operators
    uint256 internal constant _BOND = 1 ether;

    /// @notice The split distribution incentive
    uint16 public constant SPLIT_DISTRIBUTION_INCENTIVE = 20_000; // 2% for the distributor

    /// @notice Number of nodes in a Distributed Validator
    uint8 internal constant _CLUSTER_SIZE_4 = 4;
    uint8 internal constant _CLUSTER_SIZE_7 = 7;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice StrategyVaultManager contract
    IStrategyVaultManager public immutable strategyVaultManager;

    /// @notice 0xSplits' PushSplitFactory contract
    PushSplitFactory public immutable pushSplitFactory;

    /// @notice StakerRewards contract
    IStakerRewards public immutable stakerRewards;

    /* ===================== STATE VARIABLES ===================== */

    /// @notice Red-Black tree to store the main auction scores (auction gathering DV4, DV7 and already created DVs)
    HitchensOrderStatisticsTreeLib.Tree internal _mainAuctionTree;

    /// @notice Red-Black tree to store the sub-auction scores (DV4)
    HitchensOrderStatisticsTreeLib.Tree internal _dv4AuctionTree;
    /// @notice Latest winning info of the dv4 sub-auction
    LatestWinningInfo internal _dv4LatestWinningInfo;

    /// @notice Red-Black tree to store the sub-auction non-winning scores (DV7)
    HitchensOrderStatisticsTreeLib.Tree internal _dv7AuctionTree;
    /// @notice Latest winning info of the dv7 sub-auction
    LatestWinningInfo internal _dv7LatestWinningInfo;

    /// @notice Daily rewards of Ethereum Pos (in WEI)
    uint256 public expectedDailyReturnWei;
    /// @notice Minimum duration to be part of a DV (in days)
    uint32 public minDuration;
    /// @notice Number of node operators in the DV4 sub-auction
    uint16 public dv4AuctionNumNodeOps;
    /// @notice Number of node operators in the DV7 sub-auction
    uint16 public dv7AuctionNumNodeOps;
    /// @notice Maximum discount rate (i.e the max profit margin of node op) in percentage
    uint16 public maxDiscountRate;

    /// @notice Node operator address => node operator global details
    mapping(address => NodeOpGlobalDetails) internal _nodeOpsDetails;

    /// @notice Bid id => bid details
    mapping(bytes32 => BidDetails) internal _bidDetails;

    /// @notice Cluster ID => cluster details
    mapping(bytes32 => ClusterDetails) internal _clusterDetails;

    /* ================= CONSTRUCTOR ================= */ 

    constructor(
        IEscrow _escrow,
        IStrategyVaultManager _strategyVaultManager,
        PushSplitFactory _pushSplitFactory,
        IStakerRewards _stakerRewards
    ) {
        escrow = _escrow;
        strategyVaultManager = _strategyVaultManager;
        pushSplitFactory = _pushSplitFactory;
        stakerRewards = _stakerRewards;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}