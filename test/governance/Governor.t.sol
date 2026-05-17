// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernanceToken} from "../../src/token/GovernanceToken.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {Box} from "../../src/governance/Box.sol";

/// @notice Full lifecycle tests for ProtocolGovernor + ProtocolTimelock + Box.
contract GovernorTest is Test {
    // ─── Actors ───────────────────────────────────────────────────────────────

    address internal deployer = makeAddr("deployer");
    address internal proposer = makeAddr("proposer");
    address internal voter = makeAddr("voter");
    address internal delegatee = makeAddr("delegatee");

    // Addresses consumed by GovernanceToken constructor (not used in governance tests).
    address internal treasury = makeAddr("treasury");
    address internal airdrop = makeAddr("airdrop");
    address internal liquidity = makeAddr("liquidity");

    // ─── Contracts ────────────────────────────────────────────────────────────

    GovernanceToken internal token;
    ProtocolTimelock internal timelock;
    ProtocolGovernor internal governor;
    Box internal box;

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 internal constant PROPOSAL_THRESHOLD = 1_000e18;
    uint256 internal constant QUORUM_TOKENS = 40_000e18; // 4 % of 1 000 000 GOV
    uint256 internal constant TIMELOCK_DELAY = 60; // seconds (test value)

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy GovernanceToken.
        //    Constructor mints: deployer=400k, treasury=300k, airdrop=200k, liquidity=100k.
        token = new GovernanceToken(treasury, airdrop, liquidity);

        // 2. Distribute tokens to test actors.
        //    proposer: 2 000 GOV (> threshold, < quorum)
        //    voter:    100 000 GOV (> quorum)
        token.transfer(proposer, 2_000e18);
        token.transfer(voter, 100_000e18);

        // 3. Deploy timelock with minDelay = 60 s; no initial proposers/executors.
        address[] memory emptyProposers = new address[](0);
        address[] memory emptyExecutors = new address[](0);
        timelock = new ProtocolTimelock(TIMELOCK_DELAY, emptyProposers, emptyExecutors, deployer);

        // 4. Deploy governor.
        governor = new ProtocolGovernor(IVotes(address(token)), timelock);

        // 5. Wire up roles.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0)); // anyone can execute
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Deploy Box owned by timelock — only governance can call store().
        box = new Box(address(timelock));

        vm.stopPrank();

        // 7. Delegates: each actor self-delegates so voting power registers.
        vm.prank(proposer);
        token.delegate(proposer);

        vm.prank(voter);
        token.delegate(voter);

        // 8. Roll forward one block so checkpoint is past the current block.
        vm.roll(block.number + 1);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Build a simple proposal to call box.store(value).
    function _buildProposal(uint256 value)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(box);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(Box.store, (value));
        description = "Store a new value in Box";
    }

    /// @dev Propose, vote For, queue, and execute a proposal; returns the new Box value.
    function _passProposal(uint256 value) internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(value);

        // Propose.
        vm.prank(proposer);
        proposalId = governor.propose(targets, vals, calldatas, description);

        // Wait out the voting delay.
        vm.roll(block.number + governor.votingDelay() + 1);

        // Vote for with sufficient voting power.
        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        // Wait out the voting period.
        vm.roll(block.number + governor.votingPeriod());

        // Queue.
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, vals, calldatas, descHash);

        // Warp past timelock delay.
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute.
        governor.execute(targets, vals, calldatas, descHash);
    }

    // ─── 1. ProposalCreation ─────────────────────────────────────────────────

    function test_ProposalCreation() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    // ─── 2. ProposalCreation: below threshold reverts ────────────────────────

    function test_ProposalCreation_RevertWhen_BelowThreshold() public {
        address nobody = makeAddr("nobody");
        // nobody has 0 tokens → below proposalThreshold

        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(nobody);
        vm.expectRevert();
        governor.propose(targets, vals, calldatas, description);
    }

    // ─── 3. State transitions to Active after voting delay ───────────────────

    function test_VotingDelay_StateProgressesToActive() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);

        // Should be Pending immediately.
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // Roll past the voting delay.
        vm.roll(block.number + governor.votingDelay() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));
    }

    // ─── 4. CastVote For ─────────────────────────────────────────────────────

    function test_CastVoteFor() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertEq(againstVotes, 0);
    }

    // ─── 5. CastVote Against ─────────────────────────────────────────────────

    function test_CastVoteAgainst() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));

        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertGt(againstVotes, 0);
        assertEq(forVotes, 0);
    }

    // ─── 6. CastVote Abstain ─────────────────────────────────────────────────

    function test_CastVoteAbstain() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Abstain));

        (,, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertGt(abstainVotes, 0);
    }

    // ─── 7. Quorum not met → Defeated ────────────────────────────────────────

    function test_QuorumNotMet_ProposalDefeated() public {
        // proposer has only 2_000 GOV (< 4 % quorum of 40_000 GOV).
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        // Only the proposer (2 000 GOV) votes For — quorum not reached.
        vm.prank(proposer);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        // Roll past voting period.
        vm.roll(block.number + governor.votingPeriod());

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    // ─── 8. Proposal Succeeded after quorum ──────────────────────────────────

    function test_ProposalSucceededAfterQuorum() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        // voter has 100 000 GOV (> quorum).
        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + governor.votingPeriod());

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    // ─── 9. Queue after Succeeded ────────────────────────────────────────────

    function test_QueueAfterSuccess() public {
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(1);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + governor.votingPeriod());

        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, vals, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));
    }

    // ─── 10. Execute after timelock delay ────────────────────────────────────

    function test_ExecuteAfterTimelock() public {
        uint256 newValue = 99;
        (address[] memory targets, uint256[] memory vals, bytes[] memory calldatas, string memory description) =
            _buildProposal(newValue);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, vals, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + governor.votingPeriod());

        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, vals, calldatas, descHash);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, vals, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(box.retrieve(), newValue);
    }

    // ─── 11. Full lifecycle: propose → vote → queue → execute ────────────────

    function test_FullLifecycle() public {
        uint256 magic = 42;
        _passProposal(magic);
        assertEq(box.retrieve(), magic, "Box value mismatch after full lifecycle");
    }

    // ─── 12. Delegate voting ─────────────────────────────────────────────────

    function test_DelegateVoting() public {
        // voter re-delegates to delegatee.
        uint256 voterPower = token.balanceOf(voter);

        vm.prank(voter);
        token.delegate(delegatee);

        // Roll so checkpoint registers.
        vm.roll(block.number + 1);

        assertEq(token.getVotes(delegatee), voterPower, "delegatee should hold voter's power");
        assertEq(token.getVotes(voter), 0, "voter should have 0 power after delegating away");
    }
}
