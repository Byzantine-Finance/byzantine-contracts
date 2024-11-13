# ByzNft
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/tokens/ByzNft.sol)

**Inherits:**
Initializable, OwnableUpgradeable, ERC721Upgradeable, [IByzNft](/src/interfaces/IByzNft.sol/interface.IByzNft.md)


## Functions
### initialize

*Initializes name, symbol and owner of the ERC721 collection.*

*owner is the StrategyVaultManager proxy contract*


```solidity
function initialize(IStrategyVaultManager _strategyVaultManager) external initializer;
```

### mint

Gets called when a Strategy Vault is created


```solidity
function mint(address _to, uint64 _nounce) external onlyOwner returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address of the Strategy Vault creator|
|`_nounce`|`uint64`|To prevent minting the same tokenId twice|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tokenId of the newly minted ByzNft|


### _beforeTokenTransfer

*Overrides `_beforeTokenTransfer` to restrict token transfers.*


```solidity
function _beforeTokenTransfer(address from, address, uint256) internal view override;
```

