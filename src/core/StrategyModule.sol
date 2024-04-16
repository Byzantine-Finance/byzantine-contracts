// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "eigenlayer-contracts/interfaces/IEigenPodManager.sol";

import "../interfaces/IStrategyModuleManager.sol";
import "../interfaces/IStrategyModule.sol";

contract StrategyModule is IStrategyModule {

    /* ============== STATE VARIABLES ============== */

    /// @notice The single StrategyModuleManager for Byzantine
    IStrategyModuleManager public immutable stratModManager;

    /// @notice address of EigenLayerPod Manager
    /// @dev this is the pod manager transparent proxy
    IEigenPodManager public immutable eigenPodManager;

    /// @notice The owner of this StrategyModule
    address public stratModOwner;

    /* ============== MODIFIERS ============== */

    modifier onlyStratModManager() {
        if (msg.sender != address(stratModManager)) revert CallableOnlyByStrategyModuleManager();
        _;
    }

    modifier onlyStratModOwner() {
        if (msg.sender != stratModOwner) revert CallableOnlyByStrategyModuleOwner();
        _;
    }

    /* ============== CONSTRUCTOR ============== */

    constructor(
        address _stratModManagerAddr,
        address _eigenPodManagerAddr,
        address _stratModOwner
    ) {
        stratModManager = IStrategyModuleManager(_stratModManagerAddr);
        eigenPodManager = IEigenPodManager(_eigenPodManagerAddr);
        stratModOwner = _stratModOwner;
    }

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
      * @notice Call the EigenPodManager contract
      * @param data to call contract 
     */
    function callEigenPodManager(bytes calldata data) external payable onlyStratModManager returns (bytes memory) {
        return _executeCall(payable(address(eigenPodManager)), msg.value, data);
    }

    /* ============== INTERNAL FUNCTIONS ============== */

    /// @notice Execute a low level call
    /// @param to address to execute call
    /// @param value amount of ETH to send with call
    /// @param data bytes array to execute
    function _executeCall(
        address payable to,
        uint256 value,
        bytes memory data
    ) private returns (bytes memory) {
        (bool success, bytes memory retData) = address(to).call{value: value}(data);
        if (!success) revert CallFailed(data);
        return retData;
    }

}