// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldVault} from "../../src/vault/YieldVault.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

contract YieldVaultTest is Test {
    YieldVault internal vault;
    MockERC20 internal token;

    address internal owner;
    address internal alice;
    address internal bob;

    uint256 internal constant INITIAL_BALANCE = 1_000_000e18;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new MockERC20("Stablecoin", "USDC");
        vault = new YieldVault(IERC20(address(token)), owner);

        // Fund all three actors.
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        token.mint(owner, INITIAL_BALANCE);

        // Pre-approve the vault from all actors.
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        vm.prank(owner);
        token.approve(address(vault), type(uint256).max);
    }

    // ─── 1. Initial state ─────────────────────────────────────────────────────

    function test_InitialState() public view {
        assertEq(vault.totalAssets(), 0, "totalAssets == 0");
        assertEq(vault.totalSupply(), 0, "totalSupply == 0");
        assertEq(vault.totalHarvested(), 0, "totalHarvested == 0");
        assertEq(vault.asset(), address(token), "asset is the token");
    }

    // ─── 2. First deposit mints 1:1 shares ───────────────────────────────────

    function test_Deposit_MintsShares1to1FirstDepositor() public {
        uint256 depositAmount = 1_000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, depositAmount, "first depositor gets 1:1 shares");
        assertEq(vault.balanceOf(alice), depositAmount, "alice's share balance");
        assertEq(vault.totalAssets(), depositAmount, "total assets after deposit");
    }

    // ─── 3. Deposit emits the custom event ───────────────────────────────────

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 500e18;
        uint256 expectedShares = depositAmount; // 1:1 on first deposit

        vm.expectEmit(true, true, false, true);
        emit YieldVault.DepositWithReceipt(alice, alice, depositAmount, expectedShares);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);
    }

    // ─── 4. Deposit reverts on zero assets ───────────────────────────────────

    function test_Deposit_RevertWhen_ZeroAssets() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    // ─── 5. Mint pulls the correct asset amount ───────────────────────────────

    function test_Mint_PullsCorrectAssetAmount() public {
        uint256 sharesToMint = 1_000e18;
        uint256 expectedAssets = vault.previewMint(sharesToMint); // 1:1 on first deposit

        uint256 aliceTokenBefore = token.balanceOf(alice);

        vm.prank(alice);
        uint256 actualAssets = vault.mint(sharesToMint, alice);

        assertEq(actualAssets, expectedAssets, "assets pulled equals previewMint");
        assertEq(token.balanceOf(alice), aliceTokenBefore - actualAssets, "alice token balance decreased");
        assertEq(vault.balanceOf(alice), sharesToMint, "alice received requested shares");
    }

    // ─── 6. Withdraw burns shares and transfers assets ────────────────────────

    function test_Withdraw_BurnsShares_TransfersAssets() public {
        uint256 depositAmount = 1_000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 tokenBefore = token.balanceOf(alice);
        uint256 withdrawAssets = 400e18;

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAssets, alice, alice);

        assertEq(vault.balanceOf(alice), sharesBefore - sharesBurned, "shares burned");
        assertEq(token.balanceOf(alice), tokenBefore + withdrawAssets, "assets received");
        assertGt(sharesBurned, 0, "shares burned > 0");
    }

    // ─── 7. Redeem burns the correct number of shares ─────────────────────────

    function test_Redeem_BurnsCorrectAmount() public {
        uint256 depositAmount = 2_000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = vault.balanceOf(alice) / 2;
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        uint256 tokenBefore = token.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(assetsOut, expectedAssets, "redeemed assets equal preview");
        assertEq(token.balanceOf(alice), tokenBefore + assetsOut, "alice received assets");
        assertEq(vault.balanceOf(alice), depositAmount - sharesToRedeem, "alice shares decreased");
    }

    // ─── 8. Harvest increases totalAssets ────────────────────────────────────

    function test_Harvest_IncreasesTotalAssets() public {
        uint256 depositAmount = 1_000e18;
        uint256 harvestAmount = 500e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assertEq(vault.totalAssets(), depositAmount, "before harvest");

        vm.prank(owner);
        vault.harvest(harvestAmount);

        assertEq(vault.totalAssets(), depositAmount + harvestAmount, "after harvest");
        assertEq(vault.totalHarvested(), harvestAmount, "totalHarvested updated");
    }

    // ─── 9. Harvest raises the share price (convertToAssets > deposit) ────────

    function test_Harvest_SharePriceIncreases() public {
        uint256 depositAmount = 1_000e18;
        uint256 harvestAmount = 400e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(aliceShares);

        vm.prank(owner);
        vault.harvest(harvestAmount);

        uint256 assetsAfter = vault.convertToAssets(aliceShares);

        assertGt(assetsAfter, assetsBefore, "share price must increase after harvest");
        assertGt(assetsAfter, depositAmount, "alice's shares worth more than deposited");
    }

    // ─── 10. Harvest is restricted to the owner ───────────────────────────────

    function test_Harvest_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vault.harvest(100e18);
    }

    // ─── 11. Two users get proportional yield distribution ────────────────────

    function test_TwoUsers_FairShareDistribution() public {
        // Alice deposits 1_000, bob deposits 2_000 (bob gets 2x the shares).
        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        vm.prank(bob);
        vault.deposit(2_000e18, bob);

        // Owner injects 300 yield — alice should gain ~100, bob should gain ~200.
        vm.prank(owner);
        vault.harvest(300e18);

        // Pre-compute shares before pranking (vm.prank is consumed by view calls).
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        // Alice redeems all shares.
        vm.prank(alice);
        uint256 aliceOut = vault.redeem(aliceShares, alice, alice);

        // Bob redeems all shares.
        vm.prank(bob);
        uint256 bobOut = vault.redeem(bobShares, bob, bob);

        assertGt(aliceOut, 1_000e18, "alice profits from harvest");
        assertGt(bobOut, 2_000e18, "bob profits from harvest");

        // Bob should have gained approximately 2x alice's gain (within 0.1%).
        uint256 aliceGain = aliceOut - 1_000e18;
        uint256 bobGain = bobOut - 2_000e18;
        assertApproxEqRel(bobGain, 2 * aliceGain, 0.001e18, "bob's gain is 2x alice's gain");
    }

    // ─── 12. Full lifecycle: deposit → harvest → withdraw ─────────────────────

    function test_FullCycle() public {
        uint256 depositAmount = 5_000e18;
        uint256 harvestAmount = 1_000e18;

        // 1. Alice deposits.
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        assertGt(aliceShares, 0);

        // 2. Owner harvests yield.
        vm.prank(owner);
        vault.harvest(harvestAmount);

        // 3. Alice redeems all her shares.
        vm.prank(alice);
        uint256 aliceOut = vault.redeem(aliceShares, alice, alice);

        // Alice must receive strictly more than she deposited.
        assertGt(aliceOut, depositAmount, "alice receives more than deposited after harvest");

        // Vault should be essentially empty (only dust from locked virtual shares).
        assertLt(vault.totalSupply(), aliceShares, "vault supply decreased");
    }
}
