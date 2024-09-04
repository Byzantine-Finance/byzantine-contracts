// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../interfaces/IByzNft.sol";
import "../interfaces/IStrategyVaultManager.sol";    

contract ByzNft is
    Initializable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IByzNft
{

    // Unsafe to have a constructor in the context of a proxy contract
    //constructor() ERC721("Byzantine NFT", "byzNFT") {}

    /**
     * @dev Initializes name, symbol and owner of the ERC721 collection.
     * @dev owner is the StrategyVaultManager proxy contract
     */
    function initialize(
        IStrategyVaultManager _strategyVaultManager
    ) external initializer {
        __ERC721_init("Byzantine NFT", "byzNFT");
        _transferOwnership(address(_strategyVaultManager));
    }

    /**
     * @notice Gets called when a full staker creates a Strategy Vault
     * @param _to The address of the staker who created the Strategy Vault
     * @param _nounce to calculate the tokenId. This is to prevent minting the same tokenId twice.
     * @return The tokenId of the newly minted NFT (calculated from the number of Strategy Vaults already deployed)
     */
    function mint(address _to, uint64 _nounce) external onlyOwner returns (uint256) {
        uint256 tokenId = uint256(keccak256(abi.encode(_nounce)));
        _safeMint(_to, tokenId);
        return tokenId;
    }

    /**
     * @dev Overrides `_beforeTokenTransfer` to restrict token transfers.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override view {
        revert("ByzNft is non-transferable");
    }

}