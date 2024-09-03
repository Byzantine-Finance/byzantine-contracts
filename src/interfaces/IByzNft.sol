// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC721/IERC721Upgradeable.sol";

interface IByzNft is IERC721Upgradeable {

    /**
     * @notice Gets called when a full staker creates a Strategy Vault
     * @param _to The address of the staker who created the Strategy Vault
     * @param _nounce to calculate the tokenId. This is to prevent minting the same tokenId twice.
     * @return The tokenId of the newly minted NFT (calculated from the number of Strategy Vaults already deployed)
     */
    function mint(address _to, uint64 _nounce) external returns (uint256);

}