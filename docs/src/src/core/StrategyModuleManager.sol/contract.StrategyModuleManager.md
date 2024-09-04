# StrategyVaultManager
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/core/StrategyVaultManager.sol)

**Inherits:**
Initializable, OwnableUpgradeable, [StrategyVaultManagerStorage](/src/core/StrategyVaultManagerStorage.sol/abstract.StrategyVaultManagerStorage.md)


## Functions
### constructor


```solidity
constructor(
    IBeacon _stratVaultBeacon,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager
) StrategyVaultManagerStorage(_stratVaultBeacon, _auction, _byzNft, _eigenPodManager, _delegationManager);
```

### initialize

*Initializes the address of the initial owner*


```solidity
function initialize(address initialOwner) external initializer;
```

### onlyStratVaultOwner


```solidity
modifier onlyStratVaultOwner(address owner, address stratVault);
```

### preCreateDVs

Function to pre-create Distributed Validators. Must be called at least one time to allow stakers to enter in the protocol.

*This function is only callable by Byzantine Finance. Once the first DVs are pre-created, the stakers
pre-create a new DV every time they create a new StrategyVault (if enough operators in Auction).*


```solidity
function preCreateDVs(uint8 _numDVsToPreCreate) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_numDVsToPreCreate`|`uint8`|Number of Distributed Validators to pre-create.|


### createStratVaultAndStakeNativeETH

A 32ETH staker create a Strategy Vault, use a pre-created DV as a validator and activate it by depositing 32ETH.

*This action triggers a new auction to pre-create a new Distributed Validator for the next staker (if enough operators in Auction).*

*It also fill the ClusterDetails struct of the newly created StrategyVault.*

*Function will revert if not exactly 32 ETH are sent with the transaction.*


```solidity
function createStratVaultAndStakeNativeETH(
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


### transferStratVaultOwnership

TODO Verify the pubkey in arguments to be sure it is using the right pubkey of a pre-created cluster

Strategy Vault owner can transfer its Strategy Vault to another address.
Under the hood, he transfers the ByzNft associated to the StrategyVault.
That action makes him give the ownership of the StrategyVault and all the token it owns.

*The ByzNft owner must first call the `approve` function to allow the StrategyVaultManager to transfer the ByzNft.*

*Function will revert if not called by the ByzNft holder.*

*Function will revert if the new owner is the same as the old owner.*


```solidity
function transferStratVaultOwnership(
    address stratVaultAddr,
    address newOwner
) external onlyStratVaultOwner(msg.sender, stratVaultAddr);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVaultAddr`|`address`|The address of the StrategyVault the owner will transfer.|
|`newOwner`|`address`|The address of the new owner of the StrategyVault.|


### preCalculatePodAddress

Returns the address of the Eigen Pod of a specific StrategyVault.

*Function essential to pre-crete DVs as their withdrawal address has to be the Eigen Pod address.*


```solidity
function preCalculatePodAddress(uint64 _nounce) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nounce`|`uint64`|The index of the Strategy Vault you want to know the Eigen Pod address.|


### getNumPendingClusters

Returns the number of current pending clusters waiting for a Strategy Vault.


```solidity
function getNumPendingClusters() public view returns (uint64);
```

### getPendingClusterNodeDetails

Returns the node details of a pending cluster.

*If the index does not exist, it returns the default value of the Node struct.*


```solidity
function getPendingClusterNodeDetails(uint64 clusterIndex) public view returns (IStrategyVault.Node[4] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`clusterIndex`|`uint64`|The index of the pending cluster you want to know the node details.|


### getStratVaultNumber

Returns the number of StrategyVaults owned by an address.


```solidity
function getStratVaultNumber(address staker) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know the number of Strategy Vaults it owns.|


### getStratVaultByNftId

Returns the StrategyVault address by its bound ByzNft ID.

*Returns address(0) if the nftId is not bound to a Strategy Vault (nftId is not a ByzNft)*


```solidity
function getStratVaultByNftId(uint256 nftId) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftId`|`uint256`|The ByzNft ID you want to know the attached Strategy Vault.|


### getStratVaults

Returns the addresses of the `staker`'s StrategyVaults

*Returns an empty array if the staker has no Strategy Vaults.*


```solidity
function getStratVaults(address staker) public view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The staker address you want to know the Strategy Vaults it owns.|


### hasStratVaults

Returns 'true' if the `staker` owns at least one StrategyVault, and 'false' otherwise.


```solidity
function hasStratVaults(address staker) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address you want to know if it owns at least a StrategyVault.|


### isDelegated

Specify which `staker`'s StrategyVaults are delegated.

*Revert if the `staker` doesn't have any StrategyVault.*


```solidity
function isDelegated(address staker) public view returns (bool[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyVaults' owner.|


### hasDelegatedTo

Specify to which operators `staker`'s StrategyVaults has delegated to.

*Revert if the `staker` doesn't have any StrategyVault.*


```solidity
function hasDelegatedTo(address staker) public view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address of the StrategyVaults' owner.|


### getPodByStratVaultAddr

Returns the address of the Strategy Vault's EigenPod (whether it is deployed yet or not).

*If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function getPodByStratVaultAddr(address stratVaultAddr) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVaultAddr`|`address`|The address of the StrategyVault contract you want to know the EigenPod address.|


### hasPod

Returns 'true' if the `stratVaultAddr` has created an EigenPod, and 'false' otherwise.

*If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function hasPod(address stratVaultAddr) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVaultAddr`|`address`|The StrategyVault Address you want to know if it has created an EigenPod.|


### _deployStratVault


```solidity
function _deployStratVault() internal returns (IStrategyVault);
```

