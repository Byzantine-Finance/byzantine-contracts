# HitchensOrderStatisticsTreeLib
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/libraries/HitchensOrderStatisticsTreeLib.sol)


## State Variables
### EMPTY

```solidity
uint256 private constant EMPTY = 0;
```


## Functions
### first


```solidity
function first(Tree storage self) internal view returns (uint256 _value);
```

### last


```solidity
function last(Tree storage self) internal view returns (uint256 _value);
```

### next


```solidity
function next(Tree storage self, uint256 value) internal view returns (uint256 _cursor);
```

### prev


```solidity
function prev(Tree storage self, uint256 value) internal view returns (uint256 _cursor);
```

### exists


```solidity
function exists(Tree storage self, uint256 value) internal view returns (bool _exists);
```

### keyExists


```solidity
function keyExists(Tree storage self, bytes32 key, uint256 value) internal view returns (bool _exists);
```

### getNode


```solidity
function getNode(
    Tree storage self,
    uint256 value
)
    internal
    view
    returns (uint256 _parent, uint256 _left, uint256 _right, bool _red, uint256 keyCount, uint256 __count);
```

### getNodeCount


```solidity
function getNodeCount(Tree storage self, uint256 value) internal view returns (uint256 __count);
```

### valueKeyAtIndex


```solidity
function valueKeyAtIndex(Tree storage self, uint256 value, uint256 index) internal view returns (bytes32 _key);
```

### count


```solidity
function count(Tree storage self) internal view returns (uint256 _count);
```

### percentile


```solidity
function percentile(Tree storage self, uint256 value) internal view returns (uint256 _percentile);
```

### permil


```solidity
function permil(Tree storage self, uint256 value) internal view returns (uint256 _permil);
```

### atPercentile


```solidity
function atPercentile(Tree storage self, uint256 _percentile) internal view returns (uint256 _value);
```

### atPermil


```solidity
function atPermil(Tree storage self, uint256 _permil) internal view returns (uint256 _value);
```

### median


```solidity
function median(Tree storage self) internal view returns (uint256 value);
```

### below


```solidity
function below(Tree storage self, uint256 value) public view returns (uint256 _below);
```

### above


```solidity
function above(Tree storage self, uint256 value) public view returns (uint256 _above);
```

### rank


```solidity
function rank(Tree storage self, uint256 value) internal view returns (uint256 _rank);
```

### atRank


```solidity
function atRank(Tree storage self, uint256 _rank) internal view returns (uint256 _value);
```

### insert


```solidity
function insert(Tree storage self, bytes32 key, uint256 value) internal;
```

### remove


```solidity
function remove(Tree storage self, bytes32 key, uint256 value) internal;
```

### fixCountRecurse


```solidity
function fixCountRecurse(Tree storage self, uint256 value) private;
```

### treeMinimum


```solidity
function treeMinimum(Tree storage self, uint256 value) private view returns (uint256);
```

### treeMaximum


```solidity
function treeMaximum(Tree storage self, uint256 value) private view returns (uint256);
```

### rotateLeft


```solidity
function rotateLeft(Tree storage self, uint256 value) private;
```

### rotateRight


```solidity
function rotateRight(Tree storage self, uint256 value) private;
```

### insertFixup


```solidity
function insertFixup(Tree storage self, uint256 value) private;
```

### replaceParent


```solidity
function replaceParent(Tree storage self, uint256 a, uint256 b) private;
```

### removeFixup


```solidity
function removeFixup(Tree storage self, uint256 value) private;
```

## Structs
### Node

```solidity
struct Node {
    uint256 parent;
    uint256 left;
    uint256 right;
    bool red;
    bytes32[] keys;
    mapping(bytes32 => uint256) keyMap;
    uint256 count;
}
```

### Tree

```solidity
struct Tree {
    uint256 root;
    mapping(uint256 => Node) nodes;
}
```

