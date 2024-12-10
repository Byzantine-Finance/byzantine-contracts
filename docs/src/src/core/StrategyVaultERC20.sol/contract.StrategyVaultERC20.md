# StrategyVaultERC20
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultERC20.sol)

**Inherits:**
Initializable, [StrategyVaultERC20Storage](/src/core/StrategyVaultERC20Storage.sol/abstract.StrategyVaultERC20Storage.md), [ERC4626MultiRewardVault](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md)


## Functions
### onlyNftOwner


```solidity
modifier onlyNftOwner();
```

### onlyStratVaultManager


```solidity
modifier onlyStratVaultManager();
```

### constructor


```solidity
constructor(
    IStrategyVaultManager _stratVaultManager,
    IByzNft _byzNft,
    IDelegationManager _delegationManager,
    IStrategyManager _strategyManager
);
```

### initialize

Used to initialize the StrategyVault given it's setup parameters.

*Called on construction by the StrategyVaultManager.*


```solidity
function initialize(
    uint256 _nftId,
    address _token,
    bool _whitelistedDeposit,
    bool _upgradeable,
    address _oracle
) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nftId`|`uint256`|The id of the ByzNft associated to this StrategyVault.|
|`_token`|`address`|The address of the token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking ETH.|
|`_whitelistedDeposit`|`bool`|Whether the deposit function is whitelisted or not.|
|`_upgradeable`|`bool`|Whether the StrategyVault is upgradeable or not.|
|`_oracle`|`address`|The oracle implementation to use for the vault.|


### receive

Payable fallback function that receives ether deposited to the StrategyVault contract

*Strategy Vault is the address where to send the principal ethers post exit.*


```solidity
receive() external payable;
```

### stakeERC20

Deposit ERC20 tokens into the StrategyVault.

*The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.*


```solidity
function stakeERC20(IStrategy strategy, IERC20 token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`strategy`|`IStrategy`|The EigenLayer StrategyBaseTVLLimits contract for the depositing token.|
|`token`|`IERC20`|The address of the ERC20 token to deposit.|
|`amount`|`uint256`|The amount of tokens to deposit.|


### startWithdrawERC20

Begins the withdrawal process to pull ERC20 tokens out of the StrategyVault

*Withdrawal is not instant - a withdrawal delay exists for removing the assets from EigenLayer*


```solidity
function startWithdrawERC20(
    IDelegationManager.QueuedWithdrawalParams[] calldata queuedWithdrawalParams,
    IStrategy[] calldata strategies
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`queuedWithdrawalParams`|`IDelegationManager.QueuedWithdrawalParams[]`|TODO: Fill in|
|`strategies`|`IStrategy[]`|An array of strategy contracts for all tokens being withdrawn from EigenLayer.|


### delegateTo

Finalizes the withdrawal of ERC20 tokens from the StrategyVault

The caller delegate its Strategy Vault's stake to an Eigen Layer operator.

/!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.

*Can only be called after the withdrawal delay is finished*

*The operator must not have set a delegation approver, everyone can delegate to it without permission.*

*Ensures that:
1) the `staker` is not already delegated to an operator
2) the `operator` has indeed registered as an operator in EigenLayer*


```solidity
function delegateTo(address operator) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.|


### updateWhitelistedDeposit

Updates the whitelistedDeposit flag.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function updateWhitelistedDeposit(bool _whitelistedDeposit) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_whitelistedDeposit`|`bool`|The new whitelistedDeposit flag.|


### whitelistStaker

Whitelist a staker.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function whitelistStaker(address staker) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address to whitelist.|


### stratVaultOwner

Returns the address of the owner of the Strategy Vault's ByzNft.


```solidity
function stratVaultOwner() public view returns (address);
```

### hasDelegatedTo

Returns the Eigen Layer operator that the Strategy Vault is delegated to


```solidity
function hasDelegatedTo() public view returns (address);
```

