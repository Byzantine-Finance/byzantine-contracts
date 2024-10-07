// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/vault/ERC7535MultiRewardVault.sol";
import "../src/interfaces/IOracle.sol";
import "./mocks/EmptyContract.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
 
contract MockOracle is IOracle {
    function getPrice(address, address) external pure returns (uint256) {
        // Mock implementation
        return 1000 * 1e18; // $1000 with 18 decimals
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract ERC7535MultiRewardVaultTest is Test {
    ProxyAdmin public byzantineProxyAdmin;
    ERC7535MultiRewardVault public vault;
    
    MockOracle oracle;
    MockERC20 rewardToken1;
    MockERC20 rewardToken2;

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 internal constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        oracle = new MockOracle();

        // Deploy the vault directly without a proxy (cannot test upgradability in this file)
        vault = new ERC7535MultiRewardVault();

        // Initialize the vault
        vault.initialize(address(oracle));

        // Setup reward tokens
        rewardToken1 = new MockERC20("Reward Token 1", "RT1");
        rewardToken2 = new MockERC20("Reward Token 2", "RT2");

        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);
    }

    function testInitialization() public {
        // Verify the owner is set correctly
        assertEq(vault.owner(), address(this));

        // Verify the oracle is set correctly
        assertEq(address(vault.oracle()), address(oracle));
    }

    function testDeposit() public {
        /* ===================== ALICE DEPOSITS 1 ETH ===================== */
        vm.prank(alice);
        uint256 shares = vault.deposit{value: 1 ether}(1 ether, alice);
        
        // Verify the correct amount of shares are minted
        assertEq(shares, 1 ether);

        // Verify the shares are sent to alice 
        assertEq(vault.balanceOf(alice), 1 ether);

        // Verify the vault contract receives the correct amount of ETH
        assertEq(address(vault).balance, 1 ether);

        /* ===================== ALICE DEPOSITS 1 ETH WHILE REWARD TOKENS ARE ADDED ===================== */
        // Add reward tokens that are worth 1:1 ratio with ETH
        vault.addRewardToken(IERC20Upgradeable(address(rewardToken1)), address(0x123));
        rewardToken1.mint(address(vault), 1 ether);

        // Deposit 1 ETH
        vm.prank(alice);
        vault.deposit{value: 1 ether}(1 ether, alice);

        // Verify the correct amount of shares are minted

        
    }

    function testMint() public {
        /* ===================== BOB MINTS 1 ETH WORTH OF SHARES ===================== */
        // vm.prank(bob);
        // uint256 assets = vault.mint{value: 1 ether}(1 ether, bob);

        // Verify the correct amount of ETH was deposited

        // Verify the correct amount of shares are minted

        // Verify the shares are sent to bob

        // Verify the vault contract receives the ETH
    }

    function testWithdraw() public {
        /* ===================== ALICE DEPOSITS AND THEN WITHDRAWS HALF ===================== */

    }

    function testRedeem() public {
        /* ===================== BOB DEPOSITS AND THEN REDEEMS HALF ===================== */
    }

    function testAddRewardToken() public {
        /* ===================== ADD REWARD TOKEN 1 ===================== */
        vault.addRewardToken(IERC20Upgradeable(address(rewardToken1)), address(0x123));
        (address priceFeed, uint8 decimals) = vault.rewardInfo(IERC20Upgradeable(address(rewardToken1)));
        
        // Verify the price feed is set correctly
        assertEq(priceFeed, address(0x123));

        // Verify the decimals are set correctly
        assertEq(decimals, 18);
    }

    function testUpdateRewardPriceFeed() public {
        /* ===================== UPDATE REWARD TOKEN 1 PRICE FEED ===================== */
        vault.addRewardToken(IERC20Upgradeable(address(rewardToken1)), address(0x123));
        vault.updateRewardPriceFeed(IERC20Upgradeable(address(rewardToken1)), address(0x456));
        (address priceFeed,) = vault.rewardInfo(IERC20Upgradeable(address(rewardToken1)));

        // Verify the price feed is updated correctly
        assertEq(priceFeed, address(0x456));
    }

    function testTotalAssets() public {
        /* ===================== CALCULATE TOTAL ASSETS ===================== */
        uint256 oneEth = 1 ether;
        uint256 expectedValuePerAsset = 1000 * 1e18; // $1000 in 18 decimal precision

        // Deposit 1 ETH
        vm.prank(alice);
        vault.deposit{value: oneEth}(oneEth, alice);

        // Add Reward Token 1 (RT1)
        vault.addRewardToken(IERC20Upgradeable(address(rewardToken1)), address(0x123));
        rewardToken1.mint(address(vault), oneEth); // Mint 1 reward token (assuming 18 decimals)

        // Verify the total assets are calculated correctly
        uint256 expectedTotalAssets = 2 * expectedValuePerAsset; // $2000 (1000 from ETH + 1000 from reward token)
        uint256 actualTotalAssets = vault.totalAssets();        
        assertEq(actualTotalAssets, expectedTotalAssets);
    }

    function testRewardDistribution() public {
        // TODO: Implement test for reward distribution
        /* ===================== DISTRIBUTE REWARDS ===================== */
        // 1. Deposit some ETH from multiple users
        // 2. Add reward tokens
        // 3. Mint some reward tokens to the vault
        // 4. Withdraw or redeem for one user
        // 5. Check if rewards are correctly distributed proportionally to the shares
    }

}