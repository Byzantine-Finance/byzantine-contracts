// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../../src/core/StrategyVaultManager.sol";
import "../../src/core/StrategyVault.sol";
import "../../src/tokens/ByzNft.sol";
import "../../src/core/Auction.sol";
import "../../src/vault/Escrow.sol";

import "eigenlayer-contracts/pods/EigenPodManager.sol";
import "eigenlayer-contracts/core/DelegationManager.sol";

import "splits-v2/splitters/push/PushSplitFactory.sol";

import "../../test/mocks/EmptyContract.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract ExistingDeploymentParser is Script, Test {
    // Byzantine contracts
    ProxyAdmin public byzantineProxyAdmin;
    StrategyVaultManager public strategyVaultManager;
    StrategyVaultManager public strategyVaultManagerImplementation;
    UpgradeableBeacon public strategyVaultBeacon;
    StrategyVault public strategyVaultImplementation;
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
    uint160 MIN_VALIDATION_DURATION;
    uint8 CLUSTER_SIZE;

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
        MIN_VALIDATION_DURATION = uint160(stdJson.readUint(initialDeploymentData, ".auctionConfig.min_Validation_duration"));
        CLUSTER_SIZE = uint8(stdJson.readUint(initialDeploymentData, ".auctionConfig.cluster_size"));

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
        strategyVaultBeacon = UpgradeableBeacon(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultBeacon"));
        strategyVaultImplementation = StrategyVault(payable(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultImplementation")));
        strategyVaultManager = StrategyVaultManager(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultManager"));
        strategyVaultManagerImplementation = StrategyVaultManager(stdJson.readAddress(contractsAddressesData, ".addresses.strategyVaultManagerImplementation"));

        // read byzantineAdmin address
        byzantineAdmin = stdJson.readAddress(contractsAddressesData, ".parameters.byzantineAdmin");
    }

    /// @notice Ensure contracts point at each other correctly via constructors
    function _verifyContractPointers() internal view virtual {
        // StrategyVaultManager
        require(
            strategyVaultManager.stratModBeacon() == strategyVaultBeacon,
            "strategyVaultManager: stratModBeacon address not set correctly"
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
        require(
            strategyVaultManager.pushSplitFactory() == pushSplitFactory,
            "strategyVaultManager: pushSplitFactory address not set correctly"
        );
        // StrategyVaultImplementation
        require(
            strategyVaultImplementation.stratModManager() == strategyVaultManager,
            "strategyVaultImplementation: strategyVaultManager address not set correctly"
        );
        require(
            strategyVaultImplementation.byzNft() == byzNft,
            "strategyVaultImplementation: byzNft address not set correctly"
        );
        require(
            strategyVaultImplementation.auction() == auction,
            "strategyVaultImplementation: auction address not set correctly"
        );
        require(
            strategyVaultImplementation.eigenPodManager() == eigenPodManager,
            "strategyVaultImplementation: eigenPodManager address not set correctly"
        );
        require(
            strategyVaultImplementation.delegationManager() == delegation,
            "strategyVaultImplementation: delegationManager address not set correctly"
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
        // strategyVaultBeacon
        require(
            strategyVaultBeacon.implementation() == address(strategyVaultImplementation),
            "strategyVaultBeacon: implementation set incorrectly"
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
        auction.initialize(byzantineAdmin, EXPECTED_POS_DAILY_RETURN_WEI, MAX_DISCOUNT_RATE, MIN_VALIDATION_DURATION, CLUSTER_SIZE);
    }

    /// @notice Verify params based on config constants that are updated from calling `_parseInitialDeploymentParams`
    function _verifyInitializationParams() internal view virtual {
        // StrategyVaultManager
        require(strategyVaultManager.owner() == byzantineAdmin, "strategyVaultManager: owner not set correctly");
        // StrategyVaultBeacon
        require(strategyVaultBeacon.owner() == byzantineAdmin, "strategyVaultBeacon: owner not set correctly");
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
        emit log_named_uint("CLUSTER_SIZE", CLUSTER_SIZE);

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
        vm.serializeAddress(deployed_addresses, "strategyVaultBeacon", address(strategyVaultBeacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultImplementation", address(strategyVaultImplementation));
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
        vm.serializeAddress(deployed_addresses, "strategyVaultBeacon", address(strategyVaultBeacon));
        vm.serializeAddress(deployed_addresses, "strategyVaultImplementation", address(strategyVaultImplementation));
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