// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../ERC7535/ERC7535Upgradeable.sol";
import {SymPod} from "./SymPod.sol";
import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

contract NativeSymVault is Initializable, OwnableUpgradeable, ERC7535Upgradeable {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice The vault that this NativeSymVault is associated with
    IVault public vault;

    /// @notice The SymPod contract address
    address payable public symPod;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    // TODO: remove constructor, requires changing the initialization in SymbioticVaultFactory
    // constructor() {
    //     // Disable initializer in the context of the implementation contract
    //     _disableInitializers();
    // }

    function initialize(
        address initialOwner, 
        address _vaultAddress,
        address _stakingMinivault
    ) external initializer {
        __NativeSymVault_init(
            initialOwner,
            _vaultAddress,
            _stakingMinivault
        );
    }

    function __NativeSymVault_init(
        address initialOwner,
        address _vaultAddress,
        address _stakingMinivault
    ) internal onlyInitializing {
        // Initialize parent contracts
        __Ownable_init(msg.sender);
        __ERC7535_init();

        // Initialize the contract
        __NativeSymVault_init_unchained(
            initialOwner,
            _vaultAddress,
            _stakingMinivault
        );
    }

    function __NativeSymVault_init_unchained(
        address initialOwner,
        address _vaultAddress,
        address _stakingMinivault
    ) internal onlyInitializing {
        // Set vault reference
        vault = IVault(_vaultAddress);

        // Set symPod reference
        symPod = payable(_stakingMinivault);

        // Whitelist NativeSymVault to deposit into Symbiotic vault
        vault.setDepositorWhitelistStatus(address(this), true);

        // Transfer ownership
        _transferOwnership(initialOwner);
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Payable fallback function that receives ether deposited to the NativeSymVault contract
     */
    receive() external override payable {
        // TODO: emit an event to notify
    }

    /**
     * @notice Deposits ETH into the vault. Amount is determined by ETH depositing.
     * @param assets The amount of ETH being deposit.
     * @param receiver The address to receive the Native Restaking Vaultshares (NRVS).
     * @return The amount of NRVS shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable returns (uint256) {
        // Deposit ETH into the vault to receive NRVS
        uint256 nrvShares = super.deposit(assets, receiver);
        
        // Send the ETH to the Staking Minivault to be staked on the beacon chain and mint the corresponding SymPod shares (SPS)
        uint256 spShares = SymPod(symPod).deposit{value: assets}(assets, address(this));

        // Emit only for testing purposes of SymbioticVaultFactoryTest 
        emit SPSReceived(spShares);

        // NativeSymVault approves Symbiotic vault to transfer SPS
        SymPod(symPod).approve(address(vault), spShares);

        // Deposit SPS into Symbiotic vault
        (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(address(this), spShares);
        
        // Emit only for testing purposes of SymbioticVaultFactoryTest 
        emit SpsToSymbioticVault(mintedShares, depositedAmount);

        return nrvShares;
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
        uint256 stakingAssets = SymPod(symPod).mint{value: assets}(shares, receiver);

        // Deposit SVS into Symbiotic vault
        (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(receiver, stakingAssets);

        return assets;
    }

    /**
     * @notice Returns the total value of assets in the vault.
     * @return The total value of assets in the vault.
     */
    function totalAssets() public view override returns (uint256) {
        return SymPod(symPod).getTotalStaked() + address(this).balance;
    }

    // Event to emit svShares for testing purposes in SymbioticVaultFactoryTest
    event SPSReceived(uint256 svShares);
    event SpsToSymbioticVault(uint256 mintedShares, uint256 depositedAmount);

}
