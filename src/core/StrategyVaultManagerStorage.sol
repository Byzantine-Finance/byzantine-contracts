// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../interfaces/IStrategyVaultManager.sol";
import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "splits-v2/splitters/push/PushSplitFactory.sol";

abstract contract StrategyVaultManagerStorage is IStrategyVaultManager {
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice The split operators allocation
    uint256 public constant NODE_OP_SPLIT_ALLOCATION = 250_000; // 25%

    /// @notice The split distribution incentive
    uint16 public constant SPLIT_DISTRIBUTION_INCENTIVE = 20_000; // 2% for the distributor

    /// @notice The split total allocation
    uint256 public constant SPLIT_TOTAL_ALLOCATION = 1_000_000; // 100% is 1_000_000

    /// @notice Beacon proxy to which the StrategyVaults point
    IBeacon public immutable stratVaultBeacon;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Auction contract
    IAuction public immutable auction;

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /// @notice 0xSplits' PushSplitFactory contract
    PushSplitFactory public immutable pushSplitFactory;

    /* ============== STATE VARIABLES ============== */

    /// @notice Staker to its owned StrategyVaults
    mapping(address => address[]) public stakerToStratVaults;

    /// @notice ByzNft tokenId to its tied StrategyVault
    mapping(uint256 => address) public nftIdToStratVault;

    /// @notice Mapping to store the pre-created clusters waiting for work
    mapping(uint64 => PendingClusterDetails) public pendingClusters;

    /// @notice The number of pre-created clusters. Used as the mapping index.
    uint64 public numPreCreatedClusters;

    /// @notice The number of StratVaults that have been deployed
    uint64 public numStratVaults; // This is also the number of ByzNft minted

    /* ================= CONSTRUCTOR ================= */ 

    constructor(
        IBeacon _stratVaultBeacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager,
        PushSplitFactory _pushSplitFactory
    ) {
        stratVaultBeacon = _stratVaultBeacon;
        auction = _auction;
        byzNft = _byzNft;
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
        pushSplitFactory = _pushSplitFactory;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;

}