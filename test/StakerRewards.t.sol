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
import "./mocks/BidInvestmentMock.sol";

import {console} from "forge-std/console.sol";

contract StakerRewardsTest is ProofParsing, ByzantineDeployer {
    /// @notice Initial balance of all the node operators
    uint256 internal constant STARTING_BALANCE = 500 ether;
    /// @notice Conversion factor from gwei to wei
    uint256 private constant _GWEI_TO_WEI = 1e9;
    /// @notice Scale factor for the staked balance rate
    uint256 private constant _STAKED_BALANCE_RATE_SCALE = 1e4;

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
        vm.prank(byzantineAdmin);
        stakerRewards.setForwarderAddress(forwarder);

        // Fill the node operators' balance
        for (uint256 i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        // vm.deal(alice, STARTING_BALANCE);
        // vm.deal(bob, STARTING_BALANCE);

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

    function test_dvActivationCheckpoint_oneVault() public startAtPresentDay {

        /* ====================== Activation of DV1 ====================== */

        // ARRANGE 
        // Deposit 96 ETH in total
        // Total VCs of 3 clusters: 1741
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether); // 3 clusters
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();

        uint256 initialBalanceCP1 = address(bidInvestment).balance;
        uint256 clusterTotalVCs = _getClusterTotalVCs(clusterIds[0]);

        // ACT
        // CP1: DV1 activation
        vm.warp(block.timestamp + 1 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // ASSERT 
        // This is the first DV of the stratVaultETH: no rewards should be sent to stratVaultETH and checkpoint is not updated
        uint256 totalVCsCP1 = stakerRewards.getCheckpointData().totalVCs;
        uint256 dailyUsedVCsPer32ETHCP1 = stakerRewards.numValidators4() * 4 * 1e18 / stakerRewards.numValidators4();
        uint256 daily32EthBaseRewardsCP1 = (stakerRewards.getAllocatableRewards() / totalVCsCP1) * dailyUsedVCsPer32ETHCP1 / 1e18;
        uint256 distributedRewardsCP1 = daily32EthBaseRewardsCP1 * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;

        assertEq(address(stakerRewards).balance, 0);
        assertEq(address(bidInvestment).balance, initialBalanceCP1);
        assertEq(stakerRewards.getAllocatableRewards(), stakerRewards.getCheckpointData().totalActivedBids);
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);
        assertEq(stakerRewards.getCheckpointData().updateTime, block.timestamp);
        assertEq(stakerRewards.getCheckpointData().daily32EthBaseRewards, daily32EthBaseRewardsCP1);
        assertEq(stakerRewards.getCheckpointData().totalVCs, clusterTotalVCs); // 1742
        assertEq(stakerRewards.numValidators4(), 1);

        // Check if cluster data is updated
        assertEq(stakerRewards.getClusterData(clusterIds[0]).activeTime, block.timestamp);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).smallestVC, 150);
        assertEq(stakerRewards.getClusterData(clusterIds[0]).exitTimestamp, block.timestamp + 150 * 1 days);

        // Check if vault data is updated
        uint16 stakedBalanceRate = _getStakedBalanceRate(address(stratVaultETH), auction.getClusterDetails(clusterIds[0]).clusterPubKeyHash);
        IStakerRewards.VaultData memory vaultDataCP1 = stakerRewards.getVaultData(address(stratVaultETH));
        assertEq(vaultDataCP1.lastUpdate, block.timestamp);
        assertEq(vaultDataCP1.accruedStakedBalanceRate, stakedBalanceRate);

        /* ====================== Activation of DV2 and DV3 ====================== */

        // ARRANGE
        address stratVaultETHAddress = address(stratVaultETH);
        bytes32[] memory clusterIdsCopy = stratVaultETH.getAllDVIds();
        vm.warp(block.timestamp + 5 days);

        // CP2: DV2 activation
        vm.prank(beaconChainAdmin);
        IStrategyVaultETH(stratVaultETHAddress).activateCluster(pubkey, signature, depositDataRoot, clusterIdsCopy[1]);
        uint256 initialBalanceCP2 = address(bidInvestment).balance;
        uint256 rewardsPer32ETHCP2 = stakerRewards.getCheckpointData().daily32EthBaseRewards;
        IStakerRewards.VaultData memory vaultDataCP2 = stakerRewards.getVaultData(stratVaultETHAddress);
        uint256 lastUpdateCP2 = vaultDataCP2.lastUpdate;
        uint256 accruedStakedBalanceRateCP2 = vaultDataCP2.accruedStakedBalanceRate;
        uint256 consumedVCsCP2 = 5 * stakerRewards.getCheckpointData().totalDailyConsumedVCs;
        uint256 distributedRewardsCP2 = distributedRewardsCP1 + rewardsPer32ETHCP2 * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;

        // ACT
        // CP3: DV3 activation
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        IStrategyVaultETH(stratVaultETHAddress).activateCluster(pubkey, signature, depositDataRoot, clusterIdsCopy[2]);

        // ASSERT
        uint256 vaultPendingRewardsCP3 = stakerRewards.getVaultData(stratVaultETHAddress).pendingRewards;

        // This the the 3rd DV activated few days after the second one
        uint256 totalVCsCP3 = stakerRewards.getCheckpointData().totalVCs - consumedVCsCP2 - 2 * stakerRewards.getCheckpointData().totalDailyConsumedVCs;
        uint256 distributedRewardsCP3 = distributedRewardsCP2 + rewardsPer32ETHCP2 * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;        
        uint256 allocatableAmount = stakerRewards.getCheckpointData().totalActivedBids - distributedRewardsCP3;
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, 0);
        assertEq(stakerRewards.getAllocatableRewards(), allocatableAmount);
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsCP3);
        // Check daily32EthBaseRewards
        uint256 rewardsPer32ETHCP3 = stakerRewards.getCheckpointData().daily32EthBaseRewards;
        uint256 consumedVCsPerDayPerValidator = (stakerRewards.numValidators4() * 4 + stakerRewards.numValidators7() * 7) * 1e18 / (stakerRewards.numValidators4() + stakerRewards.numValidators7());
        console.log("consumedVCsPerDayPerValidator: %s", consumedVCsPerDayPerValidator); // 40000000000000000000
        uint256 dailyRewardsPer32ETH = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * consumedVCsPerDayPerValidator / 1e18;
        console.log("dailyRewardsPer32ETH: %18e", dailyRewardsPer32ETH); // 0.00306012384631726 ETH
        assertEq(rewardsPer32ETHCP3, dailyRewardsPer32ETH);
        // Check the pending rewards stored in VaultData: all distributed rewards go to the vault
        assertEq(vaultPendingRewardsCP3, distributedRewardsCP3);
        console.log("vaultPendingRewardsCP3: %s", vaultPendingRewardsCP3);
    }

    function test_dvActivationCheckpoint_threeVaults() public startAtPresentDay {
        // Cluster 1 VCs: 200, 200, 150, 150 = 700
        // Cluster 2 VCs: 200, 200, 149, 149 = 698
        // Cluster 3 VCs: 148, 100, 50, 45 = 343
        // Cluster 4 VCs: 277

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
        uint256 consumedVCsDV1 = 3 * stakerRewards.getCheckpointData().totalDailyConsumedVCs; // 3 days * totalDailyConsumedVCs
        uint256 distributedRewardsDV1 = stakerRewards.getCheckpointData().daily32EthBaseRewards * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;
        vm.prank(beaconChainAdmin);
        yVault.activateCluster(pubkey, signature, depositDataRoot, yVaultClusterIds[0]);

        // ACT
        // CP3: DV4 activation
        vm.warp(block.timestamp + 4 days);
        uint256 consumedVCsDV3 = 4 * stakerRewards.getCheckpointData().totalDailyConsumedVCs; 
        uint256 distributedRewardsDV3 = stakerRewards.getCheckpointData().daily32EthBaseRewards * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;
        vm.prank(beaconChainAdmin);
        zVault.activateCluster(pubkey, signature, depositDataRoot, zVaultClusterIds[0]);
        uint256 consumedVCsDV4 = 4 * stakerRewards.getCheckpointData().totalDailyConsumedVCs;
        uint256 distributedRewardsDV4 = stakerRewards.getCheckpointData().daily32EthBaseRewards * _getElapsedDays(stakerRewards.getCheckpointData().updateTime) * stakerRewards.getCheckpointData().totalStakedBalanceRate;

        // ASSERT
        // Check if the total VCs is updated correctly
        assertEq(initialVCs, 0);
        uint256 totalVCsCP3 = (700 + 343 + 277) - (consumedVCsDV1 + consumedVCsDV3 + consumedVCsDV4);
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsCP3);
        // Check if totalPendingRewards is increased and totalAllocatableRewards is decreased
        uint256 totalDistributedRewards = distributedRewardsDV1 + distributedRewardsDV3 + distributedRewardsDV4;
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, totalDistributedRewards);
        assertEq(stakerRewards.getAllocatableRewards(), stakerRewards.getCheckpointData().totalActivedBids - totalDistributedRewards);
    }

    function test_dvActivationCheckpoint_validatorsExistAndCheckpointUpdatedLessThanOneDay() public startAtPresentDay {
        // Cluster 1 VCs: 200, 200, 150, 150 = 700
        // Cluster 2 VCs: 200, 200, 149, 149 = 698
        // Cluster 3 VCs: 148, 100, 50, 45 = 343

        // ARRANGE
        // xVault creation
        IStrategyVaultETH xVault = _createStratVaultETHAndStake(alice, 64 ether); // cluster 1 and 2
        bytes32[] memory xVaultClusterIds = xVault.getAllDVIds();
        assertEq(stakerRewards.numValidators4(), 0);

        // CP1: DV1 activation
        vm.prank(beaconChainAdmin);
        uint256 dv1ActivationTime = block.timestamp;
        xVault.activateCluster(pubkey, signature, depositDataRoot, xVaultClusterIds[0]); // Validator 1 in xVault
        IStakerRewards.Checkpoint memory checkpointCP1 = stakerRewards.getCheckpointData();
        uint256 totalVCsCP1 = checkpointCP1.totalVCs;
        uint256 totalPendingRewardsCP1 = checkpointCP1.totalPendingRewards;
        uint256 vaultPendingRewardsCP1 = stakerRewards.getVaultData(address(xVault)).pendingRewards;

        // ACT
        // CP2: 3 hours later: DV2 activation 
        vm.warp(block.timestamp + 3 hours);
        vm.prank(beaconChainAdmin);
        xVault.activateCluster(pubkey, signature, depositDataRoot, xVaultClusterIds[1]); // Validator 2 in xVault
        uint256 clusterVCsDV2 = _getClusterTotalVCs(xVaultClusterIds[1]);

        // ASSERT
        // Check totalVCs: new VCs but no consumed VCs yet
        assertEq(stakerRewards.getCheckpointData().totalVCs, totalVCsCP1 + clusterVCsDV2);
        // Check totalPendingRewards: no distributed rewards yet
        assertEq(stakerRewards.getCheckpointData().totalPendingRewards, totalPendingRewardsCP1);
        // Check vault pending rewards: no ditributed rewards to the vault 
        assertEq(stakerRewards.getVaultData(address(xVault)).pendingRewards, vaultPendingRewardsCP1);
        // Calculate daily32EthBaseRewards
        uint256 dailyUsedVCsPer32ETH = ((stakerRewards.numValidators4() * 4) * 1e18) / (stakerRewards.numValidators4());
        uint256 daily32EthBaseRewards = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * dailyUsedVCsPer32ETH / 1e18;
        assertEq(stakerRewards.getCheckpointData().daily32EthBaseRewards, daily32EthBaseRewards);
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
        address txOrigin = address(0);
        _createStratVaultETHAndStake(alice, 96 ether);
        // 10 days later
        vm.warp(block.timestamp + 10 days);

        // ACT
        // Manually call checkUpkeep
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);
        assertEq(performData, "");
    }

    function test_checkUpkeep_ReturnFalse_ifCalledWithinTheUpkeepIntervalTimeline() public startAtPresentDay {
        // ARRANGE
        address txOrigin = address(0);
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 32 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.warp(block.timestamp + 1 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // 150 days and 1 second later
        vm.warp(block.timestamp + 150 days + 1);
        // Manually call checkUpkeep and performUpkeep
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (bool upkeepNeeded, bytes memory performDataUpkeep1) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);
        // vm.prank(forwarder);
        // stakerRewards.performUpkeep(performDataUpkeep1);
        // assertEq(stakerRewards.lastPerformUpkeep(), block.timestamp);

        // // ACT AND ASSERT
        // // 30 seconds later
        // vm.warp(block.timestamp + 30 seconds);
        // assertLt(block.timestamp - stakerRewards.lastPerformUpkeep(), stakerRewards.upkeepInterval());
        // vm.prank(msg.sender, txOrigin);
        // (bool upkeepNeeded2, ) = stakerRewards.checkUpkeep("");
        // assert(!upkeepNeeded2);
    }

    function test_checkUpkeep_ReturnsFalse_ifNoValidatorsHaveConsumedAllVCs() public startAtPresentDay {
        // ARRANGE
        address txOrigin = address(0);
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
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (bool upkeepNeeded, ) = stakerRewards.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);
    }

    function test_checkUpkeep_ReturnsTrue_ifOneValidatorConsumedAllVCs() public startAtPresentDay {
        // The smallest VC number of cluster 1 is 150 

        // ARRANGE
        address txOrigin = address(0);
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.startPrank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[2]);
        vm.stopPrank();
        uint256 totalValidators = stakerRewards.numValidators4();
        
        // 45 days and 1 second later
        vm.warp(block.timestamp + 45 days + 1);

        // ACT
        // Manually call checkUpkeep and performUpkeep
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (bool upkeepNeeded, bytes memory performDataUpkeep1) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performDataUpkeep1);

        // ASSERT
        assert(upkeepNeeded);
        assertEq(stakerRewards.numValidators4(), totalValidators - 1);
    }

    function test_performUpkeep_RevertWhen_calledByNonForwarder() public {
        // ARRANGE
        address txOrigin = address(0);
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        
        // 150 days and 1 second later
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 150 days + 1);
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
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

        // Activate DV1 
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // Activate DV2
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]);
        // Get the initial number of VCs and total bid price of DV2
        uint256 initialClusterVCsDV2 = 0;
        uint256 totalBidPriceDV2 = 0;
        uint256 remainingBidsToEscrowDV2 = 0;
        uint256 smallestVcDV2 = stakerRewards.getClusterData(clusterIds[1]).smallestVC;
        IAuction.ClusterDetails memory clusterDetailsDV2 = auction.getClusterDetails(clusterIds[1]);
        uint256 lengthDV2 = clusterDetailsDV2.nodes.length;

        for (uint256 i = 0; i < lengthDV2; i++) {
            IAuction.NodeDetails memory node = clusterDetailsDV2.nodes[i];
            initialClusterVCsDV2 += node.currentVCNumber;
            IAuction.BidDetails memory bidDetails = auction.getBidDetails(node.bidId);
            totalBidPriceDV2 += bidDetails.bidPrice;

            uint256 dailyVcPrice = _getDailyVcPrice(bidDetails.bidPrice, bidDetails.vcNumber);
            remainingBidsToEscrowDV2 += (dailyVcPrice * (bidDetails.vcNumber - smallestVcDV2));
        }
        uint256 remainingVCsToRemoveDV2 = initialClusterVCsDV2 - smallestVcDV2 * lengthDV2;
        uint16 stakedBalanceRateDV2 = _getStakedBalanceRate(address(stratVaultETH), clusterDetailsDV2.clusterPubKeyHash);
        
        // 150 days and 1 second later
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 150 days + 1);
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        address txOrigin = address(0);
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);

        // ACT
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // ASSERT
        // Decode performData
        (
            bytes32[] memory clusterIdsToExit,
            uint64[] memory remainingVCsToRemove,
            uint256[] memory totalBidsToEscrow,
            uint16[] memory totalStakedBalanceRateToRemove,
            uint64[] memory totalDailyConsumedVCsToRemove
        ) = abi.decode(performData, (bytes32[], uint64[], uint256[], uint16[], uint64[]));

        // PerformData should contain DV1 and DV2 metrics for exit
        assertEq(clusterIdsToExit.length, 2);
        assertEq(remainingVCsToRemove[1], remainingVCsToRemoveDV2);
        assertEq(totalBidsToEscrow[1], remainingBidsToEscrowDV2);
        assertEq(totalStakedBalanceRateToRemove[1], stakedBalanceRateDV2);
        assertEq(totalDailyConsumedVCsToRemove[1], stakedBalanceRateDV2 * lengthDV2);
    }

    function test_performUpkeep_correctlyUpdatesData() public startAtPresentDay {
        // Cluster 1 VCs: 200, 200, 150, 150 = 700
        // Cluster 2 VCs: 200, 200, 149, 149 = 698
        // Cluster 3 VCs: 148, 100, 50, 45 = 343

        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 64 ether);
        address txOrigin = address(0);

        // Activate DV1 and DV2
        vm.startPrank(beaconChainAdmin);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]); // smallest VC = 150
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]); // smallest VC = 149
        vm.stopPrank(); 

        bytes32 cluster2Id = clusterIds[1];
        IAuction.ClusterDetails memory cluster2Details = auction.getClusterDetails(cluster2Id);

        // 149 days and 1 second later, first upkeep returns true for DV2
        // Manually call checkUpkeep and performUpkeep
        vm.warp(block.timestamp + 149 days + 1);
        // Only address(0) can call checkUpkeep with cannotExecute modifier
        vm.prank(msg.sender, txOrigin); // make tx.origin be address(0)
        (, bytes memory performData) = stakerRewards.checkUpkeep("");
        (, uint64[] memory remainingVCsToRemove1, uint256[] memory totalBidsToEscrow1, , uint64[] memory totalDailyConsumedVCsToRemove1) 
        = abi.decode(performData, (bytes32[], uint64[], uint256[], uint16[], uint64[]));

        // Cluster 2 nodes' VC number
        uint64 vcNumBeforeUpkeep = stakerRewards.getCheckpointData().totalVCs;
        // Get staked balance rate
        uint16 stakedBalanceRateDV2 = _getStakedBalanceRate(address(stratVaultETH), cluster2Details.clusterPubKeyHash);
        uint24 totalStakedBalanceRateBeforeUpkeep = stakerRewards.getCheckpointData().totalStakedBalanceRate;
        // Get daily consumed VCs
        uint64 dailyConsumedVCsDV2 = stakedBalanceRateDV2 * 4;
        uint64 totalDailyConsumedVCs = stakerRewards.getCheckpointData().totalDailyConsumedVCs;
        // Escrow balance
        uint256 escrowBalanceBeforeUpkeep = address(escrow).balance;
        
        // ACT
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // ASSERT
        bytes32 custer2IdCopy = clusterIds[1];
        IAuction.ClusterDetails memory cluster2DetailsAfterUpkeep = auction.getClusterDetails(custer2IdCopy);
        // Check if remaining bid prices sent back to Escrow 
        assertEq(address(escrow).balance, escrowBalanceBeforeUpkeep + totalBidsToEscrow1[0]);
        // Check total VC number
        assertEq(stakerRewards.getCheckpointData().totalVCs, vcNumBeforeUpkeep - remainingVCsToRemove1[0]);
        // Check if total staked balance rate decreased
        assertEq(stakerRewards.getCheckpointData().totalStakedBalanceRate, totalStakedBalanceRateBeforeUpkeep - stakedBalanceRateDV2);
        // Check if total daily consumed VCs decreased
        assertEq(stakerRewards.getCheckpointData().totalDailyConsumedVCs, totalDailyConsumedVCs - dailyConsumedVCsDV2);
        // Check if node operator's VCs decreased 
        assertEq(cluster2DetailsAfterUpkeep.nodes[0].currentVCNumber, 200 - 149);
        assertEq(cluster2DetailsAfterUpkeep.nodes[1].currentVCNumber, 200 - 149);
        assertEq(cluster2DetailsAfterUpkeep.nodes[2].currentVCNumber, 0);
        assertEq(cluster2DetailsAfterUpkeep.nodes[3].currentVCNumber, 0);
        // Check if cluster data updated
        IStakerRewards.ClusterData memory cluster = stakerRewards.getClusterData(custer2IdCopy);
        assertEq(cluster.smallestVC, 0);
        assertEq(cluster.activeTime, 0);
        assertEq(cluster.exitTimestamp, 0);
        // Check validator number
        assertEq(stakerRewards.numValidators4(), 1);
    }

    function test_getVaultRewards_ReturnsCorrectValue() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        uint256 dailyRewardsPer32ETHActivation1 = stakerRewards.getCheckpointData().daily32EthBaseRewards;
        uint16 accruedStakedBalanceRate1 = stakerRewards.getVaultData(address(stratVaultETH)).accruedStakedBalanceRate;
        uint16 stakedBalanceRate1 = _getStakedBalanceRate(address(stratVaultETH), auction.getClusterDetails(clusterIds[0]).clusterPubKeyHash);
        vm.warp(block.timestamp + 30 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]);
        uint256 dailyRewardsPer32ETHActivation2 = stakerRewards.getCheckpointData().daily32EthBaseRewards;
        vm.warp(block.timestamp + 10 days);

        // ACT
        uint256 rewards = stakerRewards.getVaultRewards(address(stratVaultETH));

        // ASSERT
        // assertEq(accruedStakedBalanceRate1, 1);
        // assertEq(stakerRewards.getVaultData(address(stratVaultETH)).accruedStakedBalanceRate, 2);
        uint256 rewardsSinceActivation2 = dailyRewardsPer32ETHActivation2 * 10 days * stakerRewards.getVaultData(address(stratVaultETH)).accruedStakedBalanceRate / 1e4;
        // assertEq(rewards, rewardsSinceActivation2);
    }

    function test_getAllocatableRewards_ReturnsCorrectValue() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();

        // Activate DV1 and DV2
        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);
        uint256 totalBidsDV1 = _getClusterTotalBids(clusterIds[0]);

        vm.warp(block.timestamp + 2 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[1]);
        uint256 totalBidsDV2 = _getClusterTotalBids(clusterIds[1]);

        // ACT
        uint256 allocatableRewards = stakerRewards.getAllocatableRewards();

        // ASSERT
        assertEq(allocatableRewards, totalBidsDV1 + totalBidsDV2 - stakerRewards.getCheckpointData().totalPendingRewards);
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
        // uint256 numValidatorsInVault = vaultData.numValidatorsInVault;

        // ASSERT
        assertEq(lastUpdate, block.timestamp);
        // assertEq(numValidatorsInVault, 1);
    }

    function test_getCheckpointData_ReturnsCorrectData() public startAtPresentDay {
        // ARRANGE
        IStrategyVaultETH stratVaultETH =_createStratVaultETHAndStake(alice, 32 ether);
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        uint256 dvActivationTime = block.timestamp;

        // ASSERT
        assertEq(stakerRewards.getCheckpointData().updateTime, 0);

        // ACT
        vm.warp(dvActivationTime + 1 days);
        vm.prank(beaconChainAdmin);
        stratVaultETH.activateCluster(pubkey, signature, depositDataRoot, clusterIds[0]);

        // ASSERT
        uint256 averageVCsUsedPerDayPerValidator = (stakerRewards.numValidators4() * 4 * 1e18) / stakerRewards.numValidators4();
        uint256 dailyRewardsPer32ETH = (stakerRewards.getAllocatableRewards() / stakerRewards.getCheckpointData().totalVCs) * averageVCsUsedPerDayPerValidator / 1e18;

        assertEq(stakerRewards.getCheckpointData().updateTime, block.timestamp);
        assertEq(stakerRewards.getCheckpointData().daily32EthBaseRewards, dailyRewardsPer32ETH);
    }

    function test_updateUpkeepInterval() public {
        vm.prank(byzantineAdmin);
        stakerRewards.updateUpkeepInterval(100);
        assertEq(stakerRewards.upkeepInterval(), 100);
    }

    function test_updateUpkeepInterval_RevertWhen_calledByNonByzantineAdmin() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        stakerRewards.updateUpkeepInterval(100);
    }

    function test_setForwarderAddress() public {
        address newForwarder = address(1);
        vm.prank(byzantineAdmin);
        stakerRewards.setForwarderAddress(newForwarder);
        assertEq(stakerRewards.forwarderAddress(), newForwarder);
    }

    function test_setForwarderAddress_RevertWhen_calledByNonByzantineAdmin() public {
        address newForwarder = address(1);
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        stakerRewards.setForwarderAddress(newForwarder);
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

    function _getStakedBalanceRate(address _vaultAddr, bytes32 _clusterPubKeyHash) private returns (uint16) {
        // Calculate the pectra ratio and add it up to accruedStakedBalanceRate
        IEigenPod eigenPod = eigenPodManager.ownerToPod(_vaultAddr);
        IEigenPod.ValidatorInfo memory validatorInfo = eigenPod.validatorPubkeyHashToInfo(_clusterPubKeyHash);
        IEigenPod.VALIDATOR_STATUS status = eigenPod.validatorStatus(_clusterPubKeyHash);
        if (status == IEigenPod.VALIDATOR_STATUS.INACTIVE) {
            console.log("validator status: INACTIVE");
        } else if (status == IEigenPod.VALIDATOR_STATUS.ACTIVE) {
            console.log("validator status: ACTIVE");
        } else if (status == IEigenPod.VALIDATOR_STATUS.WITHDRAWN) {
            console.log("validator status: WITHDRAWN");
        }
        
        console.log("validator index", validatorInfo.validatorIndex); // 0
        console.log("validatorInfo.restakedBalanceGwei", validatorInfo.restakedBalanceGwei); // 0
        return uint16((validatorInfo.restakedBalanceGwei * _GWEI_TO_WEI * _STAKED_BALANCE_RATE_SCALE) / 32 ether);
    }

    function _getClusterTotalVCs(bytes32 _clusterId) internal view returns (uint256) {
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(_clusterId);
        uint256 totalVCs = 0;
        for (uint256 i = 0; i < clusterDetails.nodes.length; i++) {
            totalVCs += clusterDetails.nodes[i].currentVCNumber;
        }
        return totalVCs;
    }

    function _getClusterTotalBids(bytes32 _clusterId) internal view returns (uint256) {
        IAuction.ClusterDetails memory clusterDetails = auction.getClusterDetails(_clusterId);
        uint256 totalBids = 0;
        for (uint256 i = 0; i < clusterDetails.nodes.length; i++) {
            totalBids += auction.getBidDetails(clusterDetails.nodes[i].bidId).bidPrice;
        }
        return totalBids;
    }

    /* ===================== MODIFIERS ===================== */

    modifier startAtPresentDay() {
        vm.warp(1727876759);
        _;
    }
}