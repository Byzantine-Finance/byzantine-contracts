// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../utils/ExistingDeploymentParser.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @notice Script used for the first deployment of Byzantine contracts to Holesky
 * forge script script/deploy/holesky/Deploy_Holesky_From_Scratch.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * forge script script/deploy/holesky/Deploy_Holesky_From_Scratch.s.sol --rpc-url $HOLESKY_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * 
 */
contract Deploy_Holesky_From_Scratch is ExistingDeploymentParser {
    function run() external virtual {
        _parseInitialDeploymentParams("script/configs/holesky/Deploy_from_scratch.holesky.config.json");

        // START RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.startBroadcast();

        emit log_named_address("Deployer Address", msg.sender);

        _deployFromScratch();

        // STOP RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.stopBroadcast();

        // Sanity Checks
        _verifyContractPointers();
        _verifyImplementations();
        _verifyContractsInitialized();
        _verifyInitializationParams();

        logAndOutputContractAddresses("script/output/holesky/Deploy_from_scratch.holesky.config.json");
    }

    /**
     * @notice Deploy Byzantine contracts from scratch for Holesky
     */
    function _deployFromScratch() internal {
        // Byzantine Admin is the deployer
        byzantineAdmin = msg.sender;

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        strategyVaultManager = StrategyVaultManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineAdmin), ""))
        );
        byzNft = ByzNft(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineAdmin), ""))
        );
        auction = Auction(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineAdmin), ""))
        );
        escrow = Escrow(
            payable(address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineAdmin), "")))
        );
        stakerRewards = StakerRewards(
            payable(address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineAdmin), "")))
        );

        // StrategyVaultETH implementation contract
        strategyVaultETHImplementation = new StrategyVaultETH(
            strategyVaultManager,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            stakerRewards,
            beaconChainAdmin
        );
        // StrategyVaultETH beacon contract. The Beacon Proxy contract is deployed in the StrategyVaultManager
        // This contract points to the implementation contract.
        strategyVaultETHBeacon = new UpgradeableBeacon(address(strategyVaultETHImplementation), byzantineAdmin);

        // StrategyVaultERC20 implementation contract
        strategyVaultERC20Implementation = new StrategyVaultERC20(
            strategyVaultManager,
            byzNft,
            delegation,
            strategyManager
        );
        // StrategyVaultERC20 beacon contract. The Beacon Proxy contract is deployed in the StrategyVaultManager
        // This contract points to the implementation contract.
        strategyVaultERC20Beacon = new UpgradeableBeacon(address(strategyVaultERC20Implementation), byzantineAdmin);

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        strategyVaultManagerImplementation = new StrategyVaultManager(
            strategyVaultETHBeacon,
            strategyVaultERC20Beacon,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            strategyManager
        );
        byzNftImplementation = new ByzNft();
        auctionImplementation = new Auction(
            escrow,
            strategyVaultManager,
            pushSplitFactory,
            stakerRewards
        );
        escrowImplementation = new Escrow(
            stakerRewards,
            auction
        );
        stakerRewardsImplementation = new StakerRewards(
            strategyVaultManager,
            escrow,
            auction
        );

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        // Upgrade StrategyVaultManager
        proxyAdmin = _getProxyAdmin(address(strategyVaultManager));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(strategyVaultManager))),
            address(strategyVaultManagerImplementation),
            abi.encodeWithSelector(
                StrategyVaultManager.initialize.selector,
                byzantineAdmin
            )
        );
        // Upgrade ByzNft
        proxyAdmin = _getProxyAdmin(address(byzNft));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(byzNft))),
            address(byzNftImplementation),
            abi.encodeWithSelector(
                ByzNft.initialize.selector,
                strategyVaultManager
            )
        );
        // Upgrade Auction
        proxyAdmin = _getProxyAdmin(address(auction));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(auction))),
            address(auctionImplementation),
            abi.encodeWithSelector(
                Auction.initialize.selector,
                byzantineAdmin,
                EXPECTED_POS_DAILY_RETURN_WEI,
                MAX_DISCOUNT_RATE,
                MIN_VALIDATION_DURATION
            )
        );
        // Upgrade Escrow
        proxyAdmin = _getProxyAdmin(address(escrow));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(escrow))),
            address(escrowImplementation),
            ""
        );
        // Upgrade StakerRewards
        proxyAdmin = _getProxyAdmin(address(stakerRewards));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(stakerRewards))),
            address(stakerRewardsImplementation),
            abi.encodeWithSelector(
                StakerRewards.initialize.selector,
                UPKEEP_INTERVAL
            )
        );
    }
}