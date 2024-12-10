// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../ERC7535/ERC7535Upgradeable.sol";

import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {StakingMinivaultMock} from "../../../test/mocks/StakingMinivaultMock.sol";

contract ByzFiNativeSymbioticVault is Initializable, OwnableUpgradeable, ERC7535Upgradeable {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice The vault that this ByzFiNativeSymbioticVault is associated with
    IVault public vault;

    /// @notice The StakingMinivault contract address
    address public stakingMinivault;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner, the vault address, and the staking minivault address
     */
    function initialize(address initialOwner, address _vaultAddress, address _stakingMinivaultAddress) external initializer {
        vault = IVault(_vaultAddress);
        stakingMinivault = _stakingMinivaultAddress;
        _transferOwnership(initialOwner);
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Payable fallback function that receives ether deposited to the ByzFiNativeSymbioticVault contract
     */
    receive() external override payable {
        // TODO: emit an event to notify
    }

    /**
     * @notice Whitelists the StakingMinivault contract to be able to deposit ETH into the Symbiotic Vault
     */
    function whitelistDepositors() external onlyOwner {
        vault.setDepositorWhitelistStatus(stakingMinivault, true); 
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
