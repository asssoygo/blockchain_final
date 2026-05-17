// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

/// @dev Thin external wrapper so gas measurements capture real EVM call overhead.
contract MathLibWrapper {
    function sqrtYul(uint256 x) external pure returns (uint256) {
        return MathLib.sqrtYul(x);
    }

    function sqrtSolidity(uint256 x) external pure returns (uint256) {
        return MathLib.sqrtSolidity(x);
    }

    function minYul(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.minYul(a, b);
    }

    function minSolidity(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.minSolidity(a, b);
    }
}

contract MathLibTest is Test {
    MathLibWrapper internal wrapper;

    function setUp() public {
        wrapper = new MathLibWrapper();
    }

    // ─── 1. sqrt(0) == 0 for both implementations ─────────────────────────────

    function test_Sqrt_Zero() public pure {
        assertEq(MathLib.sqrtYul(0), 0, "Yul sqrt(0)");
        assertEq(MathLib.sqrtSolidity(0), 0, "Solidity sqrt(0)");
    }

    // ─── 2. Perfect square ────────────────────────────────────────────────────

    function test_Sqrt_PerfectSquare() public pure {
        assertEq(MathLib.sqrtYul(10_000), 100, "Yul sqrt(10000)");
        assertEq(MathLib.sqrtSolidity(10_000), 100, "Solidity sqrt(10000)");
    }

    // ─── 3. Non-perfect square floors correctly ───────────────────────────────

    function test_Sqrt_NonPerfectSquare() public pure {
        // floor(sqrt(2)) == 1  (1^2 = 1 ≤ 2 < 4 = 2^2)
        assertEq(MathLib.sqrtYul(2), 1, "Yul sqrt(2)");
        assertEq(MathLib.sqrtSolidity(2), 1, "Solidity sqrt(2)");

        // floor(sqrt(8)) == 2  (2^2 = 4 ≤ 8 < 9 = 3^2)
        assertEq(MathLib.sqrtYul(8), 2, "Yul sqrt(8)");
        assertEq(MathLib.sqrtSolidity(8), 2, "Solidity sqrt(8)");
    }

    // ─── 4. Large number — floor(sqrt(2^128 - 1)) == 2^64 - 1 ────────────────

    function test_Sqrt_LargeNumber() public pure {
        uint256 x = type(uint128).max; // 2^128 - 1
        uint256 expected = type(uint64).max; // 2^64  - 1  (floor value)

        assertEq(MathLib.sqrtYul(x), expected, "Yul sqrt(uint128.max)");
        assertEq(MathLib.sqrtSolidity(x), expected, "Solidity sqrt(uint128.max)");
    }

    // ─── 5. Fuzz: both implementations always agree ───────────────────────────

    function testFuzz_SqrtYul_EqualsSqrtSolidity(uint256 x) public pure {
        assertEq(MathLib.sqrtYul(x), MathLib.sqrtSolidity(x), "sqrtYul and sqrtSolidity must agree for all inputs");
    }

    // ─── 6. Gas benchmark: Yul sqrt must be cheaper than Solidity sqrt ────────

    function test_GasBenchmark_Sqrt() public {
        // Use a large input where the Babylonian Solidity loop takes many iterations (~128)
        // while the Yul Newton method always uses exactly 7 iterations.
        uint256 largeX = type(uint256).max / 3;

        uint256 gasBefore;
        uint256 gasUsedYul;
        uint256 gasUsedSolidity;

        gasBefore = gasleft();
        wrapper.sqrtYul(largeX);
        gasUsedYul = gasBefore - gasleft();

        gasBefore = gasleft();
        wrapper.sqrtSolidity(largeX);
        gasUsedSolidity = gasBefore - gasleft();

        console.log("sqrtYul      gas:", gasUsedYul);
        console.log("sqrtSolidity gas:", gasUsedSolidity);
        console.log("Yul savings     :", gasUsedSolidity - gasUsedYul);

        assertLt(gasUsedYul, gasUsedSolidity, "Yul sqrt must be cheaper than Solidity sqrt");
    }

    // ─── 7. Fuzz: minYul and minSolidity always agree ─────────────────────────

    function testFuzz_MinYul_EqualsMinSolidity(uint256 a, uint256 b) public pure {
        assertEq(MathLib.minYul(a, b), MathLib.minSolidity(a, b), "minYul and minSolidity must agree for all inputs");
    }
}
