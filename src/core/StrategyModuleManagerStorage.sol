// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "../interfaces/IStakerRewards.sol";
import "splits-v2/splitters/push/PushSplitFactory.sol";

abstract contract StrategyModuleManagerStorage is IStrategyModuleManager {
    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice Beacon proxy to which the StrategyModules point
    IBeacon public immutable stratModBeacon;

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice Auction contract
    IAuction public immutable auction;

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /// @notice StakerReward contract
    IStakerRewards public immutable stakerRewards;

    /// @notice 0xSplits' PushSplitFactory contract
    PushSplitFactory public immutable pushSplitFactory;

    /* ============== STATE VARIABLES ============== */

    /// @notice Staker to its owned StrategyModules
    mapping(address => address[]) public stakerToStratMods;

    /// @notice ByzNft tokenId to its tied StrategyModule
    mapping(uint256 => address) public nftIdToStratMod;

    /// @notice Mapping to store the pre-created clusters waiting for work
    mapping(uint64 => IStrategyModule.ClusterDetails) public pendingClusters;

    /// @notice The number of pre-created clusters. Used as the mapping index.
    uint64 public numPreCreatedClusters;

    /// @notice The number of StratMods that have been deployed
    uint64 public numStratMods; // This is also the number of ByzNft minted

    /* ================= CONSTRUCTOR ================= */

    constructor(
        IBeacon _stratModBeacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager,
        IStakerRewards _stakerRewards,
        PushSplitFactory _pushSplitFactory
    ) {
        stratModBeacon = _stratModBeacon;
        auction = _auction;
        byzNft = _byzNft;
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
        stakerRewards = _stakerRewards;
        pushSplitFactory = _pushSplitFactory;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts
     */
    uint256[44] private __gap;
}
