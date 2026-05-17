// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReentrancyFixed
/// @notice FIXED version of ReentrancyVulnerable, demonstrating proper mitigation.
/// @dev Two layers of defense:
///      1. Checks-Effects-Interactions (CEI) pattern — state is updated BEFORE the external call
///      2. OpenZeppelin ReentrancyGuard — nonReentrant modifier locks the function during execution
///      This is the "Case Study #1 — fixed version" for Section 3.2.
contract ReentrancyFixed is ReentrancyGuard {
    mapping(address => uint256) public balances;

    error NoBalance();
    error TransferFailed();

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Deposit ETH into the contract.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice FIXED withdraw — updates state BEFORE the external call (CEI),
    ///         and is wrapped in nonReentrant as defense-in-depth.
    /// @dev If attacker tries to re-enter via receive(), balances[msg.sender] is already 0,
    ///      so the NoBalance check reverts. Additionally, nonReentrant blocks re-entry at the modifier level.
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NoBalance();

        // CEI: Effect (state update) BEFORE Interaction (external call).
        balances[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the contract's total ETH balance.
    function totalBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
