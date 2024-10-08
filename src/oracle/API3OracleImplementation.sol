// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// API3 Proxy Interface from https://github.com/api3dao/contracts/blob/main/contracts/api3-server-v1/proxies/interfaces/IProxy.sol
interface IProxy {
    function read() external view returns (int224 value, uint32 timestamp);

    function api3ServerV1() external view returns (address);
}

/// @title API3OracleImplementation
/// @author Byzantine Finance
/// @notice This API3 oracle implementation is used to get the price of an asset from an API3 dAPI.
/// @dev This implementation has the ability to edit the ETH_USD_PROXY address.
contract API3OracleImplementation is IOracle, Ownable {
    error InvalidPrice();
    error StalePrice(uint256 timestamp);
    error InvalidProxyAddress();

    uint256 public constant MAX_DELAY = 1 hours;  // Maximum acceptable delay
    address public ETH_USD_PROXY = 0xa47Fd122b11CdD7aad7c3e8B740FB91D83Ce43D1; // ETH/USD Proxy on Holesky

    /// @notice Get the price of an asset from an API3 dAPI
    /// @param asset The asset to get the price of (unused in this implementation but kept for interface compatibility)
    /// @param proxyAddress The address of the API3 dAPI proxy for the desired price feed
    /// @return price The price of the asset with 18 decimal places
    function getPrice(address asset, address proxyAddress) external view override returns (uint256) {
        if (proxyAddress == address(0)) revert InvalidProxyAddress();
        
        // If asset is the special ETH address, use the ETH/USD proxy
        if (asset == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            proxyAddress = ETH_USD_PROXY;
        }

        // Get price data from the API3 dAPI proxy
        (int224 value, uint256 timestamp) = IProxy(proxyAddress).read();
        
        // Check if the price is valid
        if (value <= 0) revert InvalidPrice();
        if (block.timestamp - timestamp > MAX_DELAY) revert StalePrice(timestamp);
        
        // Convert the int224 value to uint256
        // API3 dAPIs always return values with 18 decimal places, so no conversion is needed
        return uint256(int256(value));
    }

    /// @notice Set the ETH/USD proxy address
    /// @param _newProxy The new proxy address
    function setETHUSDProxy(address _newProxy) external onlyOwner {
        ETH_USD_PROXY = _newProxy;
    }
}