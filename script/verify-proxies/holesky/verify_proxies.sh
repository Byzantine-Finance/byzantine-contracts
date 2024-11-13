#!/bin/bash

HOLESKY_CHAIN_ID=17000

# File containing the proxies addresses
output_file="script/output/holesky/Deploy_from_scratch.holesky.config.json"

# Contracts verification paths
transparent_proxy_path=lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy
upgradeable_beacon_path=lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon
proxy_admin_path=lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin
empty_contract_path=test/mocks/EmptyContract.sol:EmptyContract

# Read contract addresses from the json file
auction=$(jq -r '.addresses.auction' $output_file)
byzNft=$(jq -r '.addresses.byzNft' $output_file)
byzantineProxyAdmin=$(jq -r '.addresses.byzantineProxyAdmin' $output_file)
emptyContract=$(jq -r '.addresses.emptyContract' $output_file)
escrow=$(jq -r '.addresses.escrow' $output_file)
strategyVaultBeacon=$(jq -r '.addresses.strategyVaultBeacon' $output_file)
strategyVaultImplementation=$(jq -r '.addresses.strategyVaultImplementation' $output_file)
strategyVaultManager=$(jq -r '.addresses.strategyVaultManager' $output_file)

# Verify byzantineProxyAdmin
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch $byzantineProxyAdmin $proxy_admin_path

# Verify emptyContract
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch $emptyContract $empty_contract_path

# Verify the auction proxy
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch --constructor-args $(cast abi-encode "constructor(address,address,bytes)" "$emptyContract" "$byzantineProxyAdmin" "0x") $auction $transparent_proxy_path
# Verify the byzNft proxy
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch --constructor-args $(cast abi-encode "constructor(address,address,bytes)" "$emptyContract" "$byzantineProxyAdmin" "0x") $byzNft $transparent_proxy_path
# Verify the escrow proxy
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch --constructor-args $(cast abi-encode "constructor(address,address,bytes)" "$emptyContract" "$byzantineProxyAdmin" "0x") $escrow $transparent_proxy_path
# Verify the strategyVaultManager proxy
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch --constructor-args $(cast abi-encode "constructor(address,address,bytes)" "$emptyContract" "$byzantineProxyAdmin" "0x") $strategyVaultManager $transparent_proxy_path
# Verify strategyVaultBeacon
forge verify-contract --chain-id $HOLESKY_CHAIN_ID --watch --constructor-args $(cast abi-encode "constructor(address)" "$strategyVaultImplementation") $strategyVaultBeacon $upgradeable_beacon_path
