// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "./eigenlayer-helper/EigenLayerDeployer.t.sol";
import "./splits-helper/SplitsV2Deployer.t.sol";

import "../src/core/StrategyVaultManager.sol";
import "../src/core/StrategyVault.sol";
import "../src/tokens/ByzNft.sol";
import "../src/core/Auction.sol";
import "../src/vault/Escrow.sol";

contract ByzantineDeployer is EigenLayerDeployer, SplitsV2Deployer {

    // Byzantine contracts
    ProxyAdmin public byzantineProxyAdmin;
    StrategyVaultManager public strategyVaultManager;
    UpgradeableBeacon public strategyVaultBeacon;
    ByzNft public byzNft;
    Auction public auction;
    Escrow public escrow;

    // Byzantine Admin
    address public byzantineAdmin = address(this);
    // Address which receives the bid of the winners (will be a smart contract in the future to distribute the rewards)
    address public bidReceiver = makeAddr("bidReceiver");
    // Initial Auction parameters
    uint256 public currentPoSDailyReturnWei = (uint256(32 ether) * 37) / (1000 * 365); // 3.7% APY
    uint16 public maxDiscountRate = 15e2; // 15%
    uint160 public minValidationDuration = 30; // 30 days
    uint8 public clusterSize = 4;

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

    function setUp() public virtual override(EigenLayerDeployer, SplitsV2Deployer) {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();
        // deploy locally SplitsV2 contracts
        SplitsV2Deployer.setUp();
        // deploy locally Byzantine contracts
        _deployByzantineContractsLocal();
    }

    function _deployByzantineContractsLocal() internal {
        // deploy proxy admin for ability to upgrade proxy contracts
        byzantineProxyAdmin = new ProxyAdmin();

        
        // First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
        // not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
        emptyContract = new EmptyContract();
        strategyVaultManager = StrategyVaultManager(
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

        // StrategyVault implementation contract
        IStrategyVault strategyVaultImplementation = new StrategyVault(
            strategyVaultManager,
            auction,
            byzNft,
            eigenPodManager,
            delegation
        );
        // StrategyVault beacon contract. The Beacon Proxy contract is deployed in the StrategyVaultManager
        // This contract points to the implementation contract.
        strategyVaultBeacon = new UpgradeableBeacon(address(strategyVaultImplementation));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        StrategyVaultManager strategyVaultManagerImplementation = new StrategyVaultManager(
            strategyVaultBeacon,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            pushSplitFactory
        );
        ByzNft byzNftImplementation = new ByzNft();
        Auction auctionImplementation = new Auction(
            escrow,
            strategyVaultManager
        );
        Escrow escrowImplementation = new Escrow(
            bidReceiver,
            auction
        );

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        // Upgrade StrategyVaultManager
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyVaultManager))),
            address(strategyVaultManagerImplementation),
            abi.encodeWithSelector(
                StrategyVaultManager.initialize.selector,
                byzantineAdmin
            )
        );
        // Upgrade ByzNft
        byzantineProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(byzNft))),
            address(byzNftImplementation),
            abi.encodeWithSelector(
                ByzNft.initialize.selector,
                strategyVaultManager
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
    }

    function testByzantineContractsInitialization() public view {
        // StrategyVaultManager
        assertEq(strategyVaultManager.owner(), byzantineAdmin);
        // ByzNft
        assertEq(byzNft.owner(), address(strategyVaultManager));
        assertEq(byzNft.symbol(), "byzNFT");
        // Auction
        assertEq(auction.owner(), byzantineAdmin);
        assertEq(auction.expectedDailyReturnWei(), currentPoSDailyReturnWei);
        assertEq(auction.maxDiscountRate(), maxDiscountRate);
        assertEq(auction.minDuration(), minValidationDuration);
        assertEq(auction.clusterSize(), clusterSize);
    }

} 