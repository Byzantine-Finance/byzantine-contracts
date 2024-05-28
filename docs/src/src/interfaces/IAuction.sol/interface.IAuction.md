# IAuction
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/a175940c55bcb788c83621ba4e22c28c3fbfcb7d/src/interfaces/IAuction.sol)


## Functions
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


### createDV

Function triggered by the StrategyModuleManager every time a staker deposit 32ETH and ask for a DV.
It finds the `_clusterSize` node operators with the highest auction scores and put them in a DV.

*The status of the winners is updated to `inDV`.*

*Reverts if not enough node operators are available.*


```solidity
function createDV(IStrategyModule _stratModNeedingDV) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_stratModNeedingDV`|`IStrategyModule`||


### getPriceToPay

Fonction to determine the auction price for a validator according to its bid parameters

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function getPriceToPay(
    address _nodeOpAddr,
    uint256 _discountRate,
    uint256 _timeInDays
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### bid

Operators set their standing bid parameters and pay their bid to an escrow smart contract.
If a node op doesn't win the auction, its bid stays in the escrow contract for the next auction.
An node op who hasn't won an auction can ask the escrow contract to refund its bid if he wants to leave the protocol.
If a node op wants to update its bid parameters, call `updateBid` function.

Non-whitelisted operators will have to pay the 1ETH bond as well.

*By calling this function, the node op insert a data in the auction Binary Search Tree (sorted by auction score).*

*Revert if the node op is already in auction. Call `updateBid` instead.*

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*

*Revert if the ethers sent by the node op are not enough to pay for the bid (and the bond).*

*Reverts if the transfer of the funds to the Escrow contract failed.*

*If too many ethers has been sent the function give back the excess to the sender.*


```solidity
function bid(uint256 _discountRate, uint256 _timeInDays) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### getUpdateBidPrice

Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decrease its bid.

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function getUpdateBidPrice(
    address _nodeOpAddr,
    uint256 _discountRate,
    uint256 _timeInDays
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### updateBid

Update the bid of a node operator. A same address cannot have several bids, so the node op
will have to pay more if he outbids. If he decreases his bid, the escrow contract will send him the difference.

*To call that function, the node op has to be inAuction.*

*Reverts if the transfer of the funds to the Escrow contract failed.*

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function updateBid(uint256 _newDiscountRate, uint256 _newTimeInDays) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newDiscountRate`|`uint256`||
|`_newTimeInDays`|`uint256`||


### withdrawBid

Allow a node operator to abandon the auction and withdraw the bid he paid.
It's not possible to withdraw if the node operator is actively validating.

*Status is set to inactive and auction details to 0 unless the reputation which is unmodified*


```solidity
function withdrawBid() external;
```

### updateAuctionConfig

Update the auction configuration except cluster size


```solidity
function updateAuctionConfig(
    uint256 __expectedDailyReturnWei,
    uint256 __maxDiscountRate,
    uint256 __minDuration
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`__expectedDailyReturnWei`|`uint256`||
|`__maxDiscountRate`|`uint256`||
|`__minDuration`|`uint256`||


### updateClusterSize

Update the cluster size (i.e the number of node operators in a DV)


```solidity
function updateClusterSize(uint256 __clusterSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`__clusterSize`|`uint256`||


### isWhitelisted

Return true if the `_nodeOpAddr` is whitelisted, false otherwise.


```solidity
function isWhitelisted(address _nodeOpAddr) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||


### getNodeOpDetails

Returns the auction details of a node operator


```solidity
function getNodeOpDetails(address _nodeOpAddr)
    external
    view
    returns (uint256, uint256, uint256, uint256, NodeOpStatus);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`|The node operator address to get the details|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|(vcNumber, bidPrice, auctionScore, reputationScore, nodeStatus)|
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`NodeOpStatus`||


### getAuctionScoreToNodeOp

Returns the node operator who have the `_auctionScore`


```solidity
function getAuctionScoreToNodeOp(uint256 _auctionScore) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_auctionScore`|`uint256`|The auction score to get the node operator|


### getAuctionConfigValues

Returns the auction configuration values.

*Function callable only by the owner.*


```solidity
function getAuctionConfigValues() external view returns (uint256, uint256, uint256, uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|(_expectedDailyReturnWei, _maxDiscountRate, _minDuration, _clusterSize)|
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`uint256`||


## Events
### NodeOpJoined

```solidity
event NodeOpJoined(address nodeOpAddress);
```

### NodeOpLeft

```solidity
event NodeOpLeft(address nodeOpAddress);
```

### BidUpdated

```solidity
event BidUpdated(address nodeOpAddress, uint256 bidPrice, uint256 auctionScore, uint256 reputationScore);
```

### AuctionConfigUpdated

```solidity
event AuctionConfigUpdated(uint256 _expectedDailyReturnWei, uint256 _maxDiscountRate, uint256 _minDuration);
```

### ClusterSizeUpdated

```solidity
event ClusterSizeUpdated(uint256 _clusterSize);
```

### TopWinners

```solidity
event TopWinners(address[] winners);
```

### BidPaid

```solidity
event BidPaid(address nodeOpAddress, uint256 bidPrice);
```

### ListOfNodeOps

```solidity
event ListOfNodeOps(address[] nodeOps);
```

## Errors
### OnlyStrategyModuleManager
*Error when unauthorized call to a function callable only by the StrategyModuleManager.*


```solidity
error OnlyStrategyModuleManager();
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

### AlreadyInAuction
*Returned when a node operator is already in auction and therefore not allowed to bid again*


```solidity
error AlreadyInAuction();
```

### NotInAuction
*Returned when a node operator is not in auction and therefore cannot update its bid*


```solidity
error NotInAuction();
```

### BidAlreadyExists
*Error when two node operators have the same auction score*


```solidity
error BidAlreadyExists();
```

### NotEnoughEtherSent
*Returned when bidder didn't pay its entire bid*


```solidity
error NotEnoughEtherSent();
```

### NotEnoughNodeOps
*Returned when trying to create a DV but not enough node operators are in auction*


```solidity
error NotEnoughNodeOps();
```

### EscrowTransferFailed
*Returned when the deposit to the Escrow contract failed*


```solidity
error EscrowTransferFailed();
```

## Structs
### NodeOpDetails
Stores auction details of node operators


```solidity
struct NodeOpDetails {
    uint256 vcNumber;
    uint256 bidPrice;
    uint256 auctionScore;
    uint256 reputationScore;
    NodeOpStatus nodeStatus;
}
```

## Enums
### NodeOpStatus

```solidity
enum NodeOpStatus {
    inactive,
    inAuction,
    inDV
}
```

