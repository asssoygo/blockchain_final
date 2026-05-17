// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  TreasuryV1
/// @notice UUPS-upgradeable treasury holding ETH and ERC-20 tokens on behalf of the DAO.
/// @dev    All OZ v5 mixin storage uses ERC-7201 namespaced slots, so the user-defined
///         variables below occupy sequential proxy storage slots starting at 0.
///
///         Storage layout (proxy slots, V1):
///           slot 0 — totalDeposited   mapping(address => uint256)
///           slot 1 — totalWithdrawn   mapping(address => uint256)
///           slot 2 — ethBalance       uint256
///           slot 3 — version          string
///
///         V2 MUST only append new variables at slot 4+. Never insert before these.
contract TreasuryV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ─── State (slots 0-3) ────────────────────────────────────────────────────

    /// @notice Cumulative ERC-20 deposits tracked per token address.
    mapping(address => uint256) public totalDeposited;

    /// @notice Cumulative ERC-20 withdrawals tracked per token address.
    mapping(address => uint256) public totalWithdrawn;

    /// @notice Running ETH balance managed by the treasury.
    uint256 public ethBalance;

    /// @notice Human-readable version string set by each version's initializer.
    string public version;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address argument is address(0).
    error ZeroAddress();

    /// @notice Thrown when a required amount is 0.
    error ZeroAmount();

    /// @notice Thrown when a low-level ETH transfer fails.
    error TransferFailed();

    /// @notice Thrown when the requested amount exceeds the available balance.
    /// @param requested Amount the caller asked for.
    /// @param available Amount currently held.
    error InsufficientBalance(uint256 requested, uint256 available);

    // ─── Events ───────────────────────────────────────────────────────────────
    event ERC20Deposited(address indexed sender, address indexed token, uint256 amount);
    /// @notice Emitted when ETH arrives via the receive() fallback.
    event ETHReceived(address indexed from, uint256 amount);

    /// @notice Emitted after a successful ETH transfer out.
    event ETHTransferred(address indexed to, uint256 amount);

    /// @notice Emitted after a successful ERC-20 transfer out.
    event ERC20Transferred(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when the version string is updated (used by V2 reinitializer).
    event Upgraded(string newVersion);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @dev Locks the implementation contract against direct initialisation.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─── Initializer ──────────────────────────────────────────────────────────

    /// @notice Initialises the V1 proxy: sets the owner and chains OZ mixins.
    /// @param _owner Address that will own the treasury (Timelock in production).
    function initialize(address _owner) public initializer {
        if (_owner == address(0)) revert ZeroAddress();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        version = "v1.0.0";
    }

    // ─── UUPS Auth ────────────────────────────────────────────────────────────

    /// @dev Only the owner (DAO Timelock in production) can push a new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ─── ETH Handling ─────────────────────────────────────────────────────────

    /// @notice Accepts plain ETH transfers and updates the tracked balance.
    receive() external payable {
        ethBalance += msg.value;
        emit ETHReceived(msg.sender, msg.value);
    }

    /// @notice Sends `amount` wei from the treasury to `to`.
    /// @dev    Follows CEI: ethBalance decremented before the external call.
    /// @param to     Destination; must not be address(0).
    /// @param amount Wei to send; must be ≤ ethBalance.
    function transferETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > ethBalance) revert InsufficientBalance(amount, ethBalance);

        ethBalance -= amount;
        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit ETHTransferred(to, amount);
    }

    /// @notice Sends `amount` of `token` from the treasury to `to`.
    /// @param token  ERC-20 address; must not be address(0).
    /// @param to     Recipient; must not be address(0).
    /// @param amount Tokens to send; must be > 0.
    function transferERC20(address token, address to, uint256 amount) external virtual onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        totalWithdrawn[token] += amount;
        SafeERC20.safeTransfer(IERC20(token), to, amount);

        emit ERC20Transferred(token, to, amount);
    }

    /// @notice Pulls `amount` of `token` from msg.sender into the treasury.
    /// @dev    Caller must have approved the treasury to spend at least `amount`.
    /// @param token  ERC-20 address; must not be address(0).
    /// @param amount Tokens to pull; must be > 0.
    function depositERC20(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        totalDeposited[token] += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit ERC20Deposited(msg.sender, token, amount);
    }

    function getERC20Balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
