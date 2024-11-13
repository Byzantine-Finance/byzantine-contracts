# StrategyVaultManager
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultManager.sol)

**Inherits:**
Initializable, OwnableUpgradeable, [StrategyVaultManagerStorage](/src/core/StrategyVaultManagerStorage.sol/abstract.StrategyVaultManagerStorage.md)


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
)
    StrategyVaultManagerStorage(
        _stratVaultETHBeacon,
        _stratVaultERC20Beacon,
        _auction,
        _byzNft,
        _eigenPodManager,
        _delegationManager,
        _strategyManager
    );
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

### createStratVaultETH

A strategy designer creates a StrategyVault for Native ETH.


```solidity
function createStratVaultETH(
    bool whitelistedDeposit,
    bool upgradeable,
    address operator,
    address oracle
) public returns (address);
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
) external returns (address stratVaultAddr);
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
|`stratVaultAddr`|`address`|address of the newly created StrategyVault.|


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
) external returns (address stratVaultAddr);
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
|`stratVaultAddr`|`address`|address of the newly created StrategyVault.|


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
function getStratVaultByNftId(uint256 nftId) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftId`|`uint256`|The ByzNft ID you want to know the attached Strategy Vault.|


### numStratVaultETHs

Returns the number of Native Strategy Vaults (a StratVaultETH)


```solidity
function numStratVaultETHs() public view returns (uint256);
```

### getAllStratVaultETHs

Returns all the Native Strategy Vaults addresses (a StratVaultETH)


```solidity
function getAllStratVaultETHs() public view returns (address[] memory);
```

### isStratVaultETH

Returns 'true' if the `stratVault` is a Native Strategy Vault (a StratVaultETH), and 'false' otherwise.


```solidity
function isStratVaultETH(address stratVault) public view returns (bool);
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
function getPodByStratVaultAddr(address stratVaultAddr) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stratVaultAddr`|`address`|The address of the StrategyVault contract you want to know the EigenPod address.|


### _deployStrategyVaultERC20

Deploy a new ERC20 Strategy Vault.

Deploy a new ERC20 Strategy Vault.


```solidity
function _deployStrategyVaultERC20(
    address token,
    bool whitelistedDeposit,
    bool upgradeable,
    address oracle
) internal returns (IStrategyVaultERC20);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to be staked.|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`oracle`|`address`|The oracle implementation to use for the vault.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IStrategyVaultERC20`|The address of the newly deployed Strategy Vault.|


### _deployStrategyVaultETH

Deploy a new ETH Strategy Vault.


```solidity
function _deployStrategyVaultETH(
    bool whitelistedDeposit,
    bool upgradeable,
    address oracle
) internal returns (IStrategyVaultETH);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`whitelistedDeposit`|`bool`|If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.|
|`upgradeable`|`bool`|If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.|
|`oracle`|`address`|The oracle implementation to use for the vault.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IStrategyVaultETH`|The address of the newly deployed Strategy Vault.|


