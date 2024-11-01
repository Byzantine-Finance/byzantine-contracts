// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/vault/ERC4626MultiRewardVault.sol";
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

contract ERC4626MultiRewardVaultTest is Test {
    ProxyAdmin public byzantineProxyAdmin;
    ERC4626MultiRewardVault public vault;
    
    MockOracle oracle;
    MockERC20 rewardToken1;
    MockERC20 asset;

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 internal constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        // Setup oracle
        oracle = new MockOracle();

        // Deploy the vault directly without a proxy (cannot test upgradability in this file)
        vault = new ERC4626MultiRewardVault();

        // Setup asset token. 1 AST = 1 ETH for testing purposes.
        asset = new MockERC20("Asset Token", "AST");

        // Initialize the vault
        vault.initialize(address(oracle), address(asset));

        // Setup reward token
        rewardToken1 = new MockERC20("Reward Token", "RWD");

        // // Distribute ETH to the accounts TODO: Remove this
        // vm.deal(alice, STARTING_BALANCE);
        // vm.deal(bob, STARTING_BALANCE);

        // Distribute asset tokens to the accounts
        asset.mint(alice, STARTING_BALANCE);
        asset.mint(bob, STARTING_BALANCE);

        // Approve the vault to use user's assets
        vm.prank(alice);
        asset.approve(address(vault), STARTING_BALANCE);
        vm.prank(bob);
        asset.approve(address(vault), STARTING_BALANCE);
    }

    function testInitialization() public view {
        // Verify the owner is set correctly
        assertEq(vault.owner(), address(this));

        // Verify the oracle is set correctly
        assertEq(address(vault.oracle()), address(oracle));

        // Verify the asset is set correctly
        assertEq(address(vault.asset()), address(asset));
    }

    function testDeposit() public {
        uint256 oneEth = 1 ether;

        console.log("~~~Initial State~~~");
        console.log("totalAssets", decimalToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        /* ===================== ALICE DEPOSITS 1 AST ===================== */
        // Alice deposits 1 AST into the vault
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(oneEth, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("return value aliceShares", aliceShares);
        console.log("totalAssets", decimalToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        
        // Verify Alice's deposit
        assertEq(aliceShares, oneEth, "Alice should receive 1e18 shares for first deposit");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should be 1e18 shares");
        assertEq(asset.balanceOf(address(vault)), oneEth, "Vault should have 1 AST");

        /* ===================== ADD 2 REWARD TOKENS ===================== */
        // Add reward token to the vault
        vault.addRewardToken(address(rewardToken1));
        // Mint 2 ETH worth of reward tokens to the vault
        rewardToken1.mint(address(vault), 2 * oneEth);
        // Verify the reward token is added
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token should be added");
        // Verify the reward token balance
        assertEq(rewardToken1.balanceOf(address(vault)), 2 * oneEth, "Vault should have 2 AST worth of reward token");

        console.log("~~~After adding 2 reward tokens~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        /* ===================== BOB DEPOSITS 1 AST ===================== */
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

        // Bob deposits 1 AST into the vault
        vm.prank(bob);
        uint256 bobShares = vault.deposit(oneEth, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("return value bobShares", bobShares);
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Bob's deposit
        assertApproxEqRel(bobShares, expectedBobShares, 1e14, "Bob should receive 0.333e18 shares (approx)");
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should remain unchanged");
        assertEq(asset.balanceOf(address(vault)), 2 * oneEth, "Vault should have 2 AST");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 4 ether, "Total assets should be worth 4 ETH");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqRel(aliceProportion, 750000000000000000, 1e14, "Alice should own 75% of the vault");
        assertApproxEqRel(bobProportion, 250000000000000000, 1e14, "Bob should own 25% of the vault");
    }

    function testMint() public {
        /* ===================== ALICE MINTS 1 ETH WORTH OF SHARES ===================== */
        uint256 aliceDesiredShares = 1 ether;
        uint256 aliceAssetsRequired = vault.previewMint(aliceDesiredShares);

        console.log("~~~Initial State~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        console.log("aliceAssetsRequired", aliceAssetsRequired);

        // Alice mints 1 ETH worth of shares
        vm.prank(alice);
        uint256 aliceAssetsDeposited = vault.mint(aliceDesiredShares, alice);
        uint256 aliceShares = vault.balanceOf(alice);

        console.log("~~~After Alice's mint~~~");
        console.log("return value assets", etherToString(aliceAssetsDeposited));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Alice's mint
        assertEq(aliceAssetsDeposited, aliceAssetsRequired, "Alice should deposit 1 AST");
        assertEq(aliceShares, aliceDesiredShares, "Alice should receive 1e18 shares for first deposit");
        assertEq(vault.balanceOf(alice), aliceDesiredShares, "Alice's balance should be 1e18 shares");
        assertEq(asset.balanceOf(address(vault)), 1 ether, "Vault should have 1 AST");
        
        /* ===================== ADD 1 REWARD TOKEN ===================== */
        // Add reward token to the vault
        vault.addRewardToken(address(rewardToken1));
        // Mint 1 ETH worth of reward tokens to the vault
        rewardToken1.mint(address(vault), 1 ether);
        // Verify the reward token is added
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token should be added");
        // Verify the reward token balance
        assertEq(rewardToken1.balanceOf(address(vault)), 1 ether, "Vault should have 1 ETH worth of reward token");
        // Verify the total amount of assets on vault
        assertEq(vault.totalAssets(), 2 ether, "Total assets should be 2 ETH");

        console.log("~~~After adding 1 reward token~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        /* ===================== BOB MINTS 1 AST WORTH OF SHARES ===================== */
        // Get the expeceted amount of shares from a deposit for 1 AST
        uint256 bobMintAmount = 1 ether;
        uint256 expectedBobShares = vault.previewDeposit(bobMintAmount);
    
        console.log("expectedBobShares", expectedBobShares);
        console.log("assetAmountReturnedFromPreviewMint", etherToString(vault.previewMint(expectedBobShares)));

        // Mint the same amount of shares that we got from the previewDeposit function
        vm.prank(bob);
        uint256 bobAssetsDeposited = vault.mint(expectedBobShares, bob);
        uint256 bobShares = vault.balanceOf(bob);

        console.log("~~~After Bob's mint~~~");
        console.log("return value assets", etherToString(bobAssetsDeposited));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Bob's mint
        assertEq(bobAssetsDeposited, bobMintAmount, "Bob should deposit 1 AST");
        assertApproxEqRel(bobShares, expectedBobShares, 1e14, "Bob should receive 0.5e18 shares (approx)");
        assertEq(vault.balanceOf(alice), 1 ether, "Alice's balance should remain unchanged");
        assertEq(asset.balanceOf(address(vault)), 2 ether, "Vault should have 2 AST");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 3 ether, "Total assets should be 3 ETH");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqRel(aliceProportion, 666666666666666666, 1e14, "Alice should own (approx) 66.66% of the vault");
        assertApproxEqRel(bobProportion, 333333333333333333, 1e14, "Bob should own (approx) 33.33% of the vault");

        /* ===================== ALICE MINTS 1 SHARE ===================== */
        uint256 aliceSharesToMint2 = 1e18;
        uint256 aliceExpectedAssets2 = vault.previewMint(aliceSharesToMint2);

        console.log("aliceSharesToMint2", decimalToString(aliceSharesToMint2));
        console.log("aliceExpectedAssets", etherToString(aliceExpectedAssets2));

        vm.prank(alice);
        uint256 aliceAssetsMinted = vault.mint(aliceSharesToMint2, alice);
        uint256 aliceSharesMinted = vault.balanceOf(alice) - aliceShares; // Deduct previous shares

        console.log("~~~After Alice's 2nd mint~~~");
        console.log("aliceAssetsMinted", etherToString(aliceAssetsMinted));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Alice's mint
        assertEq(aliceSharesToMint2, aliceSharesMinted, "Alice should receive 1 share");
        assertEq(aliceAssetsMinted, aliceExpectedAssets2, "Alice should deposit 2 AST");
        assertEq(vault.totalAssets(), 5 ether, "Vault should have 5 ETH");
        assertEq(vault.balanceOf(alice), aliceSharesToMint2 + aliceShares, "Alice's balance should be 2 shares");
    }

    function testWithdraw() public {
        /* ===================== ALICE DEPOSITS 1 AST AND THEN WITHDRAWS 0.5 AST ===================== */
        uint256 oneEth = 1 ether; 
        uint256 halfEth = 0.5 ether;

        console.log("~~~Initial State~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Alice deposits 1 AST
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(oneEth, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        console.log("alice total ETH value", etherToString(vault.getUserTotalValue(alice)));
        //console.log("alice proportion withdrawn", halfEth / vault.getUserTotalValue(alice));
        (, uint256[] memory assetAmountsAlice) = vault.getUsersOwnedAssetsAndRewards(alice);
        console.log("alice amount of AST owned", decimalToString(assetAmountsAlice[0]));

        // Alice withdraws 0.5 AST
        uint256 aliceSharesBeforeWithdraw = vault.balanceOf(alice);
        uint256 aliceASTBalanceBeforeWithdraw = asset.balanceOf(alice);
        
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(halfEth, alice, alice);

        console.log("~~~After Alice's withdrawal~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Alice's withdrawal
        assertEq(vault.balanceOf(alice), aliceSharesBeforeWithdraw - sharesBurned, "Alice's shares should decrease by the amount burned");
        assertEq(asset.balanceOf(alice) - aliceASTBalanceBeforeWithdraw, halfEth, "Alice should receive 0.5 AST");
        assertEq(vault.totalAssets(), halfEth, "Vault should have 0.5 ETH of assets remaining");

        /* ===================== BOB DEPOSITS 1 ETH ===================== */
        vm.prank(bob);
        uint256 bobShares = vault.deposit(oneEth, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Bob's deposit
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.totalAssets(), oneEth + halfEth, "Vault should have 1.5 ETH of value");

        /* ===================== ADD 1 REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), oneEth);

        console.log("~~~After adding reward token~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify reward token addition
        assertEq(rewardToken1.balanceOf(address(vault)), oneEth, "Vault should have 1 ETH worth of reward token");
        assertEq(vault.totalAssets(), 2.5 ether, "Total assets should be 2.5 ETH");

        /* ===================== BOB WITHDRAWS 1 AST ===================== */
        uint256 bobSharesBeforeWithdraw = vault.balanceOf(bob);
        uint256 bobASTBalanceBeforeWithdraw = asset.balanceOf(bob);
        uint256 bobRWDBalanceBeforeWithdraw = rewardToken1.balanceOf(bob);

        (, uint256[] memory assetAmountsBob) = vault.getUsersOwnedAssetsAndRewards(bob);
        console.log("bob amount of AST owned", decimalToString(assetAmountsBob[0]));
        console.log("bob amount of RWD owned", decimalToString(assetAmountsBob[1]));

        vm.prank(bob);
        uint256 bobSharesBurned = vault.withdraw(oneEth, bob, bob);
        console.log("bob shares burned", decimalToString(bobSharesBurned));

        uint256 bobASTBalanceAfterWithdraw = asset.balanceOf(bob);
        uint256 bobRWDBalanceAfterWithdraw = rewardToken1.balanceOf(bob);
        uint256 bobWithdrawnAST = bobASTBalanceAfterWithdraw - bobASTBalanceBeforeWithdraw;
        uint256 bobWithdrawnRWD = bobRWDBalanceAfterWithdraw - bobRWDBalanceBeforeWithdraw;

        console.log("~~~After Bob's withdrawal~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Bob's withdrawal
        assertEq(vault.balanceOf(bob), bobSharesBeforeWithdraw - bobSharesBurned, "Bob's shares should decrease by the amount burned");
        // There is 1.5 AST and 1 RWD in the vault.
        // Bob owns 66.66% of the vault.
        // Therefore, Bob owns 1 AST and 0.666 RWD.
        // Bob is withdrawing 1 AST, which is 60% of his total AST value (1 / 1.666666666666666666) ≈ 0.6 or 60% .
        // Therefore, Bob should receive 60% of the remaining AST and RWD in the vault.
        // Bob should receive 0.6 AST and 0.4 RWD.
        assertApproxEqRel(bobWithdrawnAST, 0.6 ether, 1e14, "Bob should receive approx 0.6 AST");
        assertApproxEqRel(bobWithdrawnRWD, 0.4 ether, 1e14, "Bob should receive approx 0.4 RWD");
        assertApproxEqRel(asset.balanceOf(address(vault)), 1.5 ether - bobWithdrawnAST, 1e14, "Vault should have approx 0.9 AST remaining");
        assertApproxEqRel(rewardToken1.balanceOf(address(vault)), 0.6 ether, 1e14, "Vault should have approx 0.6 RWD remaining");
        assertApproxEqRel(bobWithdrawnRWD + bobWithdrawnAST, 1 ether, 1e14, "Bob should have received approx 1 AST");
    }

    function testRedeem() public {
        console.log("~~~Initial State~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        /* ===================== ALICE DEPOSITS 1 AST AND THEN REDEEMS HALF THEIR SHARES ===================== */
        uint256 aliceDepositAmount = 1 ether;
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDepositAmount, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice AST balance", decimalToString(asset.balanceOf(alice)));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob AST balance", decimalToString(asset.balanceOf(bob)));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        uint256 halfOfAliceShares = aliceShares / 2;
        uint256 aliceAssetsToWithdraw = vault.previewRedeem(halfOfAliceShares);

        console.log("aliceAssetsToWithdraw", etherToString(aliceAssetsToWithdraw));

        uint256 aliceASTBalanceBefore = asset.balanceOf(alice);
        uint256 vaultASTBalanceBefore = asset.balanceOf(address(vault));
        vm.prank(alice);
        uint256 aliceAssetsWithdrawn = vault.redeem(halfOfAliceShares, alice, alice);

        console.log("~~~After Alice's redeem~~~");
        console.log("aliceAssetsWithdrawn", etherToString(aliceAssetsWithdrawn));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        uint256 aliceASTBalanceAfter = asset.balanceOf(alice);
        console.log("aliceASTBalanceBefore", decimalToString(aliceASTBalanceBefore));
        console.log("aliceASTBalanceAfter", decimalToString(aliceASTBalanceAfter));
        uint256 aliceWithdrawnAST = aliceASTBalanceAfter - aliceASTBalanceBefore;
        console.log("aliceWithdrawnAST", decimalToString(aliceWithdrawnAST));

        uint256 vaultASTBalanceAfter = asset.balanceOf(address(vault));
        console.log("vaultASTBalanceBefore", decimalToString(vaultASTBalanceBefore));
        console.log("vaultASTBalanceAfter", decimalToString(vaultASTBalanceAfter));
        uint256 vaultWithdrawnAST = vaultASTBalanceBefore - vaultASTBalanceAfter;
        console.log("vaultWithdrawnAST", decimalToString(vaultWithdrawnAST));

        uint256 aliceRewardTokenBalance = rewardToken1.balanceOf(alice);
        console.log("aliceRewardTokenBalance", decimalToString(aliceRewardTokenBalance));
        uint256 aliceTotalAssets = vaultWithdrawnAST + aliceRewardTokenBalance;
        console.log("aliceTotalAssets", decimalToString(aliceTotalAssets));

        // Verify Alice's redeem
        assertEq(aliceTotalAssets, 0.5 ether, "Alice should receive assets worth 0.5 AST");
        assertEq(vaultWithdrawnAST, 0.5 ether, "Vault should have lost 0.5 AST");
        assertEq(aliceWithdrawnAST, 0.5 ether, "Alice should have gained 0.5 AST");
        assertEq(vault.totalAssets(), 0.5 ether, "Vault should have 0.5 ETH in total value");
        assertEq(asset.balanceOf(address(vault)), 0.5 ether, "Vault should have 0.5 AST");
        assertEq(vault.totalSupply(), 0.5e18, "Vault should have 0.5 shares");
        
        /* ===================== BOB DEPOSITS 2 AST ===================== */
        uint256 bobDepositAmount = 2 ether;
        vm.prank(bob);
        uint256 bobSharesAfterDeposit = vault.deposit(bobDepositAmount, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        assertEq(vault.totalAssets(), 2.5 ether, "Vault should have 2.5 ETH in total value");
        assertEq(asset.balanceOf(address(vault)), 2.5 ether, "Vault should have 2.5 AST");
        assertEq(vault.totalSupply(), 2.5e18, "Vault should have 2.5 shares");

        /* ===================== ADD 1 REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        console.log("~~~After adding reward token~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        assertEq(vault.totalAssets(), 3.5 ether, "Vault should have 3.5 ETH in total value");

        /* ===================== BOB REDEEMS 1 SHARE ===================== */
        uint256 bobSharesToRedeem = 1e18;
        uint256 bobASTBalanceBefore = asset.balanceOf(bob);
        console.log("bobASTBalanceBefore", decimalToString(bobASTBalanceBefore));
        uint256 vaultASTBalanceBefore2 = asset.balanceOf(address(vault));
        console.log("vaultASTBalanceBefore2", decimalToString(vaultASTBalanceBefore2));

        vm.prank(bob);
        uint256 bobAssetsRedeemed = vault.redeem(bobSharesToRedeem, bob, bob);
        uint256 bobSharesAfterRedeem = vault.balanceOf(bob);

        console.log("~~~After Bob's redeem~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("AST in vault", decimalToString(asset.balanceOf(address(vault))));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        uint256 bobASTBalanceAfter = asset.balanceOf(bob);
        console.log("bobASTBalanceAfter", decimalToString(bobASTBalanceAfter));
        uint256 bobWithdrawnAST = bobASTBalanceAfter - bobASTBalanceBefore;
        console.log("bobWithdrawnAST", decimalToString(bobWithdrawnAST));

        uint256 vaultASTBalanceAfter2 = asset.balanceOf(address(vault));
        console.log("vaultASTBalanceAfter2", decimalToString(vaultASTBalanceAfter2));
        uint256 vaultWithdrawnAST2 = vaultASTBalanceBefore2 - vaultASTBalanceAfter2;
        console.log("vaultWithdrawnAST2", decimalToString(vaultWithdrawnAST2));

        // Verify Bob's redeem
        // There is 2.5 AST and 1 RWD in the vault.
        // Bob holds 2 shares, and the total supply is 2.5 shares.
        // Bob owns 80% of the vault.
        // Therefore, Bob owns 2 AST and 0.8 RWD.
        // Bob is withdrawing 1 share, which is 50% of his value (1 / 2 = 0.5 or 50%)
        // Therefore, Bob should receive 1 AST and 0.4 RWD.
        assertEq(bobSharesAfterRedeem, 1e18, "Bob should have 1 shares left");
        assertApproxEqRel(vaultWithdrawnAST2, 1 ether, 1e14, "Vault should have lost 1 AST");
        assertApproxEqRel(bobWithdrawnAST, 1 ether, 1e14, "Bob should have gained 1 AST");
        assertApproxEqRel(rewardToken1.balanceOf(address(vault)), 0.6 ether, 1e14, "Vault should have 0.6 RWD");
        assertApproxEqRel(rewardToken1.balanceOf(bob), 0.4 ether, 1e14, "Bob should have 0.4 RWD");
        assertApproxEqRel(vault.totalAssets(), 2.1 ether, 1e14, "Vault should have 2.1 AST in total value");
        assertApproxEqRel(asset.balanceOf(address(vault)), 1.5 ether, 1e14, "Vault should have 1.5 AST");
        assertApproxEqRel(vault.totalSupply(), 1.5e18, 1e14, "Vault should have 1.5 shares");
    }

    function testAddRewardToken() public {
        /* ===================== ADD REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token should be added");
    }

    function testTotalAssets() public {
        uint256 oneEth = 1 ether;
        uint256 expectedValuePerEth = 1000 * 1e18; // $1000 in 18 decimal precision

        // Deposit 1 AST
        vm.prank(alice);
        vault.deposit(oneEth, alice);

        console.log("totalAssets", decimalToString(vault.totalAssets()));

        // Add Reward Token (RWD) (worth $1000)
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), oneEth); // Mint 1 reward token (assuming 18 decimals)

        // Verify the total assets are calculated correctly  
        // Should be $2000 (1000 from ETH + 1000 from reward token) 
        assertEq(vault.totalAssets(), 2 ether, "Total assets should be 2 ether");
    }

    function testGetUserTotalValue() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 totalETHValue = vault.getUserTotalValue(alice);
        assertEq(totalETHValue, 2 ether, "Alice's total ETH value should be 2 ETH");
    }

    function testGetUsersOwnedAssetsAndRewards() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        (address[] memory tokens, uint256[] memory amounts) = vault.getUsersOwnedAssetsAndRewards(alice);
        assertEq(tokens[0], address(asset), "First token should be the asset token");
        assertEq(amounts[0], 1 ether, "Alice should own 1 AST");
        assertEq(tokens[1], address(rewardToken1), "Second token should be reward token");
        assertEq(amounts[1], 1 ether, "Alice should own 1 RWD");
    }

    function testPreviewDeposit() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 depositAmount = 1 ether;
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);

        assertEq(expectedShares, actualShares, "Preview deposit should match actual deposit shares");
    }

    function testPreviewMint() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 mintAmount = 0.5 ether;
        uint256 expectedAssets = vault.previewMint(mintAmount);

        vm.prank(bob);
        uint256 actualAssets = vault.mint(mintAmount, bob);

        assertEq(expectedAssets, actualAssets, "Preview mint should match actual mint assets");
    }

    function testPreviewWithdraw() public {
        console.log("~~~~~testPreviewWithdraw~~~~~");
        // Alice deposits 1 ETH
            // totalAssets = 1 ETH
            // totalETH = 1
            // totalRWD = 0
            // totalSupply = 1 share
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Add reward token (worth 1 ETH)
            // totalAssets = 2 ETH
            // totalETH = 1
            // totalRWD = 1
            // totalSupply = 1 share
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        // Alice withdraws 0.5 ETH of value
            // 0.5 ETH is 1/4 of the total value owned by Alice
            // Therefore, expected shares to burn = 1/4 * totalSupply = 1/4 * 1 share = 0.25 shares
            // Alice should receive 1/4 of their ETH and 1/4 of their RWD
            // Therefore, Alice should receive 0.25 ETH and 0.25 RWD
            // totalAssets = 1.5 ETH
            // totalETH = 0.75
            // totalRWD = 0.75
            // totalSupply = 0.75 shares
        uint256 withdrawAmount = 0.5 ether;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        console.log("Expected shares: %s", expectedShares);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);
        console.log("Actual shares: %s", actualShares);
        assertApproxEqRel(expectedShares, actualShares, 1e14, "Preview withdraw should approximately match actual withdraw shares");
    }

    function testPreviewRedeem() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 redeemAmount = 0.5 ether;
        uint256 expectedAssets = vault.previewRedeem(redeemAmount);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(redeemAmount, alice, alice);

        // User receives slightly more than expectedAssets because of rounding. Rounding is in favour of the user, as per ERC4626 recommendations.
        assertApproxEqRel(expectedAssets, actualAssets, 1e14, "Preview redeem should match actual redeem assets");
    }

    function etherToString(uint256 weiAmount) internal pure returns (string memory) {
        uint256 etherToValue = weiAmount / 1e18;
        uint256 fractional = (weiAmount % 1e18) / 1e15;  // Get 3 decimal places
        return string(abi.encodePacked(
            vm.toString(etherToValue), 
            ".", 
            fractional < 10 ? "00" : (fractional < 100 ? "0" : ""),
            vm.toString(fractional),
            " ETH"
        ));
    }

    function decimalToString(uint256 weiAmount) internal pure returns (string memory) {
        uint256 wholeNumber = weiAmount / 1e18;
        uint256 fractional = (weiAmount % 1e18) / 1e15;  // Get 3 decimal places
        return string(abi.encodePacked(
            vm.toString(wholeNumber), 
            ".", 
            fractional < 10 ? "00" : (fractional < 100 ? "0" : ""),
            vm.toString(fractional)
        ));
    }

}