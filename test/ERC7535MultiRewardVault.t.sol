
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
<<<<<<< HEAD
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/vault/ERC7535MultiRewardVault.sol";
import "./mocks/MockOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
 
=======
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/vault/ERC7535MultiRewardVault.sol";
import "../src/interfaces/IOracle.sol";
import "./mocks/EmptyContract.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
 
contract MockOracle is IOracle {
    function getPrice(address, address) external pure override returns (uint256) {
        // Return $1000 USD with 18 decimal places
        return 1000 * 1e18;
    }
}

>>>>>>> 351b0e3 (test: various edits for testing file setup)
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

    function testInitialization() public view {
        // Verify the owner is set correctly
        assertEq(vault.owner(), address(this));

        // Verify the oracle is set correctly
        assertEq(address(vault.oracle()), address(oracle));
    }

    function testDeposit() public {
        uint256 oneEth = 1 ether;

        /* ===================== ALICE DEPOSITS 1 ETH ===================== */
        // Alice deposits 1 ETH into the vault
        vm.prank(alice);
        uint256 aliceShares = vault.deposit{value: oneEth}(oneEth, alice);
        
        // Verify Alice's deposit
        assertEq(aliceShares, oneEth, "Alice should receive 1e18 shares for first deposit");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should be 1e18 shares");
        assertEq(address(vault).balance, oneEth, "Vault should have 1 ETH");

        /* ===================== ADD 2 REWARD TOKENS ===================== */
        // Add reward token to the vault
        vault.addRewardToken(address(rewardToken1));
        // Mint 2 ETH worth of reward tokens to the vault
        rewardToken1.mint(address(vault), 2 * oneEth);

        /* ===================== BOB DEPOSITS 1 ETH ===================== */
        // Bob deposits 1 ETH into the vault
        vm.prank(bob);
        uint256 bobShares = vault.deposit{value: oneEth}(oneEth, bob);

        // Calculate expected shares for Bob (should be 1/4 of total supply after his deposit)
        uint256 expectedBobShares = oneEth / 4; // 0.25e18
        
        // Verify Bob's deposit
        assertApproxEqRel(bobShares, expectedBobShares, 1e14, "Bob should receive 0.25e18 shares");
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should remain unchanged");
        assertEq(address(vault).balance, 2 * oneEth, "Vault should have 2 ETH");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 4000 * 1e18, "Total assets should be $4000");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqRel(aliceProportion, 800000000000000000, 1e14, "Alice should own 80% of the vault");
        assertApproxEqRel(bobProportion, 200000000000000000, 1e14, "Bob should own 20% of the vault");
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
        //vault.addRewardToken(rewardToken1, address(0x123));        
    }

    function testTotalAssets() public {
        uint256 oneEth = 1 ether;
        uint256 expectedValuePerEth = 1000 * 1e18; // $1000 in 18 decimal precision

        // Deposit 1 ETH
        vm.prank(alice);
        vault.deposit{value: oneEth}(oneEth, alice);

        // Add Reward Token 1 (RT1) (worth $1000)
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), oneEth); // Mint 1 reward token (assuming 18 decimals)

        // Verify the total assets are calculated correctly
        uint256 expectedTotalAssets = 2 * expectedValuePerEth; // $2000 (1000 from ETH + 1000 from reward token)
        uint256 actualTotalAssets = vault.totalAssets();        
        assertEq(actualTotalAssets, expectedTotalAssets, "Total assets should be $2000");
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