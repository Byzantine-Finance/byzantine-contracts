// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../interfaces/IOracle.sol";

// API3 Proxy Interface from https://github.com/api3dao/contracts/blob/main/contracts/api3-server-v1/proxies/interfaces/IProxy.sol
interface IProxy {
    function read() external view returns (int224 value, uint32 timestamp);

    function api3ServerV1() external view returns (address);
}

contract API3OracleImplementation is IOracle {
    error InvalidPrice();
    error StalePrice(uint256 timestamp);
    uint256 public constant PRICE_PRECISION = 1e18;  // Standardized precision
    uint256 public constant MAX_DELAY = 1 hours;  // Maximum acceptable delay
    /// @notice Get the price of an asset from an API3 dAPI
    /// @param asset The asset to get the price of (unused in this implementation but kept for interface compatibility)
    /// @param proxyAddress The address of the API3 dAPI proxy for the desired price feed
    /// @return price The price of the asset with 18 decimal places
    function getPrice(address asset, address proxyAddress) external view override returns (uint256) {
        require(proxyAddress != address(0), "Invalid proxy address");
        
        // Get price data from the API3 dAPI proxy
        (int224 value, uint256 timestamp) = IProxy(proxyAddress).read();
        
        // Check if the price is valid
        if (value <= 0) revert InvalidPrice();
        if (block.timestamp - timestamp > MAX_DELAY) revert StalePrice(timestamp);
        
        // Convert the int224 value to uint256
        // API3 dAPIs always return values with 18 decimal places, so no conversion is needed
        return uint256(int256(value));
    }
}