// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/beacon/IBeaconUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "./ByzantineVault.sol";

contract ByzantineVaultFactory is Initializable, OwnableUpgradeable {

    error VaultAlreadyExists(address asset);

    event VaultCreated(address indexed vault, address indexed asset, string name, string symbol);

    mapping(address => address) public getVault;
    address[] public allVaults;

    IBeaconUpgradeable public vaultBeacon;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IBeaconUpgradeable _vaultBeacon) public initializer {
        __Ownable_init();
        vaultBeacon = _vaultBeacon;
    }

    function createVault(
        address asset,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address) {
        if (getVault[asset] != address(0)) revert VaultAlreadyExists(asset);

        bytes memory initData = abi.encodeWithSelector(
            ByzantineVault.initialize.selector,
            asset,
            name,
            symbol
        );

        BeaconProxyUpgradeable newVault = new BeaconProxyUpgradeable(address(vaultBeacon), initData);
        
        getVault[asset] = address(newVault);
        allVaults.push(address(newVault));

        emit VaultCreated(address(newVault), asset, name, symbol);
        return address(newVault);
    }

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    uint256[49] private __gap;
}



