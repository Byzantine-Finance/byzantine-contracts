# AuctionStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/AuctionStorage.sol)

**Inherits:**
[IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)


## State Variables
### NODE_OP_SPLIT_ALLOCATION
The split operators allocation


```solidity
uint256 public constant NODE_OP_SPLIT_ALLOCATION = 250_000;
```


### SPLIT_TOTAL_ALLOCATION
The split total allocation


```solidity
uint256 public constant SPLIT_TOTAL_ALLOCATION = 1_000_000;
```


### _BOND
Bond to pay for the non whitelisted node operators


```solidity
uint256 internal constant _BOND = 1 ether;
```


### SPLIT_DISTRIBUTION_INCENTIVE
The split distribution incentive


```solidity
uint16 public constant SPLIT_DISTRIBUTION_INCENTIVE = 20_000;
```


### _CLUSTER_SIZE_4
Number of nodes in a Distributed Validator


```solidity
uint8 internal constant _CLUSTER_SIZE_4 = 4;
```


### _CLUSTER_SIZE_7

```solidity
uint8 internal constant _CLUSTER_SIZE_7 = 7;
```


### escrow
Escrow contract


```solidity
IEscrow public immutable escrow;
```


### strategyVaultManager
StrategyVaultManager contract


```solidity
IStrategyVaultManager public immutable strategyVaultManager;
```


### pushSplitFactory
0xSplits' PushSplitFactory contract


```solidity
PushSplitFactory public immutable pushSplitFactory;
```


### stakerRewards
StakerRewards contract


```solidity
IStakerRewards public immutable stakerRewards;
```


### _mainAuctionTree
Red-Black tree to store the main auction scores (auction gathering DV4, DV7 and already created DVs)


```solidity
HitchensOrderStatisticsTreeLib.Tree internal _mainAuctionTree;
```


### _dv4AuctionTree
Red-Black tree to store the sub-auction scores (DV4)


```solidity
HitchensOrderStatisticsTreeLib.Tree internal _dv4AuctionTree;
```


### _dv4LatestWinningInfo
Latest winning info of the dv4 sub-auction


```solidity
LatestWinningInfo internal _dv4LatestWinningInfo;
```


### _dv7AuctionTree
Red-Black tree to store the sub-auction non-winning scores (DV7)


```solidity
HitchensOrderStatisticsTreeLib.Tree internal _dv7AuctionTree;
```


### _dv7LatestWinningInfo
Latest winning info of the dv7 sub-auction


```solidity
LatestWinningInfo internal _dv7LatestWinningInfo;
```


### expectedDailyReturnWei
Daily rewards of Ethereum Pos (in WEI)


```solidity
uint256 public expectedDailyReturnWei;
```


### minDuration
Minimum duration to be part of a DV (in days)


```solidity
uint32 public minDuration;
```


### dv4AuctionNumNodeOps
Number of node operators in the DV4 sub-auction


```solidity
uint16 public dv4AuctionNumNodeOps;
```


### dv7AuctionNumNodeOps
Number of node operators in the DV7 sub-auction


```solidity
uint16 public dv7AuctionNumNodeOps;
```


### maxDiscountRate
Maximum discount rate (i.e the max profit margin of node op) in percentage


```solidity
uint16 public maxDiscountRate;
```


### _nodeOpsDetails
Node operator address => node operator global details


```solidity
mapping(address => NodeOpGlobalDetails) internal _nodeOpsDetails;
```


### _bidDetails
Bid id => bid details


```solidity
mapping(bytes32 => BidDetails) internal _bidDetails;
```


### _clusterDetails
Cluster ID => cluster details


```solidity
mapping(bytes32 => ClusterDetails) internal _clusterDetails;
```


### __gap
*This empty reserved space is put in place to allow future versions to add new
variables without shifting down storage in the inheritance chain.
See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts*


```solidity
uint256[44] private __gap;
```


## Functions
### constructor


```solidity
constructor(
    IEscrow _escrow,
    IStrategyVaultManager _strategyVaultManager,
    PushSplitFactory _pushSplitFactory,
    IStakerRewards _stakerRewards
);
```

