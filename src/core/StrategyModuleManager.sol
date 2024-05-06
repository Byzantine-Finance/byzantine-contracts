// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "../tokens/ByzNft.sol";
import "./StrategyModule.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStrategyModuleManager.sol";

// TODO: Emit events to notify what happened

contract StrategyModuleManager is IStrategyModuleManager, Ownable {

    /* ============== STATE VARIABLES ============== */

    /// @notice ByzNft contract
    IByzNft public immutable byzNft;

    /// @notice EigenLayer's EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /// @notice EigenLayer's DelegationManager contract
    IDelegationManager public immutable delegationManager;

    /// @notice Staker to its owned StrategyModules
    mapping(address => address[]) public stakerToStratMods;

    /// @notice ByzNft tokenId to its tied StrategyModule
    mapping(uint256 => address) public nftIdToStratMod;

    /// @notice The number of StratMods that have been deployed
    uint256 public numStratMods; // This is also the number of ByzNft minted   

    /* =============== CONSTRUCTOR =============== */

    constructor(
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager
    ) {
        byzNft = IByzNft(address(new ByzNft()));
        eigenPodManager = _eigenPodManager;
        delegationManager = _delegationManager;
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
        address stratMod = address(
            new StrategyModule(
                address(this),
                byzNft,
                nftId,
                address(eigenPodManager),
                address(delegationManager)
            )
        );

        // store the stratMod in the nftId mapping
        nftIdToStratMod[nftId] = stratMod;

        // store the stratMod in the staker mapping
        stakerToStratMods[msg.sender].push(stratMod);

        return stratMod;
    }

}