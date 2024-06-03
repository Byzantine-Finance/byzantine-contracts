## Byzantine Finance

**Byzantine Finance is the Stripe of restaking. Institutional restaking is one of the fastest growing segments in Web3. Our white-label restaking infrastructure aggregates technically complex integrations and allows Web3 enterprises to build a custom restaking offering for their users in days.**

**Byzantine is a fully decentralised, liquid, and native restaking protocol - aggregating and simplifying access to a wide diversity of restaking protocols.**

## Documentation

### Protocol

To understand the core mechanism of **Byzantine Finance protocol**, check out our [whitepaper](https://docs.byzantine.fi/).

### Deep Dive

You can access the **smart contracts documentation** [here](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/docs/src/SUMMARY.md).

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project and run tests with these commands:

```
foundryup

forge build
forge test
```

## Deployments

### Current Testnet Deployment

The current testnet deployment is on holesky, and is from our MVP release. You can view the deployed contract addresses below.

###### Core

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- |
| [`StrategyModuleManager`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModuleManager.sol) | [`0xCfaa14b36E64CB8e4F11b0EFa28DC8E017A8C52f`](https://holesky.etherscan.io/address/0xCfaa14b36E64CB8e4F11b0EFa28DC8E017A8C52f) | [`0xE591...22Ff`](https://holesky.etherscan.io/address/0xE59132C95972FecE8D1686A304C983798fd022Ff) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| [`StrategyModule (beacon)`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModule.sol) | [`0x32df4D3C1624b6Ed6f87b7931acC80bd46748eAD`](https://holesky.etherscan.io/address/0x32df4D3C1624b6Ed6f87b7931acC80bd46748eAD) | [`0x0649...1FE4`](https://holesky.etherscan.io/address/0x06492BAc2abC1E6543314EeB5F4e1d9a105D1FE4) | - Beacon: [`BeaconProxy`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/BeaconProxy.sol) <br />- StrategyModules: [`UpgradeableBeacon`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/UpgradeableBeacon.sol) |
| [`Auction`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/Auction.sol) | [`0x2E311c8018634910D5ce236e72D92683A7A85A1e`](https://holesky.etherscan.io/address/0x2E311c8018634910D5ce236e72D92683A7A85A1e) | [`0x195A...8765`](https://holesky.etherscan.io/address/0x195A22ed47B7567FD6Be5B724CaD045Cf4188765) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Token

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`ByzNft`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/tokens/ByzNft.sol) | [`0x0e00e37D48B214dA408bb4d4706aCb3F1B22B91D`](https://holesky.etherscan.io/address/0x0e00e37D48B214dA408bb4d4706aCb3F1B22B91D) | [`0x22e6...1215`](https://holesky.etherscan.io/address/0x22e623c70c776f894cEb284F4A4EFfA853C81215) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Vault

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`Escrow`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/vault/Escrow.sol) | [`0x07e4e0391661C1D7B48b503BE8B02E8B93461d80`](https://holesky.etherscan.io/address/0x07e4e0391661C1D7B48b503BE8B02E8B93461d80) | [`0x0431...cF48`](https://holesky.etherscan.io/address/0x04311fa86EaAE2CF657D8E2c8a58E98bFd3CcF48) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Admin

| Name | Address |
| -------- | -------- |
| `Byzantine Admin` | [`0x5c27a880ec9024F006A70B8f1fB91b82d94ef4D4`](https://holesky.etherscan.io/address/0x5c27a880ec9024F006A70B8f1fB91b82d94ef4D4)


###### Multisigs

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
