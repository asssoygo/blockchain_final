// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenVesting} from "../../src/token/TokenVesting.sol";

/// @dev Minimal ERC20 used as the vested asset in these unit tests.
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    TokenVesting internal vesting;
    MockToken internal token;

    address internal beneficiary;

    uint256 internal constant ALLOCATION = 1_000e18;
    uint256 internal constant DURATION = 365 days;

    function setUp() public {
        beneficiary = makeAddr("beneficiary");
        token = new MockToken();
        vesting = new TokenVesting(IERC20(address(token)), beneficiary, ALLOCATION);

        // Fund the vesting contract with the full allocation (mirrors GovernanceToken.setVestingContract)
        token.mint(address(vesting), ALLOCATION);
    }

    // ─── 1. Initial state ─────────────────────────────────────────────────────

    /// @dev At construction time nothing has vested, nothing has been released.
    function test_InitialState() public view {
        assertEq(vesting.released(), 0, "released");
        assertEq(vesting.vestedAmount(), 0, "vestedAmount");
        assertEq(vesting.releasable(), 0, "releasable");
    }

    // ─── 2. Vested amount at the halfway point ────────────────────────────────

    /// @dev Exactly half the duration elapsed => exactly half the allocation has vested.
    function test_VestedAmountAtHalfway() public {
        vm.warp(block.timestamp + DURATION / 2);

        uint256 expected = ALLOCATION * (DURATION / 2) / DURATION;
        assertEq(vesting.vestedAmount(), expected, "half allocation vested");
    }

    // ─── 3. Vested amount after full duration ─────────────────────────────────

    /// @dev After the full duration the entire allocation is vested.
    function test_VestedAmountAfterFullDuration() public {
        vm.warp(block.timestamp + DURATION);
        assertEq(vesting.vestedAmount(), ALLOCATION, "full allocation vested");
    }

    // ─── 4. Vested amount never exceeds allocation before completion ──────────

    /// @dev One second before the end the vested amount must still be < totalAllocation.
    function test_VestedAmountBeforeFullDuration_DoesNotExceedAllocation() public {
        vm.warp(block.timestamp + DURATION - 1);
        assertLt(vesting.vestedAmount(), ALLOCATION, "should not be at cap yet");
    }

    // ─── 5. Release transfers the correct token amount ─────────────────────────

    /// @dev At the halfway mark, release() must transfer exactly the vested portion to the beneficiary.
    function test_Release_TransfersTokens() public {
        vm.warp(block.timestamp + DURATION / 2);

        uint256 expectedRelease = ALLOCATION * (DURATION / 2) / DURATION;
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expectedRelease, "beneficiary balance");
        assertEq(vesting.released(), expectedRelease, "released counter");
    }

    // ─── 6. Release reverts immediately (nothing to release) ──────────────────

    /// @dev Calling release() at t=0 must revert with NothingToRelease.
    function test_Release_RevertWhen_NothingToRelease() public {
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release();
    }

    // ─── 7. No double-claim in the same block ────────────────────────────────

    /// @dev Two consecutive release() calls in the same block — the second must revert.
    function test_Release_NoDoubleClaim() public {
        vm.warp(block.timestamp + 100 days);

        vesting.release(); // first call succeeds

        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release(); // second call in same block must fail
    }

    // ─── 8. Full release after the vesting duration ───────────────────────────

    /// @dev After the full duration a single release() must send the entire allocation.
    function test_FullReleaseAfterDuration() public {
        vm.warp(block.timestamp + DURATION);

        vesting.release();

        assertEq(token.balanceOf(beneficiary), ALLOCATION, "beneficiary holds full allocation");
        assertEq(vesting.released(), ALLOCATION, "released equals totalAllocation");
        assertEq(vesting.releasable(), 0, "nothing left to release");
    }
}
