# AuctionStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/a175940c55bcb788c83621ba4e22c28c3fbfcb7d/src/core/AuctionStorage.sol)

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
Auction scores stored in a Red-Black tree (complexity O(log n))


```solidity
BokkyPooBahsRedBlackTreeLibrary.Tree internal _auctionTree;
```


### _expectedDailyReturnWei
Daily rewards of Ethereum Pos (in WEI)


```solidity
uint256 internal _expectedDailyReturnWei;
```


### _minDuration
Minimum duration to be part of a DV (in days)


```solidity
uint256 internal _minDuration;
```


### _maxDiscountRate
Maximum discount rate (i.e the max profit margin of node op) in percentage (from 0 to 10000 -> 100%)


```solidity
uint256 internal _maxDiscountRate;
```


### _clusterSize
Number of nodes in a Distributed Validator


```solidity
uint256 internal _clusterSize;
```


### escrowAddr
Escrow contract address where the bids and the bonds are sent and stored


```solidity
address payable public escrowAddr;
```


### _nodeOpsInfo
Node operator address => node operator auction details


```solidity
mapping(address => NodeOpDetails) internal _nodeOpsInfo;
```


### _auctionScoreToNodeOp
Auction score => node operator address


```solidity
mapping(uint256 => address) internal _auctionScoreToNodeOp;
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

