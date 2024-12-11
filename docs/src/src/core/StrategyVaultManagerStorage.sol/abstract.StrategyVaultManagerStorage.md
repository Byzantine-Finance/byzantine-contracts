# StrategyVaultManagerStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultManagerStorage.sol)

**Inherits:**
[IStrategyVaultManager](/src/interfaces/IStrategyVaultManager.sol/interface.IStrategyVaultManager.md)


## State Variables
### stratVaultETHBeacon
Beacon proxy to which all the StrategyVaultETHs point


```solidity
IBeacon public immutable stratVaultETHBeacon;
```


### stratVaultERC20Beacon
Beacon proxy to which all the StrategyVaultERC20s point


```solidity
IBeacon public immutable stratVaultERC20Beacon;
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


### strategyManager
EigenLayer's StrategyManager contract


```solidity
IStrategyManager public immutable strategyManager;
```


### _stratVaultETHSet
Unordered Set of all the StratVaultETHs


```solidity
HitchensUnorderedAddressSetLib.Set internal _stratVaultETHSet;
```


### nftIdToStratVault
ByzNft tokenId to its tied StrategyVault


```solidity
mapping(uint256 => address) public nftIdToStratVault;
```


### numStratVaults
The number of StratVaults that have been deployed


```solidity
uint64 public numStratVaults;
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
    IBeacon _stratVaultETHBeacon,
    IBeacon _stratVaultERC20Beacon,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager,
    IStrategyManager _strategyManager
);
```

