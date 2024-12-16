// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC7535Upgradeable} from "../ERC7535/ERC7535Upgradeable.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {ISymPodFactory} from "../symbiotic/interfaces/ISymPodFactory.sol";
import {ISymPod} from "../symbiotic/interfaces/ISymPod.sol";
import {BeaconChainProofs} from "../libraries/BeaconChainProofs.sol";
import {FIFOLib} from "../libraries/FIFOLib.sol";

/**
 * @title StakingMinivault
 * @author Byzantine Finance
 * @notice ERC7535 vault for staking ETH through SymPod
 */
contract StakingMinivault is ERC7535Upgradeable {
    using BeaconChainProofs for bytes32[];
    using FIFOLib for FIFOLib.FIFO;

    /* =================== MODIFIERS =================== */
    
    modifier checkWhitelist() {
        if (whitelistedDeposit && !isWhitelisted[msg.sender]) {
            revert OnlyWhitelistedDeposit();
        }
        _;
    }

    modifier onlyBeaconChainAdmin() {
        if(msg.sender != beaconChainAdmin) revert OnlyBeaconChainAdmin();
        _;
    }

    // TODO: Move file imports, errors, events, constants, state variables to a StakingMinivaultStorage.sol

    /* =================== ERRORS =================== */
    error InvalidDeposit();
    error InsufficientBalance();
    error UnauthorizedSlasher();
    error InvalidWithdrawalKey();
    error WithdrawalDelayNotMet();
    error CheckpointInProgress();
    error InvalidProof();
    error OnlyBeaconChainAdmin();
    error ClusterNotInVault();
    error OnlyWhitelistedDeposit();
    error StakerAlreadyWhitelisted();
    error WhitelistedDepositDisabled();

    /* =================== EVENTS =================== */
    event ValidatorCreated(uint256 indexed validatorIndex, bytes pubkey);
    event CheckpointStarted(uint256 timestamp);
    event CheckpointCompleted(uint256 timestamp, int256 balanceDelta);
    event WithdrawalInitiated(bytes32 withdrawalKey, uint256 amount, uint256 timestamp);
    event WithdrawalCompleted(bytes32 withdrawalKey, uint256 amount);
    event ClusterActivated(bytes32 indexed clusterId, bytes pubkey);

    /* =================== CONSTANTS =================== */
    uint256 public constant VALIDATOR_DEPOSIT = 32 ether;

    /* =================== STATE VARIABLES =================== */
    ISymPod public symPod;
    ISymPodFactory public immutable symPodFactory;
    IAuction public immutable auction;
    address public immutable beaconChainAdmin;
    
    uint256 public totalStaked;
    mapping(bytes32 => uint256) public withdrawalTimestamps;
    FIFOLib.FIFO public clusterIdsFIFO;
    mapping(address => bool) public isWhitelisted;
    bool public whitelistedDeposit;

    /* =================== CONSTRUCTOR & INITIALIZER =================== */
    
        /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _symPodFactory,
        address _auction, 
        address _beaconChainAdmin,
        bool _whitelistedDeposit,
        address _creator
    ) external initializer {
        __StakingMinivault_init(
            _symPodFactory,
            _auction,
            _beaconChainAdmin,
            _whitelistedDeposit,
            _creator
        );
    }

    function __StakingMinivault_init(
        address _symPodFactory,
        address _auction,
        address _beaconChainAdmin,
        bool _whitelistedDeposit,
        address _creator
    ) internal onlyInitializing {
        __ERC7535_init();
        __StakingMinivault_init_unchained(
            _symPodFactory,
            _auction,
            _beaconChainAdmin,
            _whitelistedDeposit,
            _creator
        );
    }

    function __StakingMinivault_init_unchained(
        address _symPodFactory,
        address _auction,
        address _beaconChainAdmin,
        bool _whitelistedDeposit,
        address _creator
    ) internal onlyInitializing {
        // Set the contract references
        symPodFactory = ISymPodFactory(_symPodFactory);
        auction = IAuction(_auction);
        beaconChainAdmin = _beaconChainAdmin;

        // Initialize SymPod
        symPod = ISymPod(symPodFactory.createSymPod(
            "ByzFi Staking Pod",
            "bSTK",
            address(this),
            address(this),
            address(this),
            address(this)
        ));

        // Initialize whitelist settings
        whitelistedDeposit = _whitelistedDeposit;
        if (_whitelistedDeposit) {
            isWhitelisted[_creator] = true;
        }
    }

    /* =================== FALLBACK =================== */

    receive() external payable override {
        // TODO: emit event to notify
    }

    /* =================== EXTERNAL FUNCTIONS =================== */

    /**
     * @notice Deposit ETH into the vault
     * @param assets Amount of ETH to deposit
     * @param receiver Address to receive shares
     * @return Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public payable override checkWhitelist returns (uint256) {
        if(assets % VALIDATOR_DEPOSIT != 0 || assets != msg.value) {
            revert InvalidDeposit();
        }

        uint256 shares = super.deposit(assets, receiver);
        _triggerAuction();
        totalStaked += assets;
        return shares;
    }

    /**
     * @notice Mint shares by depositing ETH
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return Amount of ETH deposited
     */
    function mint(uint256 shares, address receiver) public payable override checkWhitelist returns (uint256) {
        uint256 assets = previewMint(shares);
        if(assets % VALIDATOR_DEPOSIT != 0 || assets != msg.value) {
            revert InvalidDeposit();
        }

        shares = super.mint(shares, receiver);
        _triggerAuction();
        totalStaked += assets;
        return shares;
    }

    /* =================== BEACON CHAIN ADMIN FUNCTIONS =================== */

    /**
     * @notice Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
     * @dev Function callable only by BeaconChainAdmin to be sure the deposit data are the ones of a DV created within the Byzantine protocol. 
     * @param pubkey The 48 bytes public key of the beacon chain DV.
     * @param signature The DV's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the DV's deposit.
     * @param clusterId The ID of the cluster associated to these deposit data.
     * @dev Reverts if not exactly 32 ETH are sent.
     * @dev Reverts if the cluster is not in the vault.
     */
    function activateCluster(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        bytes32 clusterId
    ) external onlyBeaconChainAdmin {
        if (!clusterIdsFIFO.exists(clusterId)) revert ClusterNotInVault();

        symPod.stake{value: VALIDATOR_DEPOSIT}(
            pubkey,
            signature,
            depositDataRoot
        );

        auction.updateClusterStatus(clusterId, IAuction.ClusterStatus.DEPOSITED);
        auction.setClusterPubKey(clusterId, pubkey);

        emit ClusterActivated(clusterId, pubkey);
    }

    /* =================== VAULT CREATOR FUNCTIONS =================== */

    /**
     * @notice Updates the whitelistedDeposit flag.
     * @param _whitelistedDeposit The new whitelistedDeposit flag.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function updateWhitelistedDeposit(bool _whitelistedDeposit) external {
        // TODO: Add access control
        whitelistedDeposit = _whitelistedDeposit;
    }

    /**
     * @notice Whitelist a staker.
     * @param staker The address to whitelist.
     * @dev Callable only by the owner of the Strategy Vault's ByzNft.
     */
    function whitelistStaker(address staker) external {
        // TODO: Add access control
        if (!whitelistedDeposit) revert WhitelistedDepositDisabled();
        if (isWhitelisted[staker]) revert StakerAlreadyWhitelisted();
        isWhitelisted[staker] = true;
    }

    /* =================== VIEW FUNCTIONS =================== */

    /**
     * @notice Returns the total value of assets in the vault.
     * @return The total value of assets in the vault.
     */
    function totalAssets() public view override returns (uint256) {
        return _getETHBalance() + totalStaked;
    }

    /**
     * @notice Returns the number of active DVs staked by the Strategy Vault.
     */
    function getVaultDVNumber() public view returns (uint256) {
        return clusterIdsFIFO.getNumElements();
    }

    /**
     * @notice Returns the IDs of the active DVs staked by the Strategy Vault.
     */
    function getAllDVIds() public view returns (bytes32[] memory) {
        return clusterIdsFIFO.getAllElements();
    }

    /* =================== INTERNAL FUNCTIONS =================== */

    function _getETHBalance() internal view virtual returns (uint256) {
        return address(this).balance;
    }

    function _triggerAuction() internal {
        if(msg.value % VALIDATOR_DEPOSIT != 0) revert InvalidDeposit();
        
        uint256 validatorCount = msg.value / VALIDATOR_DEPOSIT;
        for(uint256 i = 0; i < validatorCount;) {
            bytes32 winningClusterId = auction.triggerAuction();
            clusterIdsFIFO.push(winningClusterId);
            unchecked { ++i; }
        }
    }
}