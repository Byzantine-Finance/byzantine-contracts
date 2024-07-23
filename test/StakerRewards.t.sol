// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable private-vars-leading-underscore
// solhint-disable var-name-mixedcase
// solhint-disable func-name-mixedcase

import {StakerRewards} from "../src/core/StakerRewards.sol";
import "./ByzantineDeployer.t.sol";
import "../src/interfaces/IAuction.sol";
import "../src/interfaces/IStrategyModule.sol";
import "../src/interfaces/IStrategyModuleManager.sol";
import "../src/interfaces/IStakerRewards.sol";
import "../src/core/StrategyModule.sol";
import "../src/core/StrategyModuleManager.sol";
import "../src/core/Auction.sol";
import "./ByzantineDeployer.t.sol";


import {Test, console} from "forge-std/Test.sol";

contract StakerRewardsTest is ByzantineDeployer {

    function setup() external {
        stakerRewards = new StakerRewards(IStrategyModuleManager(address(strategyModuleManager)), IAuction(address(auction)));
    }


}

