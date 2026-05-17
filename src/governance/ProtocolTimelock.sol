// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title  ProtocolTimelock
/// @notice Thin wrapper around OZ TimelockController that fixes the constructor signature
///         for clarity and documents the recommended production configuration.
///
/// @dev    PRODUCTION: use minDelay = 172800 (2 days).
///         Tests may use smaller values (e.g. 60 seconds) to keep suites fast.
contract ProtocolTimelock is TimelockController {
    /// @notice Deploys the timelock.
    /// @dev    PRODUCTION minDelay should be 172800 (2 days).
    ///         Testing may use smaller values such as 60 seconds.
    /// @param minDelay   Minimum delay before a queued operation can execute.
    /// @param proposers  Addresses granted the PROPOSER_ROLE (typically the Governor).
    /// @param executors  Addresses granted the EXECUTOR_ROLE (address(0) = anyone).
    /// @param admin      Initial admin; should be renounced after setup.
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
