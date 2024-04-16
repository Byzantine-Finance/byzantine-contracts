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

contract StrategyModuleManager is IStrategyModuleManager, Ownable {

    /* ============== STATE VARIABLES ============== */

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice StratMod owner to deployed StratMod address
    mapping(address => IStrategyModule) public ownerToStratMod;

    /// @notice The number of StratMods that have been deployed
    uint256 public numStratMods;

    /* =============== CONSTRUCTOR =============== */

    constructor(
        IEigenPodManager _eigenPodManager
    ) {
        eigenPodManager = _eigenPodManager;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates a StrategyModule for the sender.
     * @dev Function will revert if the `msg.sender` already has a StrategyModule.
     * @dev Returns StrategyModule address 
     */
    function createStratMod() external returns (address) {
        if (hasStratMod(msg.sender)) revert AlreadyHasStrategyModule();
        // Deploy a StrategyModule if sender does not already have one
        IStrategyModule stratmod = _deployStratMod();

        return address(stratmod);
    }

    /**
     * @notice Creates an EigenPod for the sender's strategy module.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     * @dev Function will create a StrategyModule if the sender doesn't have one already.
     * @dev Returns EigenPod address and StrategyModule address (which is the EigenPod owner)
     */
    function createPod() external returns (address, address) {
        if (!hasStratMod(msg.sender)) {
            _deployStratMod();
        }
        IStrategyModule stratMod = ownerToStratMod[msg.sender];
        // deploy a pod if the sender doesn't have one already
        bytes memory retData = stratMod.callEigenPodManager(abi.encodeWithSignature("createPod()"));
        // decode the return data
        address podAddr  = abi.decode(retData, (address));

        return (podAddr, address(stratMod));
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the address of the `stratModOwner`'s StrategyModule (whether it is deployed yet or not).       
     */
    function getStratMod(address stratModOwner) public view returns (IStrategyModule) {
        IStrategyModule stratMod = ownerToStratMod[stratModOwner];
        // if strat mod does not exist already, calculate what its address *will be* once it is deployed
        if (address(stratMod) == address(0)) {
            stratMod = IStrategyModule(
                Create2.computeAddress(
                    bytes32(uint256(uint160(stratModOwner))), //salt
                    keccak256(abi.encodePacked(type(StrategyModule).creationCode, abi.encode(address(this),address(eigenPodManager), msg.sender))) //bytecode
                )
            );
        }
        return stratMod;
    }

    /**
     * @notice Returns 'true' if the `stratModOwner` has created a StrategyModule, and 'false' otherwise.       
     */
    function hasStratMod(address stratModOwner) public view returns (bool) {
        return address(ownerToStratMod[stratModOwner]) != address(0);
    }

    /**
     * @notice Returns the address of the `stratModOwner`'s EigenPod (whether it is deployed yet or not).       
     */
    function getPod(address stratModOwner) public view returns (IEigenPod) {
        if (!hasStratMod(stratModOwner)) {
            return eigenPodManager.getPod(address(getStratMod(msg.sender)));
        }
        return eigenPodManager.getPod(address(ownerToStratMod[stratModOwner]));
    }

    /**
     * @notice Returns 'true' if the `stratModOwner` has created an EigenPod, and 'false' otherwise.
     */
    function hasPod(address stratModOwner) public view returns (bool) {
        return eigenPodManager.hasPod(address(ownerToStratMod[stratModOwner]));
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _deployStratMod() internal returns (IStrategyModule) {
        ++numStratMods;
        // create the stratMod
        IStrategyModule stratMod = IStrategyModule(
            Create2.deploy(
                0,
                bytes32(uint256(uint160(msg.sender))),
                abi.encodePacked(type(StrategyModule).creationCode, abi.encode(address(this), address(eigenPodManager), msg.sender))
            )
        );
        // store the stratMod in the mapping
        ownerToStratMod[msg.sender] = stratMod;
        return stratMod;
    }

}