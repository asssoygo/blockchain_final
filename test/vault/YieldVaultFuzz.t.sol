// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldVault} from "../../src/vault/YieldVault.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

/// @notice Fuzz tests for YieldVault covering proportional share minting,
///         harvest-driven yield distribution, and total-assets accounting.
contract YieldVaultFuzzTest is Test {
    YieldVault internal vault;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new MockERC20("Stablecoin", "USDC");
        vault = new YieldVault(IERC20(address(token)), owner);
    }

    // ─── Fuzz 1: deposit mints proportional shares ────────────────────────────

    /// @dev For any deposit into a fresh vault the first depositor always gets 1:1
    ///      shares (since totalAssets == totalSupply == 0 before the call).
    ///      convertToAssets(shares) must round-trip back to the original amount
    ///      within 1 wei (OZ ERC-4626 uses +1 virtual asset/share for rounding).
    function testFuzz_DepositMintsProportionalShares(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 1e30);

        token.mint(alice, depositAmount);

        vm.prank(alice);
        token.approve(address(vault), depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertGt(shares, 0, "must mint non-zero shares");
        assertApproxEqAbs(
            vault.convertToAssets(shares), depositAmount, 1, "convertToAssets must round-trip within 1 wei"
        );
    }

    // ─── Fuzz 2: harvest distributes yield proportionally ─────────────────────

    /// @dev After alice and bob each deposit, the owner injects yield via harvest.
    ///      Both depositors must be able to redeem at least their original deposit
    ///      because harvestAmount > 0 strictly increases the share price.
    function testFuzz_HarvestPreservesShareRatio(uint256 aliceDeposit, uint256 bobDeposit, uint256 harvestAmount)
        public
    {
        aliceDeposit = bound(aliceDeposit, 1e18, 1e24);
        bobDeposit = bound(bobDeposit, 1e18, 1e24);
        harvestAmount = bound(harvestAmount, 1e18, 1e24);

        // Mint and approve.
        token.mint(alice, aliceDeposit);
        token.mint(bob, bobDeposit);
        token.mint(owner, harvestAmount);

        vm.prank(alice);
        token.approve(address(vault), aliceDeposit);
        vm.prank(bob);
        token.approve(address(vault), bobDeposit);
        vm.prank(owner);
        token.approve(address(vault), harvestAmount);

        // Deposit.
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        // Inject yield — raises totalAssets without changing totalSupply.
        vm.prank(owner);
        vault.harvest(harvestAmount);

        // Redeem and assert: each depositor gets back at least their original stake.
        vm.prank(alice);
        uint256 aliceWithdrawn = vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        uint256 bobWithdrawn = vault.redeem(bobShares, bob, bob);

        assertGe(aliceWithdrawn, aliceDeposit, "alice must receive >= her deposit");
        assertGe(bobWithdrawn, bobDeposit, "bob must receive >= his deposit");
    }

    // ─── Fuzz 3: withdrawal never inflates totalAssets ────────────────────────

    /// @dev After a single deposit, any partial redemption must decrease totalAssets
    ///      by exactly the amount transferred out — no rounding inflation.
    function testFuzz_WithdrawNeverExceedsTotalAssets(uint256 deposit, uint256 withdrawFraction) public {
        deposit = bound(deposit, 2e18, 1e24);
        withdrawFraction = bound(withdrawFraction, 1, 1_000); // 0.1 %–100 %

        token.mint(alice, deposit);

        vm.prank(alice);
        token.approve(address(vault), deposit);

        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 toRedeem = shares * withdrawFraction / 1_000;
        if (toRedeem == 0) toRedeem = 1;

        uint256 totalBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(toRedeem, alice, alice);

        uint256 totalAfter = vault.totalAssets();

        assertLe(totalAfter, totalBefore, "totalAssets must not increase after withdrawal");
        assertEq(totalBefore - totalAfter, assetsOut, "assets out must exactly equal the reduction in totalAssets");
    }
}
