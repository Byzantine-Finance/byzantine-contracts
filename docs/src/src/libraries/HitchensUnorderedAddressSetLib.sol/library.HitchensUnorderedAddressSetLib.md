# HitchensUnorderedAddressSetLib
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/libraries/HitchensUnorderedAddressSetLib.sol)


## Functions
### insert


```solidity
function insert(Set storage self, address key) internal;
```

### remove


```solidity
function remove(Set storage self, address key) internal;
```

### count


```solidity
function count(Set storage self) internal view returns (uint256);
```

### exists


```solidity
function exists(Set storage self, address key) internal view returns (bool);
```

### keyAtIndex


```solidity
function keyAtIndex(Set storage self, uint256 index) internal view returns (address);
```

## Structs
### Set

```solidity
struct Set {
    mapping(address => uint256) keyPointers;
    address[] keyList;
}
```

