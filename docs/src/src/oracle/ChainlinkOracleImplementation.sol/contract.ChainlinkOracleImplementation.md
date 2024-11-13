# ChainlinkOracleImplementation
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/oracle/ChainlinkOracleImplementation.sol)

**Inherits:**
[IOracle](/src/interfaces/IOracle.sol/interface.IOracle.md)


## State Variables
### MAX_DELAY

```solidity
uint256 public constant MAX_DELAY = 1 hours;
```


### ETH_USD_PRICE_FEED

```solidity
address public constant ETH_USD_PRICE_FEED = address(0);
```


## Functions
### getPrice

Get the price of an asset from a Chainlink price feed


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

### RoundNotComplete

```solidity
error RoundNotComplete();
```

### StalePrice

```solidity
error StalePrice();
```

### PriceTooOld

```solidity
error PriceTooOld(uint256 timestamp);
```

