// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AccessControlVulnerable
/// @notice VULNERABLE example contract demonstrating missing access control.
/// @dev DO NOT USE IN PRODUCTION. Educational purposes only.
///      This is the "Case Study #2: Access Control" required by Section 3.2.
///
///      The bug: privileged functions (changeOwner, withdrawAll) have NO access modifier,
///      so any random address can call them. This is SWC-100 / SWC-105.
contract AccessControlVulnerable {
    address public owner;
    uint256 public criticalParameter;

    event ParameterChanged(uint256 newValue);
    event OwnershipChanged(address indexed newOwner);
    event FundsWithdrawn(address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    /// @notice VULNERABLE: anyone can change the critical parameter.
    /// @dev BUG: missing onlyOwner check.
    function setCriticalParameter(uint256 _value) external {
        criticalParameter = _value;
        emit ParameterChanged(_value);
    }

    /// @notice VULNERABLE: anyone can become the owner.
    /// @dev BUG: missing onlyOwner check. Catastrophic — attacker takes over the contract.
    function changeOwner(address _newOwner) external {
        owner = _newOwner;
        emit OwnershipChanged(_newOwner);
    }

    /// @notice VULNERABLE: anyone can drain ETH from this contract.
    /// @dev BUG: missing onlyOwner check.
    function withdrawAll(address payable _to) external {
        uint256 balance = address(this).balance;
        (bool success,) = _to.call{value: balance}("");
        require(success, "Transfer failed");
        emit FundsWithdrawn(_to, balance);
    }

    /// @notice Accept ETH deposits.
    receive() external payable {}
}
