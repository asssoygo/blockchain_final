// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  Box
/// @notice Simple owned value store used to demonstrate end-to-end governance execution.
///         In the test suite, ownership is transferred to the Timelock so that only a
///         successful governance proposal can call {store}.
contract Box is Ownable {
    uint256 private _value;

    /// @notice Emitted when the stored value changes.
    event ValueChanged(uint256 newValue);

    /// @param _owner Initial owner (should be the ProtocolTimelock in tests).
    constructor(address _owner) Ownable(_owner) {}

    /// @notice Stores a new value. Only callable by the owner (Timelock / governance).
    /// @param newValue The value to persist.
    function store(uint256 newValue) external onlyOwner {
        _value = newValue;
        emit ValueChanged(newValue);
    }

    /// @notice Returns the currently stored value.
    function retrieve() external view returns (uint256) {
        return _value;
    }
}
