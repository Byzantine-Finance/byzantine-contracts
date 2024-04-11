// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";

contract StrategyModule is Ownable {

    /* ============== STATE VARIABLES ============== */

    /// @notice This is the EigenPodManager contract
    IEigenPodManager public immutable eigenPodManager;

    /* ============== CONSTRUCTOR ============== */

    constructor(
        IEigenPodManager _eigenPodManager
    ) {
        eigenPodManager = _eigenPodManager;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Creates an EigenPod for the StrategyModule.
     * @dev The pod owner can only the StrategyModule itself.
     * @dev Function will revert if the StrategyModule already has an EigenPod.
     * @dev Returns EigenPod address.
     */
    function createPod() external returns (address) {
        return eigenPodManager.createPod();
    }

}