// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  MathLib
/// @notice Utility library providing integer square-root and minimum functions in two flavours:
///           1. Inline Yul assembly — fast, O(1) Newton iterations with a MSB-based initial guess.
///           2. Pure Solidity  — simple Babylonian loop, useful as a readable reference and
///              benchmark baseline.
///
/// @dev    Both sqrt variants return the same value (floor of the true square root) for every
///         possible uint256 input. The Yul variant uses the OpenZeppelin / Uniswap V3 approach:
///         a bit-search initial estimate followed by exactly 7 Newton–Raphson steps, giving O(1)
///         gas regardless of input magnitude. The Solidity Babylonian method requires O(log x)
///         iterations, which can reach ~128 steps for 256-bit inputs.
library MathLib {
    // ─── Square Root ──────────────────────────────────────────────────────────

    /// @notice Computes floor(sqrt(x)) using an inline Yul assembly Newton–Raphson method.
    /// @dev    Uses a bit-search initial estimate so exactly 7 Newton iterations always suffice,
    ///         giving constant O(1) gas. A final correction step (`min(z, x/z)`) guarantees the
    ///         result is the floor, not the ceiling. Proven correct for all uint256 inputs.
    /// @param x The input value.
    /// @return z floor(sqrt(x))
    function sqrtYul(uint256 x) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 { z := 0 }
            default {
                // Build an initial estimate of sqrt(x) by locating the most significant bit
                // of x through successive right-shifts (each iteration halves the search space).
                // The accumulated left-shifts in z give 2^(msb/2), a starting point within 2×
                // of the true sqrt.
                z := 1
                let xAux := x

                if iszero(lt(xAux, 0x100000000000000000000000000000000)) {
                    xAux := shr(128, xAux)
                    z := shl(64, z)
                }
                if iszero(lt(xAux, 0x10000000000000000)) {
                    xAux := shr(64, xAux)
                    z := shl(32, z)
                }
                if iszero(lt(xAux, 0x100000000)) {
                    xAux := shr(32, xAux)
                    z := shl(16, z)
                }
                if iszero(lt(xAux, 0x10000)) {
                    xAux := shr(16, xAux)
                    z := shl(8, z)
                }
                if iszero(lt(xAux, 0x100)) {
                    xAux := shr(8, xAux)
                    z := shl(4, z)
                }
                if iszero(lt(xAux, 0x10)) {
                    xAux := shr(4, xAux)
                    z := shl(2, z)
                }
                if iszero(lt(xAux, 0x4)) {
                    z := shl(1, z)
                }

                // Seven Newton–Raphson iterations: z_new = (z + x/z) / 2.
                // Starting within 2× of the true sqrt, 7 steps give full 256-bit precision.
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))
                z := shr(1, add(z, div(x, z)))

                // Correction: Newton's method converges from above; if x/z < z, the true
                // floor is x/z (integer division rounds down as required).
                let roundedDown := div(x, z)
                if lt(roundedDown, z) { z := roundedDown }
            }
        }
    }

    /// @notice Computes floor(sqrt(x)) using the Babylonian (Heron's) method in pure Solidity.
    /// @dev    Reference implementation for benchmark comparison with {sqrtYul}. Starts from
    ///         `z = x` and converges via `z = (x/z + z) / 2` until the estimate stops decreasing.
    ///         Requires O(log x) iterations — up to ~128 steps for 256-bit inputs — making it
    ///         significantly more expensive than {sqrtYul} for large values.
    /// @param x The input value.
    /// @return z floor(sqrt(x))
    function sqrtSolidity(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        // For x in [1,3], floor(sqrt(x)) == 1. The loop below requires y < z to enter;
        // with y = x/2+1 and z = x that condition is false when x <= 3, so guard explicitly.
        if (x < 4) return 1;
        z = x;
        uint256 y = x / 2 + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }

    // ─── Minimum ──────────────────────────────────────────────────────────────

    /// @notice Returns the smaller of two uint256 values using a branchless Yul expression.
    /// @dev    `xor(a, mul(xor(a, b), lt(b, a)))` equals `b` when b < a, else `a`, with no
    ///         conditional jump (cheaper on pipelined EVM implementations).
    /// @param a First operand.
    /// @param b Second operand.
    /// @return c min(a, b)
    function minYul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly {
            c := xor(a, mul(xor(a, b), lt(b, a)))
        }
    }

    /// @notice Returns the smaller of two uint256 values using a pure Solidity ternary.
    /// @param a First operand.
    /// @param b Second operand.
    /// @return min(a, b)
    function minSolidity(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
