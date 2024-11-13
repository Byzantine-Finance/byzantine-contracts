# IByzNft
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IByzNft.sol)

**Inherits:**
IERC721Upgradeable


## Functions
### mint

Gets called when a Strategy Vault is created


```solidity
function mint(address _to, uint64 _nounce) external returns (uint256);
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


