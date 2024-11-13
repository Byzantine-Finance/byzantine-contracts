# FIFOLib
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/libraries/FIFOLib.sol)

Library which implements a FIFO (First In First Out) logic

The FIFO elements must be non-repeating and non-null

*The library is used to handle the clusterIds in the StrategyVaultETH contract storage*


## Functions
### push


```solidity
function push(FIFO storage self, bytes32 _id) internal;
```

### pop


```solidity
function pop(FIFO storage self) internal returns (bytes32);
```

### getNumElements


```solidity
function getNumElements(FIFO storage self) internal view returns (uint256);
```

### getAllElements


```solidity
function getAllElements(FIFO storage self) internal view returns (bytes32[] memory);
```

### exists


```solidity
function exists(FIFO storage self, bytes32 _id) internal view returns (bool);
```

## Structs
### FIFOElement

```solidity
struct FIFOElement {
    bytes32 id;
    bytes32 nextId;
}
```

### FIFO

```solidity
struct FIFO {
    FIFOElement head;
    FIFOElement tail;
    mapping(bytes32 => FIFOElement) element;
    uint256 count;
}
```

