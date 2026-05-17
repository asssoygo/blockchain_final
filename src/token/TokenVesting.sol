// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  TokenVesting
/// @notice Linear vesting contract that releases tokens to a single beneficiary over VESTING_DURATION.
/// @dev    The token balance must be deposited into this contract (via the parent token's
///         {GovernanceToken.setVestingContract}) before any release is possible. The contract
///         does not pull tokens itself; it merely tracks how many of its balance are releasable.
///
///         Security: {release} follows the checks-effects-interactions pattern — the `released`
///         counter is incremented before the external {SafeERC20.safeTransfer} call.
contract TokenVesting {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Duration of the vesting schedule in seconds (365 days).
    uint256 public constant VESTING_DURATION = 365 days;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The ERC20 token subject to this vesting schedule.
    IERC20 public immutable token;

    /// @notice Address that receives tokens as they vest.
    address public immutable beneficiary;

    /// @notice Unix timestamp at which vesting begins (set to block.timestamp at construction).
    uint256 public immutable startTime;

    /// @notice Total number of tokens assigned to this vesting schedule.
    /// @dev    The contract assumes its token balance equals this value at construction time.
    uint256 public immutable totalAllocation;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Cumulative tokens that have already been transferred to the beneficiary.
    uint256 public released;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the allocation passed to the constructor is zero.
    error ZeroAllocation();

    /// @notice Thrown by {release} when no tokens have vested beyond what was already released.
    error NothingToRelease();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted each time tokens are successfully transferred to the beneficiary.
    /// @param beneficiary The address that received the tokens.
    /// @param amount      Number of tokens released in this call.
    event TokensReleased(address indexed beneficiary, uint256 amount);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Initialises the vesting schedule. Vesting begins immediately (startTime = now).
    /// @dev    Reverts with {ZeroAddress} if `_token` or `_beneficiary` is the zero address.
    ///         Reverts with {ZeroAllocation} if `_allocation` is zero.
    /// @param _token       ERC20 token to vest.
    /// @param _beneficiary Recipient of tokens as they vest.
    /// @param _allocation  Total number of tokens this contract will release over VESTING_DURATION.
    constructor(IERC20 _token, address _beneficiary, uint256 _allocation) {
        if (address(_token) == address(0) || _beneficiary == address(0)) revert ZeroAddress();
        if (_allocation == 0) revert ZeroAllocation();

        token = _token;
        beneficiary = _beneficiary;
        startTime = block.timestamp;
        totalAllocation = _allocation;
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @notice Calculates the total amount that has vested as of the current block.
    /// @dev    Returns 0 before startTime (edge-case guard), linearly interpolates between
    ///         startTime and startTime + VESTING_DURATION, and returns totalAllocation
    ///         once the full duration has elapsed.
    /// @return The cumulative vested amount, including tokens already released.
    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < startTime) return 0;
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= VESTING_DURATION) return totalAllocation;
        return totalAllocation * elapsed / VESTING_DURATION;
    }

    /// @notice Returns the number of tokens that can be released right now.
    /// @return Vested amount minus tokens already transferred to the beneficiary.
    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    // ─── State-Changing Functions ─────────────────────────────────────────────

    /// @notice Transfers all currently releasable tokens to the beneficiary.
    /// @dev    Implements checks-effects-interactions:
    ///           1. Check — reverts if nothing is releasable.
    ///           2. Effect — increments `released` before any external call.
    ///           3. Interaction — calls {SafeERC20.safeTransfer}.
    ///         Reverts with {NothingToRelease} if called before any tokens have vested or
    ///         immediately after a previous release in the same block.
    function release() external {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();

        released += amount; // effect before interaction
        token.safeTransfer(beneficiary, amount);

        emit TokensReleased(beneficiary, amount);
    }
}
