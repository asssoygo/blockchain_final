// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title  AMM — Constant-Product Automated Market Maker (x*y=k)
/// @notice A from-scratch x*y=k AMM with a 0.3 % swap fee. The contract itself is the LP token
///         (ERC20 "DeFi-LP" / "DLP"). Liquidity providers mint LP tokens proportional to their
///         deposit and burn them to withdraw.
/// @dev    Security: ReentrancyGuard on every state-changing external function.
///                   SafeERC20 for all token interactions.
///                   Checks-Effects-Interactions order in {removeLiquidity} and {addLiquidity}.
///         Reserve packing: reserve0, reserve1, and blockTimestampLast are packed into a single
///         32-byte storage slot (uint112 + uint112 + uint32 = 256 bits) to minimise SLOAD cost.
contract AMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Amount of LP permanently locked on the first mint to prevent pool-draining attacks.
    uint256 public constant MINIMUM_LIQUIDITY = 1_000;

    /// @notice Numerator of the swap fee (3 / 1000 = 0.3 %).
    uint256 public constant FEE_NUMERATOR = 3;

    /// @notice Denominator of the swap fee.
    uint256 public constant FEE_DENOMINATOR = 1_000;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The token with the lower address in the pair (sorted at construction).
    IERC20 public immutable token0;

    /// @notice The token with the higher address in the pair (sorted at construction).
    IERC20 public immutable token1;

    // ─── Packed reserve slot ──────────────────────────────────────────────────
    // reserve0 (112 bits) + reserve1 (112 bits) + blockTimestampLast (32 bits) = 256 bits → 1 slot.

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error ZeroAddress();
    error IdenticalTokens();
    error ZeroAmount();
    error Overflow();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientAmount();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InsufficientAOptimal();
    error InsufficientBOptimal();
    error InvalidRecipient();
    error KInvariantViolated();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when liquidity is added and LP tokens are minted.
    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);

    /// @notice Emitted when liquidity is removed and LP tokens are burned.
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    /// @notice Emitted on every swap.
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /// @notice Emitted whenever the reserves are updated.
    event Sync(uint112 reserve0, uint112 reserve1);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the pool and sorts the two tokens by address (lower first).
    /// @dev    Sorting ensures a canonical pair address regardless of argument order and
    ///         matches the convention used by factory contracts.
    /// @param _token0 Address of the first token (will be sorted).
    /// @param _token1 Address of the second token (will be sorted).
    constructor(address _token0, address _token1) ERC20("DeFi-LP", "DLP") {
        if (_token0 == address(0) || _token1 == address(0)) revert ZeroAddress();
        if (_token0 == _token1) revert IdenticalTokens();

        // Sort so that token0 always holds the lower address.
        if (_token0 < _token1) {
            token0 = IERC20(_token0);
            token1 = IERC20(_token1);
        } else {
            token0 = IERC20(_token1);
            token1 = IERC20(_token0);
        }
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @notice Returns the current reserves and the timestamp of the last update.
    /// @return _reserve0          Current reserve of token0.
    /// @return _reserve1          Current reserve of token1.
    /// @return _blockTimestampLast Timestamp of the last reserve update.
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    /// @notice Writes new reserves to storage and emits {Sync}.
    /// @dev    Reverts with {Overflow} if either balance exceeds uint112.max, keeping the packed
    ///         slot invariant intact.
    function _update(uint256 balance0, uint256 balance1) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    // ─── Liquidity Functions ──────────────────────────────────────────────────

    /// @notice Deposits token0 and token1 into the pool and mints LP tokens to `to`.
    /// @dev    On the first deposit (reserves == 0) the depositor can choose any ratio; afterwards
    ///         the ratio must match the current reserves, and the side requiring fewer tokens is used
    ///         to cap the actual deposit. The first mint permanently locks {MINIMUM_LIQUIDITY} LP
    ///         tokens to address(0xdead) to prevent the total-supply from ever reaching zero.
    /// @param amount0Desired Preferred amount of token0 to deposit.
    /// @param amount1Desired Preferred amount of token1 to deposit.
    /// @param amount0Min     Minimum acceptable amount of token0 (slippage guard).
    /// @param amount1Min     Minimum acceptable amount of token1 (slippage guard).
    /// @param to             Recipient of the minted LP tokens.
    /// @return amount0   Actual amount of token0 deposited.
    /// @return amount1   Actual amount of token1 deposited.
    /// @return liquidity Number of LP tokens minted to `to`.
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        if (to == address(0)) revert ZeroAddress();
        if (amount0Desired == 0 || amount1Desired == 0) revert ZeroAmount();

        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;

        // ── Compute optimal deposit amounts ───────────────────────────────────
        if (_reserve0 == 0 && _reserve1 == 0) {
            // First liquidity: accept the desired amounts as-is.
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = uint256(amount0Desired) * uint256(_reserve1) / uint256(_reserve0);
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert InsufficientBOptimal();
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = uint256(amount1Desired) * uint256(_reserve0) / uint256(_reserve1);
                if (amount0Optimal < amount0Min) revert InsufficientAOptimal();
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        // ── Pull tokens (interaction before effect is safe here — minting happens after) ──
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // ── Compute LP to mint ────────────────────────────────────────────────
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply == 0) {
            uint256 sqrtProduct = Math.sqrt(amount0 * amount1);
            // Permanently lock MINIMUM_LIQUIDITY; protects pool from total-supply going to 0.
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
            liquidity = sqrtProduct - MINIMUM_LIQUIDITY; // reverts (underflow) if sqrt too small
        } else {
            liquidity = Math.min(
                amount0 * currentTotalSupply / uint256(_reserve0), amount1 * currentTotalSupply / uint256(_reserve1)
            );
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        // ── Effect: mint LP ───────────────────────────────────────────────────
        _mint(to, liquidity);

        // ── Update reserves ───────────────────────────────────────────────────
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    /// @notice Burns `liquidity` LP tokens from the caller and returns underlying tokens to `to`.
    /// @dev    CEI: LP tokens are burned (effect) before any token transfer (interaction).
    /// @param liquidity   Amount of LP tokens to burn.
    /// @param amount0Min  Minimum token0 to receive (slippage guard).
    /// @param amount1Min  Minimum token1 to receive (slippage guard).
    /// @param to          Recipient of the returned tokens.
    /// @return amount0 Amount of token0 returned.
    /// @return amount1 Amount of token1 returned.
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (to == address(0)) revert ZeroAddress();
        if (liquidity == 0) revert ZeroAmount();

        uint256 currentTotalSupply = totalSupply();
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        // Proportional share of each reserve.
        amount0 = liquidity * balance0 / currentTotalSupply;
        amount1 = liquidity * balance1 / currentTotalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        if (amount0 < amount0Min) revert InsufficientAmount();
        if (amount1 < amount1Min) revert InsufficientAmount();

        // ── Effect: burn LP before any external call ──────────────────────────
        _burn(msg.sender, liquidity);

        // ── Interactions: transfer underlying tokens ──────────────────────────
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // ─── Swap ─────────────────────────────────────────────────────────────────

    /// @notice Swaps tokens using the constant-product formula with a 0.3 % fee.
    /// @dev    Low-level function: the caller MUST transfer input tokens to this contract before
    ///         calling {swap}. The contract optimistically sends output tokens first, then verifies
    ///         that the adjusted k-invariant (accounting for the fee) is satisfied.
    ///
    ///         Flow:
    ///           1. Validate parameters.
    ///           2. Optimistically transfer output tokens.
    ///           3. Measure how much input arrived (balance delta).
    ///           4. Verify k-invariant: (b0*1000 - in0*3) * (b1*1000 - in1*3) >= r0*r1*1000000.
    ///           5. Update reserves.
    ///
    /// @param amount0Out Amount of token0 to send out (0 when swapping token0 in).
    /// @param amount1Out Amount of token1 to send out (0 when swapping token1 in).
    /// @param to         Recipient of the output tokens.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        if (to == address(0)) revert ZeroAddress();
        if (to == address(token0) || to == address(token1)) revert InvalidRecipient();

        // Cache reserves to avoid repeated SLOADs.
        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;

        if (amount0Out >= uint256(_reserve0) || amount1Out >= uint256(_reserve1)) revert InsufficientLiquidity();

        // ── Optimistic output transfer ────────────────────────────────────────
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        // ── Measure balances after transfer ───────────────────────────────────
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        // Input amounts = balance increase above (reserve − amount sent out).
        uint256 amount0In =
            balance0 > uint256(_reserve0) - amount0Out ? balance0 - (uint256(_reserve0) - amount0Out) : 0;
        uint256 amount1In =
            balance1 > uint256(_reserve1) - amount1Out ? balance1 - (uint256(_reserve1) - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // ── Verify k-invariant with fee ───────────────────────────────────────
        // Adjusted balances subtract the fee portion of each input.
        // (balance * 1000 - amountIn * 3) * (...) >= reserve0 * reserve1 * 1_000_000
        uint256 balance0Adjusted = balance0 * FEE_DENOMINATOR - amount0In * FEE_NUMERATOR;
        uint256 balance1Adjusted = balance1 * FEE_DENOMINATOR - amount1In * FEE_NUMERATOR;

        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * uint256(_reserve1) * (FEE_DENOMINATOR ** 2)) {
            revert KInvariantViolated();
        }

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // ─── Quote Helper ─────────────────────────────────────────────────────────

    /// @notice Computes the output amount for a given input using the x*y=k formula with 0.3 % fee.
    /// @dev    Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    /// @param amountIn   Exact amount of input token.
    /// @param reserveIn  Current reserve of the input token.
    /// @param reserveOut Current reserve of the output token.
    /// @return amountOut Expected output amount (always < reserveOut).
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR); // amountIn * 997
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
