// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";
import "eigenlayer-contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/libraries/BeaconChainProofs.sol";
import { SplitV2Lib } from "splits-v2/libraries/SplitV2.sol";
import "./utils/ProofParsing.sol";
import "./ByzantineDeployer.t.sol";

import "../src/interfaces/IStrategyVaultERC20.sol";
import "../src/interfaces/IStrategyVaultETH.sol";
import "../src/interfaces/IStrategyVaultManager.sol";
import "../src/interfaces/IAuction.sol";
import "../src/core/StrategyVaultETH.sol";
import "../src/interfaces/IStakerRewards.sol";

import {console} from "forge-std/console.sol";

contract StakerRewardsTest is ProofParsing, ByzantineDeployer {
    /// @notice Initial balance of all the node operators
    uint256 internal constant STARTING_BALANCE = 500 ether;

    /// @notice Array of all the bid ids
    bytes32[] internal bidId;

    /// @notice Random validator deposit data (simulates a Byzantine DV)
    bytes private pubkey;
    bytes private signature;
    bytes32 private depositDataRoot;

    /// @notice Forwarder address to call performUpkeep
    address forwarder = makeAddr("forwarder");

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

        // Set forwarder address
        vm.prank(address(strategyVaultManager));
        stakerRewards.setForwarderAddress(forwarder);

        // Fill the node operators' balance
        for (uint256 i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // whitelist all the node operators
        auction.whitelistNodeOps(nodeOps);

        // Fill protagonists' balance
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // 6 nodeOps bid, 11 bids in total, be able to create 4 DVs
        // Cluster 1 VCs: 200, 200, 150, 150 = 700
        // Cluster 2 VCs: 200, 200, 149, 149 = 698
        // Cluster 3 VCs: 148, 100, 50, 45 = 343
        bidId = _createMultipleBids();

        // Get deposit data of a random validator
        _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
    }

    function test_dvCreationCheckpoint_withoutActiveValidators() public startAtPresentDay {     
        // ACT
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);

        /* ====================== Only DV creation, no active validators ====================== */

        // ASSERT
        // Check if the global variables are correct
        assertEq(stratVaultETH.getVaultDVNumber(), 3);
        assertEq(stakerRewards.getCheckpointData().totalVCs, 1741);
        assertEq(stakerRewards.numClusters4(), 3);
        assertEq(stakerRewards.numClusters7(), 0);
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);
        assertEq(stakerRewards.numValidators4(), 0);
        assertEq(stakerRewards.numValidators7(), 0);

        // Check if cluster 1 data is correct
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        assertEq(stakerRewards.getClusterData(clusterIds[0]).activeTime, 0);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).smallestVC, 150);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).exitTimestamp, 0);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).clusterSize, 4);
        // Check if cluster 3 data is correct
        assertEq(stakerRewards.getClusterData(clusterIds[2]).activeTime, 0);
        assertEq(stakerRewards.getClusterData(clusterIds[2]).smallestVC, 45);
        assertEq(stakerRewards.getClusterData(clusterIds[2]).exitTimestamp, 0);
    
        // Check if the total bids of the 3 clusters are sent to the SR contract
        bytes32[] memory clusterIdsCopy = stratVaultETH.getAllDVIds();
        uint256 totalBids = 0;
        for (uint8 i = 0; i < stakerRewards.getClusterData(clusterIds[0]).clusterSize; i++) {
            for (uint8 j = 0; j < clusterIdsCopy.length; j++) {
                bytes32 id = auction.getClusterDetails(clusterIdsCopy[j]).nodes[i].bidId;
                IAuction.BidDetails memory bidDetails = auction.getBidDetails(id);
                totalBids += bidDetails.bidPrice;
            }
        }
        assertEq(address(stakerRewards).balance, totalBids);
        assertEq(stakerRewards.getAllocatableRewards(), address(stakerRewards).balance);

        // Check if the checkpoint is updated
        uint256 dvCreationTimeCopy = block.timestamp;
        assertEq(stakerRewards.getCheckpointData().updateTime, dvCreationTimeCopy);
        uint256 consumedVCsPerDayPerValidator = (stakerRewards.numClusters4() * 4 + stakerRewards.numClusters7() * 7) * 1e18 / (stakerRewards.numClusters4() + stakerRewards.numClusters7());
        console.log("consumedVCsPerDayPerValidator: %s", consumedVCsPerDayPerValidator); // 40000000000000000000
        uint256 dailyRewardsPer32ETH = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * consumedVCsPerDayPerValidator / 1e18;
        console.log("dailyRewardsPer32ETH: %18e", dailyRewardsPer32ETH); // 3060123846317260 = 0,00306012384631726 ETH
        assertEq(stakerRewards.getCheckpointData().dailyRewardsPer32ETH, dailyRewardsPer32ETH);
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);        
    }

    function test_dvCreationCheckpoint_withActiveValidators() public startAtPresentDay {

        /* ====================== 2 validators active while DV creation ====================== */
        // Check if (numValidators4 + numValidators7 > 0 && _hasTimeElapsed(checkpoint.updateTime, _ONE_DAY)) condition

        // ARRANGE
        IStrategyVaultETH stratVaultETH1 = _createStratVaultETHAndStake(alice, 64 ether); // 2 clusters
        bytes32[] memory clusterIdsStratVault1 = stratVaultETH1.getAllDVIds();

        // 1 days later
        vm.warp(block.timestamp + 1 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH1.activateCluster(pubkey, signature, depositDataRoot, clusterIdsStratVault1[0]); // 1 validator
        vm.prank(beaconChainAdmin);
        stratVaultETH1.activateCluster(pubkey, signature, depositDataRoot, clusterIdsStratVault1[1]); // 1 validator
        uint256 totalVCsBeforeNewDVCreation = stakerRewards.getCheckpointData().totalVCs;
        uint256 updateTime = stakerRewards.getCheckpointData().updateTime;
        uint256 rewardsPer32ETH = stakerRewards.getCheckpointData().dailyRewardsPer32ETH;

        // ACT 
        // 1 days later
        vm.warp(block.timestamp + 1 days);
        IStrategyVaultETH stratVaultETH2 = _createStratVaultETHAndStake(bob, 32 ether); // 1 cluster
        bytes32[] memory clusterIdsStratVault2 = stratVaultETH2.getAllDVIds();

        // ASSERT
        assertEq(stakerRewards.numClusters4(), 3);
        assertEq(stakerRewards.numValidators4(), 2);
        // Check if number of consumed VCs has been correctly removed from totalVCs
        uint256 cluster3TotalVCs = 0;
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(clusterIdsStratVault2[0]);
        for (uint256 i = 0; i < clusterDetails.nodes.length; i++) {
            IAuction.NodeDetails memory node = clusterDetails.nodes[i];
            cluster3TotalVCs += node.currentVCNumber;
        }
        uint256 consumedVCs = 1 * 4 * stakerRewards.numValidators4(); // 1 day * 4 VCs * numValidators4
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsBeforeNewDVCreation + cluster3TotalVCs - consumedVCs);
        // Check if the pending rewards have been distributed
        uint256 distributedRewards = rewardsPer32ETH * _getElapsedDays(updateTime) * stakerRewards.numValidators4();
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, distributedRewards);
        assertEq(stakerRewards.getAllocatableRewards(), address(stakerRewards).balance - distributedRewards);
    }

    function test_dvCreationCheckpoint_RevertWhen_calledByNonStratVaultETH() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();

        // ACT AND ASSERT
        vm.expectRevert(IStakerRewards.OnlyStratVaultETH.selector);
        stakerRewards.dvCreationCheckpoint(clusterIds[0]);
    }

    function test_dvActivationCheckpoint_oneVault() public startAtPresentDay {

        /* ====================== Activation of DV1 ====================== */

        // ARRANGE 
        // Deposit 96 ETH in total
        // Total VCs of 3 clusters: 1741
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether); // 3 clusters
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        uint256 initialBalanceCP1 = address(stakerRewards).balance;
        uint256 initialRewardsPer32ETHCP1 = stakerRewards.getCheckpointData().dailyRewardsPer32ETH;
        uint256 initialVCs = stakerRewards.getCheckpointData().totalVCs;

        // ACT
        // CP1: DV1 activation
        vm.warp(block.timestamp + 1 days);
        uint256 dvActivationTimeCP1 = block.timestamp;
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // ASSERT 
        // This is the first DV of the stratVaultETH: no rewards should be sent to stratVaultETH and checkpoint is not updated
        assertEq(address(stakerRewards).balance, initialBalanceCP1);
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);
        assertEq(stakerRewards.getCheckpointData().updateTime, dvActivationTimeCP1);
        assertEq(stakerRewards.getCheckpointData().dailyRewardsPer32ETH, initialRewardsPer32ETHCP1);
        assertEq(stakerRewards.getCheckpointData().totalVCs, initialVCs); // 1742
        assertEq(stakerRewards.numValidators4(), 1);

        // Check if cluster data is updated
        assertEq(stakerRewards.getClusterData(clusterIds[0]).activeTime, dvActivationTimeCP1);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).smallestVC, 150);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).exitTimestamp, dvActivationTimeCP1 + 150 * 1 days);

        // Check if vault data is updated
        IStakerRewards.VaultData memory vaultDataCP1 = stakerRewards.getVaultData(address(stratVaultETH));
        assertEq(vaultDataCP1.lastUpdate, dvActivationTimeCP1);
        assertEq(vaultDataCP1.numValidatorsInVault, 1);

        /* ====================== Activation of DV2 and DV3 ====================== */

        // ARRANGE
        address stratVaultETHAddress = address(stratVaultETH);
        bytes32[] memory clusterIdsCopy = stratVaultETH.getAllDVIds();
        vm.warp(block.timestamp + 5 days);
        uint256 usedVCsCP2 = 5 * 4 * stakerRewards.numValidators4(); // 5 days * 4 VCs * numValidators4

        // CP2: DV2 activation
        vm.prank(beaconChainAdmin);
        IStrategyVaultETH(stratVaultETHAddress).activateCluster(pubkey, signature, depositDataRoot, clusterIdsCopy[1]);
        uint256 initialBalanceCP2 = address(stakerRewards).balance;
        uint256 rewardsPer32ETHCP2 = stakerRewards.getCheckpointData().dailyRewardsPer32ETH;
        IStakerRewards.VaultData memory vaultDataCP2 = stakerRewards.getVaultData(stratVaultETHAddress);
        uint256 lastUpdateCP2 = vaultDataCP2.lastUpdate;
        uint256 numActiveDVsCP2 = vaultDataCP2.numValidatorsInVault;
        uint256 usedVCsCP3 = 2 * 4 * stakerRewards.numValidators4(); // 2 days * 4 VCs * numValidators4

        // ACT
        // CP3: DV3 activation
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        IStrategyVaultETH(stratVaultETHAddress).activateCluster(pubkey, signature, depositDataRoot, clusterIdsCopy[2]);

        // ASSERT
        // This the the 3rd DV activated few days after the second one: pending rewards should be sent to stratVaultETH and vairables are updated
        uint256 pendingRewardsToVault = rewardsPer32ETHCP2 * _getElapsedDays(lastUpdateCP2) * numActiveDVsCP2;
        assertEq(address(stakerRewards).balance, initialBalanceCP2 - pendingRewardsToVault);
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);
        assertEq(stakerRewards.getAllocatableRewards(), address(stakerRewards).balance);
        assertEq(stakerRewards.getCheckpointData().totalVCs, 1741 - usedVCsCP2 - usedVCsCP3);
        uint256 rewardsPer32ETHCP3 = stakerRewards.getCheckpointData().dailyRewardsPer32ETH;
        uint256 consumedVCsPerDayPerValidator = (stakerRewards.numClusters4() * 4 + stakerRewards.numClusters7() * 7) * 1e18 / (stakerRewards.numClusters4() + stakerRewards.numClusters7());
        console.log("consumedVCsPerDayPerValidator: %s", consumedVCsPerDayPerValidator); // 40000000000000000000
        uint256 dailyRewardsPer32ETH = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * consumedVCsPerDayPerValidator / 1e18;
        console.log("dailyRewardsPer32ETH: %18e", dailyRewardsPer32ETH); // 0.00306012384631726 ETH
        assertEq(rewardsPer32ETHCP3, dailyRewardsPer32ETH);
    }

    function test_dvActivationCheckpoint_threeVaults() public startAtPresentDay {
        // ARRANGE
        // Three vaults and 4 clusters have been created
        uint256 vaultCreationTime = block.timestamp;
        IStrategyVaultETH xVault = _createStratVaultETHAndStake(alice, 64 ether); // cluster 1 and 2
        bytes32[] memory xVaultClusterIds = xVault.getAllDVIds();
        IStrategyVaultETH yVault = _createStratVaultETHAndStake(bob, 32 ether); // cluster 3
        bytes32[] memory yVaultClusterIds = yVault.getAllDVIds();
        IStrategyVaultETH zVault = _createStratVaultETHAndStake(alice, 32 ether); // cluster 4
        bytes32[] memory zVaultClusterIds = zVault.getAllDVIds();
        uint256 initialVCs = stakerRewards.getCheckpointData().totalVCs;

        // CP1: DV1 activation (DV2 is not active yet)
        // No VCs consumed and no rewards are sent to the vault as DV1 is the first active validator
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        xVault.activateCluster(pubkey, signature, depositDataRoot, xVaultClusterIds[0]);

        // CP2: DV3 activation
        vm.warp(block.timestamp + 3 days);
        uint256 consumedVCsCP2 = 3 * 4 * stakerRewards.numValidators4(); // 3 days * 4 VCs * numValidators4
        uint256 distributedRewardsToVaultCP2 = stakerRewards.getCheckpointData().dailyRewardsPer32ETH * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.numValidators4();
        vm.prank(beaconChainAdmin);
        yVault.activateCluster(pubkey, signature, depositDataRoot, yVaultClusterIds[0]);

        // ACT
        // CP3: DV4 activation
        vm.warp(block.timestamp + 4 days);
        uint256 consumedVCsCP3 = 4 * 4 * stakerRewards.numValidators4(); 
        uint256 distributedRewardsToVaultCP3 = stakerRewards.getCheckpointData().dailyRewardsPer32ETH * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.numValidators4();
        vm.prank(beaconChainAdmin);
        zVault.activateCluster(pubkey, signature, depositDataRoot, zVaultClusterIds[0]);

        // ASSERT
        // Check if the total VCs is updated correctly
        uint256 totalConsumedVCs = consumedVCsCP2 + consumedVCsCP3;
        assertEq(stakerRewards.getCheckpointData().totalVCs, initialVCs - totalConsumedVCs);
        // Check if totalPendingRewards is increased and totalAllocatableRewards is decreased
        uint256 totalDistributedRewards = distributedRewardsToVaultCP2 + distributedRewardsToVaultCP3;
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, totalDistributedRewards);
        assertEq(stakerRewards.getAllocatableRewards(), address(stakerRewards).balance - totalDistributedRewards);
    }

    function test_dvActivationCheckpoint_validatorsExistAndCheckpointUpdatedLessThanOneDay() public startAtPresentDay {
        // Test: else if (numValsInVault > 0 && _hasTimeElapsed(vault.lastUpdate, _ONE_DAY)) && !_hasTimeElapsed(_checkpoint.updateTime, _ONE_DAY)
        // Cluster 1 VCs: 200, 200, 150, 150 = 700
        // Cluster 2 VCs: 200, 200, 149, 149 = 698
        // Cluster 3 VCs: 148, 100, 50, 45 = 343

        // ARRANGE
        // CP1: xVault creation
        IStrategyVaultETH xVault = _createStratVaultETHAndStake(alice, 64 ether); // cluster 1 and 2
        bytes32[] memory xVaultClusterIds = xVault.getAllDVIds();
        assertEq(stakerRewards.numValidators4(), 0);
        // CP2: DV1 activation
        vm.prank(beaconChainAdmin);
        xVault.activateCluster(pubkey, signature, depositDataRoot, xVaultClusterIds[0]); // Validator 1 in xVault
        uint256 lastUpdate = stakerRewards.getVaultData(address(xVault)).lastUpdate;

        // ACT
        // 5 day later: creation of a new vault (yVault) and activation of a new DV in xVault on the same day
        // CP3: yVault creation
        vm.warp(block.timestamp + 5 days);
        _createStratVaultETHAndStake(bob, 32 ether); // cluster 3

        // uint256 newVCsByCluster3 = 343; // 148, 100, 50, 45
        uint256 balanceBeforeDVActivation = address(stakerRewards).balance;
        uint256 rewardsToXVault = stakerRewards.getCheckpointData().dailyRewardsPer32ETH 
        * _getElapsedDays(stakerRewards.getVaultData(address(xVault)).lastUpdate) 
        * stakerRewards.getVaultData(address(xVault)).numValidatorsInVault;
        uint256 totalVCsCP3 = stakerRewards.getCheckpointData().totalVCs;
        uint256 totalPendingRewardsCP3 = stakerRewards.getCheckpointData().totalPendingRewards;
        assertGt(block.timestamp - lastUpdate, 1 days);

        // CP4: DV2 activation
        vm.warp(block.timestamp + 3 hours);
        vm.prank(beaconChainAdmin);
        xVault.activateCluster(pubkey, signature, depositDataRoot, xVaultClusterIds[1]); // Validator 2 in xVault

        // ASSERT
        assertLt(block.timestamp - stakerRewards.getCheckpointData().updateTime, 1 days);
        // Check if rewards are sent to the xVault
        assertEq(address(stakerRewards).balance, balanceBeforeDVActivation - rewardsToXVault);
        // Check if totalVCs is updated correctly
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsCP3);
        // Check if totalPendingRewards is increased 
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, totalPendingRewardsCP3 - rewardsToXVault);
    }

    function test_dvActivationCheckpoint_RevertWhen_calledByNonStratVaultETH() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();

        // ACT AND ASSERT
        vm.expectRevert(IStakerRewards.OnlyStratVaultETH.selector);
        stakerRewards.dvActivationCheckpoint(address(stratVaultETH), clusterIds[0]);
    }

    function test_checkUpkeep_ReturnsFalse_ifNoValidators() public startAtPresentDay {
        // ARRANGE
        _createStratVaultETHAndStake(alice, 96 ether);
        // 10 days later
        vm.warp(block.timestamp + 10 days);

        // ACT
        // Manually call checkUpkeep
        (bool upkeepNeeded, ) = stakerRewards.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);

        // Check performUpkeep revert if upkeepNeeded is false  
        vm.prank(forwarder);
        vm.expectRevert(IStakerRewards.UpkeepNotNeeded.selector);
        stakerRewards.performUpkeep("");
    }

    function test_checkUpkeep_ReturnFalse_ifCalledWithinTheUpkeepIntervalTimeline() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 32 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.warp(block.timestamp + 1 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // 150 days and 1 second later
        vm.warp(block.timestamp + 150 days + 1);
        // Manually call checkUpkeep and performUpkeep
        (bool upkeepNeeded, bytes memory performDataUpkeep1) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performDataUpkeep1);
        assertEq(stakerRewards.lastPerformUpkeep(), block.timestamp);

        // ACT AND ASSERT
        // 30 seconds later
        vm.warp(block.timestamp + 30 seconds);
        assertLt(block.timestamp - stakerRewards.lastPerformUpkeep(), stakerRewards.upkeepInterval());
        (bool upkeepNeeded2, ) = stakerRewards.checkUpkeep("");
        assert(!upkeepNeeded2);
    }

    function test_checkUpkeep_ReturnsFalse_ifNoValidatorsHaveConsumedAllVCs() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 64 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]);
        // 100 days later
        vm.warp(block.timestamp + 100 days);

        // ACT
        // Manually call checkUpkeep and performUpkeep
        (bool upkeepNeeded, ) = stakerRewards.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);
        // Check performUpkeep revert if upkeepNeeded is false  
        vm.prank(forwarder);
        vm.expectRevert(IStakerRewards.UpkeepNotNeeded.selector);
        stakerRewards.performUpkeep("");
    }

    function test_checkUpkeep_ReturnsTrue_ifOneValidatorConsumedAllVCs() public startAtPresentDay {
        // The smallest VC number of cluster 1 is 150 

        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.startPrank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[2]);
        vm.stopPrank();
        uint256 totalClusters = stakerRewards.numClusters4();
        
        // 45 days and 1 second later
        vm.warp(block.timestamp + 45 days + 1);

        // ACT
        // Manually call checkUpkeep and performUpkeep
        (bool upkeepNeeded, bytes memory performDataUpkeep1) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performDataUpkeep1);

        // ASSERT
        assert(upkeepNeeded);
        assertEq(stakerRewards.numClusters4(), totalClusters - 1);
    }

    function test_performUpkeep_RevertWhen_calledByNonForwarder() public {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        
        // 150 days and 1 second later
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 150 days + 1);
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");

        // ACT AND ASSERT
        assert(upkeepNeeded);
        vm.expectRevert();
        stakerRewards.performUpkeep(performData);
    }

    function test_performUpkeep_decodedPerformDataIsCorrect() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        uint256 smallestVC = stakerRewards.getClusterData(clusterIds[0]).smallestVC;

        // Get the initial number of VCs of the cluster
        uint256 initialClusterVCs = 0;
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(clusterIds[0]);
        uint256 length = clusterDetails.nodes.length;
        for (uint256 i = 0; i < length; i++) {
            IAuction.NodeDetails memory node = clusterDetails.nodes[i];
            initialClusterVCs += node.currentVCNumber;
        }
        // Get the total bid price of the cluster
        uint256 totalBidPrice = 0;
        for (uint256 i = 0; i < length; i++) {
            IAuction.BidDetails memory bidDetails = auction.getBidDetails(clusterDetails.nodes[i].bidId);
            totalBidPrice += bidDetails.bidPrice;
        }

        // 150 days and 1 second later
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 150 days + 1);
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);

        // ACT
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // ASSERT
        (bytes32[] memory listClusterIds, uint256 remainingVCsToRemove, uint256 totalBidsToEscrow) = abi.decode(performData, (bytes32[], uint256, uint256));
        uint256 consumedVCs = length * smallestVC;
        assertEq(remainingVCsToRemove, initialClusterVCs - consumedVCs);
        assertEq(listClusterIds.length, 1);
        assertEq(listClusterIds[0], clusterIds[0]);
        uint256 ditributedBidPrice = 0;
        for (uint256 i = 0; i < length; i++) {
            IAuction.BidDetails memory bidDetails = auction.getBidDetails(clusterDetails.nodes[i].bidId);
            uint256 dailyVcPrice = _getDailyVcPrice(bidDetails.bidPrice, bidDetails.vcNumber);
            ditributedBidPrice += (dailyVcPrice * smallestVC);
        }
        assertEq(totalBidsToEscrow, totalBidPrice - ditributedBidPrice);
    }

    function test_performUpkeep_correctlyUpdatesData() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 64 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        uint256 initialSRBalance = address(stakerRewards).balance;
        uint256 initialEscrowBalance = address(escrow).balance;
        uint256 initialVCs = stakerRewards.getCheckpointData().totalVCs;
        uint256 rewardsPer32ETH = stakerRewards.getCheckpointData().dailyRewardsPer32ETH;

        // Activate DV1 and DV2
        vm.startPrank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]); // smallest VC = 150
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]); // smallest VC = 149
        vm.stopPrank();

        // Cluster 2 nodes' VC number
        bytes32 cluster2Id = clusterIds[1];
        IAuction.ClusterDetails memory cluster2Details = auction.getClusterDetails(cluster2Id);
        uint256[] memory cluster2NodeVcNumber = new uint256[](cluster2Details.nodes.length);
        for (uint256 i = 0; i < cluster2Details.nodes.length; i++) {
            IAuction.NodeDetails memory node = cluster2Details.nodes[i];
            cluster2NodeVcNumber[i] = node.currentVCNumber;
        }

        /* ====================== First performUpkeep ====================== */

        // ACT
        // 149 days and 1 second later, first upkeep returns true for DV2
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 149 days + 1);
        (, bytes memory performData) = stakerRewards.checkUpkeep("");
        (, uint256 remainingVCsToRemove, uint256 totalBidsToEscrow) = abi.decode(performData, (bytes32[], uint256, uint256));
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // ASSERT
        assertEq(stakerRewards.numClusters4(), 1);
        assertEq(stakerRewards.numClusters7(), 0);
        assertEq(stakerRewards.numValidators4(), 2);
        assertEq(stakerRewards.numValidators7(), 0);
        // Check if totalVCs updated correctly
        uint256 totalConsumedVCs = 149 * 4 * stakerRewards.numValidators4();
        uint256 totalVCsUpkeep1 = initialVCs - remainingVCsToRemove - totalConsumedVCs;
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsUpkeep1);
        // Check if remaining bids are correctly sent to escrow
        assertEq(address(stakerRewards).balance, initialSRBalance - totalBidsToEscrow);
        assertEq(address(escrow).balance, initialEscrowBalance + totalBidsToEscrow);
        // Check if DV nodes' VC number is updated correctly
        IAuction.ClusterDetails memory cluster2DetailsAfterUpkeep1 = auction.getClusterDetails(cluster2Id);
        for (uint256 i = 0; i < cluster2DetailsAfterUpkeep1.nodes.length; i++) {
            IAuction.NodeDetails memory node = cluster2DetailsAfterUpkeep1.nodes[i];
            assertEq(node.currentVCNumber, cluster2NodeVcNumber[i] - 149);
        }
        // Check if rewards since last checkpoint are distributed correctly 
        uint256 distributedRewards = rewardsPer32ETH * 149 * stakerRewards.numValidators4();
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, distributedRewards);
        assertEq(stakerRewards.getAllocatableRewards(), address(stakerRewards).balance - distributedRewards);
        // Check if new checkpoint is created
        uint256 averageVCsUsedPerDayPerValidator = stakerRewards.numClusters4() * 4 * 1e18 / stakerRewards.numClusters4();
        uint256 newDailyRewards = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * averageVCsUsedPerDayPerValidator / 1e18;
        assertEq(stakerRewards.getCheckpointData().dailyRewardsPer32ETH, newDailyRewards);
        assertEq(stakerRewards.getCheckpointData().updateTime, block.timestamp);

        /* ====================== Second performUpkeep ====================== */

        // ACT
        // 1 day later, second upkeep returns true for DV1
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 1 days);
        (, bytes memory performData2) = stakerRewards.checkUpkeep("");
        (, uint256 remainingVCsToRemoveUpkeep2, uint256 totalBidsToEscrowUpkeep2) = abi.decode(performData2, (bytes32[], uint256, uint256));

        // ASSERT
        uint256 TotalNumClusters = stakerRewards.numClusters4() + stakerRewards.numClusters7();
        uint256 TotalNumValidators = stakerRewards.numValidators4() + stakerRewards.numValidators7();
        assertLt(TotalNumClusters, TotalNumValidators);
        vm.prank(forwarder);
        vm.expectRevert(IStakerRewards.TotalVCsLessThanConsumedVCs.selector);
        stakerRewards.performUpkeep(performData2);
    }

    function test_getAllocatableRewards_ReturnsCorrectValue() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        // Activate DV1 and DV2
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]);

        // ACT
        uint256 allocatableRewards = stakerRewards.getAllocatableRewards();

        // ASSERT
        assertEq(allocatableRewards, address(stakerRewards).balance - stakerRewards.getCheckpointData().totalPendingRewards);
    }

    function test_getClusterData_ReturnsCorrectData() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 32 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // ACT
        IStakerRewards.ClusterData memory clusterData = stakerRewards.getClusterData(clusterIds[0]);

        // ASSERT
        assertEq(clusterData.activeTime, block.timestamp);
        assertEq(clusterData.smallestVC, 150);
        assertEq(clusterData.exitTimestamp, block.timestamp + clusterData.smallestVC * 1 days);
        assertEq(clusterData.clusterSize, 4);
    }

    function test_getVaultData_ReturnsCorrectData() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 32 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // ACT
        IStakerRewards.VaultData memory vaultData = stakerRewards.getVaultData(address(stratVaultETH));
        uint256 lastUpdate = vaultData.lastUpdate;
        uint256 numValidatorsInVault = vaultData.numValidatorsInVault;

        // ASSERT
        assertEq(lastUpdate, block.timestamp);
        assertEq(numValidatorsInVault, 1);
    }

    function test_getCheckpointData_ReturnsCorrectData() public {
        // ARRANGE
        _createStratVaultETHAndStake(alice, 32 ether);

        // ASSERT
        assertEq(stakerRewards.getCheckpointData().updateTime, block.timestamp);
        uint256 averageVCsUsedPerDayPerValidator = (stakerRewards.numClusters4() * 4 * 1e18) / stakerRewards.numClusters4();
        uint256 dailyRewardsPer32ETH = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * averageVCsUsedPerDayPerValidator / 1e18;
        assertEq(stakerRewards.getCheckpointData().dailyRewardsPer32ETH, dailyRewardsPer32ETH);
    }

    function test_updateUpkeepInterval() public {
        vm.prank(address(strategyVaultManager));
        stakerRewards.updateUpkeepInterval(100);
        assertEq(stakerRewards.upkeepInterval(), 100);
    }

    function test_updateUpkeepInterval_RevertWhen_calledByNonStratVaultManager() public {
        vm.expectRevert(IStakerRewards.OnlyStrategyVaultManager.selector);
        stakerRewards.updateUpkeepInterval(100);
    }

    function test_setForwarderAddress() public {
        vm.prank(address(strategyVaultManager));
        stakerRewards.setForwarderAddress(alice);
        assertEq(stakerRewards.forwarderAddress(), alice);
    }

    function test_setForwarderAddress_RevertWhen_calledByNonStratVaultManager() public {
        vm.expectRevert(IStakerRewards.OnlyStrategyVaultManager.selector);
        stakerRewards.setForwarderAddress(forwarder);
    }

    /* ===================== HELPER FUNCTIONS ===================== */

    function _createMultipleBids() internal returns (bytes32[] memory) {
        bytes32[] memory bidIds = new bytes32[](16);

        // nodeOps[0] bids 2 times with the same parameters
        bidIds[0] = _bidCluster4(nodeOps[0], 5e2, 200); // 1st
        bidIds[1] = _bidCluster4(nodeOps[0], 5e2, 200); // 6th

        // nodeOps[1] bids 2 times with the same parameters
        bidIds[2] = _bidCluster4(nodeOps[1], 5e2, 200); // 2nd
        bidIds[3] = _bidCluster4(nodeOps[1], 5e2, 200); // 5th

        // nodeOps[2] bids 4 times with different parameters
        bidIds[4] = _bidCluster4(nodeOps[2], 5e2, 150); // 3rd
        bidIds[5] = _bidCluster4(nodeOps[2], 5e2, 149); // 7th
        bidIds[6] = _bidCluster4(nodeOps[2], 5e2, 148); // 9th
        bidIds[7] = _bidCluster4(nodeOps[2], 5e2, 147); // 13th

        // nodeOps[3] bids
        bidIds[8] = _bidCluster4(nodeOps[3], 5e2, 150); // 4th

        // nodeOps[4] bids
        bidIds[9] = _bidCluster4(nodeOps[4], 5e2, 149); // 8th

        // nodeOps[5] bids
        bidIds[10] = _bidCluster4(nodeOps[5], 9e2, 100); // 10th

        // nodeOps[6] bids
        bidIds[11] = _bidCluster4(nodeOps[6], 12e2, 50); // 11th
        bidIds[12] = _bidCluster4(nodeOps[6], 14e2, 50); // 14th

        // nodeOps[7] bids
        bidIds[13] = _bidCluster4(nodeOps[7], 14e2, 45); // 12th
        bidIds[14] = _bidCluster4(nodeOps[7], 14e2, 40); // 15th

        // nodeOps[8] bids
        bidIds[15] = _bidCluster4(nodeOps[8], 15e2, 40); // 16th

        return bidIds;
    }

    function _bidCluster4(
        address _nodeOp,
        uint16 _discountRate,
        uint32 _timeInDays
    ) internal returns (bytes32) {
        vm.warp(block.timestamp + 1);
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(_nodeOp, _discountRate, _timeInDays, IAuction.AuctionType.JOIN_CLUSTER_4);
        vm.prank(_nodeOp);
        return auction.bid{value: priceToPay}(_discountRate, _timeInDays, IAuction.AuctionType.JOIN_CLUSTER_4);
    }

    function _createStratVaultETHAndStake(address _staker, uint256 _amount) internal returns (IStrategyVaultETH) {
        vm.prank(_staker);
        IStrategyVaultETH stratVaultETH = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: _amount}(true, true, ELOperator1, address(0), _staker));
        return stratVaultETH;
    }

    function _getDepositData(bytes memory depositFilePath) internal {
        // File generated with the Obol LaunchPad
        setJSON(string(depositFilePath));

        pubkey = getDVPubKeyDeposit();
        signature = getDVSignature();
        depositDataRoot = getDVDepositDataRoot();
    }

    function _getElapsedDays(uint256 _lastTimestamp) internal view returns (uint256) {
        return (block.timestamp - _lastTimestamp) / 1 days;
    }

    function _getDailyVcPrice(uint256 _bidPrice, uint32 _vcNumber) internal pure returns(uint256) {
        return _bidPrice / _vcNumber;
    }

    /* ===================== MODIFIERS ===================== */

    modifier startAtPresentDay() {
        vm.warp(1727876759);
        _;
    }
}