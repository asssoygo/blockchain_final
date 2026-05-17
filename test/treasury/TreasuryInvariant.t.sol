// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "../../src/treasury/TreasuryV1.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

// ─── Handler ──────────────────────────────────────────────────────────────────

/// @dev Wraps TreasuryV1 with bounded deposit and withdraw operations so the
///      invariant fuzzer can explore accounting states without triggering reverts.
contract TreasuryHandler is CommonBase, StdCheats, StdUtils {
    TreasuryV1 internal treasury;
    MockERC20 internal token;
    address internal owner;

    constructor(TreasuryV1 _treasury, MockERC20 _token, address _owner) {
        treasury = _treasury;
        token = _token;
        owner = _owner;
        // Pre-approve so safeTransferFrom inside depositERC20 succeeds.
        token.approve(address(treasury), type(uint256).max);
    }

    /// @dev Mint fresh tokens to the handler and deposit them into the treasury.
    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1e24);
        token.mint(address(this), amount);
        try treasury.depositERC20(address(token), amount) {} catch {}
    }

    /// @dev Withdraw a bounded amount from the treasury back to the handler.
    function withdraw(uint256 amount) external {
        uint256 balance = treasury.getERC20Balance(address(token));
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.prank(owner);
        try treasury.transferERC20(address(token), address(this), amount) {} catch {}
    }
}

// ─── Invariant test ───────────────────────────────────────────────────────────

/// @notice Two accounting invariants for TreasuryV1:
///
///   1. totalDeposited[token] ≥ totalWithdrawn[token]
///      — You can never withdraw more than was ever deposited through the
///        official API (the ERC-20 transfer would revert on insufficient balance).
///
///   2. totalDeposited[token] == balance + totalWithdrawn[token]
///      — Exact accounting equality holds when all flows go through the handler
///        (no direct ERC-20 transfers bypassing the treasury interface).
contract TreasuryInvariantTest is Test {
    TreasuryV1 internal treasury;
    MockERC20 internal token;
    TreasuryHandler internal handler;

    address internal owner = makeAddr("owner");

    function setUp() public {
        // Deploy TreasuryV1 behind an ERC1967Proxy.
        TreasuryV1 impl = new TreasuryV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(TreasuryV1.initialize, (owner)));
        treasury = TreasuryV1(payable(address(proxy)));

        // Deploy a fresh ERC-20 for the tests.
        token = new MockERC20("Test Token", "TST");

        // Deploy handler and register it as the sole fuzzing target.
        handler = new TreasuryHandler(treasury, token, owner);
        targetContract(address(handler));
    }

    /// @notice totalDeposited can never fall below totalWithdrawn because the ERC-20
    ///         transfer inside transferERC20 would revert before the state update
    ///         if the balance were insufficient.
    function invariant_DepositedGteWithdrawn() public view {
        assertGe(
            treasury.totalDeposited(address(token)),
            treasury.totalWithdrawn(address(token)),
            "totalDeposited must always be >= totalWithdrawn"
        );
    }

    /// @notice Exact accounting: all tokens deposited are either still in the
    ///         treasury or have been recorded as withdrawn.
    ///         Holds as equality because only the handler interacts with the
    ///         treasury — no external direct ERC-20 transfers.
    function invariant_AccountingEquality() public view {
        uint256 deposited = treasury.totalDeposited(address(token));
        uint256 withdrawn = treasury.totalWithdrawn(address(token));
        uint256 balance = treasury.getERC20Balance(address(token));

        assertEq(deposited, balance + withdrawn, "accounting must hold: deposited == balance + withdrawn");
    }
}
