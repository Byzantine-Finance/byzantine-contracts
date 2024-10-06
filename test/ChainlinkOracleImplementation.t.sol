pragma solidity ^0.8.20;

import {ChainlinkOracleImplementation} from "../src/oracle/ChainlinkOracleImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract ChainlinkOracleImplementationTest is Test {
    ChainlinkOracleImplementation oracle;

    function setUp() public {
        oracle = new ChainlinkOracleImplementation();
    }