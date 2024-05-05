// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IByzNft.sol";

contract ByzNft is IByzNft, ERC721, Ownable {

    constructor() ERC721("Byzantine NFT", "byzNFT") {}

    /**
     * @notice Gets called when a full staker creates a Strategy Module
     * @param _to The address of the staker who created the Strategy Module
     * @param _nounce to calculate the tokenId. This is to prevent minting the same tokenId twice.
     * @return The tokenId of the newly minted NFT (calculated from the number of Strategy Modules already own by the staker and the staker's address)
     */
    function mint(address _to, uint256 _nounce) external onlyOwner returns (uint256) {
        uint256 tokenId = uint256(keccak256(abi.encodePacked(_to, _nounce)));
        _safeMint(_to, tokenId);
        return tokenId;
    }

}