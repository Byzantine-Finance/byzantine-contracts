// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StrategyModuleMock.sol";
import "./StakerRewardsMock.sol";

contract StratModManagerMock  {
    /// @notice StakerReward contract
    StakerRewardsMock public stakerRewardsMock;
    
    /* ============== STATE VARIABLES ============== */

    /// @notice Staker to its owned StrategyModules
    mapping(address => address[]) public stakerToStratMods;

    /// @notice ByzNft tokenId to its tied StrategyModule
    mapping(uint256 => address) public nftIdToStratMod;

    /// @notice The number of StratMods that have been deployed
    uint64 public numStratMods; // This is also the number of ByzNft minted


    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Fallback function which receives funds for testing purposes
     * @dev This function is only present in this mock contract
     */
    receive() external payable {}

    /// @notice Function to simulate a pre-creation of a DV 
    function precreateDV(uint256 _newVCs, uint256 _clusterSize, uint256 _bidPrices) external {
        // Send bid prices to StakerRewards contract
        (bool success,) = address(stakerRewardsMock).call{value: _bidPrices}("");
        require(success, "Failed to send bid prices to StakerRewards contract");
        
        stakerRewardsMock.updateCheckpoint(_newVCs, _clusterSize);
    }

    /// @notice Function to simulate a creation of a strategy module at the same time of a DV
    function createStrategyModules(uint256 _vc1, uint256 _vc2, uint256 _vc3, uint256 _vc4, uint256 _bidPrices) external {
        // Create a new StrategyModule and store it in the mapping
        StrategyModuleMock stratMod = new StrategyModuleMock(this, stakerRewardsMock);

        // Store nodes in the clusterDetails struct
        StrategyModuleMock.Node[4] memory nodes = _createDV(_vc1, _vc2, _vc3, _vc4);
        stratMod.setClusterDetails(nodes, StrategyModuleMock.DVStatus.ACTIVE_AND_VERIFIED);

        // Set the mappings
        uint256 tokenId = uint256(keccak256(abi.encode(numStratMods)));
        nftIdToStratMod[tokenId] = address(stratMod);
        stakerToStratMods[msg.sender].push(address(stratMod));

        ++numStratMods;

        // Send bid prices to StakerRewards contract
        (bool success,) = address(stakerRewardsMock).call{value: _bidPrices}("");
        require(success, "Failed to send bid prices to StakerRewards contract");

        // Update StakerRewards checkpoint 
        uint256 totalNewVCs = _vc1 + _vc2 + _vc3 + _vc4;
        stakerRewardsMock.strategyModuleDeployed(address(stratMod), _vc1, totalNewVCs, 4);
    }

    function setStakerRewardsMock(StakerRewardsMock _stakerRewardsMock) external {
        stakerRewardsMock = _stakerRewardsMock;
    }
    
    /* ============== VIEW FUNCTIONS ============== */

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

    /**
     * @notice Returns the number of StrategyModules owned by an address.
     * @param staker The address you want to know the number of Strategy Modules it owns.
     */
    function getStratModNumber(address staker) public view returns (uint256) {
        return stakerToStratMods[staker].length;
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
     * @notice Returns the StrategyModule address by its bound ByzNft ID.
     * @param nftId The ByzNft ID you want to know the attached Strategy Module.
     * @dev Returns address(0) if the nftId is not bound to a Strategy Module (nftId is not a ByzNft)
     */
    function getStratModByNftId(uint256 nftId) public view returns (address) {
        return nftIdToStratMod[nftId];
    }

    function _createDV(uint256 vc1, uint256 vc2, uint256 vc3, uint256 vc4) internal pure returns (StrategyModuleMock.Node[4] memory) {
        StrategyModuleMock.Node[4] memory nodes;

        nodes[0] = StrategyModuleMock.Node({
            vcNumber: vc1
        });
        nodes[1] = StrategyModuleMock.Node({
            vcNumber: vc2
        });
        nodes[2] = StrategyModuleMock.Node({
            vcNumber: vc3
        });
        nodes[3] = StrategyModuleMock.Node({
            vcNumber: vc4
        });

        return nodes; 
    }
}