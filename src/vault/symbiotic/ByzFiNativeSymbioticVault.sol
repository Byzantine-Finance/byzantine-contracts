// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../ERC7535/ERC7535Upgradeable.sol";

import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

contract ByzFiNativeSymbioticVault is Initializable, OwnableUpgradeable, ERC7535Upgradeable {
    /// @notice The vault that this ByzFiNativeSymbioticVault is associated with
    IVault public vault;

    /**
     * @notice Payable fallback function that receives ether deposited to the ByzFiNativeSymbioticVault contract
     */
    receive() external override payable {
        // TODO: emit an event to notify
    }

    /**
     * @notice Used to initialize the ByzFiNativeSymbioticVault given it's setup parameters.
     * @param _vaultAddress The address of the vault that this ByzFiNativeSymbioticVault is associated with.
     */
    function initialize(address _vaultAddress) external initializer {
        vault = IVault(_vaultAddress);
    }

    /**
     * @notice Deposits ETH into the vault. Amount is determined by ETH depositing.
     * @param assets The amount of ETH being deposit.
     * @param receiver The address to receive the Native Restaking Vaultshares (NRVS).
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable returns (uint256) {
        // Deposit ETH into the vault to receive NRVS
        uint256 shares = super.deposit(assets, receiver);

        // Send the ETH to the Staking Minivault to be staked on the beacon chain and mint the corresponding Staking vaultshares (SVS) 
        // TODO: implement

        // Restake the SVS into the Symbiotic Vault
        // TODO: implement
        
        return shares;
    }

    /**
     * @notice Deposits ETH into the vault. Amount is determined by number of shares minting.
     * @param shares The amount of vault shares to mint.
     * @param receiver The address to receive the Native Restaking Vaultshares (NRVS).
     * @return The amount of ETH deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override payable returns (uint256) {
        // Mint shares of NRVS by depositing ETH into the vault
        uint256 assets = super.mint(shares, receiver);

        // Send the ETH to the Staking Minivault to be staked on the beacon chain and mint the corresponding Staking vaultshares (SVS) 
        // TODO: implement

        // Restake the SVS into the Symbiotic Vault
        // TODO: implement

        return assets;
    }

}
