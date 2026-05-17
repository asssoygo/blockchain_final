// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TreasuryV1} from "./TreasuryV1.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  TreasuryV2
/// @notice Upgrades TreasuryV1 with per-token spending caps inside rolling time windows.
///
/// @dev    V2 STORAGE LAYOUT: V1 slots 0-3 are preserved. New state appended at slots 4+.
///         This preserves the upgrade safety guaranteed by UUPS.
///
///         Full storage layout (proxy slots):
///           slot 0 — totalDeposited         (inherited from V1)
///           slot 1 — totalWithdrawn         (inherited from V1)
///           slot 2 — ethBalance             (inherited from V1)
///           slot 3 — version                (inherited from V1)
///           slot 4 — spendingCaps           mapping(address => uint256)
///           slot 5 — spentInWindow          mapping(address => uint256)
///           slot 6 — windowStartTime        mapping(address => uint256)
///           slot 7 — spendingWindowDuration uint256
contract TreasuryV2 is TreasuryV1 {
    using SafeERC20 for IERC20;

    // ─── V2 State (slots 4-7) ─────────────────────────────────────────────────

    /// @notice Maximum ERC-20 tokens that can be transferred per token per window (0 = no cap).
    mapping(address => uint256) public spendingCaps;

    /// @notice Amount already transferred in the current window per token.
    mapping(address => uint256) public spentInWindow;

    /// @notice Timestamp at which the current window started, per token.
    mapping(address => uint256) public windowStartTime;

    /// @notice Duration of each spending window in seconds.
    uint256 public spendingWindowDuration;

    // ─── Additional Errors ────────────────────────────────────────────────────

    /// @notice Thrown when a transfer would exceed the spending cap for this window.
    /// @param token     The ERC-20 token address.
    /// @param requested Amount the caller tried to transfer.
    /// @param remaining Remaining capacity in the current window.
    error SpendingCapExceeded(address token, uint256 requested, uint256 remaining);

    // ─── Additional Events ────────────────────────────────────────────────────

    /// @notice Emitted when the spending cap for a token is updated.
    event SpendingCapSet(address indexed token, uint256 cap);

    /// @notice Emitted when a spending window is reset for a token.
    event SpendingWindowReset(address indexed token, uint256 newWindowStart);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @dev Locks the V2 implementation against direct initialisation.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── V2 Initializer ───────────────────────────────────────────────────────

    /// @notice Re-initialises the proxy for V2, setting the spending window duration.
    /// @param _spendingWindowDuration Length of each spending window in seconds.
    function initializeV2(uint256 _spendingWindowDuration) public reinitializer(2) {
        spendingWindowDuration = _spendingWindowDuration;
        version = "v2.0.0";
        emit Upgraded("v2.0.0");
    }

    // ─── Spending Cap Management ──────────────────────────────────────────────

    /// @notice Sets the per-window spending cap for `token`.
    /// @param token ERC-20 address; must not be address(0).
    /// @param cap   Maximum tokens transferable per window (0 = no cap).
    function setSpendingCap(address token, uint256 cap) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        spendingCaps[token] = cap;
        emit SpendingCapSet(token, cap);
    }

    // ─── Overridden Transfer ──────────────────────────────────────────────────

    /// @notice Sends `amount` of `token` to `to`, enforcing the rolling spending cap.
    /// @dev    Window resets automatically when it expires.  CEI: state updated before transfer.
    /// @param token  ERC-20 address; must not be address(0).
    /// @param to     Recipient; must not be address(0).
    /// @param amount Tokens to send; must be > 0 and within the spending cap if set.
    function transferERC20(address token, address to, uint256 amount) external override onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Reset window if it has expired.
        if (block.timestamp >= windowStartTime[token] + spendingWindowDuration) {
            spentInWindow[token] = 0;
            windowStartTime[token] = block.timestamp;
            emit SpendingWindowReset(token, block.timestamp);
        }

        // Enforce cap (0 means no cap).
        if (spendingCaps[token] > 0 && spentInWindow[token] + amount > spendingCaps[token]) {
            revert SpendingCapExceeded(token, amount, spendingCaps[token] - spentInWindow[token]);
        }

        // CEI: update state before external transfer.
        spentInWindow[token] += amount;
        totalWithdrawn[token] += amount;
        SafeERC20.safeTransfer(IERC20(token), to, amount);

        emit ERC20Transferred(token, to, amount);
    }
}
