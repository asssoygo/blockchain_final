// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AMM} from "../../src/amm/AMM.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

contract AMMTest is Test {
    AMM internal amm;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    // token0 / token1 mirror the AMM's sorted references.
    IERC20 internal token0;
    IERC20 internal token1;

    address internal alice;
    address internal bob;

    uint256 internal constant MINIMUM_LIQUIDITY = 1_000;
    uint256 internal constant INITIAL_MINT = 1_000_000e18;

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        amm = new AMM(address(tokenA), address(tokenB));

        // Mirror the AMM's internal sorting so we reference the right tokens in tests.
        token0 = amm.token0();
        token1 = amm.token1();

        // Fund alice and bob.
        MockERC20(address(token0)).mint(alice, INITIAL_MINT);
        MockERC20(address(token1)).mint(alice, INITIAL_MINT);
        MockERC20(address(token0)).mint(bob, INITIAL_MINT);
        MockERC20(address(token1)).mint(bob, INITIAL_MINT);

        // Pre-approve the AMM for max uint256 (covers addLiquidity transferFrom).
        vm.startPrank(alice);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Transfers `amountIn` of token0 from `user` to the AMM, then calls swap.
    function _swapToken0ForToken1(address user, uint256 amountIn) internal returns (uint256 amountOut) {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        amountOut = amm.getAmountOut(amountIn, r0, r1);
        vm.prank(user);
        token0.transfer(address(amm), amountIn);
        vm.prank(user);
        amm.swap(0, amountOut, user);
    }

    /// @dev Transfers `amountIn` of token1 from `user` to the AMM, then calls swap.
    function _swapToken1ForToken0(address user, uint256 amountIn) internal returns (uint256 amountOut) {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        amountOut = amm.getAmountOut(amountIn, r1, r0);
        vm.prank(user);
        token1.transfer(address(amm), amountIn);
        vm.prank(user);
        amm.swap(amountOut, 0, user);
    }

    // ─── 1. Constructor sorts tokens ──────────────────────────────────────────

    function test_Constructor_SortsTokens() public {
        MockERC20 tLow = new MockERC20("Low", "LOW");
        MockERC20 tHigh = new MockERC20("High", "HIGH");

        // Guarantee ordering for the test.
        if (address(tLow) > address(tHigh)) {
            (tLow, tHigh) = (tHigh, tLow);
        }

        // Deploy with the higher-address token listed first.
        AMM ammSorted = new AMM(address(tHigh), address(tLow));
        assertEq(address(ammSorted.token0()), address(tLow), "token0 must be lower address");
        assertEq(address(ammSorted.token1()), address(tHigh), "token1 must be higher address");
    }

    // ─── 2. Constructor rejects zero address ──────────────────────────────────

    function test_Constructor_RevertWhen_ZeroToken() public {
        vm.expectRevert(AMM.ZeroAddress.selector);
        new AMM(address(0), address(tokenB));
    }

    // ─── 3. Constructor rejects identical tokens ──────────────────────────────

    function test_Constructor_RevertWhen_IdenticalTokens() public {
        vm.expectRevert(AMM.IdenticalTokens.selector);
        new AMM(address(tokenA), address(tokenA));
    }

    // ─── 4. First addLiquidity mints correct LP ───────────────────────────────

    function test_AddInitialLiquidity_MintsCorrectLP() public {
        uint256 amount0 = 100e18;
        uint256 amount1 = 400e18;
        uint256 expectedLiquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;

        vm.prank(alice);
        (,, uint256 liquidity) = amm.addLiquidity(amount0, amount1, 0, 0, alice);

        assertEq(liquidity, expectedLiquidity, "LP minted to alice");
        assertEq(amm.balanceOf(alice), expectedLiquidity, "alice LP balance");
    }

    // ─── 5. MINIMUM_LIQUIDITY permanently locked to 0xdead ───────────────────

    function test_AddInitialLiquidity_LocksMinimumLiquidity() public {
        vm.prank(alice);
        amm.addLiquidity(100e18, 100e18, 0, 0, alice);

        assertEq(amm.balanceOf(address(0xdead)), MINIMUM_LIQUIDITY, "dead address holds minimum");
    }

    // ─── 6. Subsequent LP mint is proportional ────────────────────────────────

    function test_AddLiquidity_Subsequent_ProportionalMint() public {
        // Alice adds 100/200.
        vm.prank(alice);
        (,, uint256 aliceLP) = amm.addLiquidity(100e18, 200e18, 0, 0, alice);

        // Bob adds exactly half: 50/100.
        vm.prank(bob);
        (,, uint256 bobLP) = amm.addLiquidity(50e18, 100e18, 0, 0, bob);

        // totalSupply after alice = aliceLP + MINIMUM_LIQUIDITY.
        // Bob contributes 50 % of reserves → gets 50 % of totalSupply.
        // bobLP / aliceLP ≈ 0.5 (small deviation from integer division).
        assertApproxEqRel(bobLP, aliceLP / 2, 0.001e18, "bob gets ~half of alice's LP");
    }

    // ─── 7. addLiquidity reverts when below amount0Min ────────────────────────

    function test_AddLiquidity_RevertWhen_BelowAMin() public {
        // Seed pool 1:1.
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        // Bob wants ratio 1:2 (amount1Desired < amount1Optimal)
        // → code falls to else: amount0Optimal = amount1Desired * r0 / r1 = 50e18
        // Bob requires amount0Min = 200e18 → reverts InsufficientAOptimal.
        vm.prank(bob);
        vm.expectRevert(AMM.InsufficientAOptimal.selector);
        amm.addLiquidity(500e18, 50e18, 200e18, 0, bob);
    }

    // ─── 8. addLiquidity updates reserves ────────────────────────────────────

    function test_AddLiquidity_UpdatesReserves() public {
        uint256 a0 = 300e18;
        uint256 a1 = 600e18;

        vm.prank(alice);
        amm.addLiquidity(a0, a1, 0, 0, alice);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), a0, "reserve0");
        assertEq(uint256(r1), a1, "reserve1");
    }

    // ─── 9. removeLiquidity returns proportional amounts ─────────────────────

    function test_RemoveLiquidity_ReturnsProportionalAmounts() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        uint256 aliceLP = amm.balanceOf(alice);
        uint256 halfLP = aliceLP / 2;

        uint256 alice0Before = token0.balanceOf(alice);
        uint256 alice1Before = token1.balanceOf(alice);

        vm.prank(alice);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(halfLP, 0, 0, alice);

        // With 1:1 pool and 1000e18 total supply, each LP unit ≈ 1 token.
        assertEq(token0.balanceOf(alice), alice0Before + out0, "alice token0 balance");
        assertEq(token1.balanceOf(alice), alice1Before + out1, "alice token1 balance");
        assertGt(out0, 0, "received token0");
        assertGt(out1, 0, "received token1");
    }

    // ─── 10. removeLiquidity burns LP tokens ─────────────────────────────────

    function test_RemoveLiquidity_BurnsLPTokens() public {
        vm.prank(alice);
        amm.addLiquidity(500e18, 500e18, 0, 0, alice);

        uint256 aliceLP = amm.balanceOf(alice);
        uint256 supplyBefore = amm.totalSupply();

        vm.prank(alice);
        amm.removeLiquidity(aliceLP, 0, 0, alice);

        assertEq(amm.balanceOf(alice), 0, "alice LP fully burned");
        assertEq(amm.totalSupply(), supplyBefore - aliceLP, "total supply decreased");
    }

    // ─── 11. removeLiquidity reverts when liquidity == 0 ─────────────────────

    function test_RemoveLiquidity_RevertWhen_ZeroLiquidity() public {
        vm.prank(alice);
        amm.addLiquidity(100e18, 100e18, 0, 0, alice);

        vm.prank(alice);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.removeLiquidity(0, 0, 0, alice);
    }

    // ─── 12. removeLiquidity reverts when below amount0Min ───────────────────

    function test_RemoveLiquidity_RevertWhen_BelowAMin() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        uint256 aliceLP = amm.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(AMM.InsufficientAmount.selector);
        amm.removeLiquidity(aliceLP, type(uint256).max, 0, alice);
    }

    // ─── 13. Swap token0 → token1 matches getAmountOut ───────────────────────

    function test_Swap_ExactInput_Token0ForToken1() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 amountIn = 100e18;
        uint256 expectedOut = amm.getAmountOut(amountIn, r0, r1);

        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.prank(bob);
        token0.transfer(address(amm), amountIn);
        vm.prank(bob);
        amm.swap(0, expectedOut, bob);

        assertEq(token1.balanceOf(bob), bobToken1Before + expectedOut, "bob received correct token1");
    }

    // ─── 14. Swap token1 → token0 matches getAmountOut ───────────────────────

    function test_Swap_ExactInput_Token1ForToken0() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 amountIn = 50e18;
        uint256 expectedOut = amm.getAmountOut(amountIn, r1, r0);

        uint256 bobToken0Before = token0.balanceOf(bob);

        vm.prank(bob);
        token1.transfer(address(amm), amountIn);
        vm.prank(bob);
        amm.swap(expectedOut, 0, bob);

        assertEq(token0.balanceOf(bob), bobToken0Before + expectedOut, "bob received correct token0");
    }

    // ─── 15. swap reverts when both outputs are zero ──────────────────────────

    function test_Swap_RevertWhen_InsufficientOutput() public {
        vm.prank(alice);
        amm.addLiquidity(100e18, 100e18, 0, 0, alice);

        vm.expectRevert(AMM.InsufficientOutputAmount.selector);
        amm.swap(0, 0, bob);
    }

    // ─── 16. swap reverts when recipient is a pool token ─────────────────────

    function test_Swap_RevertWhen_RecipientIsToken() public {
        vm.prank(alice);
        amm.addLiquidity(100e18, 100e18, 0, 0, alice);

        vm.prank(bob);
        token0.transfer(address(amm), 10e18);

        vm.prank(bob);
        vm.expectRevert(AMM.InvalidRecipient.selector);
        amm.swap(0, 1e18, address(token0));
    }

    // ─── 17. swap reverts when k invariant is violated ───────────────────────

    function test_Swap_RevertWhen_KInvariantViolated() public {
        vm.prank(alice);
        amm.addLiquidity(100e18, 100e18, 0, 0, alice);

        // Send only 1 wei of token0 then ask for 50e18 of token1.
        // k-invariant check will fail: tiny input, large output.
        vm.prank(bob);
        token0.transfer(address(amm), 1);

        vm.prank(bob);
        vm.expectRevert(AMM.KInvariantViolated.selector);
        amm.swap(0, 50e18, bob);
    }

    // ─── 18. k increases after fee ───────────────────────────────────────────

    function test_Swap_KIncreasesAfterFee() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        (uint112 r0Before, uint112 r1Before,) = amm.getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);

        _swapToken0ForToken1(bob, 100e18);

        (uint112 r0After, uint112 r1After,) = amm.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        assertGt(kAfter, kBefore, "k must increase after fee accrual");
    }

    // ─── 19. swap updates reserves correctly ─────────────────────────────────

    function test_Swap_UpdatesReserves() public {
        vm.prank(alice);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, alice);

        uint256 amountIn = 100e18;
        (uint112 r0Before, uint112 r1Before,) = amm.getReserves();
        uint256 amountOut = amm.getAmountOut(amountIn, r0Before, r1Before);

        vm.prank(bob);
        token0.transfer(address(amm), amountIn);
        vm.prank(bob);
        amm.swap(0, amountOut, bob);

        (uint112 r0After, uint112 r1After,) = amm.getReserves();
        assertEq(uint256(r0After), uint256(r0Before) + amountIn, "reserve0 increased by input");
        assertEq(uint256(r1After), uint256(r1Before) - amountOut, "reserve1 decreased by output");
    }

    // ─── 20. getAmountOut — hand-computed exact match ─────────────────────────

    function test_GetAmountOut_Math() public view {
        uint256 reserveIn = 1_000e18;
        uint256 reserveOut = 1_000e18;
        uint256 amountIn = 100e18;

        // Hand derivation of AMM formula:
        //   amountInWithFee = 100e18 * 997
        //   numerator       = amountInWithFee * 1_000e18
        //   denominator     = 1_000e18 * 1_000 + amountInWithFee
        //   expected        = numerator / denominator
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1_000 + amountInWithFee;
        uint256 expected = numerator / denominator;

        assertEq(amm.getAmountOut(amountIn, reserveIn, reserveOut), expected, "exact formula match");
        // Sanity: amount out must be less than full reserve.
        assertLt(expected, reserveOut);
    }

    // ─── 21. getAmountOut reverts on zero input ───────────────────────────────

    function test_GetAmountOut_RevertWhen_ZeroInput() public {
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.getAmountOut(0, 1_000e18, 1_000e18);
    }

    // ─── 22. getAmountOut reverts on zero reserves ────────────────────────────

    function test_GetAmountOut_RevertWhen_ZeroReserves() public {
        vm.expectRevert(AMM.InsufficientLiquidity.selector);
        amm.getAmountOut(1e18, 0, 1_000e18);
    }

    // ─── 23. LP token is transferable — recipient can remove liquidity ────────

    function test_LPTokenIsTransferable() public {
        vm.prank(alice);
        amm.addLiquidity(500e18, 500e18, 0, 0, alice);

        uint256 aliceLP = amm.balanceOf(alice);

        // Alice transfers all her LP to bob.
        vm.prank(alice);
        amm.transfer(bob, aliceLP);

        assertEq(amm.balanceOf(alice), 0, "alice has no LP");
        assertEq(amm.balanceOf(bob), aliceLP, "bob received LP");

        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.prank(bob);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(aliceLP, 0, 0, bob);

        assertGt(out0, 0, "bob got token0");
        assertGt(out1, 0, "bob got token1");
        assertEq(token0.balanceOf(bob), bobToken0Before + out0);
        assertEq(token1.balanceOf(bob), bobToken1Before + out1);
    }

    // ─── 24. Large swaps have worse price than small swaps ───────────────────

    function test_PriceImpact_LargeSwapVsSmall() public {
        // Deep pool to amplify price-impact difference.
        vm.prank(alice);
        amm.addLiquidity(1_000_000e18, 1_000_000e18, 0, 0, alice);

        (uint112 r0, uint112 r1,) = amm.getReserves();

        uint256 smallIn = 100e18;
        uint256 largeIn = 100_000e18;

        uint256 smallOut = amm.getAmountOut(smallIn, r0, r1);
        uint256 largeOut = amm.getAmountOut(largeIn, r0, r1);

        // Price (out/in ratio): cross-multiply to avoid division.
        // smallOut/smallIn > largeOut/largeIn ↔ smallOut*largeIn > largeOut*smallIn
        assertGt(smallOut * largeIn, largeOut * smallIn, "small swap has better price");
    }

    // ─── 25. Full lifecycle: add, swap 5×, remove ────────────────────────────

    function test_FullCycle() public {
        // 1. Alice provides initial liquidity.
        vm.prank(alice);
        amm.addLiquidity(100_000e18, 100_000e18, 0, 0, alice);

        uint256 aliceLP = amm.balanceOf(alice);
        assertGt(aliceLP, 0);

        // 2. Five swaps alternating direction.
        _swapToken0ForToken1(bob, 1_000e18);
        _swapToken1ForToken0(bob, 800e18);
        _swapToken0ForToken1(bob, 500e18);
        _swapToken1ForToken0(bob, 300e18);
        _swapToken0ForToken1(bob, 200e18);

        // 3. Alice removes all her liquidity.
        vm.prank(alice);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(aliceLP, 0, 0, alice);

        assertGt(out0, 0, "alice received token0");
        assertGt(out1, 0, "alice received token1");
        assertEq(amm.balanceOf(alice), 0, "alice LP fully burned");

        // Locked MINIMUM_LIQUIDITY keeps reserves from reaching zero.
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertGt(uint256(r0) + uint256(r1), 0, "residual reserves from locked LP");
    }
}
