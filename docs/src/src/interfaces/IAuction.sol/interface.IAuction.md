# IAuction
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/interfaces/IAuction.sol)


## Functions
### numNodeOpsInAuction

Getter of the state variable `numNodeOpsInAuction`


```solidity
function numNodeOpsInAuction() external view returns (uint64);
```

### expectedDailyReturnWei

Get the daily rewards of Ethereum Pos (in WEI)


```solidity
function expectedDailyReturnWei() external view returns (uint256);
```

### maxDiscountRate

Get the maximum discount rate (i.e the max profit margin of node op) in percentage (upscale 1e2)


```solidity
function maxDiscountRate() external view returns (uint16);
```

### minDuration

Get the minimum duration to be part of a DV (in days)


```solidity
function minDuration() external view returns (uint160);
```

### clusterSize

Get the cluster size of a DV (i.e the number of nodes in a DV)


```solidity
function clusterSize() external view returns (uint8);
```

### addNodeOpToWhitelist

Add a node operator to the the whitelist to not make him pay the bond.

*Revert if the node operator is already whitelisted.*


```solidity
function addNodeOpToWhitelist(address _nodeOpAddr) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||


### removeNodeOpFromWhitelist

Remove a node operator to the the whitelist.

*Revert if the node operator is not whitelisted.*


```solidity
function removeNodeOpFromWhitelist(address _nodeOpAddr) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||


### getAuctionWinners

Function triggered by the StrategyVaultManager every time a staker deposit 32ETH and ask for a DV.
It allows the pre-creation of a new DV for the next staker.
It finds the `clusterSize` node operators with the highest auction scores and put them in a DV.

*Reverts if not enough node operators are available.*


```solidity
function getAuctionWinners() external returns (IStrategyVault.Node[] memory);
```

### getPriceToPay

Fonction to determine the auction price for a validator according to its bids parameters

*Revert if the two entry arrays `_discountRates` and `_timesInDays` have different length*

*Revert if `_discountRates` or `_timesInDays` don't respect the values set by the byzantine.*


```solidity
function getPriceToPay(
    address _nodeOpAddr,
    uint256[] calldata _discountRates,
    uint256[] calldata _timesInDays
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRates`|`uint256[]`||
|`_timesInDays`|`uint256[]`||


### bid

Operators set their standing bid(s) parameters and pay their bid(s) to an escrow smart contract.
If a node op doesn't win the auction, its bids stays in the escrow contract for the next auction.
An node op who hasn't won an auction can ask the escrow contract to refund its bid(s) if he wants to leave the protocol.
If a node op wants to update its bid parameters, call `updateBid` function.

Non-whitelisted operators will have to pay the 1ETH bond as well.

*By calling this function, the node op insert data in the auction Binary Search Tree (sorted by auction score).*

*Revert if `_discountRates` or `_timesInDays` don't respect the values set by the byzantine or if they don't have the same length.*

*Revert if the ethers sent by the node op are not enough to pay for the bid(s) (and the bond).*

*Reverts if the transfer of the funds to the Escrow contract failed.*

*If too many ethers has been sent the function give back the excess to the sender.*


```solidity
function bid(
    uint256[] calldata _discountRates,
    uint256[] calldata _timesInDays
) external payable returns (uint256[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_discountRates`|`uint256[]`||
|`_timesInDays`|`uint256[]`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|The array of each bid auction score.|


### getUpdateOneBidPrice

Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decreases its bid.

The bid which will be updated will be the last bid with `_auctionScore`

*Reverts if the node op doesn't have a bid with `_auctionScore`.*

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function getUpdateOneBidPrice(
    address _nodeOpAddr,
    uint256 _auctionScore,
    uint256 _discountRate,
    uint256 _timeInDays
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_auctionScore`|`uint256`||
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### updateOneBid

Update a bid of a node operator associated to `_auctionScore`. The node op will have to pay more if he outbids.
If he decreases his bid, the escrow contract will send him back the difference.

The bid which will be updated will be the last bid with `_auctionScore`

*Reverts if the node op doesn't have a bid with `_auctionScore`.*

*Reverts if the transfer of the funds to the Escrow contract failed.*

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function updateOneBid(
    uint256 _auctionScore,
    uint256 _newDiscountRate,
    uint256 _newTimeInDays
) external payable returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_auctionScore`|`uint256`||
|`_newDiscountRate`|`uint256`||
|`_newTimeInDays`|`uint256`||


### withdrawBid

Allow a node operator to withdraw a specific bid (through its auction score).
The withdrawer will be refund its bid price plus (the bond of he paid it).


```solidity
function withdrawBid(uint256 _auctionScore) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_auctionScore`|`uint256`||


### updateAuctionConfig

Update the auction configuration except cluster size


```solidity
function updateAuctionConfig(uint256 _expectedDailyReturnWei, uint16 _maxDiscountRate, uint160 _minDuration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_expectedDailyReturnWei`|`uint256`||
|`_maxDiscountRate`|`uint16`||
|`_minDuration`|`uint160`||


### updateClusterSize

Update the cluster size (i.e the number of node operators in a DV)


```solidity
function updateClusterSize(uint8 _clusterSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterSize`|`uint8`||


### isWhitelisted

Return true if the `_nodeOpAddr` is whitelisted, false otherwise.


```solidity
function isWhitelisted(address _nodeOpAddr) external view returns (bool);
```

### getNodeOpBidNumber

Return the pending bid number of the `_nodeOpAddr`.


```solidity
function getNodeOpBidNumber(address _nodeOpAddr) external view returns (uint256);
```

### getNodeOpAuctionScoreBidPrices

Return the pending bid(s) price of the `_nodeOpAddr` corresponding to `_auctionScore`.

*If `_nodeOpAddr` doesn't have `_auctionScore` in his mapping, return an empty array.*

*A same `_auctionScore` can have different bid prices depending on the reputationScore variations.*


```solidity
function getNodeOpAuctionScoreBidPrices(
    address _nodeOpAddr,
    uint256 _auctionScore
) external view returns (uint256[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_auctionScore`|`uint256`|The auction score of the node operator you want to get the corresponding bid(s) price.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|(uint256[] memory) An array of all the bid price for that specific auctionScore|


### getNodeOpAuctionScoreVcs

Return the pending VCs number of the `_nodeOpAddr` corresponding to `_auctionScore`.

*If `_nodeOpAddr` doesn't have `_auctionScore` in his mapping, return an empty array.*

*A same `_auctionScore` can have different VCs numbers depending on the reputationScore variations.*


```solidity
function getNodeOpAuctionScoreVcs(
    address _nodeOpAddr,
    uint256 _auctionScore
) external view returns (uint256[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_auctionScore`|`uint256`|The auction score of the node operator you want to get the corresponding VCs numbers.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|(uint256[] memory) An array of all the VC numbers for that specific auctionScore|


## Errors
### OnlyStrategyVaultManager
*Error when unauthorized call to a function callable only by the StrategyVaultManager.*


```solidity
error OnlyStrategyVaultManager();
```

### AlreadyWhitelisted
*Error when address already whitelisted*


```solidity
error AlreadyWhitelisted();
```

### NotWhitelisted
*Error when trying to remove from whitelist a non-whitelisted address*


```solidity
error NotWhitelisted();
```

### DiscountRateTooHigh
*Returned when node operator's discount rate is too high compared to the Byzantine's max discount rate.*


```solidity
error DiscountRateTooHigh();
```

### DurationTooShort
*Returned when node operator's duration is too short compared to the Byzantine's min duration.*


```solidity
error DurationTooShort();
```

### NotEnoughEtherSent
*Returned when bidder didn't pay its entire bid*


```solidity
error NotEnoughEtherSent();
```

### EscrowTransferFailed
*Returned when the deposit to the Escrow contract failed*


```solidity
error EscrowTransferFailed();
```

## Structs
### AuctionDetails
Stores auction details of node operators


```solidity
struct AuctionDetails {
    uint128 numBids;
    uint128 reputationScore;
    mapping(uint256 => uint256[]) auctionScoreToBidPrices;
    mapping(uint256 => uint256[]) auctionScoreToVcNumbers;
}
```

