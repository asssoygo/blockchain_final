// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {GovernanceToken} from "../../src/token/GovernanceToken.sol";

// ─── Handler ──────────────────────────────────────────────────────────────────

/// @dev Wraps GovernanceToken with bounded delegate and transfer calls so the
///      invariant fuzzer can explore voting-power states without triggering reverts.
contract GovernorHandler is CommonBase, StdCheats, StdUtils {
    GovernanceToken internal token;
    address[] internal actors;

    constructor(GovernanceToken _token, address[] memory _actors) {
        token = _token;
        actors = _actors;
    }

    /// @dev Re-delegates voting power from one tracked actor to another.
    function delegate(uint256 fromIdx, uint256 toIdx) external {
        fromIdx = bound(fromIdx, 0, actors.length - 1);
        toIdx = bound(toIdx, 0, actors.length - 1);
        vm.prank(actors[fromIdx]);
        token.delegate(actors[toIdx]);
    }

    /// @dev Transfers a bounded amount of tokens between two tracked actors.
    function transfer(uint256 fromIdx, uint256 toIdx, uint256 amount) external {
        fromIdx = bound(fromIdx, 0, actors.length - 1);
        toIdx = bound(toIdx, 0, actors.length - 1);
        uint256 balance = token.balanceOf(actors[fromIdx]);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.prank(actors[fromIdx]);
        token.transfer(actors[toIdx], amount);
    }
}

// ─── Invariant test ───────────────────────────────────────────────────────────

/// @notice Invariant: the sum of all tracked actors' ERC20Votes voting power
///         must never exceed the total token supply.
///
///         This catches bugs such as double-counting delegations, checkpoint
///         overflows, or ghost votes created by mints without supply tracking.
contract GovernorInvariantTest is Test {
    GovernanceToken internal token;
    GovernorHandler internal handler;

    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        address trs = makeAddr("treasury");
        address air = makeAddr("airdrop");
        address liq = makeAddr("liquidity");

        // GovernanceToken mints: deployer=400k, trs=300k, air=200k, liq=100k.
        vm.prank(deployer);
        token = new GovernanceToken(trs, air, liq);

        // Four active actors each receive 20 000 GOV from the deployer.
        address a0 = makeAddr("actor0");
        address a1 = makeAddr("actor1");
        address a2 = makeAddr("actor2");
        address a3 = makeAddr("actor3");

        vm.startPrank(deployer);
        token.transfer(a0, 20_000e18);
        token.transfer(a1, 20_000e18);
        token.transfer(a2, 20_000e18);
        token.transfer(a3, 20_000e18);
        vm.stopPrank();

        // Build actors array — includes deployer, trs, air, liq so the invariant
        // accounts for all known token holders.
        actors.push(a0);
        actors.push(a1);
        actors.push(a2);
        actors.push(a3);
        actors.push(deployer);
        actors.push(trs);
        actors.push(air);
        actors.push(liq);

        // Each actor self-delegates so voting power is live from the start.
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            token.delegate(actors[i]);
        }

        // Roll one block so checkpoints record the delegations.
        vm.roll(block.number + 1);

        // Handler targets only the 4 active actors to keep fuzzing productive.
        address[] memory handlerActors = new address[](4);
        handlerActors[0] = a0;
        handlerActors[1] = a1;
        handlerActors[2] = a2;
        handlerActors[3] = a3;

        handler = new GovernorHandler(token, handlerActors);
        targetContract(address(handler));
    }

    /// @notice The sum of all tracked actors' current voting power must never
    ///         exceed the total token supply.
    ///
    ///         Math: each unit of token can be delegated to exactly one address at
    ///         any time, so the total delegated power ≤ totalSupply.
    function invariant_TotalVotingPowerLeqTotalSupply() public view {
        uint256 totalVotingPower;
        for (uint256 i = 0; i < actors.length; i++) {
            totalVotingPower += token.getVotes(actors[i]);
        }
        assertLe(totalVotingPower, token.totalSupply(), "voting power sum must never exceed total supply");
    }
}
