// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AMM} from "../../src/amm/AMM.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

// ─── Handler ──────────────────────────────────────────────────────────────────

/// @dev Wraps AMM calls with bounded inputs so the invariant fuzzer can explore
///      the state space without constantly triggering reverts on bad parameters.
contract AMMHandler is CommonBase, StdCheats, StdUtils {
    AMM internal immutable amm;
    IERC20 internal immutable token0;
    IERC20 internal immutable token1;

    /// @dev Ghost variable: set to true if any swap caused k to decrease.
    bool public ghost_kDecreased;

    constructor(AMM _amm) {
        amm = _amm;
        token0 = _amm.token0();
        token1 = _amm.token1();

        // Handler holds perpetual approval so addLiquidity can pull tokens.
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
    }

    /// @dev Adds bounded liquidity to the pool as the handler itself.
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        amount0 = bound(amount0, 1e6, 1e24);
        amount1 = bound(amount1, 1e6, 1e24);

        deal(address(token0), address(this), amount0);
        deal(address(token1), address(this), amount1);

        try amm.addLiquidity(amount0, amount1, 0, 0, address(this)) {} catch {}
    }

    /// @dev Removes a bounded fraction of the handler's LP balance.
    function removeLiquidity(uint256 liquidityPct) external {
        uint256 balance = amm.balanceOf(address(this));
        if (balance == 0) return;

        uint256 liquidity = bound(liquidityPct, 1, balance);
        try amm.removeLiquidity(liquidity, 0, 0, address(this)) {} catch {}
    }

    /// @dev Swaps a bounded amount of token0 for token1 and records any k decrease.
    function swap(uint256 amount0In) external {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        if (r0 == 0 || r1 == 0) return;

        amount0In = bound(amount0In, 1, uint256(r0) / 2);

        uint256 amountOut;
        try amm.getAmountOut(amount0In, uint256(r0), uint256(r1)) returns (uint256 out) {
            amountOut = out;
        } catch {
            return;
        }
        if (amountOut == 0 || amountOut >= uint256(r1)) return;

        uint256 kBefore = uint256(r0) * uint256(r1);

        deal(address(token0), address(this), amount0In);
        token0.transfer(address(amm), amount0In);

        try amm.swap(0, amountOut, address(this)) {}
        catch {
            return;
        }

        (uint112 r0After, uint112 r1After,) = amm.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        if (kAfter < kBefore) ghost_kDecreased = true;
    }
}

// ─── Invariant Test ───────────────────────────────────────────────────────────

contract AMMInvariantTest is StdInvariant, Test {
    AMM internal amm;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    AMMHandler internal handler;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        amm = new AMM(address(tokenA), address(tokenB));

        IERC20 t0 = amm.token0();
        IERC20 t1 = amm.token1();

        // Add initial liquidity from the test contract so the pool is non-empty.
        uint256 seed = 10_000e18;
        deal(address(t0), address(this), seed);
        deal(address(t1), address(this), seed);
        t0.approve(address(amm), seed);
        t1.approve(address(amm), seed);
        amm.addLiquidity(seed, seed, 0, 0, address(this));

        // Deploy handler and register it as the only target.
        handler = new AMMHandler(amm);
        targetContract(address(handler));
    }

    // ─── Invariant 1: k never decreases across swaps ──────────────────────────

    /// @notice After any swap executed by the handler, the product of reserves must
    ///         not have decreased (the fee makes it strictly increase in practice).
    function invariant_KNeverDecreasesAfterSwaps() public view {
        assertFalse(handler.ghost_kDecreased(), "k decreased after a swap");
    }

    // ─── Invariant 2: totalSupply equals sum of all known LP holders ──────────

    /// @notice The total supply of LP tokens must equal the sum of balances held by
    ///         all actors that can receive LP in this test setup:
    ///         address(this) (initial liquidity), address(handler) (handler mints),
    ///         and address(0xdead) (permanently locked minimum).
    function invariant_TotalSupplyEqualsLPHoldings() public view {
        uint256 testBalance = amm.balanceOf(address(this));
        uint256 handlerBalance = amm.balanceOf(address(handler));
        uint256 deadBalance = amm.balanceOf(address(0xdead));

        assertEq(
            amm.totalSupply(), testBalance + handlerBalance + deadBalance, "totalSupply != sum of LP holder balances"
        );
    }

    // ─── Invariant 3: stored reserves match actual token balances ─────────────

    /// @notice The reserve0 and reserve1 values stored in the AMM state must always
    ///         equal the actual ERC20 balances held by the AMM contract.
    ///         Any discrepancy would indicate an accounting bug.
    function invariant_ReservesMatchTokenBalances() public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), amm.token0().balanceOf(address(amm)), "reserve0 != token0 balance");
        assertEq(uint256(r1), amm.token1().balanceOf(address(amm)), "reserve1 != token1 balance");
    }
}
