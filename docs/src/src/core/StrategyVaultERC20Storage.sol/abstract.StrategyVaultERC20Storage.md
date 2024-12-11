# StrategyVaultERC20Storage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultERC20Storage.sol)

**Inherits:**
[IStrategyVaultERC20](/src/interfaces/IStrategyVaultERC20.sol/interface.IStrategyVaultERC20.md)


## State Variables
### stratVaultManager
The single StrategyVaultManager for Byzantine


```solidity
IStrategyVaultManager public immutable stratVaultManager;
```


### byzNft
ByzNft contract


```solidity
IByzNft public immutable byzNft;
```


### strategyManager
EigenLayer's StrategyManager contract


```solidity
IStrategyManager public immutable strategyManager;
```


### delegationManager
EigenLayer's DelegationManager contract


```solidity
IDelegationManager public immutable delegationManager;
```


### stratVaultNftId
The ByzNft associated to this StrategyVault.

The owner of the ByzNft is the StrategyVault creator.
TODO When non-upgradeable put that variable immutable and set it in the constructor


```solidity
uint256 public stratVaultNftId;
```


### isWhitelisted
Whitelisted addresses that are allowed to deposit into the StrategyVault (activated only the whitelistedDeposit == true)


```solidity
mapping(address => bool) public isWhitelisted;
```


### whitelistedDeposit
Whether the deposit function is whitelisted or not.


```solidity
bool public whitelistedDeposit;
```


### upgradeable
Whether the strategy is upgradeable (i.e can delegate to a different operator)


```solidity
bool public upgradeable;
```


### __gap
*This empty reserved space is put in place to allow future versions to add new
variables without shifting down storage in the inheritance chain.
See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts*


```solidity
uint256[44] private __gap;
```


