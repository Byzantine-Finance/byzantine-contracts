// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import { SplitsWarehouse } from "splits-v2/SplitsWarehouse.sol";
import { PushSplitFactory } from "splits-v2/splitters/push/PushSplitFactory.sol";

import "forge-std/Test.sol";

contract SplitsV2Deployer is Test {

    // 0xSplits contracts
    SplitsWarehouse public warehouse;
    PushSplitFactory public pushSplitFactory;

    string constant NATIVE_TOKEN_NAME = "Ether";
    string constant NATIVE_TOKEN_SYMBOL = "ETH";

    function setUp() public virtual {
        _deploySplitsV2ContractsLocal();
    }

    function _deploySplitsV2ContractsLocal() internal {
        // Deploy SplitsWarehouse
        warehouse = new SplitsWarehouse(NATIVE_TOKEN_NAME, NATIVE_TOKEN_SYMBOL);
        // Deploy PushSplitFactory
        pushSplitFactory = new PushSplitFactory(address(warehouse));
    }

}