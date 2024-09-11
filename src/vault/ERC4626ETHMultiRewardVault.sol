// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";

contract ERC4626MultiRewardVault is Initializable, ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable[] public rewardTokens;
    mapping(IERC20Upgradeable => uint8) public rewardTokenDecimals;

    function initialize() public initializer {
        __ERC4626_init(IERC20MetadataUpgradeable(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        __ERC20_init("ETH Byzantine StrategyVault Token", "byzETH");
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    receive() external payable {
        // TODO: emit an event to notify
    }

    function addRewardToken(IERC20Upgradeable _rewardToken) external onlyOwner {
        rewardTokens.push(_rewardToken);
        uint8 decimals = IERC20MetadataUpgradeable(address(_rewardToken)).decimals();
        rewardTokenDecimals[_rewardToken] = decimals;
    }

    function deposit(uint256 assets, address receiver) public virtual override payable nonReentrant returns (uint256) {
        require(msg.value == assets, "Incorrect ETH amount");
        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        uint256 shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        _distributeRewards(receiver, shares);
        payable(receiver).transfer(assets);
        return shares;
    }

    function _distributeRewards(address receiver, uint256 sharesBurned) internal {
        uint256 totalShares = totalSupply();
        for (uint i = 0; i < rewardTokens.length; i++) {
            IERC20Upgradeable rewardToken = rewardTokens[i];
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            uint256 rewardAmount = (rewardBalance * sharesBurned) / totalShares;
            if (rewardAmount > 0) {
                rewardToken.safeTransfer(receiver, rewardAmount);
            }
        }
    }

    function totalAssets() public view override returns (uint256) {
        uint256 totalValue = super.totalAssets();
        // TODO: Integrate with oracle to determine total value of all tokens in vault
        return totalValue;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0)
            ? assets
            : (assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares 
            :(shares * totalAssets()) / supply;
    }
}
