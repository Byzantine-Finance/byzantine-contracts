// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "./eigenlayer-helper/EigenLayerDeployer.t.sol";

import "../src/core/StrategyModuleManager.sol";
import "../src/core/StrategyModule.sol";
import "../src/tokens/ByzNft.sol";
import "../src/core/Auction.sol";
import "../src/vault/Escrow.sol";
import "../src/core/StakerRewards.sol";

contract ByzantineDeployer is EigenLayerDeployer {

    // Byzantine contracts
    ProxyAdmin public byzantineProxyAdmin;
    StrategyModuleManager public strategyModuleManager;
    UpgradeableBeacon public strategyModuleBeacon;
    ByzNft public byzNft;
    Auction public auction;
    Escrow public escrow;
    StakerRewards public stakerRewards;

    // Byzantine Admin
    address public byzantineAdmin = address(this);
    // Address which receives the bid of the winners (will be a smart contract in the future to distribute the rewards)
    address public bidReceiver = makeAddr("bidReceiver");
    // Initial Auction parameters
    uint256 public currentPoSDailyReturnWei = (uint256(32 ether) * 37) / (1000 * 365); // 3.7% APY
    uint16 public maxDiscountRate = 15e2; // 15%
    uint160 public minValidationDuration = 30; // 30 days
    uint8 public clusterSize = 4;
    // Initial StakerRewards parameters
    uint256 public upkeepInterval = 60;

    /* =============== TEST VARIABLES AND STRUCT =============== */
   
    // Eigen Layer operator securing AVS
    address ELOperator1 = address(0x1516171819);
    
    // Tests protagonists
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Node operators seeking for a DV in Byzantine
    address[] public nodeOps = [
        makeAddr("node_operator_0"),
        makeAddr("node_operator_1"),
        makeAddr("node_operator_2"),
        makeAddr("node_operator_3"),
        makeAddr("node_operator_4"),
        makeAddr("node_operator_5"),
        makeAddr("node_operator_6"),
        makeAddr("node_operator_7"),
        makeAddr("node_operator_8"),
        makeAddr("node_operator_9")
    ];

    struct NodeOpBid {
        address nodeOp;
        uint256[] discountRates;
        uint256[] timesInDays;
    }

    function setUp() public virtual override {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();
        // deploy locally Byzantine contracts
        _deployByzantineContractsLocal();
    }

    function _deployByzantineContractsLocal() internal {
        // deploy proxy admin for ability to upgrade proxy contracts
        byzantineProxyAdmin = new ProxyAdmin();

        
        // First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
        // not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
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
        IStrategyModule strategyModuleImplementation = new StrategyModule(
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
        StrategyModuleManager strategyModuleManagerImplementation = new StrategyModuleManager(
            strategyModuleBeacon,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            stakerRewards
        );
        ByzNft byzNftImplementation = new ByzNft();
        Auction auctionImplementation = new Auction(
            escrow,
            strategyModuleManager
        );
        Escrow escrowImplementation = new Escrow(
            stakerRewards,
            auction
        );
        StakerRewards stakerRewardsImplementation = new StakerRewards(
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
                currentPoSDailyReturnWei,
                maxDiscountRate,
                minValidationDuration,
                clusterSize
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
                StakerRewards.initialize.selector,
                upkeepInterval
            )
        );
    }

    function testByzantineContractsInitialization() public view {
        // StrategyModuleManager
        assertEq(strategyModuleManager.owner(), byzantineAdmin);
        // ByzNft
        assertEq(byzNft.owner(), address(strategyModuleManager));
        assertEq(byzNft.symbol(), "byzNFT");
        // Auction
        assertEq(auction.owner(), byzantineAdmin);
        assertEq(auction.expectedDailyReturnWei(), currentPoSDailyReturnWei);
        assertEq(auction.maxDiscountRate(), maxDiscountRate);
        assertEq(auction.minDuration(), minValidationDuration);
        assertEq(auction.clusterSize(), clusterSize);
        // StakerRewards
        assertEq(stakerRewards.totalVCs(), 0);
        assertEq(stakerRewards.upkeepInterval(), upkeepInterval);
    }

} 