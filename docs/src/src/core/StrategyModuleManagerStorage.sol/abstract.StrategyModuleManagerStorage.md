# StrategyVaultManagerStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/core/StrategyVaultManagerStorage.sol)

**Inherits:**
[IStrategyVaultManager](/src/interfaces/IStrategyVaultManager.sol/interface.IStrategyVaultManager.md)


## State Variables
### stratModBeacon
Beacon proxy to which the StrategyVaults point


```solidity
IBeacon public immutable stratModBeacon;
```


### byzNft
ByzNft contract


```solidity
IByzNft public immutable byzNft;
```


### auction
Auction contract


```solidity
IAuction public immutable auction;
```


### eigenPodManager
EigenLayer's EigenPodManager contract


```solidity
IEigenPodManager public immutable eigenPodManager;
```


### delegationManager
EigenLayer's DelegationManager contract


```solidity
IDelegationManager public immutable delegationManager;
```


### stakerToStratMods
Staker to its owned StrategyVaults


```solidity
mapping(address => address[]) public stakerToStratMods;
```


### nftIdToStratMod
ByzNft tokenId to its tied StrategyVault


```solidity
mapping(uint256 => address) public nftIdToStratMod;
```


### pendingClusters
Mapping to store the pre-created clusters waiting for work


```solidity
mapping(uint64 => IStrategyVault.ClusterDetails) public pendingClusters;
```


### numPreCreatedClusters
The number of pre-created clusters. Used as the mapping index.


```solidity
uint64 public numPreCreatedClusters;
```


### numStratMods
The number of StratMods that have been deployed


```solidity
uint64 public numStratMods;
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
    IBeacon _stratModBeacon,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager
);
```

