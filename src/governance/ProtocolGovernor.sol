// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title  ProtocolGovernor
/// @notice On-chain governance contract for the DeFi Super-App protocol.
///
/// @dev    Composes the standard OZ v5 Governor extension set:
///           - GovernorSettings      — configurable delay, period, threshold
///           - GovernorCountingSimple — For / Against / Abstain vote counting
///           - GovernorVotes          — voting power from an IVotes token
///           - GovernorVotesQuorumFraction — quorum as a % of total supply
///           - GovernorTimelockControl    — routes execution through TimelockController
///
///         ACTIVE (test-friendly) values:
///           votingDelay       = 1 block
///           votingPeriod      = 50 blocks
///           proposalThreshold = 1 000 GOV  (1_000e18)
///           quorum            = 4 %
///
///         PRODUCTION values (commented):
///           votingDelay       = 7 200 blocks (~1 day on Arbitrum One at 12 s/block)
///           votingPeriod      = 50 400 blocks (~1 week)
///           proposalThreshold = 10 000e18    (1 % of 1 000 000 GOV supply)
///           quorum            = 4 %
contract ProtocolGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Deploys the governor bound to `_token` for voting power and `_timelock` for execution.
    /// @param _token    IVotes-compatible governance token (GovernanceToken).
    /// @param _timelock ProtocolTimelock that executes queued proposals.
    constructor(IVotes _token, TimelockController _timelock)
        Governor("ProtocolGovernor")
        GovernorSettings(
            1, // votingDelay:       1 block  (PRODUCTION: 7200)
            50, // votingPeriod:      50 blocks (PRODUCTION: 50400)
            1_000e18 // proposalThreshold: 1 000 GOV (PRODUCTION: 10_000e18)
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4 % quorum
        GovernorTimelockControl(_timelock)
    {}

    // ─── Required OZ v5 Overrides ─────────────────────────────────────────────

    /// @inheritdoc GovernorSettings
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @inheritdoc GovernorSettings
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @inheritdoc GovernorSettings
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @inheritdoc GovernorVotesQuorumFraction
    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    /// @inheritdoc GovernorTimelockControl
    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    /// @inheritdoc GovernorTimelockControl
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @inheritdoc GovernorTimelockControl
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorTimelockControl
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorTimelockControl
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorTimelockControl
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
