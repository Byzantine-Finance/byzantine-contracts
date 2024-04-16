// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStrategyModule {

    /**
      * @notice Call the EigenPodManager contract
      * @param data to call contract 
     */
    function callEigenPodManager(bytes calldata data) external payable returns (bytes memory);

    /**
     * @dev Error when unauthorized call to a function callable only by the StrategyModuleManager.
     */
    error CallableOnlyByStrategyModuleManager();

    /**
     * @dev Error when unauthorized call to a function callable only by the StrategyModuleOwner.
     */
    error CallableOnlyByStrategyModuleOwner();

    /**
     * @dev Returned on failed Eigen Layer contracts call
     */
    error CallFailed(bytes data);

}