# IStrategyVaultManager
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IStrategyVaultManager.sol)


## Functions
### numStratVaults

Get the total number of Strategy Vaults that have been deployed.


```solidity
function numStratVaults() external view returns (uint64);
```

### createStratVaultETH

A strategy designer creates a StrategyVault for Native ETH.


```solidity
function createStratVaultETH(
    bool whitelistedDeposit,
    bool upgradeable,
    address operator,
    address oracle
) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`operator`|`address`|The address for the operator that this StrategyVault will delegate to.|
|`oracle`|`address`|The oracle implementation to use for the vault.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the newly created StrategyVaultETH.|


### createStratVaultAndStakeNativeETH

A staker (which can also be referred as to a strategy designer) first creates a Strategy Vault ETH and then stakes ETH on it.

*It calls newStratVault.stakeNativeETH(): that function triggers the necessary number of auctions to create the DVs who gonna validate the ETH staked.*

*This action triggers (a) new auction(s) to get (a) new Distributed Validator(s) to stake on the Beacon Chain. The number of Auction triggered depends on the number of ETH sent.*

*Function will revert unless a multiple of 32 ETH are sent with the transaction.*

*The caller receives Byzantine StrategyVault shares in return for the ETH staked.*


```solidity
function createStratVaultAndStakeNativeETH(
    bool whitelistedDeposit,
    bool upgradeable,
    address operator,
    address oracle,
    address receiver
) external payable returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`operator`|`address`|The address for the operator that this StrategyVault will delegate to.|
|`oracle`|`address`|The oracle implementation to use for the vault.|
|`receiver`|`address`|The address to receive the Byzantine vault shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the newly created StrategyVaultETH.|


### createStratVaultERC20

Staker creates a StrategyVault with an ERC20 deposit token.

*The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.*


```solidity
function createStratVaultERC20(
    IERC20 token,
    bool whitelistedDeposit,
    bool upgradeable,
    address operator,
    address oracle
) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`IERC20`|The ERC20 deposit token for the StrategyVault.|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`operator`|`address`|The address for the operator that this StrategyVault will delegate to.|
|`oracle`|`address`|The oracle implementation to use for the vault.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|stratVaultAddr address of the newly created StrategyVault.|


### createStratVaultAndStakeERC20

Staker creates a Strategy Vault and stakes ERC20.

*The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.*


```solidity
function createStratVaultAndStakeERC20(
    IStrategy strategy,
    IERC20 token,
    uint256 amount,
    bool whitelistedDeposit,
    bool upgradeable,
    address operator,
    address oracle
) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`strategy`|`IStrategy`|The EigenLayer StrategyBaseTVLLimits contract for the depositing token.|
|`token`|`IERC20`|The ERC20 token to stake.|
|`amount`|`uint256`|The amount of token to stake.|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`operator`|`address`|The address for the operator that this StrategyVault will delegate to.|
|`oracle`|`address`|The oracle implementation to use for the vault.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|stratVaultAddr address of the newly created StrategyVault.|


### distributeSplitBalance

Distributes the tokens issued from the PoS rewards evenly between the node operators of a specific cluster.

*Reverts if the cluster doesn't have a split address set / doesn't exist*

*The distributor is the msg.sender. He will earn the distribution fees.*

*If the push failed, the tokens will be sent to the SplitWarehouse. NodeOp will have to call the withdraw function.*


```solidity
function distributeSplitBalance(bytes32 _clusterId, SplitV2Lib.Split calldata _split, address _token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_clusterId`|`bytes32`|The cluster ID to distribute the POS rewards for.|
|`_split`|`SplitV2Lib.Split`|The current split struct of the cluster. Can be reconstructed offchain since the only variable is the `recipients` field.|
|`_token`|`address`|The address of the token to distribute. NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE|


### getStratVaultByNftId

Returns the StrategyVault address by its bound ByzNft ID.

*Returns address(0) if the nftId is not bound to a Strategy Vault (nftId is not a ByzNft)*


```solidity
function getStratVaultByNftId(uint256 nftId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftId`|`uint256`|The ByzNft ID you want to know the attached Strategy Vault.|


### numStratVaultETHs

Returns the number of Native Strategy Vaults (aka StratVaultETH)


```solidity
function numStratVaultETHs() external view returns (uint256);
```

### getAllStratVaultETHs

Returns all the Native Strategy Vaults addresses (aka StratVaultETH)


```solidity
function getAllStratVaultETHs() external view returns (address[] memory);
```

### isStratVaultETH

Returns 'true' if the `stratVault` is a Native Strategy Vault (a StratVaultETH), and 'false' otherwise.


```solidity
function isStratVaultETH(address stratVault) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVault`|`address`|The address of the StrategyVault contract you want to know if it is a StratVaultETH.|


### getPodByStratVaultAddr

Returns the address of the Strategy Vault's EigenPod (whether it is deployed yet or not).

*If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same
returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.*


```solidity
function getPodByStratVaultAddr(address stratVaultAddr) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVaultAddr`|`address`|The address of the StrategyVault contract you want to know the EigenPod address.|


## Events
### EigenLayerNativeVaultCreated
Emitted when an Eigen Layer Native (ETH) Strategy Vault is created


```solidity
event EigenLayerNativeVaultCreated(
    address indexed vaultAddr,
    address indexed eigenLayerStrat,
    address vaultCreator,
    address byzantineOracle,
    bool privateVault,
    bool stratUpgradeable
);
```

## Errors
### DoNotHaveStratVault
*Returned when a specific address doesn't have a StrategyVault*


```solidity
error DoNotHaveStratVault(address);
```

### NotStratVaultOwner
*Returned when unauthorized call to a function only callable by the StrategyVault owner*


```solidity
error NotStratVaultOwner();
```

### EmptyAuction
*Returned when not enough node operators in Auction to create a new DV*


```solidity
error EmptyAuction();
```

### SplitAddressNotSet
*Returned when trying to distribute the split balance of a cluster that doesn't have a split address set*


```solidity
error SplitAddressNotSet();
```

