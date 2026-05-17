// TEST-ONLY CONTRACT — DO NOT USE IN PRODUCTION
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal mintable ERC20 used exclusively in test suites.
///         Anyone can call mint() — there is intentionally no access control.
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @notice Mints `amount` tokens to `to`. No access control — test use only.
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
