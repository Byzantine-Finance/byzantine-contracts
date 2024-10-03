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

// import "../src/tokens/ByzNft.sol";
// import "../src/core/Auction.sol";

import "../src/interfaces/IStrategyVaultERC20.sol";
import "../src/interfaces/IStrategyVaultETH.sol";
import "../src/interfaces/IStrategyVaultManager.sol";
import "../src/interfaces/IAuction.sol";
import "../src/core/StrategyVaultETH.sol";

import {console} from "forge-std/console.sol";

contract StakerRewardsTest is ProofParsing, ByzantineDeployer {
    /// @notice Initial balance of all the node operators
    uint256 internal constant STARTING_BALANCE = 500 ether;

    /// @notice Array of all the bid ids
    bytes32[] internal bidId;
    
    function setUp() public override {
        // deploy locally EigenLayer and Byzantine contracts
        ByzantineDeployer.setUp();

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
        bidId = _createMultipleBids();

        // Get deposit data of a random validator
        // _getDepositData(abi.encodePacked("./test/test-data/deposit-data-DV0-noPod.json"));
    }

    function test_dvCreationCheckpoint() public startAtPresentDay {
        // ARRANGE
        // Node winner 1 VCs: 200, 200, 150, 150 = 700
        // Node winner 2 VCs: 200, 200, 149, 149 = 698
        // Node winner 3 VCs: 148, 100, 50, 45 = 343

        // ACT
        vm.warp(block.timestamp + 1 days);
        uint256 dvCreationTime = block.timestamp;
        IStrategyVaultETH stratVaultETH = _createStratVaultETHAndStake(alice, 96 ether);

        // ASSERT
        // Get the clusterId of the strat vault
        bytes32[] memory clusterIds = stratVaultETH.getAllDVIds();
        (uint256 smallestVC, uint256 exitTimestamp, uint8 clusterSize) = stakerRewards.getClusterData(clusterIds[0]);
        uint256 finalBalance = address(stratVaultETH).balance;
        uint256 exitTime = dvCreationTime + 150 * 1 days;
        uint256 dvTotalBids = 0;
        for (uint8 i = 0; i < clusterSize; i++) {
            bytes32 id = auction.getClusterDetails(clusterIds[0]).nodes[i].bidId;
            IAuction.BidDetails memory bidDetails = auction.getBidDetails(id);
            dvTotalBids += bidDetails.bidPrice;
        }
        (uint256 updateTime, ) = stakerRewards.getCheckpointData();
        // (uint256 updateTimeVault, uint256 numActiveDVs) = stakerRewards.getVaultData(address(stratVaultETH));

        assertEq(stratVaultETH.getVaultDVNumber(), 3);
        assertEq(smallestVC, 150);
        assertEq(exitTimestamp, exitTime);
        assertEq(clusterSize, 4);
        assertEq(stakerRewards.totalVCs(), 1741);
        assertEq(stakerRewards.numberDV4(), 3);
        assertEq(stakerRewards.numberDV7(), 0);
        assertEq(stakerRewards.totalPendingRewards(), 0);
        assertEq(updateTime, dvCreationTime);
        // TODO: address(stakerRewards).balance = bidPrices of 3 DVs, supposed to be bidPrices of DV1.Changing mechanism
        // assertEq(address(stakerRewards).balance, dvTotalBids);
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
        uint256 priceToPay = auction.getPriceToPayCluster4(_nodeOp, _discountRate, _timeInDays);
        vm.prank(_nodeOp);
        return   auction.bidCluster4{value: priceToPay}(_discountRate, _timeInDays);
    }

    function _createStratVaultETHAndStake(address _staker, uint256 _amount) internal returns (IStrategyVaultETH) {
        vm.prank(_staker);
        IStrategyVaultETH stratVaultETH = IStrategyVaultETH(strategyVaultManager.createStratVaultAndStakeNativeETH{value: _amount}(true, true, ELOperator1, address(0), _staker));
        return stratVaultETH;
    }

    /* ===================== MODIFIERS ===================== */

    modifier startAtPresentDay() {
        vm.warp(1727876759);
        _;
    }
}