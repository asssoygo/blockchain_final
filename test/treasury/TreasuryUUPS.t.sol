// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "../../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../../src/treasury/TreasuryV2.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

/// @notice End-to-end UUPS upgrade tests for TreasuryV1 → TreasuryV2.
contract TreasuryUUPSTest is Test {
    // ─── Actors ───────────────────────────────────────────────────────────────

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // ─── Contracts ────────────────────────────────────────────────────────────

    TreasuryV1 internal v1Impl;
    TreasuryV2 internal v2Impl;

    TreasuryV1 internal treasury; // proxy cast as V1
    ERC1967Proxy internal proxy;

    MockERC20 internal token;

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        // Deploy implementations.
        v1Impl = new TreasuryV1();
        v2Impl = new TreasuryV2();

        // Deploy proxy initialised with owner.
        bytes memory initData = abi.encodeCall(TreasuryV1.initialize, (owner));
        proxy = new ERC1967Proxy(address(v1Impl), initData);

        // Cast proxy as V1 for convenience.
        treasury = TreasuryV1(payable(address(proxy)));

        // ERC-20 plumbing.
        token = new MockERC20("Mock", "MCK");
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(treasury), type(uint256).max);
    }

    // ─── 1. Initialize: sets owner ────────────────────────────────────────────

    function test_Initialize_SetsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    // ─── 2. Initialize: reverts on second call ────────────────────────────────

    function test_Initialize_RevertWhen_CalledTwice() public {
        vm.expectRevert();
        treasury.initialize(owner);
    }

    // ─── 3. Constructor disables initializers on the implementation ───────────

    function test_Constructor_DisablesInitializersOnImplementation() public {
        // Calling initialize directly on the bare implementation must revert
        // because _disableInitializers() was called in the constructor.
        vm.expectRevert();
        v1Impl.initialize(owner);
    }

    // ─── 4. depositERC20: tracks balance ──────────────────────────────────────

    function test_DepositERC20() public {
        vm.prank(alice);
        treasury.depositERC20(address(token), 1_000e18);

        assertEq(treasury.totalDeposited(address(token)), 1_000e18);
        assertEq(treasury.getERC20Balance(address(token)), 1_000e18);
    }

    // ─── 5. transferERC20: only owner ────────────────────────────────────────

    function test_TransferERC20_OnlyOwner() public {
        // Fund treasury.
        vm.prank(alice);
        treasury.depositERC20(address(token), 500e18);

        // Non-owner attempt should revert.
        vm.prank(alice);
        vm.expectRevert();
        treasury.transferERC20(address(token), bob, 100e18);
    }

    // ─── 6. transferERC20: insufficient balance ───────────────────────────────

    function test_TransferERC20_RevertWhen_InsufficientBalance() public {
        // Treasury has 0 tokens — asking for 1 should revert at the ERC-20 level.
        vm.prank(owner);
        vm.expectRevert();
        treasury.transferERC20(address(token), bob, 1e18);
    }

    // ─── 7. receive(): tracks ETH and emits event ─────────────────────────────

    function test_ReceiveETH() public {
        vm.deal(alice, 2 ether);

        vm.expectEmit(true, false, false, true);
        emit TreasuryV1.ETHReceived(alice, 1 ether);

        vm.prank(alice);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);

        assertEq(treasury.ethBalance(), 1 ether);
    }

    // ─── 8. transferETH: works ────────────────────────────────────────────────

    function test_TransferETH_Works() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        (bool ok,) = address(treasury).call{value: 3 ether}("");
        assertTrue(ok);

        uint256 bobBefore = bob.balance;

        vm.prank(owner);
        treasury.transferETH(payable(bob), 1 ether);

        assertEq(treasury.ethBalance(), 2 ether);
        assertEq(bob.balance, bobBefore + 1 ether);
    }

    // ─── 9. transferETH: reverts when too much ────────────────────────────────

    function test_TransferETH_RevertWhen_TooMuch() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryV1.InsufficientBalance.selector, 2 ether, 1 ether));
        treasury.transferETH(payable(bob), 2 ether);
    }

    // ─── 10. V1→V2 upgrade preserves state ───────────────────────────────────

    function test_UpgradeToV2_PreservesState() public {
        // Alice deposits before upgrade.
        vm.prank(alice);
        treasury.depositERC20(address(token), 1_000e18);

        assertEq(treasury.totalDeposited(address(token)), 1_000e18);

        // Owner upgrades to V2 and calls initializeV2.
        vm.prank(owner);
        treasury.upgradeToAndCall(address(v2Impl), abi.encodeCall(TreasuryV2.initializeV2, (1 days)));

        // State must be preserved.
        TreasuryV2 treasuryV2 = TreasuryV2(payable(address(proxy)));
        assertEq(treasuryV2.totalDeposited(address(token)), 1_000e18, "totalDeposited lost");
        assertEq(treasuryV2.owner(), owner, "owner lost");
    }

    // ─── 11. V2: spending cap enforced ────────────────────────────────────────

    function test_UpgradeToV2_NewFunctionalityWorks() public {
        // Fund treasury with tokens.
        vm.prank(alice);
        treasury.depositERC20(address(token), 1_000e18);

        // Upgrade.
        vm.prank(owner);
        treasury.upgradeToAndCall(address(v2Impl), abi.encodeCall(TreasuryV2.initializeV2, (1 days)));

        TreasuryV2 treasuryV2 = TreasuryV2(payable(address(proxy)));

        // Set a cap of 100 tokens per window.
        vm.prank(owner);
        treasuryV2.setSpendingCap(address(token), 100e18);

        // First transfer (100 tokens) should succeed.
        vm.prank(owner);
        treasuryV2.transferERC20(address(token), bob, 100e18);

        // Second transfer in the same window should revert with SpendingCapExceeded.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryV2.SpendingCapExceeded.selector, address(token), 1e18, 0));
        treasuryV2.transferERC20(address(token), bob, 1e18);
    }

    // ─── 12. V2: version string updated ──────────────────────────────────────

    function test_UpgradeToV2_VersionUpdated() public {
        assertEq(treasury.version(), "v1.0.0");

        vm.prank(owner);
        treasury.upgradeToAndCall(address(v2Impl), abi.encodeCall(TreasuryV2.initializeV2, (1 days)));

        TreasuryV2 treasuryV2 = TreasuryV2(payable(address(proxy)));
        assertEq(treasuryV2.version(), "v2.0.0");
    }

    // ─── 13. Only owner can upgrade ───────────────────────────────────────────

    function test_UpgradeToV2_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.upgradeToAndCall(address(v2Impl), "");
    }
}
