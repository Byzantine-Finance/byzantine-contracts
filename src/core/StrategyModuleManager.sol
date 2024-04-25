// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IEigenPod.sol";

import "./StrategyModule.sol";

import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStrategyModuleManager.sol";

// TODO: Emit events to notify what happened
// TODO: Deploy a StrategyModule with CREATE2 to determine the address of the EigenPod for the operators

contract StrategyModuleManager is IStrategyModuleManager, Ownable {

    /* ============== STATE VARIABLES ============== */

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice StratMod owner to deployed StratMod address
    mapping(address => IStrategyModule[]) public ownerToStratMods;

    /// @notice The number of StratMods that have been deployed
    uint256 public numStratMods;

    /* =============== CONSTRUCTOR =============== */

    constructor(
        IEigenPodManager _eigenPodManager
    ) {
        eigenPodManager = _eigenPodManager;
    }

    /* ================== MODIFIERS ================== */

    modifier checkStratModOwnerAndIndex(uint256 stratModIndex) {
        if (ownerToStratMods[msg.sender].length == 0) revert DoNotHaveStratMod(msg.sender);
        if (stratModIndex > ownerToStratMods[msg.sender].length - 1) revert InvalidStratModIndex(stratModIndex);
        _;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates a StrategyModule for the sender.
     * @dev Returns StrategyModule address 
     */
    function createStratMod() external returns (address) {
        // Deploy a StrategyModule
        IStrategyModule stratMod = _deployStratMod();

        return address(stratMod);
    }

    /**
     * @notice Create a StrategyModule for the sender and then stake native ETH for a new beacon chain validator
     * on that newly created StrategyModule. Also creates an EigenPod for the StrategyModule.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH(
        bytes calldata pubkey, 
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        IStrategyModule stratMod = _deployStratMod();
        stratMod.callEigenPodManager{value: msg.value}(abi.encodeWithSignature("stake(bytes,bytes,bytes32)", pubkey, signature, depositDataRoot));
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the addresses of the `stratModOwner`'s StrategyModules
     * @param stratModOwner The address you want to know the Strategy Modules it owns.
     */
    function getStratMods(address stratModOwner) public view returns (IStrategyModule[] memory) {
        require(hasStratMods(stratModOwner), "StrategyModuleManager: That address doesn't have Strategy Modules");
        return ownerToStratMods[stratModOwner];
    }

    /**
     * @notice Returns the StrategyModule of an address by its index.
     * @param stratModOwner The address of the StrategyModule's owner.
     * @param stratModIndex The index of the StrategyModule.
     */
    function getStratModByIndex(address stratModOwner, uint256 stratModIndex) public view returns (IStrategyModule) {
        if (ownerToStratMods[stratModOwner].length == 0) revert DoNotHaveStratMod(stratModOwner);
        if (stratModIndex + 1 > ownerToStratMods[stratModOwner].length) revert InvalidStratModIndex(stratModIndex);
        return ownerToStratMods[stratModOwner][stratModIndex];
    }

    /**
     * @notice Returns 'true' if the `stratModOwner` has created at least one StrategyModule, and 'false' otherwise.
     * @param stratModOwner The address you want to know if it owns at least a StrategyModule.
     */
    function hasStratMods(address stratModOwner) public view returns (bool) {
        if (ownerToStratMods[stratModOwner].length == 0) {
            return false;
        }
        return true;
    }

    /**
     * @notice Returns the address of the `stratMod`'s EigenPod (whether it is deployed yet or not).
     * @param stratMod The address of the StrategyModule contract you want to know the EigenPod address.
     * @dev If the `stratMod` is not an instance of a StrategyModule contract, the function will all the same 
     * returns the EigenPod of the input address.
     */
    function getPod(address stratMod) public view returns (IEigenPod) {
        return eigenPodManager.getPod(stratMod);
    }

    /**
     * @notice Returns 'true' if the `stratMod` has created an EigenPod, and 'false' otherwise.
     * @param stratModOwner The owner of the StrategyModule
     * @param stratModIndex The index of the `stratModOwner` StrategyModules you want to know if it has an EigenPod.
     */
    function hasPod(address stratModOwner, uint256 stratModIndex) public view returns (bool) {
        // Check if the index is valid
        if (stratModIndex + 1 > ownerToStratMods[stratModOwner].length) revert InvalidStratModIndex(stratModIndex);

        return eigenPodManager.hasPod(address(ownerToStratMods[stratModOwner][stratModIndex]));
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _deployStratMod() internal returns (IStrategyModule) {
        ++numStratMods;
        // create the stratMod
        IStrategyModule stratMod = IStrategyModule(
            address(
                new StrategyModule(address(this), address(eigenPodManager), msg.sender)
            )
        );

        // store the stratMod in the mapping
        ownerToStratMods[msg.sender].push(stratMod);
        return stratMod;
    }

}