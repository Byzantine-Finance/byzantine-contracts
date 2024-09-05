// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import "eigenlayer-contracts/interfaces/IDelegationManager.sol";

import "./StrategyVaultManagerStorage.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/IStrategyVault.sol";

// TODO: Emit events to notify what happened

contract StrategyVaultManager is 
    Initializable,
    OwnableUpgradeable,
    StrategyVaultManagerStorage
{
    /* =============== CONSTRUCTOR & INITIALIZER =============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IBeacon _stratVaultBeacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager,
        PushSplitFactory _pushSplitFactory
    ) StrategyVaultManagerStorage(_stratVaultBeacon, _auction, _byzNft, _eigenPodManager, _delegationManager, _pushSplitFactory) {
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

    modifier onlyStratVaultOwner(address owner, address stratVault) {
        uint256 stratVaultNftId = IStrategyVault(stratVault).stratVaultNftId();
        if (byzNft.ownerOf(stratVaultNftId) != owner) revert NotStratVaultOwner();
        _;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Function to pre-create Distributed Validators. Must be called at least one time to allow stakers to enter in the protocol.
     * @param _numDVsToPreCreate Number of Distributed Validators to pre-create.
     * @dev This function is only callable by Byzantine Finance. Once the first DVs are pre-created, the stakers
     * pre-create a new DV every time they create a new StrategyVault (if enough operators in Auction).
     * @dev Make sure there are enough bids and node operators before calling this function.
     * @dev Pre-create clusters of size 4.
     */
    function preCreateDVs(
        uint8 _numDVsToPreCreate
    ) external onlyOwner {

        // Create the Split parameters
        (address[] memory recipients, uint256[] memory allocations) = _createSplitParams();

        for (uint8 i = 0; i < _numDVsToPreCreate;) {
            _getNewPendingCluster(recipients, allocations);
            ++numPreCreatedClusters;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice A 32ETH staker create a Strategy Vault, use a pre-created DV as a validator and activate it by depositing 32ETH.
     * @param pubkey The 48 bytes public key of the beacon chain DV.
     * @param signature The DV's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @dev This action triggers a new auction to pre-create a new Distributed Validator for the next staker (if enough operators in Auction).
     * @dev It also fill the ClusterDetails struct of the newly created StrategyVault.
     * @dev Function will revert if not exactly 32 ETH are sent with the transaction.
     */
    function createStratVaultAndStakeNativeETH(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        bool whitelistedDeposit,
        bool upgradeable
    ) external payable {
        require (getNumPendingClusters() > 0, "StrategyVaultManager.createStratVaultAndStakeNativeETH: no pending DVs");
        require(msg.value == 32 ether, "StrategyVaultManager.createStratVaultAndStakeNativeETH: must initially stake for any validator with 32 ether");
        /// TODO Verify the pubkey in arguments to be sure it is using the right pubkey of a pre-created cluster. Use a monolithic blockchain

        // Create a StrategyVault
        IStrategyVault newStratVault = _deployStratVault(address(0),whitelistedDeposit, upgradeable);

        // Stake 32 ETH in the Beacon Chain
        newStratVault.stakeNativeETH{value: msg.value}(pubkey, signature, depositDataRoot);

        uint256 clusterSize = pendingClusters[numStratVaults].nodes.length;

        // deploy the Split contract
        address splitAddr = pushSplitFactory.createSplitDeterministic(pendingClusters[numStratVaults].splitParams, owner(), owner(), bytes32(uint256(keccak256(abi.encode(numStratVaults)))));

        // Set the ClusterDetails struct of the new StrategyVault
        newStratVault.setClusterDetails(
            pendingClusters[numStratVaults].nodes,
            splitAddr,
            IStrategyVault.DVStatus.DEPOSITED_NOT_VERIFIED
        );

        // Update pending clusters container and cursor
        delete pendingClusters[numStratVaults];
        ++numStratVaults;

        // If enough node ops in Auction, trigger a new auction for the next staker's DV
        if (auction.numNodeOpsInAuction() >= clusterSize) {
            // Create the Split parameters
            (address[] memory recipients, uint256[] memory allocations) = _createSplitParams();
            _getNewPendingCluster(recipients, allocations);
            ++numPreCreatedClusters;
        }
    }

    /**
     * @notice Staker creates a Strategy Vault and stakes ERC20.
     * @param strategy The EigenLayer StrategyBaseTVLLimits contract for the depositing token.
     * @param token The ERC20 token to stake.
     * @param amount The amount of token to stake.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     */
    function createStratVaultAndStakeERC20(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        bool whitelistedDeposit,
        bool upgradeable
    ) external {

        // Create a StrategyVault
        IStrategyVault newStratVault = _deployStratVault(address(token), whitelistedDeposit, upgradeable);

        // Stake ERC20
        newStratVault.depositIntoStrategy(strategy,token, amount);

    }

    /**
     * @notice Strategy Vault owner can transfer its Strategy Vault to another address.
     * Under the hood, he transfers the ByzNft associated to the StrategyVault.
     * That action makes him give the ownership of the StrategyVault and all the token it owns.
     * @param stratVaultAddr The address of the StrategyVault the owner will transfer.
     * @param newOwner The address of the new owner of the StrategyVault.
     * @dev The ByzNft owner must first call the `approve` function to allow the StrategyVaultManager to transfer the ByzNft.
     * @dev Function will revert if not called by the ByzNft holder.
     * @dev Function will revert if the new owner is the same as the old owner.
     */
    function transferStratVaultOwnership(address stratVaultAddr, address newOwner) external onlyStratVaultOwner(msg.sender, stratVaultAddr) {
        
        require(newOwner != msg.sender, "StrategyVaultManager.transferStratVaultOwnership: cannot transfer ownership to the same address");
        
        // Transfer the ByzNft
        byzNft.safeTransferFrom(msg.sender, newOwner, IStrategyVault(stratVaultAddr).stratVaultNftId());

        // Delete stratVault from owner's portfolio
        address[] storage stratVaults = stakerToStratVaults[msg.sender];
        for (uint256 i = 0; i < stratVaults.length;) {
            if (stratVaults[i] == stratVaultAddr) {
                stratVaults[i] = stratVaults[stratVaults.length - 1];
                stratVaults.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Add stratVault to newOwner's portfolio
        stakerToStratVaults[newOwner].push(stratVaultAddr);
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the address of the EigenPod and the Split contract of the next StrategyVault to be created.
     * @param _nounce The index of the StrategyVault you want to know the EigenPod and Split contract address.
     * @dev Ownership of the Split contract belongs to ByzantineAdmin to be able to update it.
     * @dev Function essential to pre-create DVs as their withdrawal address has to be the EigenPod and fee recipient address the Split.
     */
    function preCalculatePodAndSplitAddr(uint64 _nounce) external view returns (address podAddr, address splitAddr) {
        require(_nounce < numPreCreatedClusters && _nounce >= numStratVaults, "StrategyVaultManager.preCalculatePodAndSplitAddr: invalid nounce. Should be in the precreated clusters range");

        // Pre-calculate next nft id
        uint256 preNftId = uint256(keccak256(abi.encode(_nounce)));

        // Pre-calculate the address of the next Strategy Vault
        address stratVaultAddr = address(
            Create2.computeAddress(
                bytes32(preNftId), //salt
                keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(stratVaultBeacon, ""))) //bytecode
            )
        );

        // Returns the next StrategyVault's EigenPod address
        podAddr = getPodByStratVaultAddr(stratVaultAddr);

        // Returns the next StrategyVault's Split address
        splitAddr = pushSplitFactory.predictDeterministicAddress(
            pendingClusters[_nounce].splitParams,
            owner(),
            bytes32(preNftId)
        );
    }

    /// @notice Returns the number of current pending clusters waiting for a Strategy Vault.
    function getNumPendingClusters() public view returns (uint64) {
        return numPreCreatedClusters - numStratVaults;
    }

    /**
     * @notice Returns the node details of a pending cluster.
     * @param clusterIndex The index of the pending cluster you want to know the node details.
     * @dev If the index does not exist, it returns the default value of the Node struct.
     */
    function getPendingClusterNodeDetails(uint64 clusterIndex) public view returns (IStrategyVault.Node[4] memory) {
        return pendingClusters[clusterIndex].nodes;
    }

    /**
     * @notice Returns the number of StrategyVaults owned by an address.
     * @param staker The address you want to know the number of Strategy Vaults it owns.
     */
    function getStratVaultNumber(address staker) public view returns (uint256) {
        return stakerToStratVaults[staker].length;
    }

    /**
     * @notice Returns the StrategyVault address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Vault.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Vault (nftId is not a ByzNft)
     */
    function getStratVaultByNftId(uint256 nftId) public view returns (address) {
        return nftIdToStratVault[nftId];
    }

    /**
     * @notice Returns the addresses of the `staker`'s StrategyVaults
     * @param staker The staker address you want to know the Strategy Vaults it owns.
     * @dev Returns an empty array if the staker has no Strategy Vaults.
     */
    function getStratVaults(address staker) public view returns (address[] memory) {
        if (!hasStratVaults(staker)) {
            return new address[](0);
        }
        return stakerToStratVaults[staker];
    }

    /**
     * @notice Returns 'true' if the `staker` owns at least one StrategyVault, and 'false' otherwise.
     * @param staker The address you want to know if it owns at least a StrategyVault.
     */
    function hasStratVaults(address staker) public view returns (bool) {
        if (getStratVaultNumber(staker) == 0) {
            return false;
        }
        return true;
    }

    /* ============== EIGEN LAYER INTERACTION ============== */

    /**
     * @notice Specify which `staker`'s StrategyVaults are delegated.
     * @param staker The address of the StrategyVaults' owner.
     * @dev Revert if the `staker` doesn't have any StrategyVault.
     */
    function isDelegated(address staker) public view returns (bool[] memory) {
        if (!hasStratVaults(staker)) revert DoNotHaveStratVault(staker);

        address[] memory stratVaults = getStratVaults(staker);
        bool[] memory stratVaultsDelegated = new bool[](stratVaults.length);
        for (uint256 i = 0; i < stratVaults.length;) {
            stratVaultsDelegated[i] = delegationManager.isDelegated(stratVaults[i]);
            unchecked {
                ++i;
            }
        }
        return stratVaultsDelegated;
    }

    /**
     * @notice Specify to which operators `staker`'s StrategyVaults has delegated to.
     * @param staker The address of the StrategyVaults' owner.
     * @dev Revert if the `staker` doesn't have any StrategyVault.
     */
    function hasDelegatedTo(address staker) public view returns (address[] memory) {
        if (!hasStratVaults(staker)) revert DoNotHaveStratVault(staker);

        address[] memory stratVaults = getStratVaults(staker);
        address[] memory stratVaultsDelegateTo = new address[](stratVaults.length);
        for (uint256 i = 0; i < stratVaults.length;) {
            stratVaultsDelegateTo[i] = delegationManager.delegatedTo(stratVaults[i]);
            unchecked {
                ++i;
            }
        }
        return stratVaultsDelegateTo;
    }

    /**
     * @notice Returns the address of the Strategy Vault's EigenPod (whether it is deployed yet or not).
     * @param stratVaultAddr The address of the StrategyVault contract you want to know the EigenPod address.
     * @dev If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function getPodByStratVaultAddr(address stratVaultAddr) public view returns (address) {
        return address(eigenPodManager.getPod(stratVaultAddr));
    }

    /**
     * @notice Returns 'true' if the `stratVaultAddr` has created an EigenPod, and 'false' otherwise.
     * @param stratVaultAddr The StrategyVault Address you want to know if it has created an EigenPod.
     * @dev If the `stratVaultAddr` is not an instance of a StrategyVault contract, the function will all the same 
     * returns the EigenPod of the input address. SO USE THAT FUNCTION CARREFULLY.
     */
    function hasPod(address stratVaultAddr) public view returns (bool) {
        return eigenPodManager.hasPod(stratVaultAddr);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /**
     * @notice Deploy a new Strategy Vault.
     * @param token The address of the token to be staked. Address(0) if staking ETH.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @return The address of the newly deployed Strategy Vault.
     */
    function _deployStratVault(address token, bool whitelistedDeposit, bool upgradeable) internal returns (IStrategyVault) {
        // mint a byzNft for the Strategy Vault's creator
        uint256 nftId = byzNft.mint(msg.sender, numStratVaults);

        // create the stratVault
        address stratVault = Create2.deploy(
            0,
            bytes32(nftId),
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(stratVaultBeacon, ""))
        );
        IStrategyVault(stratVault).initialize(nftId, msg.sender, token, whitelistedDeposit, upgradeable);

        // store the stratVault in the nftId mapping
        nftIdToStratVault[nftId] = stratVault;

        // store the stratVault in the staker mapping
        stakerToStratVaults[msg.sender].push(stratVault);

        return IStrategyVault(stratVault);
    }

    function _createSplitParams() internal pure returns (
        address[] memory recipients,
        uint256[] memory allocations
    ) {
        // Split operators allocation
        allocations = new uint256[](4);
        for (uint8 i = 0; i < 4;) {
            allocations[i] = NODE_OP_SPLIT_ALLOCATION;
            unchecked {
                ++i;
            }
        }
        // Split recipient addresses
        recipients = new address[](4); 
    }

    function _getNewPendingCluster(address[] memory recipients, uint256[] memory allocations) internal {
        IStrategyVault.Node[] memory nodes = auction.getAuctionWinners();
        require(nodes.length == 4, "Incompatible cluster size");

        for (uint8 j = 0; j < nodes.length;) {
            pendingClusters[numPreCreatedClusters].nodes[j] = nodes[j];
            recipients[j] = nodes[j].eth1Addr;
            unchecked {
                ++j;
            }
        }
        // Create the Split structure
        pendingClusters[numPreCreatedClusters].splitParams = SplitV2Lib.Split(recipients, allocations, SPLIT_TOTAL_ALLOCATION, SPLIT_DISTRIBUTION_INCENTIVE);
    }

}