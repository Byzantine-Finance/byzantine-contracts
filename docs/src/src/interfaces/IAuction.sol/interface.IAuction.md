# IAuction
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IAuction.sol)


## Functions
### expectedDailyReturnWei

Returns the daily rewards of Ethereum PoS (in WEI)

*Used for the Validation Credit's price calculation*


```solidity
function expectedDailyReturnWei() external view returns (uint256);
```

### minDuration

Returns the minimum duration to be part of a DV (in days)


```solidity
function minDuration() external view returns (uint32);
```

### maxDiscountRate

Returns the maximum discount rate (i.e the max profit margin of node op) in percentage (0 to 10_000 -> 100%)


```solidity
function maxDiscountRate() external view returns (uint16);
```

### isWhitelisted

Returns true if `_nodeOpAddr` is whitelisted, false otherwise.


```solidity
function isWhitelisted(address _nodeOpAddr) external view returns (bool);
```

### getNodeOpDetails

Returns the globaldetails of a specific node operator


```solidity
function getNodeOpDetails(address _nodeOpAddr) external view returns (NodeOpGlobalDetails memory);
```

### getNumDVInAuction

Returns the number of DVs in the main auction


```solidity
function getNumDVInAuction() external view returns (uint256);
```

### getBidDetails

Returns the details of a specific bid


```solidity
function getBidDetails(bytes32 _bidId) external view returns (BidDetails memory);
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
function getClusterDetails(bytes32 _clusterId) external view returns (ClusterDetails memory);
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

*Returns 0 if main tree is empty*


```solidity
function getWinningCluster() external view returns (bytes32, uint256);
```

### triggerAuction

Function triggered by the StrategyVaultManager or a StrategyVaultETH every time a staker deposits ETH

*It triggers the DV Auction, returns the winning cluster ID and triggers a new sub-auction*

*Reverts if not enough node operators in the protocol*

*Reverts if the caller is not a StrategyVaultETH contract or the StrategyVaultManager*


```solidity
function triggerAuction() external returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The id of the winning cluster|


### getPriceToPay

Function to determine the bid price a node operator will have to pay

*Revert if `_discountRate` or `_timeInDays` don't respect the minimum values set by Byzantine.*

*Revert if the auction type is unknown*


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
function bid(uint16 _discountRate, uint32 _timeInDays, AuctionType _auctionType) external payable returns (bytes32);
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
|`<none>`|`bytes32`|bidId The id of the bid|


### getUpdateBidPrice

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
function updateBid(bytes32 _bidId, uint16 _newDiscountRate, uint32 _newTimeInDays) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`bytes32`||
|`_newDiscountRate`|`uint16`||
|`_newTimeInDays`|`uint32`||


### withdrawBid

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


### updateClusterStatus

Update the status of a cluster

*Callable only by a StrategyVaultETH contract*

*The check to know if the cluster is in the calling vault is done in the StrategyVaultETH contract*


```solidity
function updateClusterStatus(bytes32 _clusterId, IAuction.ClusterStatus _newStatus) external;
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
function setClusterPubKey(bytes32 _clusterId, bytes calldata _clusterPubkey) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The id of the cluster to set the pubkey hash|
|`_clusterPubkey`|`bytes`|The pubkey of the cluster|


### whitelistNodeOps

Add node operators to the whitelist


```solidity
function whitelistNodeOps(address[] calldata _nodeOpAddrs) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddrs`|`address[]`||


### updateExpectedDailyReturnWei

Update the expected daily PoS rewards variable (in Wei)

*This function is callable only by the Auction contract's owner*


```solidity
function updateExpectedDailyReturnWei(uint256 _newExpectedDailyReturnWei) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newExpectedDailyReturnWei`|`uint256`||


### updateMinDuration

Update the minimum validation duration

*This function is callable only by the Auction contract's owner*


```solidity
function updateMinDuration(uint32 _newMinDuration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMinDuration`|`uint32`||


### updateMaxDiscountRate

Update the maximum discount rate

*This function is callable only by the Auction contract's owner*


```solidity
function updateMaxDiscountRate(uint16 _newMaxDiscountRate) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMaxDiscountRate`|`uint16`||


### updateNodeVCNumber

Update the VC number of a node and the cluster status

*This function is callable only by the StakerRewards contract*


```solidity
function updateNodeVCNumber(bytes32 _clusterId, uint32 _consumedVCs) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`||
|`_consumedVCs`|`uint32`||


## Events
### BidPlaced
Emitted when a bid is placed. Track all the bids done on Byzantine.


```solidity
event BidPlaced(
    address indexed nodeOpAddr,
    bytes32 bidId,
    uint16 discountRate,
    uint32 duration,
    uint256 bidPrice,
    uint256 auctionScore,
    AuctionType auctionType
);
```

### BidUpdated
Emitted when a bid is updated


```solidity
event BidUpdated(
    address indexed nodeOpAddr,
    bytes32 indexed bidId,
    uint16 newDiscountRate,
    uint32 newDuration,
    uint256 newBidPrice,
    uint256 newAuctionScore
);
```

### BidWithdrawn
Emitted when a bid is withdrawn


```solidity
event BidWithdrawn(address indexed nodeOpAddr, bytes32 indexed bidId);
```

### WinnerJoinedCluster
Emitted when a node operator joins a cluster. Track node operators' clusters.


```solidity
event WinnerJoinedCluster(address indexed nodeOpAddr, bytes32 indexed clusterJoined, bytes32 winningBidId);
```

### ClusterCreated
Emitted when a cluster is created. Track all the Byzantines' clusters.


```solidity
event ClusterCreated(
    bytes32 indexed clusterId, uint256 averageAuctionScore, address vaultAddr, address splitAddr, address eigenPodAddr
);
```

## Errors
### OnlyStratVaultETH
*Error when unauthorized call to a function callable only by a StratVaultETH.*


```solidity
error OnlyStratVaultETH();
```

### OnlyStakerRewards
*Error when unauthorized call to a function callable only by a StakerRewards.*


```solidity
error OnlyStakerRewards();
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

### RefundFailed
*Returned when a bid refund failed*


```solidity
error RefundFailed();
```

### MainAuctionEmpty
*Returned when the main auction tree is empty, and therefore when it's not possible to create a new DV*


```solidity
error MainAuctionEmpty();
```

### SenderNotBidder
*Returned when the sender is not the bidder of the bid to update or withdraw*


```solidity
error SenderNotBidder();
```

### InvalidAuctionType
*Returned when the auction type (i.e the sub-auction) is unknown*


```solidity
error InvalidAuctionType();
```

## Structs
### BidDetails
Stores the details of a specific bid


```solidity
struct BidDetails {
    uint256 auctionScore;
    uint256 bidPrice;
    address nodeOp;
    uint32 vcNumber;
    uint16 discountRate;
    AuctionType auctionType;
}
```

### NodeOpGlobalDetails
Stores the node operators global auction's details


```solidity
struct NodeOpGlobalDetails {
    uint32 reputationScore;
    uint16 numBonds;
    uint8 numBidsCluster4;
    uint8 numBidsCluster7;
    bool isWhitelisted;
}
```

### LatestWinningInfo
Stores the threshold above which a virtual cluster changes plus the id of the lastest winning cluster


```solidity
struct LatestWinningInfo {
    uint256 lastestWinningScore;
    bytes32 latestWinningClusterId;
}
```

### ClusterDetails
Stores the nodes details of a Distributed Validator


```solidity
struct ClusterDetails {
    bytes32 clusterPubKeyHash;
    uint256 averageAuctionScore;
    NodeDetails[] nodes;
    address splitAddr;
    ClusterStatus status;
}
```

### NodeDetails
Stores a node operator DV details through its winning bidId

*When rebuying VCs, take the discount rate of the bidId*


```solidity
struct NodeDetails {
    bytes32 bidId;
    uint32 currentVCNumber;
}
```

## Enums
### AuctionType
Defines the types of auctions available


```solidity
enum AuctionType {
    NULL,
    JOIN_CLUSTER_4,
    JOIN_CLUSTER_7
}
```

### ClusterStatus
Defines the status of a cluster


```solidity
enum ClusterStatus {
    INACTIVE,
    IN_CREATION,
    DEPOSITED,
    EXITED
}
```

