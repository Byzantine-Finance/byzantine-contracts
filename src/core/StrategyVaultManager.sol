// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PushSplit} from "splits-v2/splitters/push/PushSplit.sol";

import {IStrategyVaultETH} from "../interfaces/IStrategyVaultETH.sol";
import {IStrategyVaultERC20} from "../interfaces/IStrategyVaultERC20.sol";
import {IStrategyVault} from "../interfaces/IStrategyVault.sol";

import "./StrategyVaultManagerStorage.sol";

// TODO: Emit events to notify what happened

contract StrategyVaultManager is 
    Initializable,
    OwnableUpgradeable,
    StrategyVaultManagerStorage
{
    using HitchensUnorderedAddressSetLib for HitchensUnorderedAddressSetLib.Set;

    /* =============== CONSTRUCTOR & INITIALIZER =============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IBeacon _stratVaultETHBeacon,
        IBeacon _stratVaultERC20Beacon,
        IAuction _auction,
        IByzNft _byzNft,
        IEigenPodManager _eigenPodManager,
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager
    ) StrategyVaultManagerStorage(_stratVaultETHBeacon, _stratVaultERC20Beacon, _auction, _byzNft, _eigenPodManager, _delegationManager, _strategyManager) {
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
     * @notice A strategy designer creates a StrategyVault for Native ETH.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @return The address of the newly created StrategyVaultETH.
     */
    function createStratVaultETH(
        bool whitelistedDeposit,
        bool upgradeable,
        address operator
    ) public returns (address) {
        // Create a Native ETH StrategyVault
        IStrategyVaultETH newStratVault = _deployStratVaultETH(whitelistedDeposit, upgradeable);

        // Delegate the StrategyVault towards the operator
        newStratVault.delegateTo(operator);

        return address(newStratVault);
    }

    /**
     * @notice A staker (which can also be referred as to a strategy designer) first creates a Strategy Vault ETH and then stakes ETH on it.
     * @dev It calls newStratVault.stakeNativeETH(): that function triggers the necessary number of auctions to create the DVs who gonna validate the ETH staked.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @dev This action triggers (a) new auction(s) to get (a) new Distributed Validator(s) to stake on the Beacon Chain. The number of Auction triggered depends on the number of ETH sent.
     * @dev Function will revert unless a multiple of 32 ETH are sent with the transaction.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ETH staked.
     * @return The address of the newly created StrategyVaultETH.
     */
    function createStratVaultAndStakeNativeETH(
        bool whitelistedDeposit,
        bool upgradeable,
        address operator
    ) external payable returns (address) {

        // Create a Native ETH StrategyVault
        IStrategyVaultETH newStratVault = IStrategyVaultETH(createStratVaultETH(whitelistedDeposit, upgradeable, operator));

        // Stake the ETH on the new StrategyVault
        newStratVault.stakeNativeETH{value: msg.value}();

        return address(newStratVault);

    }

    /**
     * @notice Staker creates a StrategyVault with an ERC20 deposit token.
     * @param token The ERC20 deposit token for the StrategyVault.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
     */
    function createStratVaultERC20(
        IERC20 token,
        bool whitelistedDeposit,
        bool upgradeable,
        address operator
    ) external {
        // Create a ERC20 StrategyVault
        IStrategyVaultERC20 newStratVault = _deployStratVaultERC20(address(token), whitelistedDeposit, upgradeable);

        // Delegate the StrategyVault towards the operator
        newStratVault.delegateTo(operator);
    }

    /**
     * @notice Staker creates a Strategy Vault and stakes ERC20.
     * @param token The ERC20 token to stake.
     * @param amount The amount of token to stake.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @param operator The address for the operator that this StrategyVault will delegate to.
     * @dev The caller receives Byzantine StrategyVault shares in return for the ERC20 tokens staked.
     */
    function createStratVaultAndStakeERC20(
        IERC20 token,
        uint256 amount,
        bool whitelistedDeposit,
        bool upgradeable,
        address operator
    ) external {

        // Create a ERC20 StrategyVault
        IStrategyVaultERC20 newStratVault = _deployStratVaultERC20(address(token), whitelistedDeposit, upgradeable);

        // Delegate the StrategyVault towards the operator
        newStratVault.delegateTo(operator);

        // Stake ERC20
        newStratVault.stakeERC20(token, amount);
    }

    /**
     * @notice Distributes the tokens issued from the PoS rewards evenly between the node operators of a specific cluster.
     * @param _clusterId The cluster ID to distribute the POS rewards for.
     * @param _split The current split struct of the cluster. Can be reconstructed offchain since the only variable is the `recipients` field.
     * @param _token The address of the token to distribute. NATIVE_TOKEN_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
     * @dev Reverts if the cluster doesn't have a split address set / doesn't exist
     * @dev The distributor is the msg.sender. He will earn the distribution fees.
     * @dev If the push failed, the tokens will be sent to the SplitWarehouse. NodeOp will have to call the withdraw function.
     */
    function distributeSplitBalance(
        bytes32 _clusterId,
        SplitV2Lib.Split calldata _split,
        address _token
    ) external {
        address splitAddr = auction.getClusterDetails(_clusterId).splitAddr;
        if (splitAddr == address(0)) revert SplitAddressNotSet();
        PushSplit(splitAddr).distribute(_split, _token, msg.sender);
    }

    /* ============== VIEW FUNCTIONS ============== */

    /**
     * @notice Returns the StrategyVault address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Vault.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Vault (nftId is not a ByzNft)
     */
    function getStratVaultByNftId(uint256 nftId) public view returns (address) {
        return nftIdToStratVault[nftId];
    }

    
    /// @notice Returns the number of Native Strategy Vaults (a StratVaultETH)
    function numStratVaultETHs() public view returns (uint256) {
        return _stratVaultETHSet.count();
    }

    /// @notice Returns all the Native Strategy Vaults addresses (a StratVaultETH)
    function getAllStratVaultETHs() public view returns (address[] memory) {
        uint256 stratVaultETHNum = _stratVaultETHSet.count();

        address[] memory stratVaultETHs = new address[](stratVaultETHNum);
        for (uint256 i = 0; i < stratVaultETHNum;) {
            stratVaultETHs[i] = _stratVaultETHSet.keyAtIndex(i);
            unchecked {
                ++i;
            }
        }
        return stratVaultETHs;
    }

    /**
     * @notice Returns 'true' if the `stratVault` is a Native Strategy Vault (a StratVaultETH), and 'false' otherwise.
     * @param stratVault The address of the StrategyVault contract you want to know if it is a StratVaultETH.
     */
    function isStratVaultETH(address stratVault) public view returns (bool) {
        return _stratVaultETHSet.exists(stratVault);
    }

    /* ============== EIGEN LAYER INTERACTION ============== */

    /**
     * @notice Specify which `staker`'s StrategyVaults are delegated.
     * @param staker The address of the StrategyVaults' owner.
     * @dev Revert if the `staker` doesn't have any StrategyVault.
     */
    function isDelegated(address staker) public view returns (bool[] memory) {
        // if (!hasStratVaults(staker)) revert DoNotHaveStratVault(staker);

        // address[] memory stratVaults = getStratVaults(staker);
        // bool[] memory stratVaultsDelegated = new bool[](stratVaults.length);
        // for (uint256 i = 0; i < stratVaults.length;) {
        //     stratVaultsDelegated[i] = delegationManager.isDelegated(stratVaults[i]);
        //     unchecked {
        //         ++i;
        //     }
        // }
        // return stratVaultsDelegated;
    }

    /**
     * @notice Specify to which operators `staker`'s StrategyVaults has delegated to.
     * @param staker The address of the StrategyVaults' owner.
     * @dev Revert if the `staker` doesn't have any StrategyVault.
     */
    function hasDelegatedTo(address staker) public view returns (address[] memory) {
        // if (!hasStratVaults(staker)) revert DoNotHaveStratVault(staker);

        // address[] memory stratVaults = getStratVaults(staker);
        // address[] memory stratVaultsDelegateTo = new address[](stratVaults.length);
        // for (uint256 i = 0; i < stratVaults.length;) {
        //     stratVaultsDelegateTo[i] = delegationManager.delegatedTo(stratVaults[i]);
        //     unchecked {
        //         ++i;
        //     }
        // }
        // return stratVaultsDelegateTo;
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
     * @notice Deploy a new ERC20 Strategy Vault.
     * @param token The address of the token to be staked.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @return The address of the newly deployed Strategy Vault.
     */
    function _deployStratVaultERC20(address token, bool whitelistedDeposit, bool upgradeable) internal returns (IStrategyVaultERC20) {
        // mint a byzNft for the Strategy Vault's creator
        uint256 nftId = byzNft.mint(msg.sender, numStratVaults);

        // create the stratVault
        address stratVault = address(new BeaconProxy(address(stratVaultERC20Beacon), ""));
        IStrategyVaultERC20(stratVault).initialize(nftId, msg.sender, token, whitelistedDeposit, upgradeable);

        // store the nftId in the stratVault mapping
        nftIdToStratVault[nftId] = stratVault;

        // Update the number of StratVaults
        ++numStratVaults;

        return IStrategyVaultERC20(stratVault);
    }

    /**
     * @notice Deploy a new ETH Strategy Vault.
     * @param whitelistedDeposit If false, anyone can deposit into the Strategy Vault. If true, only whitelisted addresses can deposit into the Strategy Vault.
     * @param upgradeable If true, the Strategy Vault is upgradeable. If false, the Strategy Vault is not upgradeable.
     * @return The address of the newly deployed Strategy Vault.
     */
    function _deployStratVaultETH(bool whitelistedDeposit, bool upgradeable) internal returns (IStrategyVaultETH) {
        // mint a byzNft for the Strategy Vault's creator
        uint256 nftId = byzNft.mint(msg.sender, numStratVaults);

        // create the stratVault
        address stratVault = address(new BeaconProxy(address(stratVaultETHBeacon), ""));
        IStrategyVaultETH(stratVault).initialize(nftId, msg.sender, whitelistedDeposit, upgradeable);

        // Add the newly created stratVaultETH to the unordered stratVaultETH set
        _stratVaultETHSet.insert(stratVault);

        // store the nftId in the stratVault mapping
        nftIdToStratVault[nftId] = stratVault;

        // Update the number of StratVaults
        ++numStratVaults;

        return IStrategyVaultETH(stratVault);
    }

}