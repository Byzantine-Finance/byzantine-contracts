# IStakerRewards
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IStakerRewards.sol)


## Functions
### dvCreationCheckpoint

Function called by StratVaultETH when a DV is created to add a new checkpoint and update variables


```solidity
function dvCreationCheckpoint(bytes32 _clusterId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The ID of the cluster|


### dvActivationCheckpoint

Function called by StratVaultETH when a DV is activated to add a new checkpoint and update variables


```solidity
function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|The address of the vault|
|`_clusterId`|`bytes32`|The ID of the cluster|


### withdrawCheckpoint

Function called by StratVaultETH when a staker exits the validator (unstake)


```solidity
function withdrawCheckpoint(address _vaultAddr) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|The address of the vault|


### updateUpkeepInterval

Function to update the upkeep interval


```solidity
function updateUpkeepInterval(uint256 _upkeepInterval) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_upkeepInterval`|`uint256`|The new upkeep interval|


### setForwarderAddress

Function to set the forwarder address


```solidity
function setForwarderAddress(address _forwarderAddress) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_forwarderAddress`|`address`|The address of the forwarder|


### calculateRewards

Calculate the pending rewards since last update

*Revert if the last update timestamp is 0*


```solidity
function calculateRewards(address _vaultAddr, uint256 _numDVs) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|
|`_numDVs`|`uint256`|Number of validators in the vault|


### getAllocatableRewards

Calculate the allocatable amount of ETH in the StakerRewards contract

*The calculation of the dailyRewardsPer32ETH cannot take into account the rewards that were already distributed to the stakers.*


```solidity
function getAllocatableRewards() external view returns (uint256);
```

### getClusterData

Returns the cluster data of a given clusterId


```solidity
function getClusterData(bytes32 _clusterId) external view returns (ClusterData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The ID of the cluster|


### getCheckpointData

Function to get the checkpoint data


```solidity
function getCheckpointData() external view returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The checkpoint data|


### getVaultData

Function to get the vault data for a given vault address


```solidity
function getVaultData(address _vaultAddr) external view returns (VaultData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|


## Errors
### OnlyStrategyVaultManager
*Error when unauthorized call to a function callable only by the StrategyVaultManager.*


```solidity
error OnlyStrategyVaultManager();
```

### OnlyStratVaultETH
*Error when unauthorized call to a function callable only by a StratVaultETH.*


```solidity
error OnlyStratVaultETH();
```

### FailedToSendRewards
*Returned when the transfer of the rewards to the StratVaultETH failed*


```solidity
error FailedToSendRewards();
```

### FailedToSendBidsToEscrow
*Error when the bid price cannot be sent back to the escrow*


```solidity
error FailedToSendBidsToEscrow();
```

### InvalidTimestamp
*Error when the timestamp is invalid*


```solidity
error InvalidTimestamp();
```

### NoCreatedClusters
*Error when there are no active cluster in the StakerRewards contract*


```solidity
error NoCreatedClusters();
```

### TotalVCsCannotBeZero
*Error when the total VC cannot be zero*


```solidity
error TotalVCsCannotBeZero();
```

### TotalVCsLessThanConsumedVCs
*Error when the total VC is less than the consumed VC*


```solidity
error TotalVCsLessThanConsumedVCs();
```

### UpkeepNotNeeded
*Returned when the upkeep is not needed*


```solidity
error UpkeepNotNeeded();
```

### NoPermissionToCallPerformUpkeep
*Error when performUpkeep() is not called by the Forwarder*


```solidity
error NoPermissionToCallPerformUpkeep();
```

## Structs
### Checkpoint
Checkpoint updated at every new event


```solidity
struct Checkpoint {
    uint256 updateTime;
    uint256 totalPendingRewards;
    uint256 dailyRewardsPer32ETH;
    uint64 totalVCs;
}
```

### ClusterData
Record every cluster at dvCreationCheckpoint


```solidity
struct ClusterData {
    uint256 activeTime;
    uint256 exitTimestamp;
    uint32 smallestVC;
    uint8 clusterSize;
}
```

### VaultData
Record every StratVaultETH at dvActivationCheckpoint


```solidity
struct VaultData {
    uint256 lastUpdate;
    uint16 numValidatorsInVault;
}
```

