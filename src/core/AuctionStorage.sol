// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IAuction.sol";
import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IEscrow.sol";

import "../libraries/HitchensOrderStatisticsTreeLib.sol";

abstract contract AuctionStorage is IAuction {
    /* ================= CONSTANTS + IMMUTABLES ================= */

    uint256 internal constant _WAD = 1e18;
    uint256 internal constant _BOND = 1 ether;
    /// @notice Interval from which it is possible to trigger auctions and create DVs
    uint256 public immutable auctionCountdown;
    /// @notice Timestamp of the contract deployment
    uint256 internal immutable deploymentTimestamp;

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice StrategyModuleManager contract
    IStrategyModuleManager public immutable strategyModuleManager;

    /* ===================== STATE VARIABLES ===================== */

    /// @notice Auction scores stored in a Red-Black tree (complexity O(log 2n))
    HitchensOrderStatisticsTreeLib.Tree internal _auctionTree;

    /// @notice Daily rewards of Ethereum Pos (in WEI)
    uint256 public expectedDailyReturnWei;
    /// @notice Minimum duration to be part of a DV (in days)
    uint160 public minDuration;
    /// @notice Number of node operators in auction and seeking for a DV
    uint64 public numNodeOpsInAuction;    
    /// @notice Maximum discount rate (i.e the max profit margin of node op) in percentage
    uint16 public maxDiscountRate;
    /// @notice Number of nodes in a Distributed Validator
    uint8 public clusterSize;
    /// @notice Variable to avoid verifying bock.timestamp once countdown is finished
    bool public auctionCountdownFinished;

    /// @notice Node operator address => node operator auction details
    mapping(address => AuctionDetails) internal _nodeOpsInfo;

    /// @notice Mapping for the whitelisted node operators
    mapping(address => bool) internal _nodeOpsWhitelist;  
    

    /* ================= CONSTRUCTOR ================= */ 

    constructor(
        uint256 _auctionCountdown,
        IEscrow _escrow,
        IStrategyModuleManager _strategyModuleManager
    ) {
        auctionCountdown = _auctionCountdown;
        deploymentTimestamp = block.timestamp;
        escrow = _escrow;
        strategyModuleManager = _strategyModuleManager;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}