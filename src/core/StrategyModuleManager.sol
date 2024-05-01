// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "./StrategyModule.sol";

import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStrategyModuleManager.sol";

// TODO: Emit events to notify what happened
// TODO: Implement the possibility to delegate to an operator on behalf of the StrategyModule owner -> delegationManager.delegateToBySignature
//       Create a function in StrategyModule to have a signature from the StrategyModule (function callable only by stratModOwner)

contract StrategyModuleManager is IStrategyModuleManager, Ownable {

    /* ============== STATE VARIABLES ============== */

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /// @notice StratMod owner to deployed StratMod address
    mapping(address => address[]) public ownerToStratMods;

    /// @notice The number of StratMods that have been deployed
    uint256 public numStratMods;

    /* =============== CONSTRUCTOR =============== */

    constructor(
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) {
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
    }

    /* ================== MODIFIERS ================== */

    modifier checkStratModOwnerAndIndex(address stratModOwner, uint256 stratModIndex) {
        if (!hasStratMods(stratModOwner)) revert DoNotHaveStratMod(stratModOwner);
        if (stratModIndex + 1 > ownerToStratMods[stratModOwner].length) revert InvalidStratModIndex(stratModIndex);
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
    ) external payable returns (address) {
        address stratMod = _deployStratMod();
        IStrategyModule(stratMod).callEigenPodManager{value: msg.value}(abi.encodeWithSignature("stake(bytes,bytes,bytes32)", pubkey, signature, depositDataRoot));
        return stratMod;
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the number of StrategyModules owned by an address.
     * @param stratModOwner The address you want to know the number of Strategy Modules it owns.
     */
    function getStratModNumber(address stratModOwner) public view returns (uint256) {
        return ownerToStratMods[stratModOwner].length;
    }

    /**
     * @notice Pre-calculate the address of a new StrategyModule `stratModOwner` will deploy.
     * @dev The salt will be the address of the creator (`stratModOwner`) and the index of the new StrategyModule in creator's portfolio.
     * @param stratModOwner The address of the future StrategyModule owner.
     */
    function computeStratModAddr(address stratModOwner) public view returns (address) {
        uint256 stratModIndex = getStratModNumber(stratModOwner);

        return Create2.computeAddress(
            keccak256(abi.encodePacked(stratModOwner, stratModIndex)), //salt
            keccak256(abi.encodePacked(type(StrategyModule).creationCode, abi.encode(address(this),address(eigenPodManager),address(delegationManager),stratModOwner))) //bytecode
        );
    }

    /**
     * @notice Pre-calculate the address of a new EigenPod `stratModOwner` will deploy (via a new StrategyModule).
     * @dev The pod will be deployed on a new StrategyModule owned by `stratModOwner`.
     * @param stratModOwner The address of the future StrategyModule owner.
     */
    function computePodAddr(address stratModOwner) public view returns (address) {
        return address(eigenPodManager.getPod(computeStratModAddr(stratModOwner)));
    }

    /**
     * @notice Returns the addresses of the `stratModOwner`'s StrategyModules
     * @param stratModOwner The address you want to know the Strategy Modules it owns.
     */
    function getStratMods(address stratModOwner) public view returns (address[] memory) {
        if (!hasStratMods(stratModOwner)) revert DoNotHaveStratMod(stratModOwner);
        return ownerToStratMods[stratModOwner];
    }

    /**
     * @notice Returns the StrategyModule address of an owner by its index.
     * @param stratModOwner The address of the StrategyModule's owner.
     * @param stratModIndex The index of the StrategyModule.
     * @dev Revert if owner doesn't have StrategyModule or if index is invalid.
     */
    function getStratModByIndex(
        address stratModOwner,
        uint256 stratModIndex
    ) public view checkStratModOwnerAndIndex(stratModOwner,stratModIndex) returns (address) {
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
     * returns the EigenPod of the input address. So use that function carefully.
     */
    function getPodByStratModAddr(address stratMod) public view returns (address) {
        return address(eigenPodManager.getPod(stratMod));
    }

    /**
     * @notice Returns 'true' if the `stratMod` has created an EigenPod, and 'false' otherwise.
     * @param stratModOwner The owner of the StrategyModule
     * @param stratModIndex The index of the `stratModOwner` StrategyModules you want to know if it has an EigenPod.
     * @dev Revert if owner doesn't have StrategyModule or if index is invalid.
     */
    function hasPod(
        address stratModOwner,
        uint256 stratModIndex
    ) public view checkStratModOwnerAndIndex(stratModOwner,stratModIndex) returns (bool) {
        return eigenPodManager.hasPod(ownerToStratMods[stratModOwner][stratModIndex]);
    }

    /**
     * @notice Specify which `stratModOwner`'s StrategyModules are delegated.
     * @param stratModOwner The address of the StrategyModules' owner.
     * @dev Revert if the `stratModOwner` doesn't have any StrategyModule.
     */
    function isDelegated(address stratModOwner) public view returns (bool[] memory) {
        address[] memory stratMods = getStratMods(stratModOwner);
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
     * @notice Specify to which operators `stratModOwner`'s StrategyModules are delegated to.
     * @param stratModOwner The address of the StrategyModules' owner.
     * @dev Revert if the `stratModOwner` doesn't have any StrategyModule.
     */
    function delegateTo(address stratModOwner) public view returns (address[] memory) {
        address[] memory stratMods = getStratMods(stratModOwner);
        address[] memory stratModsDelegateTo = new address[](stratMods.length);
        for (uint256 i = 0; i < stratMods.length;) {
            stratModsDelegateTo[i] = delegationManager.delegatedTo(stratMods[i]);
            unchecked {
                ++i;
            }
        }
        return stratModsDelegateTo;
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    function _deployStratMod() internal returns (address) {
        ++numStratMods;

        // number of stratMods `msg.sender` has already created
        uint256 stratModIndex = getStratModNumber(msg.sender);

        // create the stratMod
        address stratMod = Create2.deploy(
            0,
            keccak256(abi.encodePacked(msg.sender, stratModIndex)),
            abi.encodePacked(type(StrategyModule).creationCode, abi.encode(address(this), address(eigenPodManager), address(delegationManager), msg.sender))
        );

        // store the stratMod in the mapping
        ownerToStratMods[msg.sender].push(stratMod);
        return stratMod;
    }

}