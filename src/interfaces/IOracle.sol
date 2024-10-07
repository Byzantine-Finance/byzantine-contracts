// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    /**
     * @notice Get the price of an asset from an Oracle
     * @param asset The asset to get the price of 
     * @param priceFeed The address of the price feed for `asset`
     * @return price The price of `asset` with 18 decimal places.
     * @dev Must return 18 decimals for compatibility with the Vault.
     */
    function getPrice(address asset, address priceFeed) external view returns (uint256);
}