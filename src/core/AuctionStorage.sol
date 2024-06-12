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

    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice StrategyModuleManager contract
    IStrategyModuleManager public immutable strategyModuleManager;

    /* ===================== STATE VARIABLES ===================== */

    /// @notice Auction scores stored in a Red-Black tree (complexity O(log 2n))
    HitchensOrderStatisticsTreeLib.Tree internal _auctionTree;

    /// @notice Daily rewards of Ethereum Pos (in WEI)
    uint256 internal _expectedDailyReturnWei;
    /// @notice Minimum duration to be part of a DV (in days)
    uint168 internal _minDuration;
    /// @notice Number of node operators in auction and seeking for a DV
    uint64 public numNodeOpsInAuction;    
    /// @notice Maximum discount rate (i.e the max profit margin of node op) in percentage (from 0 to 10000 -> 100%)
    uint16 internal _maxDiscountRate;
    /// @notice Number of nodes in a Distributed Validator
    uint8 internal _clusterSize;

    /// @notice Node operator address => node operator auction details
    mapping(address => AuctionDetails) internal _nodeOpsInfo;

    /// @notice Mapping for the whitelisted node operators
    mapping(address => bool) internal _nodeOpsWhitelist;  
    

    /* ================= CONSTRUCTOR ================= */ 

    constructor(
        IEscrow _escrow,
        IStrategyModuleManager _strategyModuleManager
    ) {
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