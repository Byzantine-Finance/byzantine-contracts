// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/vault/ERC7535MultiRewardVault.sol";
import "./mocks/MockOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

        console.log("~~~Initial State~~~");
        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());
        console.log("alice shares", vault.balanceOf(alice));
        console.log("bob shares", vault.balanceOf(bob));

        /* ===================== ALICE DEPOSITS 1 ETH ===================== */
        // Alice deposits 1 ETH into the vault
        vm.prank(alice);
        uint256 aliceShares = vault.deposit{value: oneEth}(oneEth, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("return value aliceShares", aliceShares);
        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());
        console.log("alice shares", vault.balanceOf(alice));
        console.log("bob shares", vault.balanceOf(bob));
        
        // Verify Alice's deposit
        assertEq(aliceShares, oneEth, "Alice should receive 1e18 shares for first deposit");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should be 1e18 shares");
        assertEq(address(vault).balance, oneEth, "Vault should have 1 ETH");

        /* ===================== ADD 2 REWARD TOKENS ===================== */
        // Add reward token to the vault
        vault.addRewardToken(address(rewardToken1));
        // Mint 2 ETH worth of reward tokens to the vault
        rewardToken1.mint(address(vault), 2 * oneEth);
        // Verify the reward token is added
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token 1 should be added");
        // Verify the reward token balance
        assertEq(rewardToken1.balanceOf(address(vault)), 2 * oneEth, "Vault should have 2 ETH worth of reward token 1");

        console.log("~~~After adding 2 reward tokens~~~");
        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());
        console.log("alice shares", vault.balanceOf(alice));
        console.log("bob shares", vault.balanceOf(bob));

        /* ===================== BOB DEPOSITS 1 ETH ===================== */
        /**
         * Calculate expected shares for Bob (should be 1/4 of total supply after his deposit)
         * shares = (assets * totalSupply) / totalAssets
         *  - shares is the number of shares the user will receive
         *  - assets is the value of underlying assets being deposited
         *  - totalSupply is the total number of existing shares before the deposit
         *  - totalAssets is the total value of underlying assets held by the vault before the deposit
         * expectedBobShares = (1 * 1) / 3 = 0.333333333333333333
         */
        uint256 expectedBobShares = vault.previewDeposit(oneEth);

        console.log("expectedBobShares", expectedBobShares);

        // Bob deposits 1 ETH into the vault
        vm.prank(bob);
        uint256 bobShares = vault.deposit{value: oneEth}(oneEth, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("return value bobShares", bobShares);
        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());
        console.log("alice shares", vault.balanceOf(alice));
        console.log("bob shares", vault.balanceOf(bob));
        
        // Verify Bob's deposit
        assertApproxEqRel(bobShares, expectedBobShares, 1e14, "Bob should receive 0.333e18 shares (approx)");
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should remain unchanged");
        assertEq(address(vault).balance, 2 * oneEth, "Vault should have 2 ETH");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 4000 * 1e18, "Total assets should be $4000");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqRel(aliceProportion, 750000000000000000, 1e14, "Alice should own 75% of the vault");
        assertApproxEqRel(bobProportion, 250000000000000000, 1e14, "Bob should own 25% of the vault");
    }

    // function testMint() public {
    //     /* ===================== ALICE MINTS 1 ETH WORTH OF SHARES ===================== */
    //     uint256 aliceMintAmount = 1 ether;

    //     console.log("~~~Initial State~~~");
    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    //     console.log("alice shares", vault.balanceOf(alice));
    //     console.log("bob shares", vault.balanceOf(bob));

    //     // Alice mints 1 ETH worth of shares
    //     vm.prank(alice);
    //     uint256 aliceAssetsDeposited = vault.mint{value: aliceMintAmount}(aliceMintAmount, alice);
    //     uint256 aliceShares = vault.balanceOf(alice);

    //     console.log("~~~After Alice's mint~~~");
    //     console.log("return value assets", aliceAssetsDeposited);
    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    //     console.log("alice shares", vault.balanceOf(alice));
    //     console.log("bob shares", vault.balanceOf(bob));

    //     // Verify Alice's mint
    //     assertEq(aliceAssetsDeposited, aliceMintAmount, "Alice should deposit 1 ETH");
    //     assertEq(aliceShares, 1 ether, "Alice should receive 1e18 shares for first deposit");
    //     assertEq(vault.balanceOf(alice), 1 ether, "Alice's balance should be 1e18 shares");
    //     assertEq(address(vault).balance, 1 ether, "Vault should have 1 ETH");
        
    //     /* ===================== ADD 1 REWARD TOKEN ===================== */
    //     // Add reward token to the vault
    //     vault.addRewardToken(address(rewardToken1));
    //     // Mint 1 ETH worth of reward tokens to the vault
    //     rewardToken1.mint(address(vault), 1 ether);
    //     // Verify the reward token is added
    //     assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token 1 should be added");
    //     // Verify the reward token balance
    //     assertEq(rewardToken1.balanceOf(address(vault)), 1 ether, "Vault should have 1 ETH worth of reward token 1");

    //     console.log("~~~After adding 1 reward token~~~");
    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    //     console.log("alice shares", vault.balanceOf(alice));
    //     console.log("bob shares", vault.balanceOf(bob));

    //     /* ===================== BOB MINTS 1 ETH WORTH OF SHARES ===================== */
    //     // Get the expeceted amount of shares from a deposit for 1 ETH
    //     uint256 bobMintAmount = 1 ether;
    //     uint256 expectedBobShares = vault.previewDeposit(bobMintAmount);
    
    //     console.log("expectedBobShares", expectedBobShares);
    //     console.log("assetAmountReturnedFromPreviewMint", vault.previewMint(expectedBobShares));

    //     // Mint the same amount of shares that we got from the previewDeposit function
    //     vm.prank(bob);
    //     uint256 bobAssetsDeposited = vault.mint{value: bobMintAmount}(expectedBobShares, bob);
    //     uint256 bobShares = vault.balanceOf(bob);

    //     console.log("~~~After Bob's mint~~~");
    //     console.log("return value assets", bobAssetsDeposited);
    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    //     console.log("alice shares", vault.balanceOf(alice));
    //     console.log("bob shares", vault.balanceOf(bob));

    //     // Verify Bob's mint
    //     assertEq(bobAssetsDeposited, bobMintAmount, "Bob should deposit 1 ETH");
    //     assertApproxEqRel(bobShares, expectedBobShares, 1e14, "Bob should receive 0.5e18 shares (approx)");
    //     assertEq(vault.balanceOf(alice), 1 ether, "Alice's balance should remain unchanged");
    //     assertEq(address(vault).balance, 2 ether, "Vault should have 2 ETH");
    //     assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
    //     assertEq(vault.totalAssets(), 3000 * 1e18, "Total assets should be $3000");

    //     // Verify proportions of ownership
    //     uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
    //     uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
    //     assertApproxEqRel(aliceProportion, 666666666666666666, 1e14, "Alice should own (approx) 66.66% of the vault");
    //     assertApproxEqRel(bobProportion, 333333333333333333, 1e14, "Bob should own (approx) 33.33% of the vault");

    //     /* ===================== ALICE MINTS 1 SHARE ===================== */
    //     uint256 aliceSharesToMint = vault.balanceOf(bob) / 2; // Half of Bob's shares
    //     uint256 aliceEthRequired = vault.previewMint(aliceSharesToMint);

    //     console.log("aliceSharesToMint", aliceSharesToMint);
    //     console.log("aliceEthRequired", aliceEthRequired);

    //     vm.prank(alice);
    //     uint256 aliceAssetsMinted = vault.mint{value: aliceEthRequired}(aliceSharesToMint, alice);

    //     console.log("~~~After Alice's 2nd mint~~~");
    //     console.log("aliceAssetsMinted", aliceAssetsMinted);
    //     console.log("totalAssets", vault.totalAssets());
    //     console.log("totalSupply", vault.totalSupply());
    //     console.log("alice shares", vault.balanceOf(alice));
    //     console.log("bob shares", vault.balanceOf(bob));

    //     // Verify Alice's mint
        
        
    // }

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
        // Should be $2000 (1000 from ETH + 1000 from reward token) 
        assertEq(vault.totalAssets(), 2 ether, "Total assets should be 2 ether");
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