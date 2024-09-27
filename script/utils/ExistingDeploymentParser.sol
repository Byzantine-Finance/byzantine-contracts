// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {StrategyVaultManager} from "../../src/core/StrategyVaultManager.sol";
import {StrategyVaultETH} from "../../src/core/StrategyVaultETH.sol";
import {StrategyVaultERC20} from "../../src/core/StrategyVaultERC20.sol";
import {ByzNft} from "../../src/tokens/ByzNft.sol";
import {Auction} from "../../src/core/Auction.sol";
import {Escrow} from "../../src/vault/Escrow.sol";

import {EigenPodManager} from "eigenlayer-contracts/pods/EigenPodManager.sol";
import {DelegationManager} from "eigenlayer-contracts/core/DelegationManager.sol";

import {PushSplitFactory} from "splits-v2/splitters/push/PushSplitFactory.sol";

import {EmptyContract} from "../../test/mocks/EmptyContract.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract ExistingDeploymentParser is Script, Test {
    // Byzantine contracts
    ProxyAdmin public byzantineProxyAdmin;
    StrategyVaultManager public strategyVaultManager;
    StrategyVaultManager public strategyVaultManagerImplementation;
    UpgradeableBeacon public strategyVaultETHBeacon;
    UpgradeableBeacon public strategyVaultERC20Beacon;
    StrategyVaultETH public strategyVaultETHImplementation;
    StrategyVaultERC20 public strategyVaultERC20Implementation;
    ByzNft public byzNft;
    ByzNft public byzNftImplementation;
    Auction public auction;
    Auction public auctionImplementation;
    Escrow public escrow;
    Escrow public escrowImplementation;

    // EigenLayer contracts
    DelegationManager public delegation;
    EigenPodManager public eigenPodManager;

    // Splits contracts
    PushSplitFactory public pushSplitFactory;

    EmptyContract public emptyContract;

    // Byzantine Admin
    address byzantineAdmin;
    // Address which receives the bid of the winners (will be a smart contract in the future to distribute the rewards)
    address bidReceiver;
    // Initial Auction parameters
    uint256 EXPECTED_POS_DAILY_RETURN_WEI;
    uint16 MAX_DISCOUNT_RATE;
    uint32 MIN_VALIDATION_DURATION;

    /// @notice use for deploying a new set of Byzantine contracts
    function _parseInitialDeploymentParams(string memory initialDeploymentParamsPath) internal virtual {
        // read and log the chainID
        uint256 currentChainId = block.chainid;
        emit log_named_uint("You are parsing on ChainID", currentChainId);

        // READ JSON CONFIG DATA
        string memory initialDeploymentData = vm.readFile(initialDeploymentParamsPath);

        // check that the chainID matches the one in the config
        uint256 configChainId = stdJson.readUint(initialDeploymentData, ".chainInfo.chainId");
        require(configChainId == currentChainId, "You are on the wrong chain for this config");

        // read auction config
        EXPECTED_POS_DAILY_RETURN_WEI = stdJson.readUint(initialDeploymentData, ".auctionConfig.expected_pos_daily_return_wei");
        MAX_DISCOUNT_RATE = uint16(stdJson.readUint(initialDeploymentData, ".auctionConfig.max_discount_rate"));
        MIN_VALIDATION_DURATION = uint32(stdJson.readUint(initialDeploymentData, ".auctionConfig.min_validation_duration"));

        // read bidReceiver address
        bidReceiver = stdJson.readAddress(initialDeploymentData, ".bidReceiver");

        // read eigen layer contract addresses
        eigenPodManager = EigenPodManager(stdJson.readAddress(initialDeploymentData, ".eigenLayerContractAddr.eigenPodManager"));
        delegation = DelegationManager(stdJson.readAddress(initialDeploymentData, ".eigenLayerContractAddr.delegation"));

        // read Splits contract addresses
        pushSplitFactory = PushSplitFactory(stdJson.readAddress(initialDeploymentData, ".splitsContracts.pushSplitFactory"));

        logInitialDeploymentParams();
    }

    /// @notice Fetch deployed contract addresses to upgrade a contract
    function _parseDeployedContractAddresses(string memory contratsAddressesPath) internal virtual {
        // READ JSON FILE DATA
        string memory contractsAddressesData = vm.readFile(contratsAddressesPath);

        // read contracts addresses
        auction = Auction(stdJson.readAddress(contractsAddressesData, ".addresses.auction"));
        auctionImplementation = Auction(stdJson.readAddress(contractsAddressesData, ".addresses.auctionImplementation"));
        byzNft = ByzNft(stdJson.readAddress(contractsAddressesData, ".addresses.byzNft"));
        byzNftImplementation = ByzNft(stdJson.readAddress(contractsAddressesData, ".addresses.byzNftImplementation"));
        byzantineProxyAdmin = ProxyAdmin(stdJson.readAddress(contractsAddressesData, ".addresses.byzantineProxyAdmin"));
        emptyContract = EmptyContract(stdJson.readAddress(contractsAddressesData, ".addresses.emptyContract"));
        escrow = Escrow(payable(stdJson.readAddress(contractsAddressesData, ".addresses.escrow")));
        escrowImplementation = Escrow(payable(stdJson.readAddress(contractsAddressesData, ".addresses.escrowImplementation")));
        strategyVaultETHBeacon = UpgradeableBeacon(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultETHBeacon"));
        strategyVaultERC20Beacon = UpgradeableBeacon(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultERC20Beacon"));
        strategyVaultETHImplementation = StrategyVaultETH(payable(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultETHImplementation")));
        strategyVaultERC20Implementation = StrategyVaultERC20(payable(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultERC20Implementation")));
        strategyVaultManager = StrategyVaultManager(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultManager"));
        strategyVaultManagerImplementation = StrategyVaultManager(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultManagerImplementation"));

        // read byzantineAdmin address
        byzantineAdmin = stdJson.readAddress(contractsAddressesData, ".parameters.byzantineAdmin");
    }

    /// @notice Ensure contracts point at each other correctly via constructors
    function _verifyContractPointers() internal view virtual {
        // StrategyVaultManager
        require(
            strategyVaultManager.stratVaultETHBeacon() == strategyVaultETHBeacon,
            "strategyVaultManager: stratVaultBeacon address not set correctly"
        );
        require(
            strategyVaultManager.stratVaultERC20Beacon() == strategyVaultERC20Beacon,
            "strategyVaultManager: stratVaultERC20Beacon address not set correctly"
        );
        require(
            strategyVaultManager.auction() == auction,
            "strategyVaultManager: auction address not set correctly"
        );
        require(
            strategyVaultManager.byzNft() == byzNft,
            "strategyVaultManager: byzNft address not set correctly"
        );
        require(
            strategyVaultManager.eigenPodManager() == eigenPodManager,
            "strategyVaultManager: eigenPodManager address not set correctly"
        );
        require(
            strategyVaultManager.delegationManager() == delegation,
            "strategyVaultManager: delegationManager address not set correctly"
        );
        // StrategyVaultETHImplementation
        require(
            strategyVaultETHImplementation.stratVaultManager() == strategyVaultManager,
            "strategyVaultETHImplementation: strategyVaultManager address not set correctly"
        );
        require(
            strategyVaultETHImplementation.byzNft() == byzNft,
            "strategyVaultETHImplementation: byzNft address not set correctly"
        );
        require(
            strategyVaultETHImplementation.auction() == auction,
            "strategyVaultETHImplementation: auction address not set correctly"
        );
        require(
            strategyVaultETHImplementation.eigenPodManager() == eigenPodManager,
            "strategyVaultETHImplementation: eigenPodManager address not set correctly"
        );
        require(
            strategyVaultETHImplementation.delegationManager() == delegation,
            "strategyVaultETHImplementation: delegationManager address not set correctly"
        );
        // StrategyVaultERC20Implementation
        require(
            strategyVaultERC20Implementation.stratVaultManager() == strategyVaultManager,
            "strategyVaultERC20Implementation: strategyVaultManager address not set correctly"
        );
        require(
            strategyVaultERC20Implementation.byzNft() == byzNft,
            "strategyVaultERC20Implementation: byzNft address not set correctly"
        );
        require(
            strategyVaultERC20Implementation.auction() == auction,
            "strategyVaultERC20Implementation: auction address not set correctly"
        );
        require(
            strategyVaultERC20Implementation.eigenPodManager() == eigenPodManager,
            "strategyVaultERC20Implementation: eigenPodManager address not set correctly"
        );
        require(
            strategyVaultERC20Implementation.delegationManager() == delegation,
            "strategyVaultERC20Implementation: delegationManager address not set correctly"
        );
        // Auction
        require(
            auction.escrow() == escrow,
            "auction: escrow address not set correctly"
        );
        require(
            auction.strategyVaultManager() == strategyVaultManager,
            "auction: strategyVaultManager address not set correctly"
        );
        require(
            auction.pushSplitFactory() == pushSplitFactory,
            "auction: pushSplitFactory address not set correctly"
        );
        // Escrow
        require(
            escrow.bidPriceReceiver() == bidReceiver,
            "escrow: bidPriceReceiver address not set correctly"
        );
        require(
            escrow.auction() == auction,
            "escrow: auction address not set correctly"
        );
    }

    function _verifyImplementations() internal view virtual {
        // strategyVaultETHBeacon
        require(
            strategyVaultETHBeacon.implementation() == address(strategyVaultETHImplementation),
            "strategyVaultETHBeacon: implementation set incorrectly"
        );
        // strategyVaultERC20Beacon
        require(
            strategyVaultERC20Beacon.implementation() == address(strategyVaultERC20Implementation),
            "strategyVaultERC20Beacon: implementation set incorrectly"
        );
        // StrategyVaultManager
        require(
            byzantineProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(strategyVaultManager)))) == address(strategyVaultManagerImplementation),
            "strategyVaultManager: implementation set incorrectly"
        );
        // ByzNft
        require(
            byzantineProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(byzNft)))) == address(byzNftImplementation),
            "byzNft: implementation set incorrectly"
        );
        // Auction
        require(
            byzantineProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(auction)))) == address(auctionImplementation),
            "auction: implementation set incorrectly"
        );
        // Escrow
        require(
            byzantineProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(escrow)))) == address(escrowImplementation),
            "escrow: implementation set incorrectly"
        );
    }

    /**
     * @notice Verify initialization of Transparent Upgradeable Proxies. Also check
     * initialization params if this is the first deployment.
     */
    function _verifyContractsInitialized() internal virtual {
        // StrategyVaultManager
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        strategyVaultManager.initialize(byzantineAdmin);
        // ByzNft
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        byzNft.initialize(strategyVaultManager);
        // Auction
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        auction.initialize(byzantineAdmin, EXPECTED_POS_DAILY_RETURN_WEI, MAX_DISCOUNT_RATE, MIN_VALIDATION_DURATION);
    }

    /// @notice Verify params based on config constants that are updated from calling `_parseInitialDeploymentParams`
    function _verifyInitializationParams() internal view virtual {
        // StrategyVaultManager
        require(strategyVaultManager.owner() == byzantineAdmin, "strategyVaultManager: owner not set correctly");
        // StrategyVaultETHBeacon
        require(strategyVaultETHBeacon.owner() == byzantineAdmin, "strategyVaultETHBeacon: owner not set correctly");
        // StrategyVaultERC20Beacon
        require(strategyVaultERC20Beacon.owner() == byzantineAdmin, "strategyVaultERC20Beacon: owner not set correctly");
        // ByzNft
        require(byzNft.owner() == address(strategyVaultManager), "byzNft: owner not set correctly");
        // Auction
        require(auction.owner() == byzantineAdmin, "auction: owner not set correctly");
        // Cannot verify _expectedDailyReturnWei, _maxDiscountRate, _minDuration,_clusterSize as it is private variables
    }

    function logInitialDeploymentParams() public {
        emit log_string("==== Parsed Initilize Params for Initial Deployment ====");

        emit log_named_address("byzantineAdmin", byzantineAdmin);

        emit log_named_uint("EXPECTED_POS_DAILY_RETURN_WEI", EXPECTED_POS_DAILY_RETURN_WEI);
        emit log_named_uint("MAX_DISCOUNT_RATE", MAX_DISCOUNT_RATE);
        emit log_named_uint("MIN_VALIDATION_DURATION", MIN_VALIDATION_DURATION);

        emit log_named_address("eigenPodManager contract address", address(eigenPodManager));
        emit log_named_address("delegationManager contract address", address(delegation));

        emit log_named_address("pushSplitFactory contract address", address(pushSplitFactory));

    }

    /**
     * @notice Log contract addresses and write to output json file
     */
    function logAndOutputContractAddresses(string memory outputPath) public {
        // WRITE JSON DATA
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "byzantineProxyAdmin", address(byzantineProxyAdmin));
        vm.serializeAddress(deployed_addresses, "strategyVaultManager", address(strategyVaultManager));
        vm.serializeAddress(deployed_addresses, "strategyVaultManagerImplementation", address(strategyVaultManagerImplementation));
        vm.serializeAddress(deployed_addresses, "strategyVaultETHBeacon", address(strategyVaultETHBeacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultERC20Beacon", address(strategyVaultERC20Beacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultETHImplementation", address(strategyVaultETHImplementation));
        vm.serializeAddress(deployed_addresses, "strategyVaultERC20Implementation", address(strategyVaultERC20Implementation));
        vm.serializeAddress(deployed_addresses, "byzNft", address(byzNft));
        vm.serializeAddress(deployed_addresses, "byzNftImplementation", address(byzNftImplementation));
        vm.serializeAddress(deployed_addresses, "auction", address(auction));
        vm.serializeAddress(deployed_addresses, "auctionImplementation", address(auctionImplementation));
        vm.serializeAddress(deployed_addresses, "escrow", address(escrow));
        vm.serializeAddress(deployed_addresses, "escrowImplementation", address(escrowImplementation));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "emptyContract", address(emptyContract));

        string memory parameters = "parameters";
        vm.serializeAddress(parameters, "byzantineAdmin", byzantineAdmin);
        string memory parameters_output = vm.serializeAddress(parameters, "bidReceiver", bidReceiver);

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        // serialize all the data
        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        vm.serializeString(parent_object, parameters, parameters_output);
        string memory finalJson = vm.serializeString(parent_object, chain_info, chain_info_output);

        vm.writeJson(finalJson, outputPath);
    }

    /**
     * @notice Update contract addresses in JSON file after an upgrade
     */
    function logAndUpdateContractAddresses(string memory outputPath) public {
        // WRITE JSON DATA ADDRESSES
        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "byzantineProxyAdmin", address(byzantineProxyAdmin));
        vm.serializeAddress(deployed_addresses, "strategyVaultManager", address(strategyVaultManager));
        vm.serializeAddress(deployed_addresses, "strategyVaultManagerImplementation", address(strategyVaultManagerImplementation));
        vm.serializeAddress(deployed_addresses, "strategyVaultETHBeacon", address(strategyVaultETHBeacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultERC20Beacon", address(strategyVaultERC20Beacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultETHImplementation", address(strategyVaultETHImplementation));
        vm.serializeAddress(deployed_addresses, "strategyVaultERC20Implementation", address(strategyVaultERC20Implementation));
        vm.serializeAddress(deployed_addresses, "byzNft", address(byzNft));
        vm.serializeAddress(deployed_addresses, "byzNftImplementation", address(byzNftImplementation));
        vm.serializeAddress(deployed_addresses, "auction", address(auction));
        vm.serializeAddress(deployed_addresses, "auctionImplementation", address(auctionImplementation));
        vm.serializeAddress(deployed_addresses, "escrow", address(escrow));
        vm.serializeAddress(deployed_addresses, "escrowImplementation", address(escrowImplementation));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "emptyContract", address(emptyContract));

        vm.writeJson(deployed_addresses_output, outputPath, ".addresses");
    }
}