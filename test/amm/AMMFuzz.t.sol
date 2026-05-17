// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AMM} from "../../src/amm/AMM.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

contract AMMFuzzTest is Test {
    AMM internal amm;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    IERC20 internal token0;
    IERC20 internal token1;

    address internal alice;

    uint256 internal constant SEED_AMOUNT = 100_000e18;

    function setUp() public {
        alice = makeAddr("alice");

        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        amm = new AMM(address(tokenA), address(tokenB));

        token0 = amm.token0();
        token1 = amm.token1();

        // Seed alice with tokens and add initial liquidity so reserves are non-zero.
        MockERC20(address(token0)).mint(alice, type(uint128).max);
        MockERC20(address(token1)).mint(alice, type(uint128).max);

        vm.startPrank(alice);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(SEED_AMOUNT, SEED_AMOUNT, 0, 0, alice);
        vm.stopPrank();
    }

    // ─── Fuzz 1: addLiquidity never mints more LP than proportional ───────────

    /// @dev For any subsequent deposit, the LP minted must be at most
    ///      min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1).
    function testFuzz_AddLiquidity_NeverMintsMoreThanProportional(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e6, 1e24);
        amount1 = bound(amount1, 1e6, 1e24);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 supplyBefore = amm.totalSupply();

        address depositor = makeAddr("depositor");
        MockERC20(address(token0)).mint(depositor, amount0);
        MockERC20(address(token1)).mint(depositor, amount1);
        vm.startPrank(depositor);
        token0.approve(address(amm), amount0);
        token1.approve(address(amm), amount1);

        (uint256 actual0, uint256 actual1, uint256 liquidity) = amm.addLiquidity(amount0, amount1, 0, 0, depositor);
        vm.stopPrank();

        uint256 maxLP = Math.min(actual0 * supplyBefore / uint256(r0), actual1 * supplyBefore / uint256(r1));

        // Allow ±1 for rounding.
        assertLe(liquidity, maxLP + 1, "minted more than proportional share");
    }

    // ─── Fuzz 2: swap output is always less than the output reserve ──────────

    /// @dev For any bounded amountIn, getAmountOut(amountIn) < reserveOut.
    function testFuzz_Swap_AmountOutLessThanReserve(uint256 amountIn) public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();

        // Bound to the available reserve to keep the swap feasible.
        amountIn = bound(amountIn, 1, uint256(r0) - 1);

        uint256 amountOut = amm.getAmountOut(amountIn, r0, r1);

        assertLt(amountOut, uint256(r1), "output must be less than reserveOut");
    }

    // ─── Fuzz 3: getAmountOut never returns >= reserveOut (pure math) ─────────

    /// @dev Mathematical proof via fuzzing: the AMM formula can never output the full reserve.
    function testFuzz_GetAmountOut_NeverExceedsReserveOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        view
    {
        amountIn = bound(amountIn, 1, 1e30);
        reserveIn = bound(reserveIn, 1, 1e30);
        reserveOut = bound(reserveOut, 1, 1e30);

        uint256 out = amm.getAmountOut(amountIn, reserveIn, reserveOut);
        assertLt(out, reserveOut, "output must be strictly less than reserveOut");
    }

    // ─── Fuzz 4: removeLiquidity returns at most reserve amounts ─────────────

    /// @dev Removed token amounts must each be ≤ the pool's reserve before removal.
    function testFuzz_RemoveLiquidity_ReturnsLessThanOrEqualToReserves(uint256 liquidityPct) public {
        uint256 aliceLP = amm.balanceOf(alice);
        uint256 liquidity = bound(liquidityPct, 1, aliceLP);

        (uint112 r0Before, uint112 r1Before,) = amm.getReserves();

        vm.prank(alice);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(liquidity, 0, 0, alice);

        assertLe(out0, uint256(r0Before), "out0 cannot exceed reserve0");
        assertLe(out1, uint256(r1Before), "out1 cannot exceed reserve1");
    }

    // ─── Fuzz 5: k never decreases after a swap ───────────────────────────────

    /// @dev For any valid amountIn, reserve0*reserve1 after the swap >= before.
    function testFuzz_Swap_KNeverDecreases(uint256 amount0In) public {
        (uint112 r0, uint112 r1,) = amm.getReserves();

        // Bound to at most half the reserve so amountOut is always < r1.
        amount0In = bound(amount0In, 1, uint256(r0) / 2);

        uint256 amountOut = amm.getAmountOut(amount0In, r0, r1);
        vm.assume(amountOut > 0 && amountOut < uint256(r1));

        uint256 kBefore = uint256(r0) * uint256(r1);

        // Caller sends token0 to AMM first, then calls swap.
        deal(address(token0), alice, amount0In);
        vm.prank(alice);
        token0.transfer(address(amm), amount0In);
        vm.prank(alice);
        amm.swap(0, amountOut, alice);

        (uint112 r0After, uint112 r1After,) = amm.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        assertGe(kAfter, kBefore, "k must not decrease after swap");
    }
}
