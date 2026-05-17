// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// TEST-ONLY CONTRACT — DO NOT DEPLOY TO PRODUCTION

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title  MockAggregator
/// @notice Minimal mock of Chainlink's AggregatorV3Interface for unit testing the PriceOracle.
///         Supports simulating stale prices and incomplete rounds.
contract MockAggregator is AggregatorV3Interface {
    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The current price answer returned by the mock.
    int256 public answer;

    /// @notice Timestamp the price was last updated (set to block.timestamp on each setAnswer call).
    uint256 public updatedAt;

    /// @notice Number of decimals the answer is expressed in.
    uint8 public override decimals;

    /// @notice Human-readable description of the feed.
    string public override description;

    /// @notice Feed version (always 1 in this mock).
    uint256 public override version;

    uint80 private currentRoundId;
    bool private isIncomplete;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _decimals      Decimal precision of the answer (e.g. 8 for Chainlink USD feeds).
    /// @param _initialAnswer Initial price answer.
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        answer = _initialAnswer;
        updatedAt = block.timestamp;
        currentRoundId = 1;
        version = 1;
        description = "Mock Aggregator";
    }

    // ─── Mutators (test helpers) ──────────────────────────────────────────────

    /// @notice Updates the price answer, increments the round, and refreshes updatedAt.
    /// @param _answer New price answer.
    function setAnswer(int256 _answer) external {
        answer = _answer;
        currentRoundId++;
        updatedAt = block.timestamp;
        isIncomplete = false;
    }

    /// @notice Manually overrides the updatedAt timestamp (used to simulate stale prices).
    /// @param _updatedAt New value for updatedAt.
    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    /// @notice Flags the current round as incomplete (answeredInRound = roundId - 1).
    function setIncompleteRound() external {
        isIncomplete = true;
    }

    // ─── AggregatorV3Interface ────────────────────────────────────────────────

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        uint80 _answeredInRound = isIncomplete ? currentRoundId - 1 : currentRoundId;
        return (currentRoundId, answer, updatedAt, updatedAt, _answeredInRound);
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        uint80 _answeredInRound = isIncomplete ? currentRoundId - 1 : currentRoundId;
        return (currentRoundId, answer, updatedAt, updatedAt, _answeredInRound);
    }
}
