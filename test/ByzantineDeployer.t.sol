// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {EigenLayerDeployer} from "./eigenlayer-helper/EigenLayerDeployer.t.sol";
import {EigenPodManager} from "eigenlayer-contracts/pods/EigenPodManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {SplitsV2Deployer} from "./splits-helper/SplitsV2Deployer.t.sol";

import {StrategyVaultManager} from "../src/core/StrategyVaultManager.sol";
import {StrategyVaultETH} from "../src/core/StrategyVaultETH.sol";
import {StrategyVaultERC20} from "../src/core/StrategyVaultERC20.sol";
import {IStrategyVault} from "../src/interfaces/IStrategyVault.sol";
import {ByzNft} from "../src/tokens/ByzNft.sol";
import {Auction} from "../src/core/Auction.sol";
import {Escrow} from "../src/vault/Escrow.sol";
import {StakerRewards} from "../src/core/StakerRewards.sol";

import {BeaconChainMock} from "./mocks/BeaconChainMock.t.sol";
import {EIP_4788_Oracle_Mock} from "./mocks/EIP_4788_Oracle_Mock.t.sol";

import {EmptyContract} from "./mocks/EmptyContract.sol";

contract ByzantineDeployer is EigenLayerDeployer, SplitsV2Deployer {

    // Byzantine contracts
    ProxyAdmin public proxyAdmin;
    StrategyVaultManager public strategyVaultManager;
    UpgradeableBeacon public strategyVaultETHBeacon;
    UpgradeableBeacon public strategyVaultERC20Beacon;
    ByzNft public byzNft;
    Auction public auction;
    Escrow public escrow;
    StakerRewards public stakerRewards;

    // Contract to simulate the beacon chain
    BeaconChainMock public beaconChain;
    // The address of the EIP-4788 beacon block root oracle
    EIP_4788_Oracle_Mock constant EIP_4788_ORACLE = EIP_4788_Oracle_Mock(0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02);

    // Beacon chain genesis time when running locally
    // Multiple of 12 for sanity's sake
    uint64 constant GENESIS_TIME_LOCAL = 1 hours * 12;

    // Byzantine Admin
    address public byzantineAdmin = address(this);
    // Address of the Beacon Chain Admin (allowed to activate DVs and submit Beacon Merkle Proofs)
    address public beaconChainAdmin = makeAddr("beaconChainAdmin");
    // Initial Auction parameters
    uint256 public currentPoSDailyReturnWei = (uint256(32 ether) * 37) / (1000 * 365); // 3.7% APY --> 3243835616438356 WEI
    uint16 public maxDiscountRate = 15e2; // 15%
    uint160 public minValidationDuration = 30; // 30 days
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

    // Struct for storing the current winning cluster details
    struct WinningClusterInfo {
        uint256[] auctionScores;
        address[] winnersAddr;
        uint256 averageAuctionScore;
        bytes32 clusterId;
    }

    function setUp() public virtual override(EigenLayerDeployer, SplitsV2Deployer) {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();
        // deploy the mock beacon chain
        beaconChain = new BeaconChainMock(EigenPodManager(address(eigenPodManager)), GENESIS_TIME_LOCAL);
        // Etch 4788 precompile
        vm.etch(address(EIP_4788_ORACLE), type(EIP_4788_Oracle_Mock).runtimeCode);
        // set the timestamp to the Beacon genesis time
        vm.warp(GENESIS_TIME_LOCAL);
        // deploy locally SplitsV2 contracts
        SplitsV2Deployer.setUp();
        // deploy locally Byzantine contracts
        _deployByzantineContractsLocal();
        // register ELOperator1 as an EL operator
        _registerAsELOperator(ELOperator1);
    }

    function _deployByzantineContractsLocal() internal {       
        // First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
        // not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
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
        IStrategyVault strategyVaultETHImplementation = new StrategyVaultETH(
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
        strategyVaultETHBeacon = new UpgradeableBeacon(address(strategyVaultETHImplementation), address(byzantineAdmin));

        // StrategyVaultERC20 implementation contract
        IStrategyVault strategyVaultERC20Implementation = new StrategyVaultERC20(
            strategyVaultManager,
            byzNft,
            delegation,
            strategyManager
        );
        // StrategyVaultERC20 beacon contract. The Beacon Proxy contract is deployed in the StrategyVaultManager
        // This contract points to the implementation contract.
        strategyVaultERC20Beacon = new UpgradeableBeacon(address(strategyVaultERC20Implementation), address(byzantineAdmin));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        StrategyVaultManager strategyVaultManagerImplementation = new StrategyVaultManager(
            strategyVaultETHBeacon,
            strategyVaultERC20Beacon,
            auction,
            byzNft,
            eigenPodManager,
            delegation,
            strategyManager
        );
        ByzNft byzNftImplementation = new ByzNft();
        Auction auctionImplementation = new Auction(
            escrow,
            strategyVaultManager,
            pushSplitFactory,
            stakerRewards
        );
        Escrow escrowImplementation = new Escrow(
            stakerRewards,
            auction
        );
        StakerRewards stakerRewardsImplementation = new StakerRewards(
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
                currentPoSDailyReturnWei,
                maxDiscountRate,
                minValidationDuration
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
                upkeepInterval
            )
        );
    }

    function _registerAsELOperator(
        address operator
    ) internal {

        // Create the operator details for the operator to delegate to
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            __deprecated_earningsReceiver: operator,
            delegationApprover: address(0),
            stakerOptOutWindowBlocks: 0
        });

        string memory emptyStringForMetadataURI;

        vm.startPrank(operator);
        delegation.registerAsOperator(operatorDetails, emptyStringForMetadataURI);
        vm.stopPrank();

        assertTrue(delegation.isOperator(operator), "_registerAsELOperator: failed to resgister `operator` as an EL operator");
        assertTrue(
            keccak256(abi.encode(delegation.operatorDetails(operator))) == keccak256(abi.encode(operatorDetails)),
            "_registerAsELOperator: operatorDetails not set appropriately"
        );
        assertTrue(delegation.isDelegated(operator), "_registerAsELOperator: operator doesn't delegate itself");
    }

    function _getProxyAdmin(address _proxy) internal view returns (ProxyAdmin) {
        bytes32 adminSlot = vm.load(_proxy, ERC1967Utils.ADMIN_SLOT);
        return ProxyAdmin(address(uint160(uint256(adminSlot))));
    }
}