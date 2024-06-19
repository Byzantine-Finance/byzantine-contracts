# AuctionStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/core/AuctionStorage.sol)

**Inherits:**
[IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)


## State Variables
### _WAD

```solidity
uint256 internal constant _WAD = 1e18;
```


### _BOND

```solidity
uint256 internal constant _BOND = 1 ether;
```


### escrow
Escrow contract


```solidity
IEscrow public immutable escrow;
```


### strategyModuleManager
StrategyModuleManager contract


```solidity
IStrategyModuleManager public immutable strategyModuleManager;
```


### _auctionTree
Auction scores stored in a Red-Black tree (complexity O(log 2n))


```solidity
HitchensOrderStatisticsTreeLib.Tree internal _auctionTree;
```


### expectedDailyReturnWei
Daily rewards of Ethereum Pos (in WEI)


```solidity
uint256 public expectedDailyReturnWei;
```


### minDuration
Minimum duration to be part of a DV (in days)


```solidity
uint160 public minDuration;
```


### numNodeOpsInAuction
Number of node operators in auction and seeking for a DV


```solidity
uint64 public numNodeOpsInAuction;
```


### maxDiscountRate
Maximum discount rate (i.e the max profit margin of node op) in percentage


```solidity
uint16 public maxDiscountRate;
```


### clusterSize
Number of nodes in a Distributed Validator


```solidity
uint8 public clusterSize;
```


### _nodeOpsInfo
Node operator address => node operator auction details


```solidity
mapping(address => AuctionDetails) internal _nodeOpsInfo;
```


### _nodeOpsWhitelist
Mapping for the whitelisted node operators


```solidity
mapping(address => bool) internal _nodeOpsWhitelist;
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
constructor(IEscrow _escrow, IStrategyModuleManager _strategyModuleManager);
```

