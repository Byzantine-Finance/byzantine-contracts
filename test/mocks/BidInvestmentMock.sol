// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

import {IEscrow} from "../../src/interfaces/IEscrow.sol";
import {IStakerRewards} from "../../src/interfaces/IStakerRewards.sol";

contract BidInvestmentMock is Initializable, ReentrancyGuardUpgradeable {
    /// @notice Escrow contract
    IEscrow public immutable escrow;

    /// @notice StakerRewards contract
    IStakerRewards public immutable stakerRewards;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IEscrow _escrow, IStakerRewards _stakerRewards) {
        escrow = _escrow;
        stakerRewards = _stakerRewards;
        // Disable initializer in the context of the implementation contract
        _disableInitializers();
    }

    function initialize() external initializer {
        __ReentrancyGuard_init();
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives the paid bid prices from the Escrow contract 
     */
    receive() external payable {}


    /**
     * @notice Send the remaining bids of the exited DVs to the escrow contract.
     * @param _amount The amount of bids to send to the escrow contract
     */
    function sendBidsToEscrow(uint256 _amount) external onlyStakerRewards {
        (bool success, ) = payable(address(escrow)).call{value: _amount}("");
        if (!success) revert FailedToSendBidsToEscrow();
    }

    /**
     * @notice Send the pending rewards from the BidInvestment contract to the vault
     * @param _vault The address of the vault
     * @param _amount The amount of rewards to send to the vault
     */
    function sendRewardsToVault(address _vault, uint256 _amount) external onlyStakerRewards {
        (bool success, ) = payable(_vault).call{value: _amount}("");
        if (!success) revert FailedToSendRewardsToVault();
    }

    modifier onlyStakerRewards() {
        if (msg.sender != address(stakerRewards)) revert OnlyStakerRewards();
        _;
    }

    /* ============== ERRORS ============== */  

    /// @dev Returned when the function is called by a non-stakerRewards address
    error OnlyStakerRewards();

    /// @dev Returned when the bids cannot be sent to the escrow contract
    error FailedToSendBidsToEscrow();

    /// @dev Returned when the rewards cannot be sent to the vault
    error FailedToSendRewardsToVault();
}
