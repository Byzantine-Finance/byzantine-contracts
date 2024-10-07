// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOracle.sol";

// Chainlink imports
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

    uint256 constant PRICE_PRECISION = 1e8;  // Chainlink typically uses 8 decimal places
    uint256 constant MAX_DELAY = 1 hours;  // Maximum acceptable delay

    /// @notice Get the price of an asset from a Chainlink price feed
    /// @param asset The asset to get the price of
    /// @param priceFeed The address of the Chainlink price feed
    /// @return price The price of the asset
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
        
        uint8 decimals = feed.decimals();
        return uint256(price) * (10 ** (PRICE_PRECISION - decimals));
    }
}