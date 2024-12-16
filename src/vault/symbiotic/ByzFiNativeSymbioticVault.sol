// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../ERC7535/ERC7535Upgradeable.sol";

import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {StakingMinivault} from "./StakingMinivault.sol";

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

    function initialize(
        address initialOwner, 
        address _vaultAddress,
        address _symPodFactory,
        address _auction,
        address _beaconChainAdmin,
        bool _whitelistedDeposit
    ) external initializer {
        __ByzFiNativeSymbioticVault_init(
            initialOwner,
            _vaultAddress,
            _symPodFactory,
            _auction,
            _beaconChainAdmin,
            _whitelistedDeposit
        );
    }

    function __ByzFiNativeSymbioticVault_init(
        address initialOwner,
        address _vaultAddress,
        address _symPodFactory,
        address _auction,
        address _beaconChainAdmin,
        bool _whitelistedDeposit
    ) internal onlyInitializing {
        // Initialize parent contracts
        __Ownable_init();
        __ERC7535_init();

        // Initialize the contract
        __ByzFiNativeSymbioticVault_init_unchained(
            initialOwner,
            _vaultAddress,
            _symPodFactory,
            _auction,
            _beaconChainAdmin,
            _whitelistedDeposit
        );
    }

    function __ByzFiNativeSymbioticVault_init_unchained(
        address initialOwner,
        address _vaultAddress,
        address _symPodFactory,
        address _auction,
        address _beaconChainAdmin,
        bool _whitelistedDeposit
    ) internal onlyInitializing {
        // Set vault reference
        vault = IVault(_vaultAddress);

        // Deploy and initialize StakingMinivault
        stakingMinivault = new StakingMinivault();
        stakingMinivault.initialize(
            _symPodFactory,
            _auction,
            _beaconChainAdmin,
            _whitelistedDeposit,
            initialOwner
        );

        // Transfer ownership
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
     * @return The amount of NRVS shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override payable returns (uint256) {
        // Deposit ETH into the vault to receive NRVS
        uint256 nrvShares = super.deposit(assets, receiver);

        // Send the ETH to the Staking Minivault to be staked on the beacon chain and mint the corresponding Staking vaultshares (SVS) 
        uint256 svShares = StakingMinivault(stakingMinivault).deposit{value: assets}(assets, receiver);

        // Restake the SVS into the Symbiotic Vault
        // TODO: implement
        
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
        uint256 stakingAssets = StakingMinivault(stakingMinivault).mint{value: assets}(shares, receiver);

        // Restake the SVS into the Symbiotic Vault
        // TODO: implement

        return assets;
    }

}
