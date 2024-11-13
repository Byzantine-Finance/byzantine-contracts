# ByzNft
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/tokens/ByzNft.sol)

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

Gets called when a full staker creates a Strategy Vault


```solidity
function mint(address _to, uint64 _nounce) external onlyOwner returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address of the staker who created the Strategy Vault|
|`_nounce`|`uint64`|to calculate the tokenId. This is to prevent minting the same tokenId twice.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tokenId of the newly minted NFT (calculated from the number of Strategy Vaults already deployed)|


### _beforeTokenTransfer

*Overrides `_beforeTokenTransfer` to restrict token transfers to the StrategyVaultManager contract.*


```solidity
function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal view override;
```

