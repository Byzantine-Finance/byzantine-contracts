// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import "./ByzantineDeployer.t.sol";
import "../src/interfaces/IAuction.sol";
import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";
import "../src/interfaces/IStakerRewards.sol";
import "../src/core/StrategyModule.sol";
import "../src/core/StrategyModuleManager.sol";
import "../src/core/Auction.sol";
import "./utils/ProofParsing.sol";

import {console} from "forge-std/Test.sol";

contract StakerRewardsTest is ProofParsing, ByzantineDeployer {
    /// @notice Random validator deposit data to be able to call `createStratModAndStakeNativeETH` function
    bytes pubkey;
    bytes signature;
    bytes32 depositDataRoot;

    /// @notice Initial balance of all the node operators
    uint256 constant STARTING_BALANCE = 100 ether;
    /// @notice Forwarder address to call performUpkeep
    address forwarder = makeAddr("forwarder");

    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp(); 

        // Set forwarder address
        vm.prank(address(strategyModuleManager));
        stakerRewards.setForwarderAddress(forwarder);

        // Fill the node ops' balance
        for (uint i = 0; i < nodeOps.length; i++) {
            vm.deal(nodeOps[i], STARTING_BALANCE);
        }
        // Fill protagonists' balance
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);

        // For the context of these tests, we assume 8 node operators has pending bids
        _8NodeOpsBid();

        // Get deposit data of a random validator
        _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
    }

    function testReceiveFunction() public {
        vm.prank(alice);
        (bool success, ) = address(stakerRewards).call{value: 2 ether}("");
        require(success);

        assertEq(address(stakerRewards).balance, 2 ether);
    }

    function testUpdateCheckpoint_RevertWhen_CalledByNonStratModManagerOrStakerRewards() public {
        vm.prank(alice);
        vm.expectRevert(IStakerRewards.OnlyStratModManagerOrStakerRewards.selector);
        stakerRewards.updateCheckpoint(700, 4);
    }

    function testUpdateCheckpoint_WhenDVsPrecreatedByStratModManager() public startAtPresentDay {
        // Timestamp starting at 1723067709 

        // ARRANGE
        uint256[8] memory timeInDaysArray = [uint256(999), 900, 800, 700, 600, 500, 400, 300];
        // Calculate the total number of VCs of DVs and the total bid prices paid by the node operators
        (uint256 totalVCsOfDVs, uint256 totalBidPrices) = _calculate8BidPrices(timeInDaysArray);
        // Escrow contract balance before Act
        uint256 escrowBalanceBeforeAct = address(escrow).balance;
        // 5 days later
        vm.warp(block.timestamp + 5 days);
        uint256 dvPrecreationTime = block.timestamp;

        // ACT
        strategyModuleManager.preCreateDVs(2);

        // ASSERT
        // Verify global variables
        assertEq(address(stakerRewards).balance, totalBidPrices);
        assertEq(totalBidPrices, escrowBalanceBeforeAct - address(escrow).balance);
        assertEq(stakerRewards.totalVCs(), totalVCsOfDVs);
        assertEq(stakerRewards.totalActiveDVs(), 0);
        // Verify Checkpoint 
        (uint256 startAt, uint256 dailyRewardsPerDV, uint256 clusterSize) = stakerRewards.getCheckpointData();
        assertEq(startAt, dvPrecreationTime);
        assertEq(clusterSize, 4);
        uint256 dailyRewards = totalBidPrices / totalVCsOfDVs * clusterSize;
        assertEq(dailyRewardsPerDV, dailyRewards);
    }

    function testStrategyModuleDeployed_RevertWhen_CalledByNonStratModManager() public preCreateClusters(1) {
        // ACT
        _createStratModAndStakeNativeETH(alice, 32 ether);

        // ASSERT
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        vm.prank(bob);
        vm.expectRevert(IStakerRewards.OnlyStrategyModuleManager.selector);
        stakerRewards.strategyModuleDeployed(aliceStratModAddr, 700, 3000, 4);
    }

    function testStrategyModuleDeployed_RevertWhen_StrategyModuleAlreadyExists() public preCreateClusters(1) {
        // ACT
        _createStratModAndStakeNativeETH(alice, 32 ether);    

        // ASSERT
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        vm.prank(address(strategyModuleManager));
        vm.expectRevert(bytes("Strategy module already deployed"));
        stakerRewards.strategyModuleDeployed(aliceStratModAddr, 700, 3000, 4);
    }

    function testStrategyModuleDeployed_WhenTwoStakersJoinedWithCreationOfNewDVs() public startAtPresentDay preCreateClusters(2) {
        // Timestamp starting at 1723067709
        // (checkpoint 1) Byzantine pre-create the first 2 DVs    

        // ARRANGE
        // Node operators bid again
        _8NodeOpsBid();
        uint256[4] memory timeInDaysArrayDV1 = [uint256(999), 900, 800, 700];
        uint256[4] memory timeInDaysArrayDV2 = [uint256(600), 500, 400, 300];
        uint256[4] memory timeInDaysArrayDV3 = [uint256(999), 900, 800, 700];
        (uint256 totalVCsOfDV1, uint256 totalBidPricesDV1) = _calculate4BidPrices(timeInDaysArrayDV1);
        (uint256 totalVCsOfDV2, uint256 totalBidPricesDV2) = _calculate4BidPrices(timeInDaysArrayDV2);
        (uint256 totalVCsOfDV3, uint256 totalBidPricesDV3) = _calculate4BidPrices(timeInDaysArrayDV3);
        // 10 days later
        vm.warp(block.timestamp + 10 days);
        uint256 aliceJoiningTime = block.timestamp;

        // ACT
        // (checkpoint 2) Alice deploys a strategy module using DV1 and precreate a new DV3
        _createStratModAndStakeNativeETH(alice, 32 ether);   

        // ASSERT
        // Alice is the first staker so no VCs consumed before and no rewards distributed yet
        // Verify global variables
        assertEq(stakerRewards.totalActiveDVs(), 1);
        assertEq(stakerRewards.totalVCs(), totalVCsOfDV1 + totalVCsOfDV2 + totalVCsOfDV3);
        assertEq(stakerRewards.totalNotYetClaimedRewards(), 0);
        assertEq(address(stakerRewards).balance, totalBidPricesDV1 + totalBidPricesDV2 + totalBidPricesDV3);
        // Verify checkpoint
        (uint256 startAtCP2, uint256 dailyRewardsPerDvCP2, uint256 clusterSize) = stakerRewards.getCheckpointData();
        assertEq(startAtCP2, aliceJoiningTime);
        assertEq(clusterSize, 4);
        uint256 dailyRewardsCP2 = address(stakerRewards).balance / (totalVCsOfDV1 + totalVCsOfDV2 + totalVCsOfDV3) * clusterSize;
        assertEq(dailyRewardsPerDvCP2, dailyRewardsCP2);
        // Verify Alice strategy module struct
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        (uint256 lastUpdateTime, uint256 smallestVCNumber, uint256 exitTimestamp, , uint256 claimPermission) = stakerRewards.getStratModData(aliceStratModAddr);
        assertEq(lastUpdateTime, aliceJoiningTime);
        assertEq(smallestVCNumber, 700);
        uint256 exitTime = aliceJoiningTime + 700 * 1 days;
        assertEq(exitTimestamp, exitTime);
        assertEq(claimPermission, 1);

        // ARRANGE
        uint256[4] memory timeInDaysArrayDV4 = [uint256(600), 500, 400, 300];
        (uint256 totalVCsOfDV4, uint256 totalBidPricesDV4) = _calculate4BidPrices(timeInDaysArrayDV4);
        // 20 days later
        vm.warp(block.timestamp + 20 days);
        uint256 bobJoiningTime = block.timestamp;
        uint256 aliceConsumedVCs = 20 * clusterSize;
        (, uint256 dailyRewardsPerDvAtCP2, ) = stakerRewards.getCheckpointData();
        uint256 distributedRewardsToAlice = dailyRewardsPerDvAtCP2 * 20 * stakerRewards.totalActiveDVs();
        uint256 totalVCsBeforeBobJoins = stakerRewards.totalVCs();
        uint256 totalBidPricesBeforeBobJoins = address(stakerRewards).balance;

        // ACT
        // (checkpoint 3) Bob deploys a strategy module using DV2 and precreates DV4
        _createStratModAndStakeNativeETH(bob, 32 ether);

        // ASSERT
        // Bob is the second staker so some of Alice's stratMod VCs have consumed since the last checkpoint
        // Verify global variables    
        assertEq(stakerRewards.totalActiveDVs(), 2);
        assertEq(stakerRewards.totalVCs(), totalVCsBeforeBobJoins + totalVCsOfDV4 - aliceConsumedVCs);
        assertEq(stakerRewards.totalNotYetClaimedRewards(), distributedRewardsToAlice);
        assertEq(address(stakerRewards).balance, totalBidPricesBeforeBobJoins + totalBidPricesDV4);
        // Verify checkpoint
        (uint256 startAtCP3, uint256 dailyRewardsPerDvCP3, ) = stakerRewards.getCheckpointData();
        assertEq(startAtCP3, bobJoiningTime);
        assertEq(stakerRewards.totalNotYetClaimedRewards(), distributedRewardsToAlice);
        uint256 totalAllocatableRewards = address(stakerRewards).balance - distributedRewardsToAlice;
        uint256 dailyRewardsCP3 = totalAllocatableRewards / stakerRewards.totalVCs() * 4;
        assertEq(dailyRewardsPerDvCP3, dailyRewardsCP3);
    }

    function testStrategyModuleDeployed_WhenSecondStratModDeployedWithoutDvPrecreated() public startAtPresentDay preCreateClusters(1) {
        // Timestamp starting at 1723067709
        // (checkpoint 1) Byzantine pre-create the first 1 DV 

        // ARRANGE
        // 10 days later
        vm.warp(block.timestamp + 10 days);
        // (checkpoint 2) Alice deploys a strategy module using DV1 and precreate a new DV2
        _createStratModAndStakeNativeETH(alice, 32 ether);   

        // 20 days later
        vm.warp(block.timestamp + 20 days);
        (, uint256 dailyRewardsPerDvCP2, ) = stakerRewards.getCheckpointData();
        uint256 aliceConsumedVCs = 20 * 4;
        uint256 distributedRewardsToAlice = dailyRewardsPerDvCP2 * 20 * stakerRewards.totalActiveDVs();
        uint256 totalVCsBeforeBobJoins = stakerRewards.totalVCs();
        uint256 totalBidPricesBeforeBobJoins = address(stakerRewards).balance;

        // ACT
        // (checkpoint 3) Bob deploys a strategy module using DV2 and does not precreate a new DV
        _createStratModAndStakeNativeETH(bob, 32 ether);    

        // ASSERT
        // Verify global variables
        assertEq(stakerRewards.totalVCs(), totalVCsBeforeBobJoins - aliceConsumedVCs);
        assertEq(address(stakerRewards).balance, totalBidPricesBeforeBobJoins);
        // Verify checkpoint
        (, uint256 dailyRewardsPerDvCP3, ) = stakerRewards.getCheckpointData();
        uint256 totalAllocatableRewards = address(stakerRewards).balance - distributedRewardsToAlice;
        uint256 dailyRewardsCP3 = totalAllocatableRewards / stakerRewards.totalVCs() * 4;
        assertEq(dailyRewardsPerDvCP3, dailyRewardsCP3);
    }

    function testCheckUpkeepReturnsFalse_IfNoStratModsHaveConsumedAllVCs() public startAtPresentDay preCreateClusters(1) {
        // The smallest VC number is 700
        // ARRANGE
        _createStratModAndStakeNativeETH(alice, 32 ether);   
        // 100 days later
        vm.warp(block.timestamp + 100 days);

        // Act
        (bool upkeepNeeded,) = stakerRewards.checkUpkeep("");
    
        // Assert
        assert(!upkeepNeeded);

        // Check performUpkeep revert if upkeepNeeded is false  
        vm.prank(forwarder);
        vm.expectRevert(IStakerRewards.UpkeepNotNeeded.selector);
        stakerRewards.performUpkeep("");
    }

    function testCheckUpkeepReturnsTrue_IfAStratModsHasConsumedAllVCs() public startAtPresentDay preCreateClusters(2) {
        // The smallest VC number is 300 for Bob

        // ARRANGE
        vm.warp(block.timestamp + 1 hours);
        _createStratModAndStakeNativeETH(alice, 32 ether);   
        vm.warp(block.timestamp + 1 hours);
        address bobStratModAddr = _createStratModAndStakeNativeETH(bob, 32 ether);   

        // 300 days and 1 second later
        vm.warp(block.timestamp + 300 days + 1);

        // Act
        (bool firstUpkeepNeeded, bytes memory firstPerformData) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(firstPerformData);
    
        // Assert
        (, , , , uint256 claimPermission) = stakerRewards.getStratModData(bobStratModAddr);
        assert(firstUpkeepNeeded);
        assertEq(stakerRewards.totalActiveDVs(), 1);
        assertEq(claimPermission, 2);

        // 100 days later, try to call another checkUpkeep
        vm.warp(block.timestamp + 100 days);
        (bool secondUpkeepNeeded,) = stakerRewards.checkUpkeep("");
        assert(!secondUpkeepNeeded);
    }

    function testCheckUpkeep_RevertWhen_CalledWithinTheUpkeepIntervalTimeline() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        // Alice deploys a strategy module 
        _createStratModAndStakeNativeETH(alice, 32 ether);
        /// 700 days and 1 second later: performUpkeep is called
        vm.warp(block.timestamp + 700 days + 1);
        // Manually call checkUpkeep and performUpkeep
        (, bytes memory performDataUpkeep1) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performDataUpkeep1);
        assertEq(stakerRewards.lastUpkeepTimestamp(), block.timestamp);

        // 30 seconds later
        vm.warp(block.timestamp + 30 seconds);
        assertLt(block.timestamp - stakerRewards.lastUpkeepTimestamp(), stakerRewards.upkeepInterval());
        vm.expectRevert(IStakerRewards.UpkeepNotNeeded.selector);
        stakerRewards.checkUpkeep("");
    }

    function testCheckUpkeep_RevertWhen_ThereIsNoStratMods() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        // 10 dayss later
        vm.warp(block.timestamp + 10 days);
        // Manually call checkUpkeep
        vm.expectRevert(IStakerRewards.UpkeepNotNeeded.selector);
        stakerRewards.checkUpkeep("");
    }

    function testPerformUpkeep_RevertWhen_NotCalledByForwarder() public startAtPresentDay preCreateClusters(2) {
        // ARRANGE
        _createStratModAndStakeNativeETH(alice, 32 ether);
        // 700 days and 1 second later: performUpkeep is called
        vm.warp(block.timestamp + 700 days + 1);
        // Manually call checkUpkeep 
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);

        // ASSERT
        vm.prank(address(strategyModuleManager));
        vm.expectRevert(IStakerRewards.NoPermissionToCallPerformUpkeep.selector);
        stakerRewards.performUpkeep(performData);
    }

    function testPerformUpkeep_PerformDataSentCorrectlyFromCheckUpkeepToPerformUpkeep() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        // Alice deploys a strategy module
        address aliceStratMod = _createStratModAndStakeNativeETH(alice, 32 ether); 
        // 700 days and 1 second later: first checkUpkeep returns true for bob's stratMod
        vm.warp(block.timestamp + 700 days + 1);
        (, bytes memory performData) = stakerRewards.checkUpkeep("");

        // ACT
        // Manually call the second performUpkeep
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // ASSERT
        (address[] memory stratModAddresses, uint256[] memory stratModTotalVCs) = abi.decode(performData, (address[], uint256[]));
        assertEq(stratModAddresses.length, 1);
        assertEq(stratModAddresses[0], aliceStratMod);
        assertEq(stratModTotalVCs[0], 3399);
    }

    function testPerformUpkeep_UpdatesTwoStratModVCsAndCheckpoint() public startAtPresentDay preCreateClusters(2) {
        // ARRANGE
        // Node operators bid again and Byzantine precreates two new DVs
        _8NodeOpsBid(); 
        strategyModuleManager.preCreateDVs(2);
        // 1 hour later Alice deploys a strategy module (DV1)
        vm.warp(block.timestamp + 1 hours);
        _createStratModAndStakeNativeETH(alice, 32 ether); // smallestVCs 700
        // 1 hour later Bob deploys a strategy module (DV2)
        vm.warp(block.timestamp + 1 hours);
        address bobStratMod = _createStratModAndStakeNativeETH(bob, 32 ether); // smallestVCs 300
        // 1 hour later Tom deploys a strategy module (DV3)
        vm.warp(block.timestamp + 1 hours);
        address tom = makeAddr("tom"); //0x7dF912D1e8D5267061d0385D4b0F79CdEB18BcD8
        vm.deal(tom, 32 ether);
        _createStratModAndStakeNativeETH(tom, 32 ether); // smallestVCs 700

        // 300 days and 1 second later: first checkUpkeep returns true for bob's stratMod
        vm.warp(block.timestamp + 300 days + 1);
        (, bytes memory firstPerformData) = stakerRewards.checkUpkeep("");
        (, uint256[] memory stratModTotalVCsUpkeep1) = abi.decode(firstPerformData, (address[], uint256[]));

        uint256 totalVCsBeforeUpkeep1 = stakerRewards.totalVCs();
        (, uint256 bobSmallestVCNumber, , , ) = stakerRewards.getStratModData(bobStratMod);
        uint256 remainingVCsToSubtractForBob = stratModTotalVCsUpkeep1[0] - bobSmallestVCNumber * 4;
        uint256 consumedVCsUpkeep1 = 300 * 4 * stakerRewards.totalActiveDVs();

        // Manually call the first performUpkeep 
        vm.prank(forwarder);
        stakerRewards.performUpkeep(firstPerformData);

        // 400 days and 1 second later: second checkUpkeep returns true for alice and tom's stratMods
        vm.warp(block.timestamp + 400 days + 1);
        (, bytes memory secondPerformData) = stakerRewards.checkUpkeep("");
        (, uint256[] memory stratModTotalVCsUpkeep2) = abi.decode(secondPerformData, (address[], uint256[]));

        address aliceStratMod = strategyModuleManager.getStratMods(alice)[0];
        uint256 totalVCsAfterFirstUpkeep = totalVCsBeforeUpkeep1 - consumedVCsUpkeep1 - remainingVCsToSubtractForBob;
        (uint256 lastUpdateTime, uint256 aliceSmallestVCNumber, uint256 exitTimestamp, , ) = stakerRewards.getStratModData(aliceStratMod);
        uint256 consumedVCsUpkeep2 = 400 * 4 * stakerRewards.totalActiveDVs();
        uint256 remainingVCsToSubtractForAliceTom = (stratModTotalVCsUpkeep2[0] - aliceSmallestVCNumber * 4) * 2;
        (uint256 startAtBefore, uint256 dailyRewardsPerDVBeforeUpkeep2, ) = stakerRewards.getCheckpointData();
        uint256 rewardsToClaimAtExit = dailyRewardsPerDVBeforeUpkeep2 * ((exitTimestamp - lastUpdateTime) / 1 days);

        // ACT
        // Manually call the second performUpkeep
        vm.prank(forwarder);
        stakerRewards.performUpkeep(secondPerformData);

        // ASSERT
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        address tomStratMod = strategyModuleManager.getStratMods(0x7dF912D1e8D5267061d0385D4b0F79CdEB18BcD8)[0];
        uint256 totalVCsAfterSecondUpkeep = totalVCsAfterFirstUpkeep - consumedVCsUpkeep2 - remainingVCsToSubtractForAliceTom;
        (, , , uint256 remainingRewardsAtExit, uint256 claimPermission) = stakerRewards.getStratModData(aliceStratModAddr);
        (uint256 startAtAfter, uint256 dailyRewardsPerDVAfterUpkeep2, ) = stakerRewards.getCheckpointData();

        // Verify if node operators' VCs have been correctly subtracted 
        IStrategyModule.Node[4] memory tomNodes = IStrategyModule(tomStratMod).getDVNodesDetails();
        IStrategyModule.Node[4] memory aliceNodes = IStrategyModule(aliceStratModAddr).getDVNodesDetails();
        StrategyModule.DVStatus aliceStratModStatus = IStrategyModule(aliceStratModAddr).getDVStatus();
        assertEq(aliceNodes[0].vcNumber, 299);
        assertEq(aliceNodes[1].vcNumber, 200);
        assertEq(aliceNodes[2].vcNumber, 100);
        assertEq(aliceNodes[3].vcNumber, 0);
        assertEq(tomNodes[0].vcNumber, 299);
        assertEq(tomNodes[1].vcNumber, 200);
        assertEq(tomNodes[2].vcNumber, 100);
        assertEq(tomNodes[3].vcNumber, 0);      
        assertEq(uint(aliceStratModStatus), uint(IStrategyModule.DVStatus.EXITED));

        // Verify global variables
        assertEq(stakerRewards.totalActiveDVs(), 0);
        assertEq(stakerRewards.totalVCs(), totalVCsAfterSecondUpkeep);
        // // Verify stratMod data
        assertEq(claimPermission, 2);
        assertEq(remainingRewardsAtExit, rewardsToClaimAtExit);
        // Verify checkpoint data => as totalActiveDVs = 0, so Checkpoint not updated
        assertEq(startAtBefore, startAtAfter); 
        assertEq(dailyRewardsPerDVAfterUpkeep2, dailyRewardsPerDVBeforeUpkeep2); 

        // TODO: send the remaining bid prices back to Escrow and test 
    }

    function testCalculateRewards_RevertWhen_CalledByNonStratModOwner() public preCreateClusters(1) {
        // ARRANGE
        address stratMod = _createStratModAndStakeNativeETH(alice, 32 ether);   
        // 100 days later
        vm.warp(block.timestamp + 100 days);

        vm.prank(bob);
        vm.expectRevert(IStakerRewards.NotStratModOwner.selector); 
        stakerRewards.calculateRewards(stratMod);
    }

    function testCalculateRewards_RevertWhen_AllRewardsHaveBeenClaimed() public preCreateClusters(1) {
        // ARRANGE
        address stratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        (, , uint256 exitTimestamp, , ) = stakerRewards.getStratModData(stratMod);

        // 700 days and 1 second later
        vm.warp(block.timestamp + 700 days + 1);
        // Manually call the checkUpkeep and performUpkeep
        (, bytes memory performUpkeep) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performUpkeep);
        (, , , , uint256 claimPermissionBeforeClaim) = stakerRewards.getStratModData(stratMod);

        // 100 days later, Alice claims her rewards
        vm.warp(block.timestamp + 100 days);

        // ACT
        vm.prank(alice);
        stakerRewards.claimRewards(stratMod);

        // ASSERT
        (, , , , uint256 claimPermissionAfterClaim) = stakerRewards.getStratModData(stratMod);

        assertGt(block.timestamp, exitTimestamp);
        assertEq(claimPermissionBeforeClaim, 2);
        assertEq(claimPermissionAfterClaim, 3);

        // 100 days later
        vm.warp(block.timestamp + 100 days);
        
        // ACT AND ASSERT
        // Alice tries to calculate her rewards again
        vm.prank(alice);
        vm.expectRevert(IStakerRewards.AllRewardsHaveBeenClaimed.selector);
        stakerRewards.calculateRewards(stratMod); 
    }

    function testCalculateRewards_RevertWhen_CalledAfterExitTimestampClaimPermissionIsNot2() public preCreateClusters(1) {
        // ARRANGE
        address stratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        (, , uint256 exitTimestamp, , ) = stakerRewards.getStratModData(stratMod);
        // Upkeep failed to be called and/or performed

        // 800 days later
        vm.warp(block.timestamp + 800 days);
        vm.prank(alice);
        vm.expectRevert(bytes("Error regarding claim permission: please contact the team."));
        stakerRewards.calculateRewards(stratMod);
    }

    function testCalculateRewards_WhenCheckRewardsBeforeExitTimestamp() public startAtPresentDay preCreateClusters(2) {
        // ARRANGE
        address aliceStratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);
        (uint256 lastUpdateTime, , , , uint256 claimPermission) = stakerRewards.getStratModData(aliceStratModAddr);
        // 100 days later
        vm.warp(block.timestamp + 100 days);
        uint256 After100Days = block.timestamp;
        (, uint256 dailyRewardsPerDV, ) = stakerRewards.getCheckpointData();

        // ACT
        // Alice claims her rewards before exitTimestamp
        vm.prank(alice);
        uint256 calculatedRewards = stakerRewards.calculateRewards(aliceStratModAddr);

        // ASSERT
        uint256 elapsedDays = (After100Days - lastUpdateTime) / 1 days;
        uint256 rewards = dailyRewardsPerDV * elapsedDays;
        assertEq(claimPermission, 1);
        assertEq(calculatedRewards, rewards);
    }

    function testCalculateRewards_WhenCheckRewardsAfterExitTimestamp() public startAtPresentDay preCreateClusters(2) {
        // ARRANGE
        address aliceStratModAddr = _createStratModAndStakeNativeETH(alice, 32 ether);
        (, uint256 smallestVCNumber, uint256 exitTimestamp, , ) = stakerRewards.getStratModData(aliceStratModAddr);

        // 700 days and 1 second later: performUpkeep is called
        vm.warp(block.timestamp + 700 days + 1);
        assertGt(block.timestamp, exitTimestamp);

        // Manually call checkUpkeep and performUpkeep
        (bool upkeepNeeded, bytes memory performData) = stakerRewards.checkUpkeep("");
        assert(upkeepNeeded);
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);

        // 800 days later
        vm.warp(block.timestamp + 800 days);

        // ACT
        // Alice claims her rewards after exitTimestamp
        vm.prank(alice);
        uint256 calculatedRewards = stakerRewards.calculateRewards(aliceStratModAddr);

        // ASSERT
        (, , , uint256 remainingRewardsAtExit, uint256 claimPermission) = stakerRewards.getStratModData(aliceStratModAddr);
        assertEq(smallestVCNumber, 700);
        assertEq(claimPermission, 2);
        assertEq(calculatedRewards, remainingRewardsAtExit);
    }

    function testClaimRewards_RevertWhen_CalledByNonStratModOwner() public preCreateClusters(1) {
        // ARRANGE
        address stratMod = _createStratModAndStakeNativeETH(alice, 32 ether);   
        // 100 days later
        vm.warp(block.timestamp + 100 days);

        vm.prank(bob);
        vm.expectRevert(IStakerRewards.NotStratModOwner.selector);
        stakerRewards.claimRewards(stratMod);
    }

    function testClaimRewards_RevertWhen_WhenTwoClaimsWithinLessThan4Days() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        address aliceStratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        // 100 days later
        vm.warp(block.timestamp + 100 days);
        // Alice claims her rewards
        vm.prank(alice);
        stakerRewards.claimRewards(aliceStratMod);
        // 3 days later
        vm.warp(block.timestamp + 3 days);
        // Alice claims her rewards again
        vm.prank(alice);
        vm.expectRevert(bytes("Claim interval or joining time less than 4 days"));
        stakerRewards.claimRewards(aliceStratMod);
    }

    function testClaimRewards_StakerBalanceIncreasedAfterClaimRewards() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        // Alice stakes 32 ETH
        address aliceStratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        // Alice balance before claim
        uint256 aliceBalanceBeforeClaim = alice.balance;
        // 400 days later
        vm.warp(block.timestamp + 400 days);
        // // At least one checkUpkeep is called
        // stakerRewards.checkUpkeep("");
        // Calculated rewards
        vm.prank(alice);
        uint256 calculatedRewards =  stakerRewards.calculateRewards(aliceStratMod);

        // ACT
        vm.prank(alice);
        stakerRewards.claimRewards(aliceStratMod);

        // ASSERT
        (, , , uint256 remainingRewardsAtExit, uint256 claimPermission) = stakerRewards.getStratModData(aliceStratMod);
        assertEq(claimPermission, 1);
        assertEq(remainingRewardsAtExit, 0);
        assertEq(calculatedRewards, alice.balance - aliceBalanceBeforeClaim);
        assertEq(alice.balance, aliceBalanceBeforeClaim + calculatedRewards);
    }

    function testClaimRewards_CorrectlyUpdatesVariablesAndCheckpointAfterClaim() public startAtPresentDay preCreateClusters(1) {
        // ARRANGE
        // (checkpoint 1) Alice stake 32 ETH
        address aliceStratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        uint256 totalVCsBeforeAliceClaim = stakerRewards.totalVCs();
        uint256 aliceConsumedVCs = 400 * 4;
        (, uint256 dailyRewardsPerDVCheckpoint1, uint256 clusterSize) = stakerRewards.getCheckpointData();
        uint256 distributedRewardsToAlice = dailyRewardsPerDVCheckpoint1 * 400;
        uint256 allocatableRewardsCheckpoint2 = address(stakerRewards).balance - distributedRewardsToAlice;
        uint256 calculatedDailyRewardsPerDVCheckpoint2 = allocatableRewardsCheckpoint2 / (totalVCsBeforeAliceClaim - aliceConsumedVCs) * clusterSize;

        // 400 days later
        vm.warp(block.timestamp + 400 days);
        uint256 aliceClaimTime = block.timestamp;

        // ACT
        // (checkpoint 2) Alice claims her rewards
        vm.prank(alice);
        stakerRewards.claimRewards(aliceStratMod);

        // ASSERT
        // There is only Alice's strategy module 
        // Verify global variables
        assertEq(stakerRewards.totalVCs(), totalVCsBeforeAliceClaim - aliceConsumedVCs);
        assertEq(stakerRewards.totalNotYetClaimedRewards(), 0);
        // Verify checkpoint data
        (uint256 startAtCheckpoint2, uint256 dailyRewardsPerDVAfterCheckpoint2, ) = stakerRewards.getCheckpointData();
        assertEq(startAtCheckpoint2, aliceClaimTime);
        assertEq(dailyRewardsPerDVAfterCheckpoint2, calculatedDailyRewardsPerDVCheckpoint2);
        // Verify Alice's strategy module data
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        (uint256 lastUpdateTime, , , , uint256 claimPermission) = stakerRewards.getStratModData(aliceStratModAddr);
        assertEq(lastUpdateTime, aliceClaimTime);
        assertEq(claimPermission, 1);
    }

    function testClaimRewards_AfterExitTimestamp() startAtPresentDay preCreateClusters(2) public {
        // ARRANGE
        uint256[4] memory timeInDaysArrayDV1 = [uint256(999), 900, 800, 700];
        (uint256 totalVCsOfDV1, uint256 totalBidPricesDV1) = _calculate4BidPrices(timeInDaysArrayDV1);

        // Alice deploys a strategy module (DV1)
        address aliceStratMod = _createStratModAndStakeNativeETH(alice, 32 ether);
        (, uint256 dailyRewardsPerDVBeforeUpkeep, ) = stakerRewards.getCheckpointData();

        // 700 days and 1 second later
        vm.warp(block.timestamp + 700 days + 1);
        // Manually calls checkUpkeep and performUpkeep
        (, bytes memory performData) = stakerRewards.checkUpkeep("");
        vm.prank(forwarder);
        stakerRewards.performUpkeep(performData);
        // TODO: send bid prices back to Escrow. Simulate manually the transfer for now
        uint256 dv1RemainingBidPricesAfterUpkeep = totalBidPricesDV1 - dailyRewardsPerDVBeforeUpkeep * 700; 
        vm.prank(address(stakerRewards));
        (bool success, ) = address(escrow).call{value: dv1RemainingBidPricesAfterUpkeep}("");
        require(success, "Fail to transfer the bid prices.");

        (, , , uint256 remainingRewardsAtExit, uint256 claimPermissionBeforeClaim) = stakerRewards.getStratModData(aliceStratMod);
        uint256 aliceBalanceBeforeClaim = alice.balance;
        assertEq(claimPermissionBeforeClaim, 2);

        // ACT
        // 100 days later, Alice claims her rewards
        vm.warp(block.timestamp + 100 days);
        vm.prank(alice);
        stakerRewards.claimRewards(aliceStratMod);

        // ASSERT
        uint256[4] memory timeInDaysArrayDV2 = [uint256(600), 500, 400, 300];
        (uint256 totalVCsOfDV2, uint256 totalBidPricesDV2) = _calculate4BidPrices(timeInDaysArrayDV2);
        address aliceStratModAddr = strategyModuleManager.getStratMods(alice)[0];
        (, , , , uint256 claimPermissionAfterClaim) = stakerRewards.getStratModData(aliceStratModAddr);

        assertEq(stakerRewards.totalNotYetClaimedRewards(), 0);
        assertEq(address(stakerRewards).balance, totalBidPricesDV2);
        assertEq(stakerRewards.totalVCs(), totalVCsOfDV2);
        assertEq(alice.balance, aliceBalanceBeforeClaim + remainingRewardsAtExit);
        assertEq(claimPermissionAfterClaim, 3);
    }

    function testUpdateUpkeepInterval() public {
        vm.prank(address(strategyModuleManager));
        stakerRewards.updateUpkeepInterval(100);
        assertEq(stakerRewards.upkeepInterval(), 100);
    }

    function testUpdateClaimInterval() public {
        vm.prank(address(strategyModuleManager));
        stakerRewards.updateClaimInterval(7);
        assertEq(stakerRewards.claimInterval(), 7);
    }

    //--------------------------------------------------------------------------------------
    //------------------------------  INTERNAL FUNCTIONS  ----------------------------------
    //--------------------------------------------------------------------------------------

    function _createStratModAndStakeNativeETH(address _staker, uint256 _stake) internal returns (address) {
        vm.prank(_staker);
        strategyModuleManager.createStratModAndStakeNativeETH{value: _stake}(pubkey, signature, depositDataRoot);
        uint256 stratModNumber = strategyModuleManager.getStratModNumber(_staker);
        if (stratModNumber == 0) {
            return address(0);
        }
        return strategyModuleManager.getStratMods(_staker)[stratModNumber - 1];
    }

    function _getDepositData(
        bytes memory depositFilePath
    ) internal {
        // File generated with the Obol LaunchPad
        setJSON(string(depositFilePath));

        pubkey = getDVPubKeyDeposit();
        signature = getDVSignature();
        depositDataRoot = getDVDepositDataRoot();
    }

    function _createOneBidParamArray(
        uint256 _discountRate,
        uint256 _timeInDays
    ) internal pure returns (uint256[] memory, uint256[] memory) {
        uint256[] memory discountRateArray = new uint256[](1);
        discountRateArray[0] = _discountRate;

        uint256[] memory timeInDaysArray = new uint256[](1);
        timeInDaysArray[0] = _timeInDays;
        
        return (discountRateArray, timeInDaysArray);
    }

    function _nodeOpsBid(
        NodeOpBid[] memory nodeOpsBids
    ) internal returns (uint256[][] memory) {
        uint256[][] memory nodeOpsAuctionScores = new uint256[][](nodeOpsBids.length);
        for (uint i = 0; i < nodeOpsBids.length; i++) {
            nodeOpsAuctionScores[i] = _nodeOpBid(nodeOpsBids[i]);
        }
        return nodeOpsAuctionScores;
    }

    function _nodeOpBid(
        NodeOpBid memory nodeOpBid
    ) internal returns (uint256[] memory) {
        // Get price to pay
        uint256 priceToPay = auction.getPriceToPay(nodeOpBid.nodeOp, nodeOpBid.discountRates, nodeOpBid.timesInDays);
        vm.prank(nodeOpBid.nodeOp);
        return auction.bid{value: priceToPay}(nodeOpBid.discountRates, nodeOpBid.timesInDays);
    }

    function _8NodeOpsBid() internal {
        (uint256[] memory DR0, uint256[] memory time0) = _createOneBidParamArray(13e2, 999);  // 1st
        (, uint256[] memory time1) = _createOneBidParamArray(13e2, 900);  // 2nd
        (, uint256[] memory time2) = _createOneBidParamArray(13e2, 800);  // 3rd
        (, uint256[] memory time3) = _createOneBidParamArray(13e2, 700);  // 4th
        (, uint256[] memory time4) = _createOneBidParamArray(13e2, 600);  // 5th
        (, uint256[] memory time5) = _createOneBidParamArray(13e2, 500);  // 6th
        (, uint256[] memory time6) = _createOneBidParamArray(13e2, 400);  // 7th
        (, uint256[] memory time7) = _createOneBidParamArray(13e2, 300);  // 8th

        NodeOpBid[] memory nodeOpBids = new NodeOpBid[](8);
        nodeOpBids[0] = NodeOpBid(nodeOps[0], DR0, time0);
        nodeOpBids[1] = NodeOpBid(nodeOps[1], DR0, time1); 
        nodeOpBids[2] = NodeOpBid(nodeOps[2], DR0, time2); 
        nodeOpBids[3] = NodeOpBid(nodeOps[3], DR0, time3);
        nodeOpBids[4] = NodeOpBid(nodeOps[4], DR0, time4);
        nodeOpBids[5] = NodeOpBid(nodeOps[5], DR0, time5);
        nodeOpBids[6] = NodeOpBid(nodeOps[6], DR0, time6);
        nodeOpBids[7] = NodeOpBid(nodeOps[7], DR0, time7);
        _nodeOpsBid(nodeOpBids);
    }

    function _calculate8BidPrices(
        uint256[8] memory _timeInDaysArray
    ) internal pure returns (uint256, uint256) {
        uint256 dayilyVCPrice = (uint(3243835616438356) * (10000 - 13e2)) / (4 * 10000);
        uint256 totalVCsOfDVs;
        uint256 totalBidPrices;
        for(uint8 i; i < _timeInDaysArray.length;) {
            totalVCsOfDVs += _timeInDaysArray[i];
            totalBidPrices += _timeInDaysArray[i] * dayilyVCPrice;

            unchecked {
                ++i;
            }
        }
        return (totalVCsOfDVs, totalBidPrices);
    }

    function _calculate4BidPrices(
        uint256[4] memory _timeInDaysArray
    ) internal pure returns (uint256, uint256) {
        uint256 dayilyVCPrice = (uint(3243835616438356) * (10000 - 13e2)) / (4 * 10000);
        uint256 totalVCsOfDVs;
        uint256 totalBidPrices;
        for(uint8 i; i < _timeInDaysArray.length;) {
            totalVCsOfDVs += _timeInDaysArray[i];
            totalBidPrices += _timeInDaysArray[i] * dayilyVCPrice;

            unchecked {
                ++i;
            }
        }
        return (totalVCsOfDVs, totalBidPrices);
    }

    /* ===================== MODIFIERS ===================== */

    modifier preCreateClusters(uint8 _numDVsToPreCreate) {
        strategyModuleManager.preCreateDVs(_numDVsToPreCreate);
        _;
    }

    modifier startAtPresentDay() {
        vm.warp(1723067709);
        _;
    }
}

