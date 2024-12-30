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

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 internal constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        // Setup oracle
        oracle = new MockOracle();

        // Deploy the vault directly without a proxy (cannot test upgradability in this file)
        vault = new ERC7535MultiRewardVault();

        // Initialize the vault
        vault.initialize(address(oracle));

        // Setup reward token
        rewardToken1 = new MockERC20("Reward Token", "RWD");

        // Distribute ETH to the accounts
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
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        /* ===================== ALICE DEPOSITS 1 ETH ===================== */
        // Alice deposits 1 ETH into the vault
        vm.prank(alice);
        uint256 aliceShares = vault.deposit{value: oneEth}(oneEth, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("return value aliceShares", aliceShares);
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        
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
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token should be added");
        // Verify the reward token balance
        assertEq(rewardToken1.balanceOf(address(vault)), 2 * oneEth, "Vault should have 2 ETH worth of reward token");

        console.log("~~~After adding 2 reward tokens~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

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
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Bob's deposit
        assertApproxEqAbs(bobShares, expectedBobShares, 2, "Bob should receive approx 0.333e18 shares");
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.balanceOf(alice), oneEth, "Alice's balance should remain unchanged");
        assertEq(address(vault).balance, 2 * oneEth, "Vault should have 2 ETH");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 4 ether, "Total assets should be worth 4 ETH");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqAbs(aliceProportion, 750000000000000000, 2, "Alice should own approx 75% of the vault");
        assertApproxEqAbs(bobProportion, 250000000000000000, 2, "Bob should own approx 25% of the vault");
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
        uint256 aliceAssetsDeposited = vault.mint{value: aliceAssetsRequired}(aliceDesiredShares, alice);
        uint256 aliceShares = vault.balanceOf(alice);

        console.log("~~~After Alice's mint~~~");
        console.log("return value assets", etherToString(aliceAssetsDeposited));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Alice's mint
        assertEq(aliceAssetsDeposited, aliceAssetsRequired, "Alice should deposit 1 ETH");
        assertEq(aliceShares, aliceDesiredShares, "Alice should receive 1e18 shares for first deposit");
        assertEq(vault.balanceOf(alice), aliceDesiredShares, "Alice's balance should be 1e18 shares");
        assertEq(address(vault).balance, 1 ether, "Vault should have 1 ETH");
        
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

        /* ===================== BOB MINTS 1 ETH WORTH OF SHARES ===================== */
        // Get the expeceted amount of shares from a deposit for 1 ETH
        uint256 bobMintAmount = 1 ether;
        uint256 expectedBobShares = vault.previewDeposit(bobMintAmount);
    
        console.log("expectedBobShares", expectedBobShares);
        console.log("assetAmountReturnedFromPreviewMint", etherToString(vault.previewMint(expectedBobShares)));

        // Mint the same amount of shares that we got from the previewDeposit function
        vm.prank(bob);
        uint256 bobAssetsDeposited = vault.mint{value: bobMintAmount}(expectedBobShares, bob);
        uint256 bobShares = vault.balanceOf(bob);

        console.log("~~~After Bob's mint~~~");
        console.log("return value assets", etherToString(bobAssetsDeposited));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Bob's mint
        assertEq(bobAssetsDeposited, bobMintAmount, "Bob should deposit 1 ETH");
        assertApproxEqAbs(bobShares, expectedBobShares, 2, "Bob should receive approx 0.5e18 shares");
        assertEq(vault.balanceOf(alice), 1 ether, "Alice's balance should remain unchanged");
        assertEq(address(vault).balance, 2 ether, "Vault should have 2 ETH");
        assertEq(vault.totalSupply(), aliceShares + bobShares, "Total supply should be sum of Alice and Bob's shares");
        assertEq(vault.totalAssets(), 3 ether, "Total assets should be 3 ETH");

        // Verify proportions of ownership
        uint256 aliceProportion = (vault.balanceOf(alice) * 1e18) / vault.totalSupply();
        uint256 bobProportion = (vault.balanceOf(bob) * 1e18) / vault.totalSupply();
        assertApproxEqAbs(aliceProportion, 666666666666666666, 2, "Alice should own approx 66.66% of the vault");
        assertApproxEqAbs(bobProportion, 333333333333333333, 2, "Bob should own approx 33.33% of the vault");

        /* ===================== ALICE MINTS 1 SHARE ===================== */
        uint256 aliceSharesToMint2 = 1e18;
        uint256 aliceExpectedAssets2 = vault.previewMint(aliceSharesToMint2);

        console.log("aliceSharesToMint2", decimalToString(aliceSharesToMint2));
        console.log("aliceExpectedAssets", etherToString(aliceExpectedAssets2));

        vm.prank(alice);
        uint256 aliceAssetsMinted = vault.mint{value: aliceExpectedAssets2}(aliceSharesToMint2, alice);
        uint256 aliceSharesMinted = vault.balanceOf(alice) - aliceShares; // Deduct previous shares

        console.log("~~~After Alice's 2nd mint~~~");
        console.log("aliceAssetsMinted", etherToString(aliceAssetsMinted));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        // Verify Alice's mint
        assertEq(aliceSharesToMint2, aliceSharesMinted, "Alice should receive 1 share");
        assertEq(aliceAssetsMinted, aliceExpectedAssets2, "Alice should deposit 2 ETH");
        assertApproxEqAbs(vault.totalAssets(), 5 ether, 2, "Vault should have approx 5 ETH");
        assertEq(vault.balanceOf(alice), aliceSharesToMint2 + aliceShares, "Alice's balance should be 2 shares");
    }

    function testWithdraw() public {
        /* ===================== ALICE DEPOSITS 1 ETH AND THEN WITHDRAWS 0.5 ETH ===================== */
        uint256 oneEth = 1 ether;
        uint256 halfEth = 0.5 ether;

        console.log("~~~Initial State~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Alice deposits 1 ETH
        vm.prank(alice);
        vault.deposit{value: oneEth}(oneEth, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        console.log("alice total ETH value", etherToString(vault.getUserTotalValue(alice)));
        //console.log("alice proportion withdrawn", halfEth / vault.getUserTotalValue(alice));
        (, uint256[] memory assetAmountsAlice) = vault.getUsersOwnedAssetsAndRewards(alice);
        console.log("alice amount of ETH owned", etherToString(assetAmountsAlice[0]));

        // Alice withdraws 0.5 ETH
        uint256 aliceSharesBeforeWithdraw = vault.balanceOf(alice);
        uint256 aliceETHBalanceBeforeWithdraw = address(alice).balance;
        
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(halfEth, alice, alice);

        console.log("~~~After Alice's withdrawal~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Alice's withdrawal
        assertEq(vault.balanceOf(alice), aliceSharesBeforeWithdraw - sharesBurned, "Alice's shares should decrease by the amount burned");
        assertEq(address(alice).balance - aliceETHBalanceBeforeWithdraw, halfEth, "Alice should receive 0.5 ETH");
        assertEq(vault.totalAssets(), halfEth, "Vault should have 0.5 ETH remaining");

        /* ===================== BOB DEPOSITS 1 ETH ===================== */
        vm.prank(bob);
        uint256 bobShares = vault.deposit{value: oneEth}(oneEth, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Bob's deposit
        assertEq(vault.balanceOf(bob), bobShares, "Bob's balance should match received shares");
        assertEq(vault.totalAssets(), oneEth + halfEth, "Vault should have 1.5 ETH");

        /* ===================== ADD 1 REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), oneEth);

        console.log("~~~After adding reward token~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify reward token addition
        assertEq(rewardToken1.balanceOf(address(vault)), oneEth, "Vault should have 1 ETH worth of reward token");
        assertEq(vault.totalAssets(), 2.5 ether, "Total assets should be 2.5 ETH");

        /* ===================== BOB WITHDRAWS 1 ETH ===================== */
        uint256 bobSharesBeforeWithdraw = vault.balanceOf(bob);
        uint256 bobETHBalanceBeforeWithdraw = address(bob).balance;
        uint256 bobRWDBalanceBeforeWithdraw = rewardToken1.balanceOf(bob);

        (, uint256[] memory assetAmountsBob) = vault.getUsersOwnedAssetsAndRewards(bob);
        console.log("bob amount of ETH owned", etherToString(assetAmountsBob[0]));
        console.log("bob amount of RWD owned", decimalToString(assetAmountsBob[1]));

        vm.prank(bob);
        uint256 bobSharesBurned = vault.withdraw(oneEth, bob, bob);
        console.log("bob shares burned", decimalToString(bobSharesBurned));

        uint256 bobETHBalanceAfterWithdraw = address(bob).balance;
        uint256 bobRWDBalanceAfterWithdraw = rewardToken1.balanceOf(bob);
        uint256 bobWithdrawnETH = bobETHBalanceAfterWithdraw - bobETHBalanceBeforeWithdraw;
        uint256 bobWithdrawnRWD = bobRWDBalanceAfterWithdraw - bobRWDBalanceBeforeWithdraw;

        console.log("~~~After Bob's withdrawal~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("alice ETH balance", etherToString(address(alice).balance));
        console.log("alice RWD balance", decimalToString(rewardToken1.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));
        console.log("bob ETH balance", etherToString(address(bob).balance));
        console.log("bob RWD balance", decimalToString(rewardToken1.balanceOf(bob)));

        // Verify Bob's withdrawal
        assertEq(vault.balanceOf(bob), bobSharesBeforeWithdraw - bobSharesBurned, "Bob's shares should decrease by the amount burned");
        // There is 1.5 ETH and 1 RWD in the vault.
        // Bob owns 66.66% of the vault.
        // Therefore, Bob owns 1 ETH and 0.666 RWD.
        // Bob is withdrawing 1 ETH, which is 60% of his total ETH value (1 / 1.666666666666666666) ≈ 0.6 or 60% .
        // Therefore, Bob should receive 60% of the remaining ETH and RWD in the vault.
        // Bob should receive 0.6 ETH and 0.4 RWD.
        assertApproxEqAbs(bobWithdrawnETH, 0.6 ether, 2, "Bob should receive approx 0.6 ether");
        assertApproxEqAbs(bobWithdrawnRWD, 0.4 ether, 2, "Bob should receive approx 0.4 RWD");
        assertApproxEqAbs(address(vault).balance, 1.5 ether - bobWithdrawnETH, 2, "Vault should have approx 0.9 ETH remaining");
        assertApproxEqAbs(rewardToken1.balanceOf(address(vault)), 0.6 ether, 2, "Vault should have approx 0.6 RWD remaining");
        assertApproxEqAbs(bobWithdrawnRWD + bobWithdrawnETH, 1 ether, 2, "Bob should have received approx 1 ether");
    }

    function testRedeem() public {
        console.log("~~~Initial State~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        /* ===================== ALICE DEPOSITS 1 ETH AND THEN REDEEMS HALF THEIR SHARES ===================== */
        uint256 aliceDepositAmount = 1 ether;
        vm.prank(alice);
        uint256 aliceShares = vault.deposit{value: aliceDepositAmount}(aliceDepositAmount, alice);

        console.log("~~~After Alice's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        uint256 halfOfAliceShares = aliceShares / 2;
        console.log("halfOfAliceShares", halfOfAliceShares);
        uint256 aliceAssetsToWithdraw = vault.previewRedeem(halfOfAliceShares);
        console.log("aliceAssetsToWithdraw", etherToString(aliceAssetsToWithdraw));

        uint256 aliceETHBalanceBefore = address(alice).balance;
        uint256 vaultETHBalanceBefore = address(vault).balance;
        vm.prank(alice);
        uint256 aliceAssetsWithdrawn = vault.redeem(halfOfAliceShares, alice, alice);

        console.log("~~~After Alice's redeem~~~");
        console.log("aliceAssetsWithdrawn", etherToString(aliceAssetsWithdrawn));
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        uint256 aliceETHBalanceAfter = address(alice).balance;
        console.log("aliceETHBalanceBefore", etherToString(aliceETHBalanceBefore));
        console.log("aliceETHBalanceAfter", etherToString(aliceETHBalanceAfter));
        uint256 aliceWithdrawnETH = aliceETHBalanceAfter - aliceETHBalanceBefore;
        console.log("aliceWithdrawnETH", etherToString(aliceWithdrawnETH));

        uint256 vaultETHBalanceAfter = address(vault).balance;
        console.log("vaultETHBalanceBefore", etherToString(vaultETHBalanceBefore));
        console.log("vaultETHBalanceAfter", etherToString(vaultETHBalanceAfter));
        uint256 vaultWithdrawnETH = vaultETHBalanceBefore - vaultETHBalanceAfter;
        console.log("vaultWithdrawnETH", etherToString(vaultWithdrawnETH));

        uint256 aliceRewardTokenBalance = rewardToken1.balanceOf(alice);
        console.log("aliceRewardTokenBalance", decimalToString(aliceRewardTokenBalance));
        uint256 aliceTotalAssets = vaultWithdrawnETH + aliceRewardTokenBalance;
        console.log("aliceTotalAssets", etherToString(aliceTotalAssets));

        // Verify Alice's redeem
        assertApproxEqAbs(aliceTotalAssets, 0.5 ether, 2, "Alice should receive assets worth approx 0.5 ETH");
        assertApproxEqAbs(vaultWithdrawnETH, 0.5 ether, 2, "Vault should have lost approx 0.5 ETH"); // TO-DO off by 2 wei, instead of 1
        assertApproxEqAbs(aliceWithdrawnETH, 0.5 ether, 2, "Alice should have gained approx 0.5 ETH");
        assertApproxEqAbs(vault.totalAssets(), 0.5 ether, 2, "Vault should have approx 0.5 ETH in total value");
        assertApproxEqAbs(address(vault).balance, 0.5 ether, 2, "Vault should have approx 0.5 ETH");
        assertApproxEqAbs(vault.totalSupply(), 0.5e18, 2, "Vault should have approx 0.5 shares");
        
        /* ===================== BOB DEPOSITS 2 ETH ===================== */
        uint256 bobDepositAmount = 2 ether;
        vm.prank(bob);
        vault.deposit{value: bobDepositAmount}(bobDepositAmount, bob);

        console.log("~~~After Bob's deposit~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        assertApproxEqAbs(vault.totalAssets(), 2.5 ether, 2, "Vault should have approx 2.5 ETH in total value");
        assertApproxEqAbs(address(vault).balance, 2.5 ether, 2, "Vault should have approx 2.5 ETH");
        assertApproxEqAbs(vault.totalSupply(), 2.5e18, 2, "Vault should have approx 2.5 shares");

        /* ===================== ADD 1 REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        console.log("~~~After adding reward token~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        assertApproxEqAbs(vault.totalAssets(), 3.5 ether, 2, "Vault should have approx 3.5 ETH in total value");

        /* ===================== BOB REDEEMS 1 SHARE ===================== */
        uint256 bobSharesToRedeem = 1e18;
        uint256 bobETHBalanceBefore = address(bob).balance;
        console.log("bobETHBalanceBefore", etherToString(bobETHBalanceBefore));
        uint256 vaultETHBalanceBefore2 = address(vault).balance;
        console.log("vaultETHBalanceBefore2", etherToString(vaultETHBalanceBefore2));

        vm.prank(bob);
        vault.redeem(bobSharesToRedeem, bob, bob);
        uint256 bobSharesAfterRedeem = vault.balanceOf(bob);

        console.log("~~~After Bob's redeem~~~");
        console.log("totalAssets", etherToString(vault.totalAssets()));
        console.log("totalSupply", decimalToString(vault.totalSupply()));
        console.log("ETH in vault", etherToString(address(vault).balance));
        console.log("RWD in vault", decimalToString(rewardToken1.balanceOf(address(vault))));
        console.log("alice shares", decimalToString(vault.balanceOf(alice)));
        console.log("bob shares", decimalToString(vault.balanceOf(bob)));

        uint256 bobETHBalanceAfter = address(bob).balance;
        console.log("bobETHBalanceAfter", etherToString(bobETHBalanceAfter));
        uint256 bobWithdrawnETH = bobETHBalanceAfter - bobETHBalanceBefore;
        console.log("bobWithdrawnETH", etherToString(bobWithdrawnETH));

        uint256 vaultETHBalanceAfter2 = address(vault).balance;
        console.log("vaultETHBalanceAfter2", etherToString(vaultETHBalanceAfter2));
        uint256 vaultWithdrawnETH2 = vaultETHBalanceBefore2 - vaultETHBalanceAfter2;
        console.log("vaultWithdrawnETH2", etherToString(vaultWithdrawnETH2));

        // Verify Bob's redeem
        // There is 2.5 ETH and 1 RWD in the vault.
        // Bob holds 2 shares, and the total supply is 2.5 shares.
        // Bob owns 80% of the vault.
        // Therefore, Bob owns 2 ETH and 0.8 RWD.
        // Bob is withdrawing 1 share, which is 50% of his value (1 / 2 = 0.5 or 50%)
        // Therefore, Bob should receive 1 ETH and 0.4 RWD.
        assertEq(bobSharesAfterRedeem, 1e18, "Bob should have 1 shares left");
        assertApproxEqAbs(vaultWithdrawnETH2, 1 ether, 2, "Vault should have lost approx 1 ETH");
        assertApproxEqAbs(bobWithdrawnETH, 1 ether, 2, "Bob should have gained approx 1 ETH");
        assertApproxEqAbs(rewardToken1.balanceOf(address(vault)), 0.6 ether, 2, "Vault should have approx 0.6 RWD");
        assertApproxEqAbs(rewardToken1.balanceOf(bob), 0.4 ether, 2, "Bob should have approx 0.4 RWD");
        assertApproxEqAbs(vault.totalAssets(), 2.1 ether, 2, "Vault should have approx 2.1 ETH in total value");
        assertApproxEqAbs(address(vault).balance, 1.5 ether, 2, "Vault should have approx 1.5 ETH");
        assertApproxEqAbs(vault.totalSupply(), 1.5e18, 2, "Vault should have approx 1.5 shares");
    }

    function testAddRewardToken() public {
        /* ===================== ADD REWARD TOKEN ===================== */
        vault.addRewardToken(address(rewardToken1));
        assertEq(vault.rewardTokens(0), address(rewardToken1), "Reward token should be added");
    }

    function testTotalAssets() public {
        uint256 oneEth = 1 ether;

        // Deposit 1 ETH
        vm.prank(alice);
        vault.deposit{value: oneEth}(oneEth, alice);

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
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 totalETHValue = vault.getUserTotalValue(alice);
        assertEq(totalETHValue, 2 ether, "Alice's total ETH value should be 2 ETH");
    }

    function testGetUsersOwnedAssetsAndRewards() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        (address[] memory tokens, uint256[] memory amounts) = vault.getUsersOwnedAssetsAndRewards(alice);
        assertEq(tokens[0], address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), "First token should be ETH");
        assertEq(amounts[0], 1 ether, "Alice should own 1 ETH");
        assertEq(tokens[1], address(rewardToken1), "Second token should be reward token");
        assertEq(amounts[1], 1 ether, "Alice should own 1 RWD");
    }

    function testPreviewDeposit() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 depositAmount = 1 ether;
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit{value: depositAmount}(depositAmount, bob);

        assertEq(expectedShares, actualShares, "Preview deposit should match actual deposit shares");
    }

    function testPreviewMint() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 mintAmount = 0.5 ether;
        uint256 expectedAssets = vault.previewMint(mintAmount);

        vm.prank(bob);
        uint256 actualAssets = vault.mint{value: expectedAssets}(mintAmount, bob);

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
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

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
        assertApproxEqAbs(expectedShares, actualShares, 2, "Preview withdraw should approximately match actual withdraw shares");
    }

    function testPreviewRedeem() public {
        uint256 initialDeposit = 1 ether;
        vm.prank(alice);
        vault.deposit{value: initialDeposit}(initialDeposit, alice);

        vault.addRewardToken(address(rewardToken1));
        rewardToken1.mint(address(vault), 1 ether);

        uint256 redeemAmount = 0.5 ether;
        uint256 expectedAssets = vault.previewRedeem(redeemAmount);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(redeemAmount, alice, alice);

        // User receives slightly more than expectedAssets because of rounding. Rounding is in favour of the user, as per ERC4626 recommendations.
        assertApproxEqAbs(expectedAssets, actualAssets, 2, "Preview redeem should match actual redeem assets");
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