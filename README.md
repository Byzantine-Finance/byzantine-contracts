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
| [`StrategyModuleManager`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModuleManager.sol) | [`0x6b70ECA73689463C863873154744169Bcc622308`](https://holesky.etherscan.io/address/0x6b70ECA73689463C863873154744169Bcc622308) | [`0x4d6...bf7`](https://holesky.etherscan.io/address/0x4d67959Ffbaafd79DE45fF73147147185d626bf7) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| [`StrategyModule (beacon)`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModule.sol) | [`0x5504899Eb7a4A21485Fa20C48371776E9E6D4E43`](https://holesky.etherscan.io/address/0x5504899Eb7a4A21485Fa20C48371776E9E6D4E43) | [`0x9E3...3b9`](https://holesky.etherscan.io/address/0x9E3e5D91A9521b14F842A747a62Af4774C4223b9) | - Beacon: [`BeaconProxy`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/BeaconProxy.sol) <br />- StrategyModules: [`UpgradeableBeacon`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/UpgradeableBeacon.sol) |
| [`Auction`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/Auction.sol) | [`0x1ae6F573F0D7b4b966Ce103BC18F3A3b9E43987b`](https://holesky.etherscan.io/address/0x1ae6F573F0D7b4b966Ce103BC18F3A3b9E43987b) | [`0x8aa...A45`](https://holesky.etherscan.io/address/0x8aa905d236b5c316716487C04e72Ed2683c68A45) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Token

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`ByzNft`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/tokens/ByzNft.sol) | [`0xB8492aD52067B0b0a520041c0B16A3092bee05Bc`](https://holesky.etherscan.io/address/0xB8492aD52067B0b0a520041c0B16A3092bee05Bc) | [`0x3F2...9Db`](https://holesky.etherscan.io/address/0x3F26e94839Bf370062043122CCB1c95e668E69Db) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Vault

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`Escrow`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/vault/Escrow.sol) | [`0x5FE3eD446e0195E9626744D1047E31C8927535d5`](https://holesky.etherscan.io/address/0x5FE3eD446e0195E9626744D1047E31C8927535d5) | [`0xD0f...439`](https://holesky.etherscan.io/address/0xD0f7EC487Bf492e1a6341648F4ce597430276439) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Admin

| Name | Address |
| -------- | -------- |
| `Byzantine Admin` | [`0x6D040d67Ab711EC159F870F5259f27bB8d62FeD7`](https://holesky.etherscan.io/address/0x6D040d67Ab711EC159F870F5259f27bB8d62FeD7)


###### Multisigs

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
