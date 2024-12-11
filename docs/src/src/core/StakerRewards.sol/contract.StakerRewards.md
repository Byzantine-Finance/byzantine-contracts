# StakerRewards
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StakerRewards.sol)

**Inherits:**
Initializable, ReentrancyGuardUpgradeable, AutomationCompatibleInterface, OwnerIsCreator, [IStakerRewards](/src/interfaces/IStakerRewards.sol/interface.IStakerRewards.md)


## State Variables
### stratVaultManager
StratVaultManager contract


```solidity
IStrategyVaultManager public immutable stratVaultManager;
```


### escrow
Escrow contract


```solidity
IEscrow public immutable escrow;
```


### auction
Auction contract


```solidity
IAuction public immutable auction;
```


### _ONE_DAY

```solidity
uint32 internal constant _ONE_DAY = 1 days;
```


### _WAD

```solidity
uint256 private constant _WAD = 1e18;
```


### upkeepInterval
Interval of time between two upkeeps


```solidity
uint256 public upkeepInterval;
```


### lastPerformUpkeep
Tracks the last upkeep performed


```solidity
uint256 public lastPerformUpkeep;
```


### _checkpoint
Checkpoint updated at every new event


```solidity
Checkpoint internal _checkpoint;
```


### _clusters
ClusterId => ClusterData


```solidity
mapping(bytes32 => ClusterData) internal _clusters;
```


### _vaults
StratVaultETH address => VaultData


```solidity
mapping(address => VaultData) internal _vaults;
```


### numClusters4
Number of created cluster of size 4

*A cluster becomes a validator when it is activated with 32ETH*


```solidity
uint16 public numClusters4;
```


### numClusters7
Number of created cluster of size 7


```solidity
uint16 public numClusters7;
```


### numValidators4
Number of validators of size 4


```solidity
uint16 public numValidators4;
```


### numValidators7
Number of validators of size 7


```solidity
uint16 public numValidators7;
```


### forwarderAddress
Address deployed by Chainlink at each registration of upkeep, it is the address that calls `performUpkeep`


```solidity
address public forwarderAddress;
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
constructor(IStrategyVaultManager _stratVaultManager, IEscrow _escrow, IAuction _auction);
```

### initialize


```solidity
function initialize(uint256 _upkeepInterval) external initializer;
```

### receive

Fallback function which receives the paid bid prices from the Escrow contract


```solidity
receive() external payable;
```

### dvCreationCheckpoint

Function called by StratVaultETH when a DV is created
1. Add a new cluster
2. Update the checkpoint and cluster counter


```solidity
function dvCreationCheckpoint(bytes32 _clusterId) external onlyStratVaultETH;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The ID of the cluster|


### dvActivationCheckpoint

Function called by StratVaultETH when a DV is activated
1. Send rewards to the vault and update the checkpoint
or send rewards to the vault and decrease the totalPendingRewards
or update the checkpoint
2. Update the timestamps and validator counter in any case
3. Update the cluster data


```solidity
function dvActivationCheckpoint(address _vaultAddr, bytes32 _clusterId) external onlyStratVaultETH;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|
|`_clusterId`|`bytes32`|The ID of the cluster|


### withdrawCheckpoint

Function called by StratVaultETH when a staker exits the validator (unstake)
Send rewards to the vault and update the checkpoint
or send rewards to the vault and decrease the totalPendingRewards
or update the checkpoint


```solidity
function withdrawCheckpoint(address _vaultAddr) external onlyStratVaultETH;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|


### checkUpkeep

Function called at every block time by the Chainlink Automation Nodes to check if an active DV should exit

*If `upkeepNeeded` returns `true`,  `performUpkeep` is called.*

*This function doe not consume any gas and is simulated offchain.*

*`checkData` is not used in our case.*

*Revert if there is no DV*

*Revert if the time interval since the last upkeep is less than the upkeep interval*


```solidity
function checkUpkeep(bytes memory) public view override returns (bool upkeepNeeded, bytes memory performData);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`upkeepNeeded`|`bool`|is true if the block timestamp is bigger than exitTimestamp of any strategy module|
|`performData`|`bytes`|contains the list of clusterIds that need to exit, their total remaining VCs to remove and their total bid prices to send back to Escrow contract|


### performUpkeep

Function triggered by `checkUpkeep` to perform the upkeep onchain if `checkUpkeep` returns `true`

*This function does the following:
1. Update lastPerformUpkeep to the current block timestamp
2. Update the VC number of each node, reset the cluster data to 0 and add up the total number of clusters4 and/or clusters7 to exit
3. Send back the total bid prices of the exited DVs to the Escrow contract
4. Update totalVCs and totalPendingRewards variables if necessary
5. Remove the total remaining VCs of the exited DVs from totalVCs if any and decrease the number of clusters4 and/or clusters7
6. Recalculate the dailyRewardsPer32ETH if there are still clusters*

*Revert if it is called by a non-forwarder address*


```solidity
function performUpkeep(bytes calldata performData) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`performData`|`bytes`|is the encoded data returned by `checkUpkeep`|


### setForwarderAddress

Set the address that `performUpkeep` is called from

*Only callable by the StratVaultManager*


```solidity
function setForwarderAddress(address _forwarderAddress) external onlyStratVaultManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_forwarderAddress`|`address`|The new address to set|


### updateUpkeepInterval

Update upkeepInterval

*Only callable by the StratVaultManager*


```solidity
function updateUpkeepInterval(uint256 _upkeepInterval) external onlyStratVaultManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_upkeepInterval`|`uint256`|The new interval between upkeep calls|


### calculateRewards

Calculate the pending rewards since last update of a given vault


```solidity
function calculateRewards(address _vaultAddr, uint256 _numDVs) public view returns (uint256);
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
function getAllocatableRewards() public view returns (uint256);
```

### getClusterData

Returns the cluster data of a given clusterId


```solidity
function getClusterData(bytes32 _clusterId) public view returns (ClusterData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The ID of the cluster|


### getCheckpointData

Returns the current checkpoint data


```solidity
function getCheckpointData() public view returns (Checkpoint memory);
```

### getVaultData

Returns the last update timestamp and the number of active DVs of a given StratVaultETH


```solidity
function getVaultData(address _vaultAddr) public view returns (VaultData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|


### _sendPendingRewards

Send rewards to the StratVaultETH


```solidity
function _sendPendingRewards(address _vaultAddr, uint256 _numDVs) private returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultAddr`|`address`|Address of the StratVaultETH|
|`_numDVs`|`uint256`|Number of validators in the vault|


### _getTotalAndSmallestVCs

Get the total number of VCs and the smallest VC number of a cluster


```solidity
function _getTotalAndSmallestVCs(IAuction.NodeDetails[] memory nodes)
    internal
    pure
    returns (uint64 totalClusterVCs, uint32 smallestVcNumber, uint8 smallClusterSize);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodes`|`IAuction.NodeDetails[]`|The nodes of the cluster|


### _updateVCsAndPendingRewards

Decrease totalVCs by the number of VCs used by the nodeOps since the previous checkpoint
and update totalPendingRewards by adding the distributed rewards since the previous checkpoint

*Rewards that were already sent to StratVaultETH should be subtracted from totalPendingRewards*


```solidity
function _updateVCsAndPendingRewards(uint256 _rewardsToVault) internal nonReentrant;
```

### _adjustDailyRewards

Update the checkpoint struct including calculating and updating dailyRewardsPer32ETH

*Revert if there are no active DVs or if totalVCs is 0*


```solidity
function _adjustDailyRewards() internal nonReentrant;
```

### _getElapsedDays

Get the number of days that have elapsed between the last checkpoint and the current one


```solidity
function _getElapsedDays(uint256 _lastTimestamp) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lastTimestamp`|`uint256`|can be Checkpoint's updateTime or StratVaultETH's lastUpdate|


### _getDailyVcPrice

Get the daily VC price of a node


```solidity
function _getDailyVcPrice(uint256 _bidPrice, uint32 _vcNumber) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidPrice`|`uint256`|The bid price paid by the node|
|`_vcNumber`|`uint32`|The VC number bought by the node|


### _hasTimeElapsed

Check if the time elapsed since the last update is greater than the given time


```solidity
function _hasTimeElapsed(uint256 _lastTimestamp, uint256 _elapsedTime) private view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lastTimestamp`|`uint256`|The last update time|
|`_elapsedTime`|`uint256`|The time elapsed|


### onlyStratVaultETH


```solidity
modifier onlyStratVaultETH();
```

### onlyStratVaultManager


```solidity
modifier onlyStratVaultManager();
```

