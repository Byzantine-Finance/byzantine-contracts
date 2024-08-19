// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../utils/ExistingDeploymentParser.sol";

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

        // Deploy ProxyAdmin, later set admins for all proxies to be byzantineMultisig TODO
        byzantineProxyAdmin = new ProxyAdmin();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        strategyModuleManager = StrategyModuleManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineProxyAdmin), ""))
        );
        byzNft = ByzNft(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineProxyAdmin), ""))
        );
        auction = Auction(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineProxyAdmin), ""))
        );
        escrow = Escrow(
            payable(address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineProxyAdmin), "")))
        );
        stakerRewards = StakerRewards(
            payable(address(new TransparentUpgradeableProxy(address(emptyContract), address(byzantineProxyAdmin), "")))
        );

        // StrategyModule implementation contract
        strategyModuleImplementation = new StrategyModule(
            strategyModuleManager,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            stakerRewards
        );
        // StrategyModule beacon contract. The Beacon Proxy contract is deployed in the StrategyModuleManager
        // This contract points to the implementation contract.
        strategyModuleBeacon = new UpgradeableBeacon(address(strategyModuleImplementation));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        strategyModuleManagerImplementation = new StrategyModuleManager(
            strategyModuleBeacon,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            stakerRewards,
            pushSplitFactory
        );
        byzNftImplementation = new ByzNft();
        auctionImplementation = new Auction(
            escrow,
            strategyModuleManager
        );
        escrowImplementation = new Escrow(
            stakerRewards,
            auction
        );
        stakerRewardsImplementation = new StakerRewards(
            strategyModuleManager,
            escrow,
            byzNft
        );

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        // Upgrade StrategyModuleManager
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyModuleManager))),
            address(strategyModuleManagerImplementation),
            abi.encodeWithSelector(
                StrategyModuleManager.initialize.selector,
                byzantineAdmin
            )
        );
        // Upgrade ByzNft
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(byzNft))),
            address(byzNftImplementation),
            abi.encodeWithSelector(
                ByzNft.initialize.selector,
                strategyModuleManager
            )
        );
        // Upgrade Auction
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(auction))),
            address(auctionImplementation),
            abi.encodeWithSelector(
                Auction.initialize.selector,
                byzantineAdmin,
                EXPECTED_POS_DAILY_RETURN_WEI,
                MAX_DISCOUNT_RATE,
                MIN_VALIDATION_DURATION,
                CLUSTER_SIZE
            )
        );
        // Upgrade Escrow
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(escrow))),
            address(escrowImplementation),
            ""
        );
        // Upgrade StakerRewards
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(stakerRewards))),
            address(stakerRewardsImplementation),
            abi.encodeWithSelector(
                stakerRewards.initialize.selector,
                UPKEEP_INTERVAL,
                CLAIM_INTERVAL
            )
        );
    }
}