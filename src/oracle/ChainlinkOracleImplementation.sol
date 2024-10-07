// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOracle.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract ChainlinkOracleImplementation is IOracle {
    error InvalidPrice();
    error RoundNotComplete();
    error StalePrice();
    error PriceTooOld(uint256 timestamp);

    uint256 public constant PRICE_PRECISION = 1e18;  // Standardized precision
    uint256 public constant MAX_DELAY = 1 hours;  // Maximum acceptable delay

    /// @notice Get the price of an asset from a Chainlink price feed
    /// @param asset The asset to get the price of (unused in this implementation but kept for interface compatibility)
    /// @param priceFeed The address of the Chainlink price feed
    /// @return price The price of the asset with 18 decimal places
    function getPrice(address asset, address priceFeed) external view override returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        
        (
            uint80 roundID, 
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        
        if (price <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert RoundNotComplete();
        if (answeredInRound < roundID) revert StalePrice();
        if (block.timestamp - updatedAt > MAX_DELAY) revert PriceTooOld(updatedAt);
        
        uint8 feedDecimals = feed.decimals();
        
        // Convert the price to 18 decimal places
        if (feedDecimals < 18) {
            return uint256(price) * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            return uint256(price) / (10 ** (feedDecimals - 18));
        }
        
        return uint256(price);
    }
}