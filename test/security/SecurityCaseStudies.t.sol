// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyVulnerable} from "../../src/security/ReentrancyVulnerable.sol";
import {ReentrancyFixed} from "../../src/security/ReentrancyFixed.sol";
import {AccessControlVulnerable} from "../../src/security/AccessControlVulnerable.sol";
import {AccessControlFixed} from "../../src/security/AccessControlFixed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Attacker contract that recursively re-enters withdraw() to drain ETH.
/// @dev Used in test_Reentrancy_Vulnerable_IsExploitable.
contract ReentrancyAttacker {
    ReentrancyVulnerable public target;
    uint256 public stolen;

    constructor(address _target) {
        target = ReentrancyVulnerable(_target);
    }

    function attack() external payable {
        require(msg.value == 1 ether, "Send 1 ETH");
        target.deposit{value: 1 ether}();
        target.withdraw();
    }

    receive() external payable {
        if (address(target).balance >= 1 ether) {
            target.withdraw();
        } else {
            stolen = address(this).balance;
        }
    }
}

/// @notice Attacker contract that tries the same exploit against the FIXED contract.
contract ReentrancyAttackerFailed {
    ReentrancyFixed public target;

    constructor(address _target) {
        target = ReentrancyFixed(_target);
    }

    function attack() external payable {
        require(msg.value == 1 ether, "Send 1 ETH");
        target.deposit{value: 1 ether}();
        target.withdraw();
    }

    receive() external payable {
        // Attempt re-entry. Will revert due to nonReentrant + zeroed balance.
        if (address(target).balance >= 1 ether) {
            target.withdraw();
        }
    }
}

/// @title SecurityCaseStudies
/// @notice Reproduces two well-known vulnerability classes (reentrancy, access control)
///         in their VULNERABLE form, demonstrates the exploit, then proves the FIXED
///         versions resist the same attack. This satisfies the assignment's Section 3.2
///         requirement for two reproduced-and-fixed case studies with before/after tests.
contract SecurityCaseStudies is Test {
    // =======================================================
    // CASE STUDY #1: REENTRANCY
    // =======================================================

    function test_Reentrancy_Vulnerable_IsExploitable() public {
        ReentrancyVulnerable vulnerable = new ReentrancyVulnerable();

        // Seed the contract with 5 ETH from honest users.
        address honest1 = makeAddr("honest1");
        address honest2 = makeAddr("honest2");
        vm.deal(honest1, 2 ether);
        vm.deal(honest2, 3 ether);
        vm.prank(honest1);
        vulnerable.deposit{value: 2 ether}();
        vm.prank(honest2);
        vulnerable.deposit{value: 3 ether}();

        assertEq(address(vulnerable).balance, 5 ether, "setup: 5 ETH in vault");

        // Attacker deposits 1 ETH and exploits the reentrancy.
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(vulnerable));
        vm.deal(address(attacker), 1 ether);
        attacker.attack{value: 1 ether}();

        // Attacker drained the entire vault: 1 ETH deposit -> withdrew all 6 ETH.
        assertEq(address(vulnerable).balance, 0, "vault drained");
        assertGt(address(attacker).balance, 1 ether, "attacker profited");
    }

    function test_Reentrancy_Fixed_BlocksTheSameAttack() public {
        ReentrancyFixed fixed_ = new ReentrancyFixed();

        // Same setup as the vulnerable test.
        address honest1 = makeAddr("honest1");
        address honest2 = makeAddr("honest2");
        vm.deal(honest1, 2 ether);
        vm.deal(honest2, 3 ether);
        vm.prank(honest1);
        fixed_.deposit{value: 2 ether}();
        vm.prank(honest2);
        fixed_.deposit{value: 3 ether}();

        assertEq(address(fixed_).balance, 5 ether);

        // Attacker tries the same exploit. Should revert due to ReentrancyGuard.
        ReentrancyAttackerFailed attacker = new ReentrancyAttackerFailed(address(fixed_));
        vm.deal(address(attacker), 1 ether);

        // The recursive call inside receive() triggers ReentrancyGuard's revert,
        // which propagates and reverts the entire attack() call.
        vm.expectRevert();
        attacker.attack{value: 1 ether}();

        // Vault is intact, honest users' funds are safe.
        assertEq(address(fixed_).balance, 5 ether, "vault untouched");
    }

    // =======================================================
    // CASE STUDY #2: ACCESS CONTROL
    // =======================================================

    function test_AccessControl_Vulnerable_AnyoneCanTakeOver() public {
        AccessControlVulnerable vulnerable = new AccessControlVulnerable();
        address legitimateOwner = address(this);
        address attacker = makeAddr("attacker");

        assertEq(vulnerable.owner(), legitimateOwner, "owner is deployer");

        // Anyone can change the critical parameter.
        vm.prank(attacker);
        vulnerable.setCriticalParameter(999);
        assertEq(vulnerable.criticalParameter(), 999, "attacker changed param");

        // Anyone can take over ownership.
        vm.prank(attacker);
        vulnerable.changeOwner(attacker);
        assertEq(vulnerable.owner(), attacker, "attacker is now owner");

        // Anyone can drain ETH.
        vm.deal(address(vulnerable), 10 ether);
        vm.prank(attacker);
        vulnerable.withdrawAll(payable(attacker));
        assertEq(address(vulnerable).balance, 0, "ETH drained");
        assertEq(attacker.balance, 10 ether, "attacker received funds");
    }

    function test_AccessControl_Fixed_RejectsUnauthorizedCallers() public {
        address legitimateOwner = makeAddr("owner");
        AccessControlFixed fixed_ = new AccessControlFixed(legitimateOwner);
        address attacker = makeAddr("attacker");

        // Attacker cannot change parameter.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fixed_.setCriticalParameter(999);

        // Attacker cannot transfer ownership.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fixed_.transferOwnership(attacker);

        // Attacker cannot withdraw.
        vm.deal(address(fixed_), 10 ether);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fixed_.withdrawAll(payable(attacker));

        // Legitimate owner CAN do all of the above.
        vm.prank(legitimateOwner);
        fixed_.setCriticalParameter(42);
        assertEq(fixed_.criticalParameter(), 42);

        vm.prank(legitimateOwner);
        fixed_.withdrawAll(payable(legitimateOwner));
        assertEq(address(fixed_).balance, 0);
        assertEq(legitimateOwner.balance, 10 ether);
    }
}
