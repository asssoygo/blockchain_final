// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ReentrancyVulnerable
/// @notice VULNERABLE example contract demonstrating the classic reentrancy bug.
/// @dev DO NOT USE IN PRODUCTION. Educational purposes only — see ReentrancyFixed.sol
///      for the corrected version. This is the "Case Study #1: Reentrancy" required
///      by the assignment's Section 3.2 security requirements.
///
///      The bug: external call (ETH send) happens BEFORE the state update,
///      allowing the recipient to re-enter withdraw() and drain the contract.
///      This is the same pattern that caused the 2016 DAO hack ($60M loss).
contract ReentrancyVulnerable {
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Deposit ETH into the contract.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice VULNERABLE withdraw — sends ETH BEFORE updating state.
    /// @dev SWC-107: Reentrancy. Attacker re-enters via receive() and drains the contract.
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");

        // BUG: external call happens BEFORE state update.
        // Recipient's receive() can call withdraw() again,
        // because balances[msg.sender] has not been zeroed yet.
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        // This line executes AFTER recursive calls drain the contract.
        balances[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the contract's total ETH balance.
    function totalBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
