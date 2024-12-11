## Byzantine Finance

**Byzantine is a fully decentralised, liquid, and native restaking 
protocol - aggregating and simplifying access to a wide diversity 
of restaking protocols.**

**We allow the creation of permissionless restaking strategies by enabling the deployment of minimal, individual, and isolated restaking strategy vaults by specifying:**

- A set of AVSs / decentralized networks to secure
- One or multiple restaking protocols (EigenLayer, Symbiotic, Babylon, etc.)
- A collateral asset
- A governance style (immutable or modifiable strategy)
- Investor permissions (open or whitelisted investors)
- A liquidity token

## Documentation

### Protocol

To understand the core mechanism of **Byzantine Finance protocol**, check out our [whitepaper](https://docs.byzantine.fi/).

### Deep Dive

You can access the **smart contracts documentation** [here](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/docs/src/SUMMARY.md) (not up to date yet). 

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
| [`StrategyModuleManager`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModuleManager.sol) | [`0x7027CfbB4E295288c7346c04C577f03aA9a1e5a4`](https://holesky.etherscan.io/address/0x7027CfbB4E295288c7346c04C577f03aA9a1e5a4) | [`0x16E1e7DE1d5B8453358A072AEb5Bc441891fd83D`](https://holesky.etherscan.io/address/0x16E1e7DE1d5B8453358A072AEb5Bc441891fd83D) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |
| [`StrategyModule (beacon)`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/StrategyModule.sol) | [`0xf9CB2b4f8945b931C0C4b2BF54fCB4f7557AecdA`](https://holesky.etherscan.io/address/0xf9CB2b4f8945b931C0C4b2BF54fCB4f7557AecdA) | [`0x5AaA3f895cF1cA36057B63283e5FfC2C9bCea956`](https://holesky.etherscan.io/address/0x5AaA3f895cF1cA36057B63283e5FfC2C9bCea956) | - Beacon: [`BeaconProxy`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/BeaconProxy.sol) <br />- StrategyModules: [`UpgradeableBeacon`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/beacon/UpgradeableBeacon.sol) |
| [`Auction`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/core/Auction.sol) | [`0xC050C50e18CB8787dDF1E1227c0FE7A8a5404815`](https://holesky.etherscan.io/address/0xC050C50e18CB8787dDF1E1227c0FE7A8a5404815) | [`0x46f5399403Ecc2784C66089E0A8772E2061F5ffF`](https://holesky.etherscan.io/address/0x46f5399403Ecc2784C66089E0A8772E2061F5ffF) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Token

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`ByzNft`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/tokens/ByzNft.sol) | [`0x55b9159B9E03fa6CFDe0c72B7AaB91487E390EAA`](https://holesky.etherscan.io/address/0x55b9159B9E03fa6CFDe0c72B7AaB91487E390EAA) | [`0xC568911d9F92d719d3150540eD0dbe336C98701C`](https://holesky.etherscan.io/address/0xC568911d9F92d719d3150540eD0dbe336C98701C) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Vault

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
| [`Escrow`](https://github.com/Byzantine-Finance/byzantine-contracts/blob/main/src/vault/Escrow.sol) | [`0x832b292469D7b08C10C166137108146587CD3cde`](https://holesky.etherscan.io/address/0x832b292469D7b08C10C166137108146587CD3cde) | [`0x10fc4C72989615eeEEB3704488F40785aDe2D903`](https://holesky.etherscan.io/address/0x10fc4C72989615eeEEB3704488F40785aDe2D903) | Proxy: [`TUP@4.7.1`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol) |

###### Admin

| Name | Address |
| -------- | -------- |
| `Byzantine Admin` | [`0x6D040d67Ab711EC159F870F5259f27bB8d62FeD7`](https://holesky.etherscan.io/address/0x6D040d67Ab711EC159F870F5259f27bB8d62FeD7)

###### Oracles

| Name | Implementation |
| -------- | -------- |
| `API3 Oracle` | [`0x83f4bC3A6eB91A2c039416aA09009D5638D2AF7a`](https://holesky.etherscan.io/address/0x83f4bC3A6eB91A2c039416aA09009D5638D2AF7a) |
| `Chainlink Oracle` | [`0x0D8005eE6948aEfEaD28eFBF8F5851d83d59bC33`](https://holesky.etherscan.io/address/0x0D8005eE6948aEfEaD28eFBF8F5851d83d59bC33) |

###### Multisigs

| Name | Proxy | Implementation | Notes |
| -------- | -------- | -------- | -------- | 
