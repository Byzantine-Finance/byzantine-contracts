# IStrategyVaultERC20
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IStrategyVaultERC20.sol)

**Inherits:**
[IStrategyVault](/src/interfaces/IStrategyVault.sol/interface.IStrategyVault.md)


## Functions
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
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nftId`|`uint256`|The id of the ByzNft associated to this StrategyVault.|
|`_token`|`address`|The address of the token to be staked. 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE if staking ETH.|
|`_whitelistedDeposit`|`bool`|Whether the deposit function is whitelisted or not.|
|`_upgradeable`|`bool`|Whether the StrategyVault is upgradeable or not.|
|`_oracle`|`address`|The address of the oracle used to get the price of the token.|


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


