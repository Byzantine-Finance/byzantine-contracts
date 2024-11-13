# IByzNft
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/interfaces/IByzNft.sol)

**Inherits:**
IERC721Upgradeable


## Functions
### mint

Gets called when a full staker creates a Strategy Vault


```solidity
function mint(address _to, uint64 _nounce) external returns (uint256);
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


