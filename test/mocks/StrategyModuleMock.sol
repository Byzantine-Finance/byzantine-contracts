// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StratModManagerMock.sol";
import "./StakerRewardsMock.sol";

contract StrategyModuleMock {

    /* ============== CONSTANTS + IMMUTABLES ============== */

    /// @notice The single StrategyModuleManager for Byzantine
    StratModManagerMock public immutable stratModManager;

    /// @notice StakerRewards contract
    StakerRewardsMock public immutable stakerRewards;

    /* ============== STATE VARIABLES ============== */

    enum DVStatus {
        WAITING_ACTIVATION, // Waiting for the cluster manager to deposit the 32ETH on the Beacon Chain
        DEPOSITED_NOT_VERIFIED, // Deposited on ethpos but withdrawal credentials has not been verified
        ACTIVE_AND_VERIFIED, // Staked on ethpos and withdrawal credentials has been verified
        EXITED // Withdraw the principal and exit the DV
    }
    
    /// @notice Struct to store the details of a DV node registered on Byzantine 
    struct Node {
        // The number of Validation Credits (1 VC = the right to run a validator as part of a DV for a day)
        uint256 vcNumber;
    }

    /// @notice Struct to store the details of a Distributed Validator created on Byzantine
    struct ClusterDetails {
        // The status of the Distributed Validator
        DVStatus dvStatus;
        // A record of the 4 nodes being part of the cluster
        Node[4] nodes;
    }

    /// @notice The ByzNft associated to this StrategyModule.
    /// @notice The owner of the ByzNft is the StrategyModule owner.
    uint256 public stratModNftId;

    // Empty struct, all the fields have their default value
    ClusterDetails public clusterDetails;

    /* ============== CONSTRUCTOR & INITIALIZER ============== */

    constructor(
        StratModManagerMock _stratModManager,
        StakerRewardsMock _stakerRewards
    ) {
        stratModManager = _stratModManager;
        stakerRewards = _stakerRewards;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Set the `clusterDetails` struct of the StrategyModule and get the smallest VC number
     * @param nodes An array of Node making up the DV
     * @param dvStatus The status of the DV, refer to the DVStatus enum for details.
     * @dev Callable only by the StrategyModuleManager and bound a pre-created DV to this StrategyModule.
     */
    function setClusterDetails(
        Node[4] calldata nodes,
        DVStatus dvStatus
    ) external /** onlyStratModManager */ returns(uint256) {
        uint256 smallestVcNumber = nodes[0].vcNumber;
        for (uint8 i = 0; i < 4;) {
            clusterDetails.nodes[i] = nodes[i];

            // If the current VC number is smaller than the smallest VC number, update it
            if (nodes[i].vcNumber < smallestVcNumber) {
                smallestVcNumber = nodes[i].vcNumber;
            }
            unchecked {
                ++i;
            }
        }

        clusterDetails.dvStatus = dvStatus;
        return smallestVcNumber;
    }

    /**
     * @notice Subtracts the consumed VC number from the VC number of each node in the DV and updates the DV status if VC number is 0.
     * @param consumedVCs The number of VC numbers to subtract from the VC number of each node in the DV
     * @dev Callable by the StakerRewards contract to update the VC number after offchain computation 
     */
    function updateNodeVcNumber(uint256 consumedVCs) external {
        for (uint8 i = 0; i < 4;) {
            clusterDetails.nodes[i].vcNumber -= consumedVCs;
            // If the VC number is 0, set the DV status to EXITED
            if (clusterDetails.nodes[i].vcNumber == 0) {
                clusterDetails.dvStatus = DVStatus.EXITED;
            }

            unchecked {
                ++i;
            }
        }
    }

    /* ================ VIEW FUNCTIONS ================ */


    /**
     * @notice Returns the status of the Distributed Validator (DV)
     */
    function getDVStatus() public view returns (DVStatus) {
        return clusterDetails.dvStatus;
    }

    /**
     * @notice Returns the DV nodes details of the Strategy Module
     * It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.
     */
    function getDVNodesDetails() public view returns (StrategyModuleMock.Node[4] memory) {
        return clusterDetails.nodes;
    }
}