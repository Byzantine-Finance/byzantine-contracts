# IOracle
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IOracle.sol)

OracleImplementation Standard for Byzantine Finance Strategy Vaults
MUST: Implement getPrice(address asset), returns price of asset.
MUST: Return value of getPrice 18 decimals for compatibility with the Vault.
MUST: Store the price feed for the native asset. When 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE is passed as the asset, the price feed for the native asset should be used.
[TO:DO] MUST: Return 0 for invalid assets.


## Functions
### getPrice

Get the price of an asset from an Oracle

*Must return 18 decimals for compatibility with the Vault.*


```solidity
function getPrice(address asset) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to get the price of|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|price The price of `asset` with 18 decimal places.|


