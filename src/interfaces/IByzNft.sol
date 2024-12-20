// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC721/IERC721Upgradeable.sol";

interface IByzNft is IERC721Upgradeable {

    /**
     * @notice Gets called when a Strategy Vault is created
     * @param _to The address of the Strategy Vault creator
     * @param _nounce To prevent minting the same tokenId twice
     * @return The tokenId of the newly minted ByzNft
     */
    function mint(address _to, uint64 _nounce) external returns (uint256);

}