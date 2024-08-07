// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StratModManagerMock} from "../../../test/mocks/StratModManagerMock.sol";
import {StakerRewardsMock} from "../../../test/mocks/StakerRewardsMock.sol";

/// @dev To run simulateDVandStratModCreation() 
/// forge script script/deploy/sepolia/Deploy_Sepolia_For_Testing_Chainlink.s.sol --sig "simulateDVandStratModCreation()" --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
/// To deploy: forge script script/deploy/sepolia/Deploy_Sepolia_For_Testing_Chainlink.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY --verify

contract Deploy_Sepolia_For_Testing_Chainlink is Script {

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
        StratModManagerMock stratModManagerMock = StratModManagerMock(payable(0x127560245D11c675283487193a455C0FE2Baf790));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 amountToSend = 6000000000000000 wei; // 0.007 ETH

        // Fund the stratModManagerMock contract
        vm.startBroadcast(deployerPrivateKey);

        // Send ETH to stratModManagerMock contract to testing purpose
        (bool success, ) = address(stratModManagerMock).call{value: amountToSend}("");
        require(success, "Failed to send ETH to stratModManagerMock");

        // Call the precreateDV function on stratModManagerMock
        stratModManagerMock.precreateDV(700, 4, 1000000000000000); // 0.001 ETH 

        // Call the createStrategyModules function on stratModManagerMock
        stratModManagerMock.createStrategyModules(330, 440, 550, 660, 2500000000000000); // 0,0025 ETH
        stratModManagerMock.createStrategyModules(420, 520, 620, 720, 2000000000000000); // 0,002 ETH
        vm.stopBroadcast();
    }
}
