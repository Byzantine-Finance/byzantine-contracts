# StrategyVaultETHStorage
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultETHStorage.sol)

**Inherits:**
[IStrategyVaultETH](/src/interfaces/IStrategyVaultETH.sol/interface.IStrategyVaultETH.md)


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


### auction
Address of the Auction contract


```solidity
IAuction public immutable auction;
```


### eigenPodManager
EigenLayer's EigenPodManager contract

*this is the pod manager transparent proxy*


```solidity
IEigenPodManager public immutable eigenPodManager;
```


### delegationManager
EigenLayer's DelegationManager contract


```solidity
IDelegationManager public immutable delegationManager;
```


### stakerRewards
StakerRewards contract


```solidity
IStakerRewards public immutable stakerRewards;
```


### FINALITY_TIME
Average time for block finality in the Beacon Chain


```solidity
uint16 internal constant FINALITY_TIME = 16 minutes;
```


### depositToken
The token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking Native ETH.


```solidity
address public constant depositToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```


### beaconChainAdmin
The address allowed to activate a DV and submit Beacon Merkle Proofs


```solidity
address public immutable beaconChainAdmin;
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


### clusterIdsFIFO
FIFO of all the cluster IDs of the StrategyVault


```solidity
FIFOLib.FIFO public clusterIdsFIFO;
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


### amountOfETH
Amount of ETH in the vault. Includes deposits from stakers as well as the accumulated Proof of Stake rewards.


```solidity
uint256 public amountOfETH;
```


### __gap
*This empty reserved space is put in place to allow future versions to add new
variables without shifting down storage in the inheritance chain.
See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts*


```solidity
uint256[43] private __gap;
```


