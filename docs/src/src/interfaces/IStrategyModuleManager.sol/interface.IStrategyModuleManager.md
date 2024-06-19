# IStrategyModuleManager
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/interfaces/IStrategyModuleManager.sol)


## Functions
### numPreCreatedClusters

Get total number of pre-created clusters.


```solidity
function numPreCreatedClusters() external view returns (uint64);
```

### numStratMods

Get the total number of Strategy Modules that have been deployed.


```solidity
function numStratMods() external view returns (uint64);
```

### preCreateDVs

Function to pre-create Distributed Validators. Must be called at least one time to allow stakers to enter in the protocol.

*This function is only callable by Byzantine Finance. Once the first DVs are pre-created, the stakers
pre-create a new DV every time they create a new StrategyModule (if enough operators in Auction).*


```solidity
function preCreateDVs(uint8 _numDVsToPreCreate) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_numDVsToPreCreate`|`uint8`|Number of Distributed Validators to pre-create.|


### createStratModAndStakeNativeETH

A 32ETH staker create a Strategy Module, use a pre-created DV as a validator and activate it by depositing 32ETH.

*This action triggers a new auction to pre-create a new Distributed Validator for the next staker (if enough operators in Auction).*

*It also fill the ClusterDetails struct of the newly created StrategyModule.*

*Function will revert if not exactly 32 ETH are sent with the transaction.*


```solidity
function createStratModAndStakeNativeETH(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 depositDataRoot
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pubkey`|`bytes`|The 48 bytes public key of the beacon chain DV.|
|`signature`|`bytes`|The DV's signature of the deposit data.|
|`depositDataRoot`|`bytes32`|The root/hash of the deposit data for the DV's deposit.|


### transferStratModOwnership

Strategy Module owner can transfer its Strategy Module to another address.
Under the hood, he transfers the ByzNft associated to the StrategyModule.
That action makes him give the ownership of the StrategyModule and all the token it owns.

*The ByzNft owner must first call the `approve` function to allow the StrategyModuleManager to transfer the ByzNft.*

*Function will revert if not called by the ByzNft holder.*

*Function will revert if the new owner is the same as the old owner.*


```solidity
function transferStratModOwnership(address stratModAddr, address newOwner) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The address of the StrategyModule the owner will transfer.|
|`newOwner`|`address`|The address of the new owner of the StrategyModule.|


### preCalculatePodAddress

Returns the address of the Eigen Pod of a specific StrategyModule.

*Function essential to pre-crete DVs as their withdrawal address has to be the Eigen Pod address.*


```solidity
function preCalculatePodAddress(uint64 _nounce) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nounce`|`uint64`|The index of the Strategy Module you want to know the Eigen Pod address.|


### getNumPendingClusters

Returns the number of current pending clusters waiting for a Strategy Module.


```solidity
function getNumPendingClusters() external view returns (uint64);
```

### getPendingClusterNodeDetails

Returns the node details of a pending cluster.

*If the index does not exist, it returns the default value of the Node struct.*


```solidity
function getPendingClusterNodeDetails(uint64 clusterIndex) external view returns (IStrategyModule.Node[4] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`clusterIndex`|`uint64`|The index of the pending cluster you want to know the node details.|


### getStratModNumber

Returns the number of StrategyModules owned by an address.


```solidity
function getStratModNumber(address staker) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know the number of Strategy Modules it owns.|


### getStratModByNftId

Returns the StrategyModule address by its bound ByzNft ID.

*Returns address(0) if the nftId is not bound to a Strategy Module (nftId is not a ByzNft)*


```solidity
function getStratModByNftId(uint256 nftId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftId`|`uint256`|The ByzNft ID you want to know the attached Strategy Module.|


### getStratMods

Returns the addresses of the `staker`'s StrategyModules

*Returns an empty array if the staker has no Strategy Modules.*


```solidity
function getStratMods(address staker) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The staker address you want to know the Strategy Modules it owns.|


### getPodByStratModAddr

Returns the address of the Strategy Module's EigenPod (whether it is deployed yet or not).

*If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function getPodByStratModAddr(address stratModAddr) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The address of the StrategyModule contract you want to know the EigenPod address.|


### hasStratMods

Returns 'true' if the `staker` owns at least one StrategyModule, and 'false' otherwise.


```solidity
function hasStratMods(address staker) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know if it owns at least a StrategyModule.|


### isDelegated

Specify which `staker`'s StrategyModules are delegated.

*Revert if the `staker` doesn't have any StrategyModule.*


```solidity
function isDelegated(address staker) external view returns (bool[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyModules' owner.|


### hasDelegatedTo

Specify to which operators `staker`'s StrategyModules has delegated to.

*Revert if the `staker` doesn't have any StrategyModule.*


```solidity
function hasDelegatedTo(address staker) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyModules' owner.|


### hasPod

Returns 'true' if the `stratModAddr` has created an EigenPod, and 'false' otherwise.

*If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function hasPod(address stratModAddr) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratModAddr`|`address`|The StrategyModule Address you want to know if it has created an EigenPod.|


## Errors
### DoNotHaveStratMod
*Returned when a specific address doesn't have a StrategyModule*


```solidity
error DoNotHaveStratMod(address);
```

### NotStratModOwner
*Returned when unauthorized call to a function only callable by the StrategyModule owner*


```solidity
error NotStratModOwner();
```

