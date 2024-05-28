# StrategyModuleManager
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/a175940c55bcb788c83621ba4e22c28c3fbfcb7d/src/core/StrategyModuleManager.sol)

**Inherits:**
Initializable, OwnableUpgradeable, [StrategyModuleManagerStorage](/src/core/StrategyModuleManagerStorage.sol/abstract.StrategyModuleManagerStorage.md)


## Functions
### constructor


```solidity
constructor(
    IBeacon _stratModBeacon,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager
) StrategyModuleManagerStorage(_stratModBeacon, _auction, _byzNft, _eigenPodManager, _delegationManager);
```

### initialize

*Initializes the address of the initial owner*


```solidity
function initialize(address initialOwner) external initializer;
```

### onlyStratModOwner


```solidity
modifier onlyStratModOwner(address owner, address stratMod);
```

### createStratMod

Creates a StrategyModule for the sender.

*Returns StrategyModule address*


```solidity
function createStratMod() external returns (address);
```

### createStratModAndStakeNativeETH

A 32ETH staker create a Strategy Module and deposit in its smart contract its stake.

*This action triggers an auction to select node operators to create a Distributed Validator.*

*One node operator of the DV (the DV manager) will have to deposit the 32ETH in the Beacon Chain.*

*Function will revert if not exactly 32 ETH are sent with the transaction.*


```solidity
function createStratModAndStakeNativeETH() external payable returns (address, address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The addresses of the newly created StrategyModule AND the address of its associated EigenPod (for the DV withdrawal address)|
|`<none>`|`address`||


### transferStratModOwnership

Strategy Module owner can transfer its Strategy Module to another address.
Under the hood, he transfers the ByzNft associated to the StrategyModule.
That action makes him give the ownership of the StrategyModule and all the token it owns.

*The ByzNft owner must first call the `approve` function to allow the StrategyModuleManager to transfer the ByzNft.*

*Function will revert if not called by the ByzNft holder.*

*Function will revert if the new owner is the same as the old owner.*


```solidity
function transferStratModOwnership(
    address stratModAddr,
    address newOwner
) external onlyStratModOwner(msg.sender, stratModAddr);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The address of the StrategyModule the owner will transfer.|
|`newOwner`|`address`|The address of the new owner of the StrategyModule.|


### setTrustedDVPubKey

Byzantine owner fill the expected/ trusted public key for a DV (retrievable from the Obol SDK/API).

*Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator.*

*Revert if not callable by StrategyModuleManager owner.*


```solidity
function setTrustedDVPubKey(address stratModAddr, bytes calldata pubKey) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The address of the Strategy Module to set the trusted DV pubkey|
|`pubKey`|`bytes`|The public key of the DV retrieved with the Obol SDK/API from a configHash|


### getStratModNumber

Returns the number of StrategyModules owned by an address.


```solidity
function getStratModNumber(address staker) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know the number of Strategy Modules it owns.|


### getStratModByNftId

Returns the StrategyModule address by its bound ByzNft ID.

*Returns address(0) if the nftId is not bound to a Strategy Module (nftId is not a ByzNft)*


```solidity
function getStratModByNftId(uint256 nftId) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftId`|`uint256`|The ByzNft ID you want to know the attached Strategy Module.|


### getStratMods

Returns the addresses of the `staker`'s StrategyModules

*Returns an empty array if the staker has no Strategy Modules.*


```solidity
function getStratMods(address staker) public view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The staker address you want to know the Strategy Modules it owns.|


### hasStratMods

Returns 'true' if the `staker` owns at least one StrategyModule, and 'false' otherwise.


```solidity
function hasStratMods(address staker) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know if it owns at least a StrategyModule.|


### isDelegated

Specify which `staker`'s StrategyModules are delegated.

*Revert if the `staker` doesn't have any StrategyModule.*


```solidity
function isDelegated(address staker) public view returns (bool[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyModules' owner.|


### delegateTo

Specify to which operators `staker`'s StrategyModules are delegated to.

*Revert if the `staker` doesn't have any StrategyModule.*


```solidity
function delegateTo(address staker) public view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyModules' owner.|


### getPodByStratModAddr

Returns the address of the Strategy Module's EigenPod (whether it is deployed yet or not).

*If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function getPodByStratModAddr(address stratModAddr) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The address of the StrategyModule contract you want to know the EigenPod address.|


### hasPod

Returns 'true' if the `stratModAddr` has created an EigenPod, and 'false' otherwise.

*If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function hasPod(address stratModAddr) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The StrategyModule Address you want to know if it has created an EigenPod.|


### _deployStratMod


```solidity
function _deployStratMod() internal returns (address);
```

