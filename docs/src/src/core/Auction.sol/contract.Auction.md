# Auction
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/039f6bfc2d98b2c720b4f881f44b17511a859648/src/core/Auction.sol)

**Inherits:**
Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, [AuctionStorage](/src/core/AuctionStorage.sol/abstract.AuctionStorage.md), DSMath

TODO: Calculation of the reputation score of node operators


## Functions
### constructor


```solidity
constructor(
    IEscrow _escrow,
    IStrategyModuleManager _strategyModuleManager
) AuctionStorage(_escrow, _strategyModuleManager);
```

### initialize

*Initializes the address of the initial owner*


```solidity
function initialize(
    address _initialOwner,
    uint256 __expectedDailyReturnWei,
    uint256 __maxDiscountRate,
    uint256 __minDuration,
    uint256 __clusterSize
) external initializer;
```

### addNodeOpToWhitelist

Add a node operator to the the whitelist to not make him pay the bond.

*Revert if the node operator is already whitelisted.*


```solidity
function addNodeOpToWhitelist(address _nodeOpAddr) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||


### removeNodeOpFromWhitelist

Remove a node operator to the the whitelist.

*Revert if the node operator is not whitelisted.*


```solidity
function removeNodeOpFromWhitelist(address _nodeOpAddr) external onlyOwner;
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
function createDV(IStrategyModule _stratModNeedingDV) external onlyStategyModuleManager nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_stratModNeedingDV`|`IStrategyModule`||


### getPriceToPay

Fonction to determine the auction price for a validator according to its bid parameters

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function getPriceToPay(address _nodeOpAddr, uint256 _discountRate, uint256 _timeInDays) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### bid

Calculate operator's bid price

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
function bid(uint256 _discountRate, uint256 _timeInDays) external payable nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### getUpdateBidPrice

TODO: Get the reputation score of msg.sender

Calculate operator's bid price and auction score

Fonction to determine the price to add in the protocol if the node operator outbids. Returns 0 if he decrease its bid.

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function getUpdateBidPrice(
    address _nodeOpAddr,
    uint256 _discountRate,
    uint256 _timeInDays
) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRate`|`uint256`||
|`_timeInDays`|`uint256`||


### updateBid

Calculate operator's new bid price

Update the bid of a node operator. A same address cannot have several bids, so the node op
will have to pay more if he outbids. If he decreases his bid, the escrow contract will send him the difference.

*To call that function, the node op has to be inAuction.*

*Reverts if the transfer of the funds to the Escrow contract failed.*

*Revert if `_discountRate` or `_timeInDays` don't respect the values set by the byzantine.*


```solidity
function updateBid(uint256 _newDiscountRate, uint256 _newTimeInDays) external payable nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newDiscountRate`|`uint256`||
|`_newTimeInDays`|`uint256`||


### withdrawBid

TODO: Get the reputation score of msg.sender

Calculate operator's new bid price and new auction score

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
) external onlyOwner;
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
function updateClusterSize(uint256 __clusterSize) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`__clusterSize`|`uint256`||


### isWhitelisted

Return true if the `_nodeOpAddr` is whitelisted, false otherwise.


```solidity
function isWhitelisted(address _nodeOpAddr) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||


### getNodeOpDetails

Returns the auction details of a node operator


```solidity
function getNodeOpDetails(address _nodeOpAddr) public view returns (uint256, uint256, uint256, uint256, NodeOpStatus);
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
function getAuctionScoreToNodeOp(uint256 _auctionScore) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_auctionScore`|`uint256`|The auction score to get the node operator|


### getAuctionConfigValues

Returns the auction configuration values.

*Function callable only by the owner.*


```solidity
function getAuctionConfigValues() external view onlyOwner returns (uint256, uint256, uint256, uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|(_expectedDailyReturnWei, _maxDiscountRate, _minDuration, _clusterSize)|
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`uint256`||


### _calculateDailyVcPrice

Calculate and returns the daily Validation Credit price (in WEI)

*vc_price = Re*(1 - D)/cluster_size*

*The `_expectedDailyReturnWei` is set by Byzantine and corresponds to the Ethereum daily staking return.*


```solidity
function _calculateDailyVcPrice(uint256 _discountRate) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_discountRate`|`uint256`||


### _calculateBidPrice

Calculate and returns the bid price that should be paid by the node operator (in WEI)

*bid_price = time_in_days * vc_price*


```solidity
function _calculateBidPrice(uint256 _timeInDays, uint256 _dailyVcPrice) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_timeInDays`|`uint256`||
|`_dailyVcPrice`|`uint256`||


### _calculateAuctionScore

Calculate and returns the auction score of a node operator

*powerValue = 1.001**_timeInDays, calculated from `_pow` function*

*The result is divided by 1e18 to downscaled from 1e36 to 1e18*


```solidity
function _calculateAuctionScore(
    uint256 _dailyVcPrice,
    uint256 _timeInDays,
    uint256 _reputation
) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dailyVcPrice`|`uint256`||
|`_timeInDays`|`uint256`||
|`_reputation`|`uint256`||


### _pow

Calculate the power value of 1.001**_timeInDays

*The result is divided by 1e9 to downscaled to 1e18 as the return value of `rpow` is upscaled to 1e27*


```solidity
function _pow(uint256 _timeIndays) internal pure returns (uint256);
```

### _getAuctionWinners

Function to get the auction winners. It returns the node operators with the highest auction score.

*Reverts if not enough node operators in the auction to create a DV.*

*Reverts if a winner address is null.*

*We assume the winners directly accept to join the DV, therefore this function cleans the auction tree and auctionScore mapping.*


```solidity
function _getAuctionWinners() internal returns (address[] memory);
```

### onlyStategyModuleManager


```solidity
modifier onlyStategyModuleManager();
```

