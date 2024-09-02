// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/math/MathUpgradeable.sol";

contract ByzantineVault is Initializable, ERC4626Upgradeable {

    error NotETHVault();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20Upgradeable asset, string memory sharesName, string memory sharesSymbol) public initializer {
        __ERC4626_init(IERC20MetadataUpgradeable(address(asset)));
        __ERC20_init(sharesName, sharesSymbol);
        
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

    uint256[50] private __gap;
}