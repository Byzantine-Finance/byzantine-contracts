// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {Test, console} from "forge-std/Test.sol";
import {StratModManagerMock} from "./mocks/StratModManagerMock.sol";
import {StakerRewardsMock} from "./mocks/StakerRewardsMock.sol";
import {StrategyModuleMock} from "./mocks/StrategyModuleMock.sol";
import {Deploy_Sepolia_For_Testing_Chainlink} from "../script/deploy/sepolia/Deploy_Sepolia_For_Testing_Chainlink.s.sol";   

contract StakerRewardsMockTest is Test {
    StratModManagerMock stratModManagerMock;
    StakerRewardsMock stakerRewardsMock;

    uint256 SEND_VALUE = 100 ether;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 interval = 60; // For test purpose

    function setUp() external {
        stratModManagerMock = new StratModManagerMock();
        stakerRewardsMock = new StakerRewardsMock(stratModManagerMock, interval);
        stratModManagerMock.setStakerRewardsMock(stakerRewardsMock);
        require(address(stratModManagerMock.stakerRewardsMock()) == address(stakerRewardsMock), "StakerRewardsMock address is not set correctly");

        vm.deal(alice, SEND_VALUE);
        vm.deal(bob, SEND_VALUE);
        vm.deal(address(stratModManagerMock), SEND_VALUE);
    }

    function testPrecreateDVAndCreateStrategyModules_WorkCorrectly() public {
        // Starting timestamp is 1

        // Checkpoint 1: Precreate a DV
        stratModManagerMock.precreateDV(700, 4, 1250000000000000000);

        assertEq(address(stakerRewardsMock).balance, 1250000000000000000);
        assertEq(stakerRewardsMock.totalVCs(), 700);
        (uint256 startAt, uint256 dailyRewardsPerDV, ) = stakerRewardsMock.checkpoint();
        assertEq(startAt, 1);
        assertEq(dailyRewardsPerDV, 7142857142857140);

        // Checkpoint 2: 10 days later, Alice creates a DV and deploys a strategy module using this DV
        vm.warp(block.timestamp + 10);
        uint256 plus10Days = block.timestamp;

        vm.prank(alice);
        stratModManagerMock.createStrategyModules(100, 200, 300, 400, 3 ether);
        assertEq(stratModManagerMock.numStratMods(), 1);
        address stratModAddr = stratModManagerMock.getStratMods(alice)[0];
        uint256 tokenId = uint256(keccak256(abi.encode(0)));
        assertEq(stratModManagerMock.getStratModByNftId(tokenId), stratModAddr);

        StrategyModuleMock.Node[4] memory nodes = StrategyModuleMock(stratModAddr).getDVNodesDetails();
        assertEq(nodes[0].vcNumber, 100);
        assertEq(nodes[1].vcNumber, 200);
        assertEq(nodes[2].vcNumber, 300);
        assertEq(nodes[3].vcNumber, 400);

        // no VCs have been consumed yet
        assertEq(address(stakerRewardsMock).balance, 4250000000000000000);
        assertEq(stakerRewardsMock.totalVCs(), 1700);
        (uint256 lastUpdateTime, uint256 smallestVCNumber, uint256 exitTimestamp, , ) = stakerRewardsMock.getStratModData(stratModAddr);
        assertEq(lastUpdateTime, 11);
        assertEq(smallestVCNumber, 100);
        assertEq(exitTimestamp, plus10Days + 100);

        (, uint256 dailyRewardsPerDV1, ) = stakerRewardsMock.checkpoint();
        assertEq(dailyRewardsPerDV1, 10000000000000000);

        // Checkpoint 3: 50 days later, Bob creates a DV and deploys a strategy module using this DV
        vm.warp(block.timestamp + 50);
        
        vm.prank(bob);
        stratModManagerMock.createStrategyModules(110, 220, 330, 440, 2500000000000000000);
        assertEq(stratModManagerMock.numStratMods(), 2);
        assertEq(stakerRewardsMock.totalActiveDVs(), 2);

        // 50 * 4 VCs have been consumed by Alice's strategy module
        uint256 distributedRewards = dailyRewardsPerDV1 * 50;
        assertEq(stakerRewardsMock.totalVCs(), 2600); // 1700 + 1100 - 200
        assertEq(address(stakerRewardsMock).balance, 6750000000000000000); // 4250000000000000000 + 2500000000000000000 
        assertEq(stakerRewardsMock.totalNotYetClaimedRewards(), distributedRewards); // 500000000000000000
        assertEq(stakerRewardsMock.getAllocatableRewards(), 6250000000000000000);
        (, uint256 dailyRewardsPerDV2, ) = stakerRewardsMock.checkpoint();
        assertEq(dailyRewardsPerDV2, 9615384615384612); // allocableRewards / totalVCs * 4

        console.log("timestamp: %s", block.timestamp); // 61
    }

    function testCheckUpkeep_ReturnsFalseIfNoStratModsHasConsumedAllVCs() public setupForTestingChainlink {
        // starting time +61 days
        // The smallest VC number is 100
        assertEq(block.timestamp, 61); 
        uint256 automationUpdateInterval = 10; 

        // Arrange
        // 60 days after Alice has deployed her strategy module
        vm.warp(block.timestamp + automationUpdateInterval);

        // Act
        (bool upkeepNeeded,) = stakerRewardsMock.checkUpkeep("");
    
        // Assert
        assert(!upkeepNeeded);

        // Check performUpkeep revert if upkeepNeeded is false  
        vm.expectRevert(StakerRewardsMock.UpkeepNotNeeded.selector);
        stakerRewardsMock.performUpkeep("");
    }

    function testCheckUpkeep_ReturnsTrueWhenParametersGood() public setupForTestingChainlink {
        // starting time +61 days
        // 50 days after Alice has deployed her strategy module
        assertEq(block.timestamp, 61); 
        uint256 automationUpdateInterval = 51;

        // Arrange
        // 100 days after Alice has deployed her strategy module, the strategy module has consumed all VCs
        vm.warp(block.timestamp + automationUpdateInterval);

        address stratModAddr = stratModManagerMock.getStratMods(alice)[0];
        (, , uint256 exitTimestamp, , ) = stakerRewardsMock.getStratModData(stratModAddr);
        assertEq(exitTimestamp, 111);

        // Act
        (bool upkeepNeeded,) = stakerRewardsMock.checkUpkeep("");
    
        // Assert
        assert(upkeepNeeded);
    }

    function testPerformUpkeep_UpdatesVCsAndCheckpoint() public setupForTestingChainlink {
        // starting time +61 days
        // if timestamp = 111, Alice's strategy module has consumed all VCs
        uint256 automationUpdateInterval = 51;
        vm.warp(block.timestamp + automationUpdateInterval);
        console.log("timestamp: %s", block.timestamp); // 112

        // Manually call checkUpkeep to set upkeepNeeded to true 
        (bool upkeepNeeded, bytes memory performData) = stakerRewardsMock.checkUpkeep("");
        
        // UpkeepNeeded should be true
        assert(upkeepNeeded);

        // Decode the performData to get the strategy module addresses
        address stratModAddr = stratModManagerMock.getStratMods(alice)[0];
        (address[] memory stratModAddresses, uint256[] memory stratModTotalVCs) = abi.decode(performData, (address[], uint256[]));
        assertEq(stratModAddresses[0], stratModAddr);
        assertEq(stratModTotalVCs[0], 1000);
        assertEq(stakerRewardsMock.totalActiveDVs(), 2);

        // Checkpoint 4: manually call performUpkeep to update VCs and checkpoint
        stakerRewardsMock.performUpkeep(performData);

        // Check totalActiveDVs 
        assertEq(stakerRewardsMock.totalActiveDVs(), 1);
        // Check if node operators' VCs have been subtracted 
        StrategyModuleMock.Node[4] memory nodes = StrategyModuleMock(stratModAddr).getDVNodesDetails();
        assertEq(nodes[0].vcNumber, 0);
        assertEq(nodes[1].vcNumber, 100);
        assertEq(nodes[2].vcNumber, 200);
        assertEq(nodes[3].vcNumber, 300);
        StrategyModuleMock.DVStatus aliceStratModStatus = StrategyModuleMock(stratModAddr).getDVStatus();
        assertEq(uint(aliceStratModStatus), uint(StrategyModuleMock.DVStatus.EXITED));

        // Check the updated checkpoint data
        (uint256 startAt, uint256 dailyRewardsPerDV, ) = stakerRewardsMock.getCheckpointData();
        assertEq(startAt, block.timestamp);
        // Consumed VCs per staker: 51 * 4 = 204
        assertEq(stakerRewardsMock.totalVCs(), 1592); // 2600 - 408 - 600(= remaining VCs)
        // distributedRewards = dailyRewardsPerDV * 51 * 2 strategy modules = 980769230769230424
        assertEq(stakerRewardsMock.totalNotYetClaimedRewards(), 1480769230769230424); // 500000000000000000 + 980769230769230424

        // TODO: send the remaining bid prices back to Escrow (below will change as well)
        assertEq(address(stakerRewardsMock).balance, 6750000000000000000); 
        assertEq(stakerRewardsMock.getAllocatableRewards(), 5269230769230769576); // 6750000000000000000 - 1480769230769230424
        assertEq(dailyRewardsPerDV, 13239273289524544);
    }

    function testPerformUpkeep_TwoUpkeepPerformedSubsequently() public setupForTestingChainlink {
        // if timestamp = 111, Alice's strategy module has consumed all VCs
        vm.warp(block.timestamp + 51);
        // Manually call checkUpkeep to set upkeepNeeded to true 
        (bool upkeepNeededAlice, bytes memory performDataAlice) = stakerRewardsMock.checkUpkeep("");
        // UpkeepNeeded should be true
        assert(upkeepNeededAlice);
        stakerRewardsMock.performUpkeep(performDataAlice);

        // if timestamp = 170, Bob's strategy module has consumed all VCs
        vm.warp(block.timestamp + 60);
        // Manually call checkUpkeep to set upkeepNeeded to true 
        (bool upkeepNeededBob, bytes memory performDataBob) = stakerRewardsMock.checkUpkeep("");
        // UpkeepNeeded should be true
        assert(upkeepNeededBob);
        stakerRewardsMock.performUpkeep(performDataBob);

        // ASSERT
        address stratModAddrBob = stratModManagerMock.getStratMods(bob)[0];
        StrategyModuleMock.Node[4] memory nodes = StrategyModuleMock(stratModAddrBob).getDVNodesDetails();
        assertEq(nodes[0].vcNumber, 0);
        assertEq(nodes[1].vcNumber, 110);
        assertEq(nodes[2].vcNumber, 220);
        assertEq(nodes[3].vcNumber, 330);
        StrategyModuleMock.DVStatus status = StrategyModuleMock(stratModAddrBob).getDVStatus();
        assertEq(uint(status), uint(StrategyModuleMock.DVStatus.EXITED));
        console.log("total VCs: ", stakerRewardsMock.totalVCs());

        // The third upkeep should not be triggered
        vm.warp(block.timestamp + 200);
        assertEq(stakerRewardsMock.totalActiveDVs(), 0);
        vm.expectRevert(StakerRewardsMock.UpkeepNotNeeded.selector);
        stakerRewardsMock.checkUpkeep("");
    }

    modifier setupForTestingChainlink() {
        testPrecreateDVAndCreateStrategyModules_WorkCorrectly();
        _;
    }
}