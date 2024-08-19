// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StratModManagerMock} from "../../../test/mocks/StratModManagerMock.sol";
import {StakerRewardsMock} from "../../../test/mocks/StakerRewardsMock.sol";

/// @dev Steps to test Chainlink Automation via The Chainlink Automation App:
/// 1. Deploy the mock contracts, comment out the `simulateDVandStratModCreation` function and run:
/// forge script script/deploy/sepolia/Deploy_Sepolia_For_Testing_Chainlink.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY --verify
/// 2. Registere the upkeep for the `StakerRewardsMock` contract on https://automation.chain.link/: 
/// 3. Simulate the transactions and perform the upkeep, run:
/// forge script script/deploy/sepolia/Deploy_Sepolia_For_Testing_Chainlink.s.sol --sig "simulateDVandStratModCreation()" --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
/// 4. Verify the Strategy Module contract and check on Etherscan

contract Deploy_Sepolia_For_Testing_Chainlink is Script {
    address stratModManagerMockAddr = 0x7bc194ef003d654Ac3a39AB50A3218c2Ab1a14Ed;

    function run() public returns (StratModManagerMock, StakerRewardsMock) {
        StakerRewardsMock stakerRewardsMock;
        StratModManagerMock stratModManagerMock;
        uint256 interval = 60; 

        // Deploy the contracts
        vm.startBroadcast();
        stratModManagerMock = new StratModManagerMock();
        stakerRewardsMock = new StakerRewardsMock(stratModManagerMock, interval);
        stratModManagerMock.setStakerRewardsMock(stakerRewardsMock);
        vm.stopBroadcast();
        return (stratModManagerMock, stakerRewardsMock);
    }

    function simulateDVandStratModCreation() public {    
        StratModManagerMock stratModManagerMock = StratModManagerMock(payable(stratModManagerMockAddr));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 amountToSend = 6000000000000000 wei; // 0.006 ETH

        // Fund the stratModManagerMock contract
        vm.startBroadcast(deployerPrivateKey);

        // Send ETH to stratModManagerMock contract to testing purpose
        (bool success, ) = address(stratModManagerMock).call{value: amountToSend}("");
        require(success, "Failed to send ETH to stratModManagerMock");

        // Call the precreateDV function on stratModManagerMock just for testing purpose to avoid underflow situation 
        stratModManagerMock.precreateDV(172800, 4, 100000000000000); // 0,0001 ETH, 172800 VCs

        // Call the createStrategyModules function on stratModManagerMock
        stratModManagerMock.createStrategyModules(90, 100, 200, 300, 2500000000000000); // 0,0025 ETH, 690 VCs 
        stratModManagerMock.createStrategyModules(110, 150, 250, 350, 2000000000000000); // 0,002 ETH, 845 VCs
        vm.stopBroadcast();
    }
}
