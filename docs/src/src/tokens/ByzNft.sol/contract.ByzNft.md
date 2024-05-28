# ByzNft
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/a175940c55bcb788c83621ba4e22c28c3fbfcb7d/src/tokens/ByzNft.sol)

**Inherits:**
Initializable, OwnableUpgradeable, ERC721Upgradeable, [IByzNft](/src/interfaces/IByzNft.sol/interface.IByzNft.md)


## Functions
### initialize

*Initializes name, symbol and owner of the ERC721 collection.*

*owner is the StrategyModuleManager proxy contract*


```solidity
function initialize(IStrategyModuleManager _strategyModuleManager) external initializer;
```

### mint

Gets called when a full staker creates a Strategy Module


```solidity
function mint(address _to, uint256 _nounce) external onlyOwner returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address of the staker who created the Strategy Module|
|`_nounce`|`uint256`|to calculate the tokenId. This is to prevent minting the same tokenId twice.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tokenId of the newly minted NFT (calculated from the number of Strategy Modules already own by the staker and the staker's address)|


### _beforeTokenTransfer

*Overrides `_beforeTokenTransfer` to restrict token transfers to the StrategyModuleManager contract.*


```solidity
function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal view override;
```

