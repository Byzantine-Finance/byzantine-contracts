// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
    OracleImplementation Standard for Byzantine Finance Strategy Vaults

    MUST: Implement getPrice(address asset, address priceFeed), returns price of asset.
    MUST: Return value of getPrice 18 decimals for compatibility with the Vault.
    MUST: Store the price feed for the native asset. When 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE is passed as the asset, the price feed for the native asset should be used.

    [TO:DO] MUST: Return 0 for invalid assets or price feeds. 
 */
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