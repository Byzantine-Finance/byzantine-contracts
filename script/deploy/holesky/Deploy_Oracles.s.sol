// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainlinkOracleImplementation} from "../../../src/oracle/ChainlinkOracleImplementation.sol";

import "forge-std/Script.sol";

/**
 * @notice Script used to deploy Byzantine Oracles implementations to Holesky
 * ORACLES_TO_DEPLOY=A,B forge script script/deploy/holesky/Deploy_Oracles.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * ORACLES_TO_DEPLOY=A,B forge script script/deploy/holesky/Deploy_Oracles.s.sol --rpc-url $HOLESKY_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 * 
 */
contract Deploy_Oracles is Script{
    // Implemented Oracles
    ChainlinkOracleImplementation public chainlinkOracleImplementation;

    function run() external {

        string memory oraclesToDeployString = vm.envString("ORACLES_TO_DEPLOY");

        // Verify if the Oracles to deploy has been specified
        if (bytes(oraclesToDeployString).length == 0) {
            console.log("Please, specify the Oracles to deploy. Example : ORACLES_TO_DEPLOY=A,B forge script script/deploy/holesky/Deploy_Oracles.s.sol --rpc-url $HOLESKY_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv");
            return;
        }

        // List of Oracles to deploy
        string[] memory oraclesToDeploy = vm.split(oraclesToDeployString, ",");

        // Deploy the specified Oracles
        for (uint256 i = 0; i < oraclesToDeploy.length; i++) {
            if (keccak256(abi.encodePacked(oraclesToDeploy[i])) == keccak256(abi.encodePacked("Chainlink"))) {
                vm.startBroadcast();
                chainlinkOracleImplementation = new ChainlinkOracleImplementation();
                console.log("ChainlinkOracleImplementation deployed at address: ", address(chainlinkOracleImplementation));
                vm.stopBroadcast();
            } else {
                console.log("Oracle not known or not implemented:", oraclesToDeploy[i]);
            }
        }

        _logAndOutputContractAddresses("script/output/holesky/Deploy_Oracles.holesky.config.json", oraclesToDeploy);
        
    }

    /**
     * @notice Log contract addresses and write to output json file
     */
    function _logAndOutputContractAddresses(string memory outputPath, string[] memory oracleNames) internal {
        // READ JSON FILE DATA
        string memory contractsAddressesData = vm.readFile(outputPath);

        // read contracts addresses
        ChainlinkOracleImplementation savedChainlinkOracleAddress = ChainlinkOracleImplementation(stdJson.readAddress(contractsAddressesData, ".addresses.lastChainlinkOracleImplementation"));

        // WRITE JSON DATA
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        string memory deployed_addresses_output;
        for (uint256 i = 0; i < oracleNames.length; i++) {
            if (keccak256(abi.encodePacked(oracleNames[i])) == keccak256(abi.encodePacked("Chainlink"))) {
                deployed_addresses_output = vm.serializeAddress(deployed_addresses, "lastChainlinkOracleImplementation", address(chainlinkOracleImplementation));
            } else {
                deployed_addresses_output = vm.serializeAddress(deployed_addresses, "lastChainlinkOracleImplementation", address(savedChainlinkOracleAddress));
            }
        }

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        // serialize all the data
        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        string memory finalJson = vm.serializeString(parent_object, chain_info, chain_info_output);

        vm.writeJson(finalJson, outputPath);
    }
}