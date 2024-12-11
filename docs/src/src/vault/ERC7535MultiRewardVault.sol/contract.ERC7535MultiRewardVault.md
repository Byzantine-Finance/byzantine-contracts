# ERC7535MultiRewardVault
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/vault/ERC7535MultiRewardVault.sol)

**Inherits:**
[ERC7535Upgradeable](/src/vault/ERC7535/ERC7535Upgradeable.sol/abstract.ERC7535Upgradeable.md), OwnableUpgradeable, ReentrancyGuardUpgradeable

**Author:**
Byzantine-Finance

ERC-7535: Native Asset ERC-4626 Tokenized Vault with support for multiple reward tokens


## State Variables
### rewardTokens
List of reward tokens


```solidity
address[] public rewardTokens;
```


### oracle
Oracle implementation


```solidity
IOracle public oracle;
```


### __gap
*This empty reserved space is put in place to allow future versions to add new
variables without shifting down storage in the inheritance chain.
See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#modifying-your-contracts*


```solidity
uint256[44] private __gap;
```


## Functions
### initialize

Initializes the ERC7535MultiRewardVault contract.


```solidity
function initialize(address _oracle) public virtual initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oracle`|`address`|The oracle implementation address to use for the vault.|


### __ERC7535MultiRewardVault_init


```solidity
function __ERC7535MultiRewardVault_init(address _oracle) internal onlyInitializing;
```

### __ERC7535MultiRewardVault_init_unchained


```solidity
function __ERC7535MultiRewardVault_init_unchained(address _oracle) internal onlyInitializing;
```

### receive

Payable fallback function that receives ether deposited to the StrategyVault contract


```solidity
receive() external payable virtual override;
```

### deposit

Deposits ETH into the vault. Amount is determined by ETH depositing.


```solidity
function deposit(uint256 assets, address receiver) public payable virtual override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of ETH being deposit.|
|`receiver`|`address`|The address to receive the Byzantine vault shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of shares minted.|


### mint

Deposits ETH into the vault. Amount is determined by number of shares minting.


```solidity
function mint(uint256 shares, address receiver) public payable virtual override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of vault shares to mint.|
|`receiver`|`address`|The address to receive the Byzantine vault shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of ETH deposited.|


### withdraw

Withdraws ETH from the vault. Amount is determined by ETH withdrawing.


```solidity
function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of ETH to withdraw.|
|`receiver`|`address`|The address to receive the ETH.|
|`owner`|`address`|The address that is withdrawing ETH.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of shares burned.|


### redeem

Withdraws ETH from the vault. Amount is determined by number of shares burning.


```solidity
function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to burn to exchange for ETH.|
|`receiver`|`address`|The address to receive the ETH.|
|`owner`|`address`|The address that is withdrawing ETH. return The amount of ETH withdrawn.|


### addRewardToken

Adds a reward token to the vault.


```solidity
function addRewardToken(address _token) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The reward token to add.|


### updateOracle

Updates the oracle implementation address for the vault.


```solidity
function updateOracle(address _oracle) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oracle`|`address`|The new oracle implementation address.|


### totalAssets

Returns the total value of assets in the vault.

*This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.*

*This ensures that when depositing or withdrawing, a user receives the correct amount of assets or shares.*

*Allows for assets to be priced in USD, ETH or any other asset, as long as the oracles are updated accordingly and uniformly.*

*Assumes that the oracle returns the price in 18 decimals.*


```solidity
function totalAssets() public view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total value of assets in the vault.|


### _convertToShares

*Internal conversion function (from assets to shares) with support for rounding direction.*

*This function is overriden to calculate total value of assets including reward tokens.*

*Treats totalAssets() as the total value of ETH + reward tokens in USD rather than the total amount of ETH.
Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
would represent an infinite amout of shares.*


```solidity
function _convertToShares(
    uint256 assets,
    MathUpgradeable.Rounding rounding
) internal view override returns (uint256 shares);
```

### _convertToAssets

*Internal conversion function (from shares to assets) with support for rounding direction.*

*This function is overriden to calculate total value of assets including reward tokens.*


```solidity
function _convertToAssets(
    uint256 shares,
    MathUpgradeable.Rounding rounding
) internal view override returns (uint256 assets);
```

### _distributeRewards

*Distributes rewards to the receiver for all rewardTokens.*


```solidity
function _distributeRewards(address receiver, uint256 sharesBurned) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address to receive the rewards.|
|`sharesBurned`|`uint256`|The amount of shares burned.|


### _getETHBalance

*Returns the ETH balance of the vault.*


```solidity
function _getETHBalance() internal view virtual returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The ETH balance of the vault.|


## Events
### RewardTokenAdded

```solidity
event RewardTokenAdded(address indexed token);
```

### OracleUpdated

```solidity
event OracleUpdated(address newOracle);
```

### RewardTokenWithdrawn

```solidity
event RewardTokenWithdrawn(address indexed receiver, address indexed rewardToken, uint256 amount);
```

## Errors
### ETHTransferFailedOnWithdrawal

```solidity
error ETHTransferFailedOnWithdrawal();
```

### TokenAlreadyAdded

```solidity
error TokenAlreadyAdded();
```

### InvalidAddress

```solidity
error InvalidAddress();
```

