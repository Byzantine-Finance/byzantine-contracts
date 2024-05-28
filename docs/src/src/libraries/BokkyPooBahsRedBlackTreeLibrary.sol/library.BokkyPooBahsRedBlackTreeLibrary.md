# BokkyPooBahsRedBlackTreeLibrary
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/a175940c55bcb788c83621ba4e22c28c3fbfcb7d/src/libraries/BokkyPooBahsRedBlackTreeLibrary.sol)


## State Variables
### EMPTY

```solidity
uint256 private constant EMPTY = 0;
```


## Functions
### first


```solidity
function first(Tree storage self) internal view returns (uint256 _key);
```

### last


```solidity
function last(Tree storage self) internal view returns (uint256 _key);
```

### next


```solidity
function next(Tree storage self, uint256 target) internal view returns (uint256 cursor);
```

### prev


```solidity
function prev(Tree storage self, uint256 target) internal view returns (uint256 cursor);
```

### exists


```solidity
function exists(Tree storage self, uint256 key) internal view returns (bool);
```

### isEmpty


```solidity
function isEmpty(uint256 key) internal pure returns (bool);
```

### getEmpty


```solidity
function getEmpty() internal pure returns (uint256);
```

### getNode


```solidity
function getNode(
    Tree storage self,
    uint256 key
) internal view returns (uint256 _returnKey, uint256 _parent, uint256 _left, uint256 _right, bool _red);
```

### insert


```solidity
function insert(Tree storage self, uint256 key) internal;
```

### remove


```solidity
function remove(Tree storage self, uint256 key) internal;
```

### treeMinimum


```solidity
function treeMinimum(Tree storage self, uint256 key) private view returns (uint256);
```

### treeMaximum


```solidity
function treeMaximum(Tree storage self, uint256 key) private view returns (uint256);
```

### rotateLeft


```solidity
function rotateLeft(Tree storage self, uint256 key) private;
```

### rotateRight


```solidity
function rotateRight(Tree storage self, uint256 key) private;
```

### insertFixup


```solidity
function insertFixup(Tree storage self, uint256 key) private;
```

### replaceParent


```solidity
function replaceParent(Tree storage self, uint256 a, uint256 b) private;
```

### removeFixup


```solidity
function removeFixup(Tree storage self, uint256 key) private;
```

## Structs
### Node

```solidity
struct Node {
    uint256 parent;
    uint256 left;
    uint256 right;
    bool red;
}
```

### Tree

```solidity
struct Tree {
    uint256 root;
    mapping(uint256 => Node) nodes;
}
```

