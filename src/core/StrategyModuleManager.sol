// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "./StrategyModuleManagerStorage.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IStrategyModule.sol";
import "../interfaces/IStakerRewards.sol";
import {console} from "forge-std/console.sol";

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
        IDelegationManager _delegationManager,
        IStakerRewards _stakerRewards
    ) StrategyModuleManagerStorage(_stratModBeacon, _auction, _byzNft, _eigenPodManager, _delegationManager, _stakerRewards) {
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
     * @notice Function to pre-create Distributed Validators. Must be called at least one time to allow stakers to enter in the protocol.
     * @param _numDVsToPreCreate Number of Distributed Validators to pre-create.
     * @dev This function is only callable by Byzantine Finance. Once the first DVs are pre-created, the stakers
     * pre-create a new DV every time they create a new StrategyModule (if enough operators in Auction).
     */
    function preCreateDVs(
        uint8 _numDVsToPreCreate
    ) external onlyOwner {
        // Add up all the VCs of the nodes in the DV
        uint256 totalVCs;   

        for (uint8 i = 0; i < _numDVsToPreCreate;) {
            IStrategyModule.Node[] memory nodes = auction.getAuctionWinners();

            for (uint8 j = 0; j < nodes.length;) {
                pendingClusters[numPreCreatedClusters].nodes[j] = nodes[j];
                totalVCs += pendingClusters[numPreCreatedClusters].nodes[j].vcNumber;

                unchecked {
                    ++j;
                }
            }
            pendingClusters[numPreCreatedClusters].dvStatus = IStrategyModule.DVStatus.WAITING_ACTIVATION;

            ++numPreCreatedClusters;

            unchecked {
                ++i;
            }
        }

        // Trigger the checkpoint in StakerRewards contract and update it
        stakerRewards.updateCheckpoint(totalVCs, auction.clusterSize());
    }

    /**
     * @notice A 32ETH staker create a Strategy Module, use a pre-created DV as a validator and activate it by depositing 32ETH.
     * @param pubkey The 48 bytes public key of the beacon chain DV.
     * @param signature The DV's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
     * @dev This action triggers a new auction to pre-create a new Distributed Validator for the next staker (if enough operators in Auction).
     * @dev It also fill the ClusterDetails struct of the newly created StrategyModule.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratModAndStakeNativeETH(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        require (getNumPendingClusters() > 0, "StrategyModuleManager.createStratModAndStakeNativeETH: no pending DVs");
        require(msg.value == 32 ether, "StrategyModuleManager.createStratModAndStakeNativeETH: must initially stake for any validator with 32 ether");
        /// TODO Verify the pubkey in arguments to be sure it is using the right pubkey of a pre-created cluster

        // Create a StrategyModule
        IStrategyModule newStratMod = _deployStratMod();

        // Stake 32 ETH in the Beacon Chain
        newStratMod.stakeNativeETH{value: msg.value}(pubkey, signature, depositDataRoot);

        uint256 clusterSize = pendingClusters[numStratMods].nodes.length;

        // Set the ClusterDetails struct of the new StrategyModule and get the smallest VC of the DV
        uint256 smallestVC = newStratMod.setClusterDetails(
            pendingClusters[numStratMods].nodes,
            IStrategyModule.DVStatus.DEPOSITED_NOT_VERIFIED
        );

        // Update pending clusters container and cursor
        delete pendingClusters[numStratMods];
        ++numStratMods;

        // Add up the VCs of all the nodes DV 
        uint256 totalVCs;
        // If enough node ops in Auction, trigger a new auction for the next staker's DV
        if (auction.numNodeOpsInAuction() >= clusterSize) {

            IStrategyModule.Node[] memory nodes = auction.getAuctionWinners();
            for (uint8 i = 0; i < nodes.length;) {
                pendingClusters[numPreCreatedClusters].nodes[i] = nodes[i];
                totalVCs += pendingClusters[numPreCreatedClusters].nodes[i].vcNumber;

                unchecked {
                    ++i;
                }
            }
            pendingClusters[numPreCreatedClusters].dvStatus = IStrategyModule.DVStatus.WAITING_ACTIVATION;
            ++numPreCreatedClusters;
        }

        // Update the staker details in the StakerRewards contract
        stakerRewards.stakerJoined(address(newStratMod), smallestVC, totalVCs, clusterSize);
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
     * @notice Returns the address of the Eigen Pod of a specific StrategyModule.
     * @param _nounce The index of the Strategy Module you want to know the Eigen Pod address.
     * @dev Function essential to pre-crete DVs as their withdrawal address has to be the Eigen Pod address.
     */
    function preCalculatePodAddress(uint64 _nounce) external view returns (address) {
        // Pre-calcualte next nft id
        uint256 preNftId = uint256(keccak256(abi.encode(_nounce)));

        // Pre-calculate the address of the next Strategy Module
        address stratModAddr = address(
            Create2.computeAddress(
                bytes32(preNftId), //salt
                keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(stratModBeacon, ""))) //bytecode
            )
        );

        // Returns the next StrategyModule's EigenPod address
        return getPodByStratModAddr(stratModAddr);
    }

    /// @notice Returns the number of current pending clusters waiting for a Strategy Module.
    function getNumPendingClusters() public view returns (uint64) {
        return numPreCreatedClusters - numStratMods;
    }

    /**
     * @notice Returns the node details of a pending cluster.
     * @param clusterIndex The index of the pending cluster you want to know the node details.
     * @dev If the index does not exist, it returns the default value of the Node struct.
     */
    function getPendingClusterNodeDetails(uint64 clusterIndex) public view returns (IStrategyModule.Node[4] memory) {
        return pendingClusters[clusterIndex].nodes;
    }

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
     * @notice Specify to which operators `staker`'s StrategyModules has delegated to.
     * @param staker The address of the StrategyModules' owner.
     * @dev Revert if the `staker` doesn't have any StrategyModule.
     */
    function hasDelegatedTo(address staker) public view returns (address[] memory) {
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

    function _deployStratMod() internal returns (IStrategyModule) {
        // mint a byzNft for the Strategy Module's creator
        uint256 nftId = byzNft.mint(msg.sender, numStratMods);

        // create the stratMod
        address stratMod = Create2.deploy(
            0,
            bytes32(nftId),
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(stratModBeacon, ""))
        );
        IStrategyModule(stratMod).initialize(nftId, msg.sender);

        // store the stratMod in the nftId mapping
        nftIdToStratMod[nftId] = stratMod;

        // store the stratMod in the staker mapping
        stakerToStratMods[msg.sender].push(stratMod);

        return IStrategyModule(stratMod);
    }

}