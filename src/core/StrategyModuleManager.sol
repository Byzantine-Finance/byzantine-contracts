// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "./StrategyModuleManagerStorage.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IStrategyModule.sol";

// TODO: Emit events to notify what happened

contract StrategyModuleManager is 
    Initializable,
    OwnableUpgradeable,
    StrategyModuleManagerStorage
{
    /* =============== CONSTRUCTOR & INITIALIZER =============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IBeacon _stratModBeacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) StrategyModuleManagerStorage(_stratModBeacon, _auction, _byzNft, _eigenPodManager, _delegationManager) {
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the address of the initial owner
     */
    function initialize(
        address initialOwner
    ) external initializer {
        _transferOwnership(initialOwner);
    }

    /* ================== MODIFIERS ================== */

    modifier onlyStratModOwner(address owner, address stratMod) {
        uint256 stratModNftId = IStrategyModule(stratMod).stratModNftId();
        if (byzNft.ownerOf(stratModNftId) != owner) revert NotStratModOwner();
        _;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates a StrategyModule for the sender.
     * @dev Returns StrategyModule address 
     */
    function createStratMod() external returns (address) {
        // Deploy a StrategyModule
        return _deployStratMod();
    }

    /**
     * @notice A 32ETH staker create a Strategy Module and deposit in its smart contract its stake.
     * @return The addresses of the newly created StrategyModule AND the address of its associated EigenPod (for the DV withdrawal address)
     * @dev This action triggers an auction to select node operators to create a Distributed Validator.
     * @dev One node operator of the DV (the DV manager) will have to deposit the 32ETH in the Beacon Chain.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH() external payable returns (address, address) {
        require(msg.value == 32 ether, "StrategyModuleManager.createStratModAndStakeNativeETH: must initially stake for any validator with 32 ether");

        // Create a StrategyModule and an EigenPod
        address newStratMod = _deployStratMod();
        address newEigenPod = IStrategyModule(newStratMod).createPod();

        // Transfer the stake in the newly created StrategyModule => the sender keep the ownership of its ETH.
        payable(newStratMod).transfer(msg.value);

        // TODO: Call Auction Smart Contract and trigger an auction to find a DV

        return (newStratMod, newEigenPod);
    }

    /**
     * @notice Strategy Module owner can transfer its Strategy Module to another address.
     * Under the hood, he transfers the ByzNft associated to the StrategyModule.
     * That action makes him give the ownership of the StrategyModule and all the token it owns.
     * @param stratModAddr The address of the StrategyModule the owner will transfer.
     * @param newOwner The address of the new owner of the StrategyModule.
     * @dev The ByzNft owner must first call the `approve` function to allow the StrategyModuleManager to transfer the ByzNft.
     * @dev Function will revert if not called by the ByzNft holder.
     * @dev Function will revert if the new owner is the same as the old owner.
     */
    function transferStratModOwnership(address stratModAddr, address newOwner) external onlyStratModOwner(msg.sender, stratModAddr) {
        
        require(newOwner != msg.sender, "StrategyModuleManager.transferStratModOwnership: cannot transfer ownership to the same address");
        
        // Transfer the ByzNft
        byzNft.safeTransferFrom(msg.sender, newOwner, IStrategyModule(stratModAddr).stratModNftId());

        // Delete stratMod from owner's portfolio
        address[] storage stratMods = stakerToStratMods[msg.sender];
        for (uint256 i = 0; i < stratMods.length;) {
            if (stratMods[i] == stratModAddr) {
                stratMods[i] = stratMods[stratMods.length - 1];
                stratMods.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Add stratMod to newOwner's portfolio
        stakerToStratMods[newOwner].push(stratModAddr);
    }

    /**
     * @notice Byzantine owner fill the expected/ trusted public key for a DV (retrievable from the Obol SDK/API).
     * @dev Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator.
     * @param stratModAddr The address of the Strategy Module to set the trusted DV pubkey
     * @param pubKey The public key of the DV retrieved with the Obol SDK/API from a configHash
     * @dev Revert if not callable by StrategyModuleManager owner.
     */
    function setTrustedDVPubKey(address stratModAddr, bytes calldata pubKey) external onlyOwner {
        IStrategyModule(stratModAddr).setTrustedDVPubKey(pubKey);
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the number of StrategyModules owned by an address.
     * @param staker The address you want to know the number of Strategy Modules it owns.
     */
    function getStratModNumber(address staker) public view returns (uint256) {
        return stakerToStratMods[staker].length;
    }

    /**
     * @notice Returns the StrategyModule address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Module.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Module (nftId is not a ByzNft)
     */
    function getStratModByNftId(uint256 nftId) public view returns (address) {
        return nftIdToStratMod[nftId];
    }

    /**
     * @notice Returns the addresses of the `staker`'s StrategyModules
     * @param staker The staker address you want to know the Strategy Modules it owns.
     * @dev Returns an empty array if the staker has no Strategy Modules.
     */
    function getStratMods(address staker) public view returns (address[] memory) {
        if (!hasStratMods(staker)) {
            return new address[](0);
        }
        return stakerToStratMods[staker];
    }

    /**
     * @notice Returns 'true' if the `staker` owns at least one StrategyModule, and 'false' otherwise.
     * @param staker The address you want to know if it owns at least a StrategyModule.
     */
    function hasStratMods(address staker) public view returns (bool) {
        if (getStratModNumber(staker) == 0) {
            return false;
        }
        return true;
    }

    /* ============== EIGEN LAYER INTERACTION ============== */

    /**
     * @notice Specify which `staker`'s StrategyModules are delegated.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function isDelegated(address staker) public view returns (bool[] memory) {
        if (!hasStratMods(staker)) revert DoNotHaveStratMod(staker);

        address[] memory stratMods = getStratMods(staker);
        bool[] memory stratModsDelegated = new bool[](stratMods.length);
        for (uint256 i = 0; i < stratMods.length;) {
            stratModsDelegated[i] = delegationManager.isDelegated(stratMods[i]);
            unchecked {
                ++i;
            }
        }
        return stratModsDelegated;
    }

    /**
     * @notice Specify to which operators `staker`'s StrategyModules are delegated to.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function delegateTo(address staker) public view returns (address[] memory) {
        if (!hasStratMods(staker)) revert DoNotHaveStratMod(staker);

        address[] memory stratMods = getStratMods(staker);
        address[] memory stratModsDelegateTo = new address[](stratMods.length);
        for (uint256 i = 0; i < stratMods.length;) {
            stratModsDelegateTo[i] = delegationManager.delegatedTo(stratMods[i]);
            unchecked {
                ++i;
            }
        }
        return stratModsDelegateTo;
    }

    /**
     * @notice Returns the address of the Strategy Module's EigenPod (whether it is deployed yet or not).
     * @param stratModAddr The address of the StrategyModule contract you want to know the EigenPod address.
     * @dev If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function getPodByStratModAddr(address stratModAddr) public view returns (address) {
        return address(eigenPodManager.getPod(stratModAddr));
    }

    /**
     * @notice Returns 'true' if the `stratModAddr` has created an EigenPod, and 'false' otherwise.
     * @param stratModAddr The StrategyModule Address you want to know if it has created an EigenPod.
     * @dev If the `stratModAddr` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function hasPod(address stratModAddr) public view returns (bool) {
        return eigenPodManager.hasPod(stratModAddr);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _deployStratMod() internal returns (address) {
        ++numStratMods;

        // mint a byzNft for the Strategy Module's creator
        uint256 nftId = byzNft.mint(msg.sender, numStratMods);

        // create the stratMod
        address stratMod = address(new BeaconProxy(address(stratModBeacon), ""));
        IStrategyModule(stratMod).initialize(nftId);

        // store the stratMod in the nftId mapping
        nftIdToStratMod[nftId] = stratMod;

        // store the stratMod in the staker mapping
        stakerToStratMods[msg.sender].push(stratMod);

        return stratMod;
    }

}