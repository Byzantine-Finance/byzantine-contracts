// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../utils/ExistingDeploymentParser.sol";

/**
 * @notice Script used for upgrading all StrategyVault deployed on Holesky
 * forge script script/upgrade/holesky/StrategyVaultsUpgrade.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * forge script script/upgrade/holesky/StrategyVaultsUpgrade.s.sol --rpc-url $HOLESKY_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * 
 */
contract StrategyVaultsUpgrade is ExistingDeploymentParser {
    function run() external virtual {
        _parseInitialDeploymentParams("script/configs/holesky/Deploy_from_scratch.holesky.config.json");
        _parseDeployedContractAddresses("script/output/holesky/Deploy_from_scratch.holesky.config.json");

        // START RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.startBroadcast();

        emit log_named_address("Upgrader Address", msg.sender);

        _upgradeStrategyVaults();

        // STOP RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.stopBroadcast();

        // Sanity Checks
        _verifyContractPointers();
        _verifyImplementations();
        _verifyContractsInitialized();
        _verifyInitializationParams();

        logAndUpdateContractAddresses("script/output/holesky/Deploy_from_scratch.holesky.config.json");
    }

    /**
     * @notice Upgrade Auction by deploying a new implementation contract and pointing the proxy to it
     */
    function _upgradeStrategyVaults() internal {
        // Deploy new implementation contract
        strategyVaultImplementation = new StrategyVault(
            strategyVaultManager,
            auction,
            byzNft,
            eigenPodManager,
            delegation
        );
        // Upgrade UpgradeableBeacon
        strategyVaultBeacon.upgradeTo(address(strategyVaultImplementation));
    }
}
