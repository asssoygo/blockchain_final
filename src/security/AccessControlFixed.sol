// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AccessControlFixed
/// @notice FIXED version of AccessControlVulnerable, demonstrating proper access control.
/// @dev Uses OpenZeppelin's Ownable for the simplest case (single admin).
///      In production, prefer AccessControl with named roles (we use both patterns in the protocol:
///      Ownable for simple cases, AccessControl on Timelock, and Timelock-as-owner for the most
///      sensitive permissions like UUPS upgrades).
///      This is the "Case Study #2 — fixed version" for Section 3.2.
contract AccessControlFixed is Ownable {
    uint256 public criticalParameter;

    error TransferFailed();

    event ParameterChanged(uint256 newValue);
    event FundsWithdrawn(address indexed to, uint256 amount);

    constructor(address _owner) Ownable(_owner) {}

    /// @notice FIXED: only owner can change the critical parameter.
    function setCriticalParameter(uint256 _value) external onlyOwner {
        criticalParameter = _value;
        emit ParameterChanged(_value);
    }

    /// @notice FIXED: ownership transfer goes through Ownable's transferOwnership(),
    ///         which is onlyOwner-protected and uses two-step ownership when desired (Ownable2Step).
    /// @dev Note: we deliberately do NOT expose a public changeOwner() here.
    ///      Use the inherited Ownable.transferOwnership(newOwner) instead.

    /// @notice FIXED: only owner can withdraw funds.
    function withdrawAll(address payable _to) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = _to.call{value: balance}("");
        if (!success) revert TransferFailed();
        emit FundsWithdrawn(_to, balance);
    }

    receive() external payable {}
}
