// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ByzantineVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ByzantineVaultFactory is Ownable {

    error VaultAlreadyExists(address asset);

    event VaultCreated(address indexed vault, address indexed asset, string name, string symbol);

    mapping(address => address) public getVault;
    address[] public allVaults;

    constructor() Ownable() {}

    function createVault(
        address asset,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address) {
        if (getVault[asset] != address(0)) revert VaultAlreadyExists(asset);

        ByzantineVault newVault = new ByzantineVault(IERC20(asset), name, symbol);
        address vaultAddress = address(newVault);
        
        getVault[asset] = vaultAddress;
        allVaults.push(vaultAddress);

        emit VaultCreated(vaultAddress, asset, name, symbol);
        return vaultAddress;
    }

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }
}



