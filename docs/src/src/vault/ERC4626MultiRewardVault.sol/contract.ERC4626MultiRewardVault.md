# ERC4626MultiRewardVault
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/vault/ERC4626MultiRewardVault.sol)

**Inherits:**
Initializable, ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable


## State Variables
### assetInfo
Mapping of asset token address to its information


```solidity
mapping(IERC20Upgradeable => TokenInfo) public assetInfo;
```


### rewardInfo
Mapping of reward token address to its information


```solidity
mapping(IERC20Upgradeable => TokenInfo) public rewardInfo;
```


### assetTokens
List of asset tokens


```solidity
IERC20Upgradeable[] public assetTokens;
```


### rewardTokens
List of reward tokens


```solidity
IERC20Upgradeable[] public rewardTokens;
```


### oracle
Oracle implementation


```solidity
IOracle public oracle;
```


## Functions
### initialize

Used to initialize the ERC4626MultiRewardVault given it's setup parameters.


```solidity
function initialize(IERC20Upgradeable _asset, address _oracle) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`IERC20Upgradeable`|The asset to be staked.|
|`_oracle`|`address`|The oracle implementation address to use for the vault.|


### withdraw

Withdraws assets from the vault.


```solidity
function withdraw(
    uint256 assets,
    address receiver,
    address owner
) public virtual override nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to withdraw.|
|`receiver`|`address`|The address to receive the withdrawn assets.|
|`owner`|`address`|The address that is withdrawing the assets.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of shares burned.|


### redeem

Withdraws assets from the vault. Amount is determined by number of shares burning.


```solidity
function redeem(
    uint256 shares,
    address receiver,
    address owner
) public virtual override nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to burn to exchange for assets.|
|`receiver`|`address`|The address to receive the assets.|
|`owner`|`address`|The address that is withdrawing assets. return The amount of assets withdrawn.|


### totalAssets

Returns the total assets in the vault.

*This function is overridden to integrate with an oracle to determine the total value of all tokens in the vault.*

*This ensures that when depsoiting or withdrawing, a user receives the correct amount of assets or shares.*


```solidity
function totalAssets() public view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total value of assets in the vault.|


### convertToShares

Converts assets to shares.


```solidity
function convertToShares(uint256 assets) public view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to convert.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of shares.|


### convertToAssets

Converts shares to assets.


```solidity
function convertToAssets(uint256 shares) public view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to convert.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of assets.|


### _distributeRewards

Distributes rewards to the receiver for all rewardTokens.


```solidity
function _distributeRewards(address receiver, uint256 sharesBurned) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address to receive the rewards.|
|`sharesBurned`|`uint256`|The amount of shares burned.|


## Events
### AssetTokenAdded

```solidity
event AssetTokenAdded(IERC20Upgradeable indexed token, address priceFeed, uint8 decimals);
```

### RewardTokenAdded

```solidity
event RewardTokenAdded(IERC20Upgradeable indexed token, address priceFeed, uint8 decimals);
```

### PriceFeedUpdated

```solidity
event PriceFeedUpdated(IERC20Upgradeable indexed token, address newPriceFeed);
```

## Errors
### TokenAlreadyAdded

```solidity
error TokenAlreadyAdded();
```

### InvalidToken

```solidity
error InvalidToken();
```

## Structs
### TokenInfo

```solidity
struct TokenInfo {
    address priceFeed;
    uint8 decimals;
}
```

