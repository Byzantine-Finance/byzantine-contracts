// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract ByzantineVault is ERC4626 {

    error NotETHVault();

    constructor(IERC20 asset, string memory sharesName, string memory sharesSymbol) 
        ERC4626(IERC20Metadata(address(asset)))
        ERC20(sharesName, sharesSymbol)
    {
        sharesName = string(abi.encodePacked("Byzantine ", sharesSymbol));
        sharesSymbol = string(abi.encodePacked("byz", sharesSymbol));
    }

    receive() external payable {
        if (address(asset()) != address(0)) revert NotETHVault();
        uint256 shares = previewDeposit(msg.value);
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, msg.sender, msg.value, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        if (address(asset()) == address(0)) {
            // ETH withdrawal
            uint256 shares = previewWithdraw(assets);
            _withdraw(_msgSender(), receiver, owner, assets, shares);
            (bool success, ) = payable(receiver).call{value: assets}("");
            require(success, "ETH transfer failed");
            return shares;
        } else {
            // ERC20 withdrawal
            return super.withdraw(assets, receiver, owner);
        }
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        if (address(asset()) == address(0)) {
            // ETH redemption
            uint256 assets = previewRedeem(shares);
            _withdraw(_msgSender(), receiver, owner, assets, shares);
            (bool success, ) = payable(receiver).call{value: assets}("");
            require(success, "ETH transfer failed");
            return assets;
        } else {
            // ERC20 redemption
            return super.redeem(shares, receiver, owner);
        }
    }
}