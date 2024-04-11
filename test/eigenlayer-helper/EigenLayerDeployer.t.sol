// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/core/DelegationManager.sol";

import "eigenlayer-contracts/interfaces/IETHPOSDeposit.sol";
import "eigenlayer-contracts/interfaces/IBeaconChainOracle.sol";

import "eigenlayer-contracts/core/StrategyManager.sol";
import "eigenlayer-contracts/strategies/StrategyBase.sol";
import "eigenlayer-contracts/core/Slasher.sol";

import "eigenlayer-contracts/pods/EigenPod.sol";
import "eigenlayer-contracts/pods/EigenPodManager.sol";
import "eigenlayer-contracts/pods/DelayedWithdrawalRouter.sol";

import "eigenlayer-contracts/permissions/PauserRegistry.sol";

import "../mocks/EmptyContract.sol";
import "../mocks/ETHDepositMock.sol";

import "forge-std/Test.sol";

contract EigenLayerDeployer is Test {
    Vm cheats = Vm(VM_ADDRESS);

    // EigenLayer contracts
    ProxyAdmin public eigenLayerProxyAdmin;
    PauserRegistry public eigenLayerPauserReg;

    Slasher public slasher;
    DelegationManager public delegation;
    StrategyManager public strategyManager;
    EigenPodManager public eigenPodManager;
    IEigenPod public pod;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;

    // testing/mock contracts
    IERC20 public eigenToken;
    IERC20 public weth;
    StrategyBase public wethStrat;
    StrategyBase public eigenStrat;
    StrategyBase public baseStrategyImplementation;
    EmptyContract public emptyContract;

    mapping(uint256 => IStrategy) public strategies;

    //from testing seed phrase
    bytes32 priv_key_0 = 0x1234567812345678123456781234567812345678123456781234567812345678;
    bytes32 priv_key_1 = 0x1234567812345678123456781234567812345698123456781234567812348976;

    address[2] public stakers;

    address[] public slashingContracts;

    uint256 wethInitialSupply = 10e50;
    IStrategy[] public initializeStrategiesToSetDelayBlocks;
    uint256[] public initializeWithdrawalDelayBlocks;
    uint256 minWithdrawalDelayBlocks = 0;
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint64 MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR = 32e9;
    uint64 GOERLI_GENESIS_TIME = 1616508000;

    address pauser;
    address unpauser;
    address theMultiSig = address(420);
    address operator = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319
    address acct_0 = cheats.addr(uint256(priv_key_0));
    address acct_1 = cheats.addr(uint256(priv_key_1));
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    address public eigenLayerReputedMultisig = address(this);

    address eigenLayerProxyAdminAddress;
    address eigenLayerPauserRegAddress;
    address slasherAddress;
    address delegationAddress;
    address strategyManagerAddress;
    address eigenPodManagerAddress;
    address podAddress;
    address delayedWithdrawalRouterAddress;
    address eigenPodBeaconAddress;
    address beaconChainOracleAddress;
    address emptyContractAddress;
    address operationsMultisig;
    address executorMultisig;

    // addresses excluded from fuzzing due to abnormal behavior. TODO: @Sidu28 define this better and give it a clearer name
    mapping(address => bool) fuzzedAddressMapping;

    //ensures that a passed in address is not set to true in the fuzzedAddressMapping
    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(fuzzedAddressMapping[addr] == false);
        _;
    }

    modifier cannotReinit() {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        _;
    }

    //performs basic deployment before each test
    // for fork tests run:  forge test -vv --fork-url https://eth-goerli.g.alchemy.com/v2/demo   -vv
    function setUp() public virtual {
        
        _deployEigenLayerContractsLocal();

        fuzzedAddressMapping[address(0)] = true;
        fuzzedAddressMapping[address(eigenLayerProxyAdmin)] = true;
        fuzzedAddressMapping[address(strategyManager)] = true;
        fuzzedAddressMapping[address(eigenPodManager)] = true;
        fuzzedAddressMapping[address(delegation)] = true;
        fuzzedAddressMapping[address(slasher)] = true;
    }

    function _deployEigenLayerContractsLocal() internal {
        pauser = address(69);
        unpauser = address(489);
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayerProxyAdmin = new ProxyAdmin();

        //deploy pauser registry
        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        eigenLayerPauserReg = new PauserRegistry(pausers, unpauser);

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        delegation = DelegationManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        delayedWithdrawalRouter = DelayedWithdrawalRouter(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        ethPOSDeposit = new ETHPOSDepositMock();
        pod = new EigenPod(
            ethPOSDeposit,
            delayedWithdrawalRouter,
            eigenPodManager,
            MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR,
            GOERLI_GENESIS_TIME
        );

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        DelegationManager delegationImplementation = new DelegationManager(strategyManager, slasher, eigenPodManager);
        StrategyManager strategyManagerImplementation = new StrategyManager(delegation, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(strategyManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(
            ethPOSDeposit,
            eigenPodBeacon,
            strategyManager,
            slasher,
            delegation
        );
        DelayedWithdrawalRouter delayedWithdrawalRouterImplementation = new DelayedWithdrawalRouter(eigenPodManager);

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                0 /*initialPausedStatus*/,
                minWithdrawalDelayBlocks,
                initializeStrategiesToSetDelayBlocks,
                initializeWithdrawalDelayBlocks
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyManager))),
            address(strategyManagerImplementation),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                eigenLayerReputedMultisig,
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                0 /*initialPausedStatus*/
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(
                Slasher.initialize.selector,
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                0 /*initialPausedStatus*/
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(
                EigenPodManager.initialize.selector,
                beaconChainOracleAddress,
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                0 /*initialPausedStatus*/
            )
        );
        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delayedWithdrawalRouter))),
            address(delayedWithdrawalRouterImplementation),
            abi.encodeWithSelector(
                DelayedWithdrawalRouter.initialize.selector,
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                initPausedStatus,
                withdrawalDelayBlocks
            )
        );

        //simple ERC20 (**NOT** WETH-like!), used in a test strategy
        weth = new ERC20PresetFixedSupply("weth", "WETH", wethInitialSupply, address(this));

        // deploy StrategyBase contract implementation, then create upgradeable proxy that points to implementation and initialize it
        baseStrategyImplementation = new StrategyBase(strategyManager);
        wethStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, weth, eigenLayerPauserReg)
                )
            )
        );

        eigenToken = new ERC20PresetFixedSupply("eigen", "EIGEN", wethInitialSupply, address(this));

        // deploy upgradeable proxy that points to StrategyBase implementation and initialize it
        eigenStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, eigenToken, eigenLayerPauserReg)
                )
            )
        );

        stakers = [acct_0, acct_1];
    }

}
