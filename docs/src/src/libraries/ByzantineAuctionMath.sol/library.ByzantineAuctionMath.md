# ByzantineAuctionMath
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/libraries/ByzantineAuctionMath.sol)

Library for the Byzantine Auction Mathematics

*The library is used to calculate the Validation Credit price, the bid price, the (average) auction scores and a cluster id*


## State Variables
### _WAD

```solidity
uint256 private constant _WAD = 1e18;
```


### _RAY

```solidity
uint256 private constant _RAY = 1e27;
```


### _DURATION_WEIGHT

```solidity
uint240 private constant _DURATION_WEIGHT = 10_001;
```


### _DISCOUNT_RATE_SCALE

```solidity
uint16 private constant _DISCOUNT_RATE_SCALE = 1e4;
```


## Functions
### calculateVCPrice

Calculate and returns the daily Validation Credit price (in WEI)

*vc_price = dailyPosRewards*(1 - discount_rate)/cluster_size*


```solidity
function calculateVCPrice(
    uint256 _expectedDailyReturnWei,
    uint16 _discountRate,
    uint8 _clusterSize
) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_expectedDailyReturnWei`|`uint256`||
|`_discountRate`|`uint16`||
|`_clusterSize`|`uint8`||


### calculateBidPrice

Calculate and returns the bid price that should be paid by the node operator (in WEI)

*bid_price = time_in_days * vc_price*


```solidity
function calculateBidPrice(uint32 _timeInDays, uint256 _dailyVcPrice) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_timeInDays`|`uint32`||
|`_dailyVcPrice`|`uint256`||


### calculateAuctionScore

Calculate and returns the auction score of a node operator

The equation incentivize the node operators to commit for a longer duration

*powerValue = 1.0001**_timeInDays*

*The result is divided by 1e18 to downscaled from 1e36 to 1e18*


```solidity
function calculateAuctionScore(
    uint256 _dailyVcPrice,
    uint32 _timeInDays,
    uint32 _reputation
) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dailyVcPrice`|`uint256`||
|`_timeInDays`|`uint32`||
|`_reputation`|`uint32`||


### calculateAverageAuctionScore

Calculate the average auction score from an array of scores


```solidity
function calculateAverageAuctionScore(uint256[] memory _auctionScores) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_auctionScores`|`uint256[]`|An array of auction scores|


### generateClusterId

Generate a unique cluster ID based on timestamp, addresses, and average auction score


```solidity
function generateClusterId(
    uint256 _timestamp,
    address[] memory _addresses,
    uint256 _averageAuctionScore
) internal pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_timestamp`|`uint256`|The current block timestamp during the cluster creation|
|`_addresses`|`address[]`|The addresses making up the cluster|
|`_averageAuctionScore`|`uint256`|The average auction score of the cluster|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|bytes32 The generated cluster ID|


### _pow

Calculate the power value of 1.0001**_timeInDays

*The result is divided by 1e9 to downscaled to 1e18 as the return value of `rpow` is upscaled to 1e27*


```solidity
function _pow(uint32 _timeIndays) private pure returns (uint256);
```

### _rpow


```solidity
function _rpow(uint256 x, uint256 n) private pure returns (uint256 z);
```

### _rmul


```solidity
function _rmul(uint256 x, uint256 y) private pure returns (uint256 z);
```

### _add


```solidity
function _add(uint256 x, uint256 y) private pure returns (uint256 z);
```

### _mul


```solidity
function _mul(uint256 x, uint256 y) private pure returns (uint256 z);
```

