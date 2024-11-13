# Auction
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/Auction.sol)

**Inherits:**
Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, [AuctionStorage](/src/core/AuctionStorage.sol/abstract.AuctionStorage.md)

TODO: Calculation of the reputation score of node operators


## Functions
### constructor


```solidity
constructor(
    IEscrow _escrow,
    IStrategyVaultManager _strategyVaultManager,
    PushSplitFactory _pushSplitFactory,
    IStakerRewards _stakerRewards
) AuctionStorage(_escrow, _strategyVaultManager, _pushSplitFactory, _stakerRewards);
```

### initialize

*Initializes the address of the initial owner plus the auction parameters*


```solidity
function initialize(
    address _initialOwner,
    uint256 _expectedDailyReturnWei,
    uint16 _maxDiscountRate,
    uint32 _minDuration
) external initializer;
```

### triggerAuction

Function triggered by the StrategyVaultManager or a StrategyVaultETH every time a staker deposits ETH

*It triggers the DV Auction, returns the winning cluster ID and triggers a new sub-auction*

*Reverts if not enough node operators in the protocol*

*Reverts if the caller is not a StrategyVaultETH contract or the StrategyVaultManager*


```solidity
function triggerAuction() external onlyStratVaultETH nonReentrant returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The id of the winning cluster|


### getPriceToPay

Function to determine the bid price a node operator will have to pay

*Revert if `_discountRate` or `_timeInDays` don't respect the minimum values set by Byzantine.*

*Reverts if the auction type is unknown*


```solidity
function getPriceToPay(
    address _nodeOpAddr,
    uint16 _discountRate,
    uint32 _timeInDays,
    AuctionType _auctionType
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_discountRate`|`uint16`||
|`_timeInDays`|`uint32`||
|`_auctionType`|`AuctionType`||


### bid

Bid function to join a cluster type specified by `_auctionType`. A call to that function will search the sub-auctions winners, calculate their average score, and put the virtual DV in the main auction.
Every time a new bid modify the sub-auctions winners, it update the main auction by removing the previous virtual DV and adding the new one.

*The bid price is sent to an escrow smart contract. As long as the node operator doesn't win the auction, its bids stays in the escrow contract.
It is possible to ask the escrow contract to refund the bid if the operator wants to leave the protocol (call `withdrawBid`)
It is possible to update an existing bid parameters (call `updateBid`).*

*Reverts if the bidder is not whitelisted (permissionless DV will arrive later)*

*Reverts if the discount rate is too high or the duration is too short*

*Reverts if the ethers sent by the node op are not enough to pay for the bid(s) (and the bond). If too many ethers has been sent the function returns the excess to the sender.*

*Reverts if the auction type is unknown*


```solidity
function bid(
    uint16 _discountRate,
    uint32 _timeInDays,
    AuctionType _auctionType
) external payable nonReentrant returns (bytes32 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_discountRate`|`uint16`|The desired profit margin in percentage of the operator (scale from 0 to 10000)|
|`_timeInDays`|`uint32`|Duration of being part of a DV, in days|
|`_auctionType`|`AuctionType`|cluster type the node operator wants to join (dv4, dv7, private dv, ...)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`bytes32`|The id of the bid|


### getUpdateBidPrice

TODO: Get the reputation score of msg.sender

Fonction to determine the price to add if the node operator outbids. Returns 0 if he downbids.

*Reverts if the node op doesn't have a bid with `_bidId`.*

*Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.*


```solidity
function getUpdateBidPrice(
    address _nodeOpAddr,
    bytes32 _bidId,
    uint16 _newDiscountRate,
    uint32 _newTimeInDays
) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`||
|`_bidId`|`bytes32`||
|`_newDiscountRate`|`uint16`||
|`_newTimeInDays`|`uint32`||


### updateBid

Update a bid of a node operator's `_bidId`. The node op will have to pay more if he outbids.
If he decreases his bid, the escrow contract will send him back the price difference.

*Reverts if the node op doesn't have a bid with `_bidId`.*

*Revert if `_newDiscountRate` or `_newTimeInDays` don't respect the values set by the byzantine.*

*Reverts if the transfer of the funds to the Escrow contract failed.*


```solidity
function updateBid(bytes32 _bidId, uint16 _newDiscountRate, uint32 _newTimeInDays) external payable nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`bytes32`||
|`_newDiscountRate`|`uint16`||
|`_newTimeInDays`|`uint32`||


### withdrawBid

TODO: Get the reputation score of msg.sender

Allow a node operator to withdraw a specific bid (through its bidId).
The withdrawer will be refund its bid price plus (the bond of he paid it).

*Reverts if the node op doesn't have a bid with `_bidId`.*


```solidity
function withdrawBid(bytes32 _bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`bytes32`||


### updateNodeVCNumber

Update the VC number of a node and the cluster status

*This function is callable only by the StakerRewards contract
TODO: add a try catch to handle the case where consumedVCs is greater than currentVCs*


```solidity
function updateNodeVCNumber(bytes32 _clusterId, uint32 _consumedVCs) external onlyStakerRewards;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`||
|`_consumedVCs`|`uint32`||


### updateClusterStatus

Update the status of a cluster

*Callable only by a StrategyVaultETH contract*

*The check to know if the cluster is in the calling vault is done in the StrategyVaultETH contract*


```solidity
function updateClusterStatus(bytes32 _clusterId, IAuction.ClusterStatus _newStatus) external onlyStratVaultETH;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The id of the cluster to update the status|
|`_newStatus`|`IAuction.ClusterStatus`|The new status|


### setClusterPubKey

Set the pubkey hash of a cluster

*Callable only by a StrategyVaultETH contract*

*The check to know if the cluster is in the calling vault is done in the StrategyVaultETH contract*


```solidity
function setClusterPubKey(bytes32 _clusterId, bytes calldata _clusterPubkey) external onlyStratVaultETH;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The id of the cluster to set the pubkey hash|
|`_clusterPubkey`|`bytes`|The pubkey of the cluster|


### isWhitelisted

Returns true if `_nodeOpAddr` is whitelisted, false otherwise.


```solidity
function isWhitelisted(address _nodeOpAddr) public view returns (bool);
```

### getNodeOpDetails

Returns the globaldetails of a specific node operator


```solidity
function getNodeOpDetails(address _nodeOpAddr) public view returns (NodeOpGlobalDetails memory);
```

### getNumDVInAuction

Returns the number of DVs in the main auction


```solidity
function getNumDVInAuction() public view returns (uint256);
```

### getBidDetails

Returns the details of a specific bid


```solidity
function getBidDetails(bytes32 _bidId) public view returns (BidDetails memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`bytes32`|The unique identifier of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BidDetails`|BidDetails struct containing the bid details|


### getClusterDetails

Returns the details of a specific cluster


```solidity
function getClusterDetails(bytes32 _clusterId) public view returns (ClusterDetails memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The unique identifier of the cluster|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ClusterDetails`|ClusterDetails struct containing the cluster details|


### getWinningCluster

Returns the id of the cluster with the highest average auction score

*Returns (bytes32(0), 0) if main tree is empty*


```solidity
function getWinningCluster() public view returns (bytes32 winningClusterId, uint256 highestAvgAuctionScore);
```

### whitelistNodeOps

Add node operators to the whitelist


```solidity
function whitelistNodeOps(address[] calldata _nodeOpAddrs) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddrs`|`address[]`||


### updateExpectedDailyReturnWei

Remove a node operator to the the whitelist.

Update the expected daily PoS rewards variable (in Wei)

*Revert if the node operator is not whitelisted.*

*This function is callable only by the Auction contract's owner*


```solidity
function updateExpectedDailyReturnWei(uint256 _newExpectedDailyReturnWei) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newExpectedDailyReturnWei`|`uint256`||


### updateMinDuration

Update the minimum validation duration

*This function is callable only by the Auction contract's owner*


```solidity
function updateMinDuration(uint32 _newMinDuration) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMinDuration`|`uint32`||


### updateMaxDiscountRate

Update the maximum discount rate

*This function is callable only by the Auction contract's owner*


```solidity
function updateMaxDiscountRate(uint16 _newMaxDiscountRate) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMaxDiscountRate`|`uint16`||


### _dv4UpdateMainAuction


```solidity
function _dv4UpdateMainAuction() private;
```

### _mainUdateSubAuction

Called to update the winning cluster's sub-auction tree


```solidity
function _mainUdateSubAuction(
    NodeDetails[] memory _nodesToRemove,
    bytes32 _winningClusterId,
    AuctionType _auctionType
) private;
```

### _updateMainAuctionTree

Update the main auction tree by adding a new virtual cluster and removing the old one


```solidity
function _updateMainAuctionTree(bytes32 _newClusterId, uint256 _newAvgAuctionScore, AuctionType _auctionType) private;
```

### _createClusterDetails

Create a new entry in the `_clusterDetails` mapping


```solidity
function _createClusterDetails(bytes32 _clusterId, uint256 _averageAuctionScore, NodeDetails[] memory _nodes) private;
```

### _verifyEthSent

Verify if the bidder has sent enough ethers. Refund the excess if it's the case.


```solidity
function _verifyEthSent(uint256 _ethSent, uint256 _priceToPay) private;
```

### _transferToEscrow

Transfer `_priceToPay` to the Escrow contract


```solidity
function _transferToEscrow(uint256 _priceToPay) private;
```

### _createSplitParams

Create the split parameters depending on the winning nodes


```solidity
function _createSplitParams(NodeDetails[] memory _nodes) internal view returns (SplitV2Lib.Split memory);
```

### onlyStratVaultETH


```solidity
modifier onlyStratVaultETH();
```

### onlyStakerRewards


```solidity
modifier onlyStakerRewards();
```

