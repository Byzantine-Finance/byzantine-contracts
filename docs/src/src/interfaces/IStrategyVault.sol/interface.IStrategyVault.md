# IStrategyVault
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IStrategyVault.sol)


## Functions
### stratVaultNftId

Returns the StrategyVault's ByzNft id


```solidity
function stratVaultNftId() external view returns (uint256);
```

### stratVaultOwner

Returns StrategyVault's creator address


```solidity
function stratVaultOwner() external view returns (address);
```

### whitelistedDeposit

Returns whether a staker needs to be whitelisted to deposit in the vault


```solidity
function whitelistedDeposit() external view returns (bool);
```

### upgradeable

Returns whether the StrategyVault's underlying strategy is upgradeable / updatable


```solidity
function upgradeable() external view returns (bool);
```

### isWhitelisted

Returns whether a staker is whitelisted to deposit in the vault


```solidity
function isWhitelisted(address account) external view returns (bool);
```

### delegateTo

The caller delegate its Strategy Vault's stake to an Eigen Layer operator.

/!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.

*The operator must not have set a delegation approver, everyone can delegate to it without permission.*

*Ensures that:
1) the `staker` is not already delegated to an operator
2) the `operator` has indeed registered as an operator in EigenLayer*


```solidity
function delegateTo(address operator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.|


### hasDelegatedTo

Returns the Eigen Layer operator that the Strategy Vault is delegated to


```solidity
function hasDelegatedTo() external view returns (address);
```

### updateWhitelistedDeposit

Updates the whitelistedDeposit flag.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function updateWhitelistedDeposit(bool _whitelistedDeposit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_whitelistedDeposit`|`bool`|The new whitelistedDeposit flag.|


### whitelistStaker

Whitelist a staker.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function whitelistStaker(address staker) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address to whitelist.|


## Errors
### OnlyNftOwner
*Error when unauthorized call to a function callable only by the Strategy Vault Owner (aka the ByzNft holder).*


```solidity
error OnlyNftOwner();
```

### OnlyWhitelistedDeposit
*Error when unauthorized call to the deposit function when whitelistedDeposit is true and caller is not whitelisted.*


```solidity
error OnlyWhitelistedDeposit();
```

### OnlyStrategyVaultManager
*Error when unauthorized call to a function callable only by the StrategyVaultManager.*


```solidity
error OnlyStrategyVaultManager();
```

### IncorrectToken
*Returned when trying to deposit an incorrect token*


```solidity
error IncorrectToken();
```

### StakerAlreadyWhitelisted
*Error when whitelisting a staker already whitelisted*


```solidity
error StakerAlreadyWhitelisted();
```

### WhitelistedDepositDisabled
*Returns when trying to whitelist a staker and whitelistedDeposit is disabled*


```solidity
error WhitelistedDepositDisabled();
```

