# API3OracleImplementation
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/oracle/API3OracleImplementation.sol)

**Inherits:**
[IOracle](/src/interfaces/IOracle.sol/interface.IOracle.md), Ownable

**Author:**
Byzantine Finance

This API3 oracle implementation is used to get the price of an asset from an API3 dAPI.

*This implementation has the ability to edit the ETH_USD_PROXY address.*


## State Variables
### MAX_DELAY

```solidity
uint256 public constant MAX_DELAY = 1 hours;
```


### ETH_USD_PROXY

```solidity
address public constant ETH_USD_PROXY = 0xa47Fd122b11CdD7aad7c3e8B740FB91D83Ce43D1;
```


## Functions
### getPrice

Get the price of an asset from an API3 dAPI


```solidity
function getPrice(address asset) external view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to get the price of|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|price The price of the asset with 18 decimal places|


## Errors
### InvalidPrice

```solidity
error InvalidPrice();
```

### StalePrice

```solidity
error StalePrice(uint256 timestamp);
```

### InvalidAsset

```solidity
error InvalidAsset();
```

