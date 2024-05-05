// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IByzNft is IERC721 {

    /**
     * @notice Gets called when a full staker creates a Strategy Module
     * @param _to The address of the staker who created the Strategy Module
     * @param _nounce to calculate the tokenId. This is to prevent minting the same tokenId twice.
     * @return The tokenId of the newly minted NFT (calculated from the number of Strategy Modules already own by the staker and the staker's address)
     */
    function mint(address _to, uint256 _nounce) external returns (uint256);

}