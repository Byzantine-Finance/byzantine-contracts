// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./eigenlayer-helper/EigenLayerDeployer.t.sol";

import "../src/core/StrategyModule.sol";

contract StrategyModuleTest is EigenLayerDeployer {

    StrategyModule public strategyModule;

    function setUp() public override {
        // deploy locally EigenLayer contracts
        EigenLayerDeployer.setUp();
        console2.log("EigenPodManager address:", address(eigenPodManager));

        // deploy StrategyModule
        strategyModule = new StrategyModule(
            eigenPodManager
        );
        console2.log("StrategyModule address:", address(strategyModule));
    }

    function testCreatePod() public {
        address podAddr = strategyModule.createPod();
        address expectedPodAddr = predictPodAddr(
            address(eigenPodManager),
            bytes32(uint256(uint160(address(strategyModule)))),
            beaconProxyBytecode,
            eigenPodBeacon
        );
        assertEq(podAddr, expectedPodAddr);
    }

    function predictPodAddr(
        address deployer,
        bytes32 salt,
        bytes memory beaconProxyBytecode,
        IBeacon eigenPodBeacon
    ) public pure returns (address) {
        bytes memory bytecode = abi.encodePacked(beaconProxyBytecode, abi.encode(eigenPodBeacon, ""));
        bytes32 bytecodeHash = keccak256(bytecode);
        bytes32 data = keccak256(
            abi.encodePacked(
                bytes1(0xff), deployer, salt, bytecodeHash
            )
        );
        return address(uint160(uint256(data)));
    }

}