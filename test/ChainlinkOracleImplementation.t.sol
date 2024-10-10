// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/oracle/ChainlinkOracleImplementation.sol";

contract MockChainlinkAggregator is AggregatorV3Interface {
    int256 private _price;
    uint256 private _updatedAt;
    uint8 private _decimals;
    uint80 private _roundId;

    function setPrice(int256 price) external {
        _price = price;
        _roundId++;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 updatedAt) external {
        _updatedAt = updatedAt;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, block.timestamp, _updatedAt, _roundId);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }
}

contract ChainlinkOracleImplementationTest is Test {
    ChainlinkOracleImplementation private oracle;
    MockChainlinkAggregator private mockAggregator;

    function setUp() public {
        oracle = new ChainlinkOracleImplementation();
        mockAggregator = new MockChainlinkAggregator();
    }

    function testValidPrice() public {
        mockAggregator.setPrice(100 * 1e8);  // $100 with 8 decimals
        mockAggregator.setUpdatedAt(block.timestamp);
        mockAggregator.setDecimals(8);

        uint256 price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertEq(price, 100 * 1e18);
    }

    function testInvalidPrice() public {
        mockAggregator.setPrice(0);
        mockAggregator.setUpdatedAt(block.timestamp);
        mockAggregator.setDecimals(8);

        vm.expectRevert(ChainlinkOracleImplementation.InvalidPrice.selector);
        oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function testRoundNotComplete() public {
        mockAggregator.setPrice(100 * 1e8);
        mockAggregator.setUpdatedAt(0);
        mockAggregator.setDecimals(8);

        vm.expectRevert(ChainlinkOracleImplementation.RoundNotComplete.selector);
        oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function testStalePrice() public {
        mockAggregator.setPrice(100 * 1e8);
        mockAggregator.setUpdatedAt(block.timestamp);
        mockAggregator.setDecimals(8);

        // Move time forward just under the staleness threshold
        vm.warp(block.timestamp + 59 minutes);

        // This should not revert
        uint256 price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertEq(price, 100 * 1e18);

        // Move time forward to exceed the staleness threshold
        vm.warp(block.timestamp + 2 minutes);

        // This should revert with PriceTooOld
        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracleImplementation.PriceTooOld.selector, block.timestamp - 61 minutes));
        oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function testPriceTooOld() public {
        mockAggregator.setPrice(100 * 1e8);
        mockAggregator.setDecimals(8);

        uint256 maxDelay = oracle.MAX_DELAY();
        
        // Set the block timestamp to a reasonable starting point
        vm.warp(maxDelay + 10);
        
        // Set the updated time to just over MAX_DELAY ago
        uint256 updatedAt = block.timestamp - maxDelay - 1;
        mockAggregator.setUpdatedAt(updatedAt);

        // Move the block timestamp forward slightly
        vm.warp(block.timestamp + 1);

        // Expect revert with PriceTooOld error
        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracleImplementation.PriceTooOld.selector, updatedAt));
        oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function testDifferentDecimals() public {
        // Test with 6 decimals
        mockAggregator.setPrice(100 * 1e6);
        mockAggregator.setUpdatedAt(block.timestamp);
        mockAggregator.setDecimals(6);

        uint256 price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertEq(price, 100 * 1e18);

        // Test with 18 decimals
        mockAggregator.setPrice(100 * 1e18);
        mockAggregator.setDecimals(18);

        price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertEq(price, 100 * 1e18);

        // Test with 20 decimals
        mockAggregator.setPrice(100 * 1e20);
        mockAggregator.setDecimals(20);

        price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        assertEq(price, 100 * 1e18);
    }
}