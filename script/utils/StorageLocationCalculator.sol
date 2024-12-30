// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title StorageLocationCalculator
 * @author Byzantine-Finance
 * @notice Script to calculate storage slots for ERC7201 namespaced storage pattern (https://eips.ethereum.org/EIPS/eip-7201)
 * @dev Usage:
 * 1. Run: STORAGE_NAMESPACE="your.namespace.here" forge script script/utils/StorageLocationCalculator.sol
 * 2. Copy the generated storage location for your contract
 */
contract StorageLocationCalculator is Script {
    // e.g. STORAGE_NAMESPACE = "openzeppelin.storage.ERC7535"
    string public STORAGE_NAMESPACE;

    /**
     * @notice Calculates and outputs the storage location for the specified namespace
     * @dev Formula: keccak256(namespace) - 1 & ~0xff
     */
    function run() public {
        STORAGE_NAMESPACE = vm.envString("STORAGE_NAMESPACE");

        bytes32 hashedNamespace = keccak256(bytes(STORAGE_NAMESPACE));
        bytes32 storageLocation = bytes32((uint256(hashedNamespace) - 1) & ~uint256(0xff));
        
        console.log("\n=== Storage Location Calculator ===");
        console.log("Namespace:", STORAGE_NAMESPACE);
        console.log("Storage Location:", vm.toString(storageLocation));
        console.log("\nFor use in contract:");
        console.log("bytes32 private constant STORAGE_LOCATION = %s;\n", vm.toString(storageLocation));
    }
}