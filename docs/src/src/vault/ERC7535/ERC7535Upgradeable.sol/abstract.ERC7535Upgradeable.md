# ERC7535Upgradeable
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/vault/ERC7535/ERC7535Upgradeable.sol)

**Inherits:**
Initializable, ERC20Upgradeable, [IERC7535Upgradeable](/src/vault/ERC7535/IERC7535Upgradeable.sol/interface.IERC7535Upgradeable.md)

**Author:**
Byzantine-Finance

ERC-4626 Tokenized Vaults with Ether (Native Asset) as the underlying asset

OpenZeppelin Upgradeable version of ERC7535


## State Variables
### __gap

```solidity
uint256[50] private __gap;
```


## Functions
### __ERC7535_init

*Initializes the ERC7535 contract. Add calls for initializers of parent contracts here.*


```solidity
function __ERC7535_init() internal onlyInitializing;
```

### __ERC7535_init_unchained

*Contains initialization logic specific to this contract.*


```solidity
function __ERC7535_init_unchained() internal onlyInitializing;
```

### decimals

*Decimals are computed by adding the decimal offset on top of the underlying asset's decimals. This
"original" value is cached during construction of the vault contract. If this read operation fails (e.g., the
asset has not been created yet), a default of 18 is used to represent the underlying asset's decimals.
See [IERC20Metadata-decimals](/lib/openzeppelin-contracts-upgradeable/contracts/token/ERC777/ERC777Upgradeable.sol/contract.ERC777Upgradeable.md#decimals).*


```solidity
function decimals() public view virtual override(IERC20MetadataUpgradeable, ERC20Upgradeable) returns (uint8);
```

### asset

*See [IERC7535-asset](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#asset).*


```solidity
function asset() public view virtual returns (address);
```

### totalAssets

*See [IERC7535-totalAssets](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md#totalassets).*


```solidity
function totalAssets() public view virtual returns (uint256);
```

### convertToShares

*See [IERC7535-convertToShares](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md#converttoshares).*


```solidity
function convertToShares(uint256 assets) public view virtual returns (uint256);
```

### convertToAssets

*See [IERC7535-convertToAssets](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md#converttoassets).*


```solidity
function convertToAssets(uint256 shares) public view virtual returns (uint256);
```

### maxDeposit

*See [IERC7535-maxDeposit](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#maxdeposit).*


```solidity
function maxDeposit(address) public view virtual returns (uint256);
```

### maxMint

*See [IERC7535-maxMint](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#maxmint).*


```solidity
function maxMint(address) public view virtual returns (uint256);
```

### maxWithdraw

*See [IERC7535-maxWithdraw](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#maxwithdraw).*


```solidity
function maxWithdraw(address owner) public view virtual returns (uint256);
```

### maxRedeem

*See [IERC7535-maxRedeem](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#maxredeem).*


```solidity
function maxRedeem(address owner) public view virtual returns (uint256);
```

### previewDeposit

*See [IERC7535-previewDeposit](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#previewdeposit).*


```solidity
function previewDeposit(uint256 assets) public view virtual returns (uint256);
```

### previewMint

*See [IERC7535-previewMint](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#previewmint).*


```solidity
function previewMint(uint256 shares) public view virtual returns (uint256);
```

### previewWithdraw

*See [IERC7535-previewWithdraw](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#previewwithdraw).*


```solidity
function previewWithdraw(uint256 assets) public view virtual returns (uint256);
```

### previewRedeem

*See [IERC7535-previewRedeem](/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC4626Upgradeable.sol/interface.IERC4626Upgradeable.md#previewredeem).*


```solidity
function previewRedeem(uint256 shares) public view virtual returns (uint256);
```

### deposit

*See [IERC7535-deposit](/src/core/StrategyVaultETH.sol/contract.StrategyVaultETH.md#deposit).*


```solidity
function deposit(uint256 assets, address receiver) public payable virtual returns (uint256);
```

### mint

*See [IERC7535-mint](/src/tokens/ByzNft.sol/contract.ByzNft.md#mint).
As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
In this case, the shares will be minted without requiring any assets to be deposited.*


```solidity
function mint(uint256 shares, address receiver) public payable virtual returns (uint256);
```

### withdraw

*See [IERC7535-withdraw](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md#withdraw).*


```solidity
function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256);
```

### redeem

*See [IERC7535-redeem](/src/vault/ERC4626MultiRewardVault.sol/contract.ERC4626MultiRewardVault.md#redeem).*


```solidity
function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256);
```

### _convertToShares

*Internal conversion function (from assets to shares) with support for rounding direction.*


```solidity
function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view virtual returns (uint256);
```

### _convertToAssets

*Internal conversion function (from shares to assets) with support for rounding direction.*


```solidity
function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual returns (uint256);
```

### _deposit

*Deposit/mint common workflow.*


```solidity
function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual;
```

### _withdraw

*Withdraw/redeem common workflow.*


```solidity
function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal virtual;
```

### _decimalsOffset


```solidity
function _decimalsOffset() internal view virtual returns (uint8);
```

### receive

*Receive ether from the caller, allowing vault to earn yield in the native asset.*


```solidity
receive() external payable virtual;
```

## Errors
### ERC7535ExceededMaxDeposit
*Attempted to deposit more assets than the max amount for `receiver`.*


```solidity
error ERC7535ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);
```

### ERC7535ExceededMaxMint
*Attempted to mint more shares than the max amount for `receiver`.*


```solidity
error ERC7535ExceededMaxMint(address receiver, uint256 shares, uint256 max);
```

### ERC7535ExceededMaxWithdraw
*Attempted to withdraw more assets than the max amount for `receiver`.*


```solidity
error ERC7535ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
```

### ERC7535ExceededMaxRedeem
*Attempted to redeem more shares than the max amount for `receiver`.*


```solidity
error ERC7535ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
```

