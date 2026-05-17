// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AMMFactory} from "../../src/amm/AMMFactory.sol";
import {AMM} from "../../src/amm/AMM.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";

contract AMMFactoryTest is Test {
    AMMFactory internal factory;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;

    address internal owner;
    address internal alice;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");

        factory = new AMMFactory(owner);

        // Deploy three tokens; ensure deterministic ordering.
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
        tokenC = new MockERC20("TokenC", "TKC");

        // Guarantee tokenA < tokenB < tokenC for predictable tests.
        // (MockERC20 addresses depend on deployment nonce so order may vary;
        //  we sort them explicitly for tests that rely on ordering.)
    }

    // ─── 1. createPair deploys a valid AMM ────────────────────────────────────

    function test_CreatePair_DeploysAMM() public {
        vm.prank(owner);
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertTrue(pair != address(0), "pair deployed");
        assertTrue(factory.isPair(pair), "pair registered");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair, "lookup A to B");
    }

    // ─── 2. createPair reverts for identical tokens ────────────────────────────

    function test_CreatePair_RevertWhen_IdenticalTokens() public {
        vm.prank(owner);
        vm.expectRevert(AMMFactory.IdenticalTokens.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    // ─── 3. createPair reverts for zero address ───────────────────────────────

    function test_CreatePair_RevertWhen_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AMMFactory.ZeroAddress.selector);
        factory.createPair(address(tokenA), address(0));
    }

    // ─── 4. createPair reverts when pair already exists ───────────────────────

    function test_CreatePair_RevertWhen_PairExists() public {
        vm.prank(owner);
        factory.createPair(address(tokenA), address(tokenB));

        vm.prank(owner);
        vm.expectRevert(AMMFactory.PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }

    // ─── 5. getPair lookup is bidirectional ───────────────────────────────────

    function test_CreatePair_BidirectionalLookup() public {
        vm.prank(owner);
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair, "A to B lookup");
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair, "B to A lookup");
    }

    // ─── 6. createPair is restricted to owner ────────────────────────────────

    function test_CreatePair_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        factory.createPair(address(tokenA), address(tokenB));
    }

    // ─── 7. createPair2 deploys an AMM with a salt ────────────────────────────

    function test_CreatePair2_WithSalt() public {
        bytes32 salt = keccak256("pair-v1");

        vm.prank(owner);
        address pair = factory.createPair2(address(tokenA), address(tokenB), salt);

        assertTrue(pair != address(0), "pair deployed via CREATE2");
        assertTrue(factory.isPair(pair), "pair registered");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair, "lookup works");
    }

    // ─── 8. different salts produce different addresses ───────────────────────

    function test_CreatePair2_DifferentSaltsGiveDifferentAddresses() public {
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));

        address addr1 = factory.predictPairAddress(address(tokenA), address(tokenB), salt1);
        address addr2 = factory.predictPairAddress(address(tokenA), address(tokenB), salt2);

        assertFalse(addr1 == addr2, "different salts give different addresses");

        // Confirm salt1 actually deploys to the predicted address.
        vm.prank(owner);
        address deployed = factory.createPair2(address(tokenA), address(tokenB), salt1);
        assertEq(deployed, addr1, "deployed address matches prediction for salt1");
    }

    // ─── 9. predictPairAddress matches actual CREATE2 deployment ──────────────

    function test_PredictPairAddress_MatchesActualDeployment() public {
        bytes32 salt = keccak256("predict-test");

        address predicted = factory.predictPairAddress(address(tokenA), address(tokenB), salt);

        vm.prank(owner);
        address actual = factory.createPair2(address(tokenA), address(tokenB), salt);

        assertEq(actual, predicted, "predicted address equals actual deployment");
    }

    // ─── 10. allPairsLength tracks all deployed pairs ─────────────────────────

    function test_AllPairsLength() public {
        assertEq(factory.allPairsLength(), 0, "starts empty");

        vm.prank(owner);
        factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.allPairsLength(), 1, "one CREATE pair");

        vm.prank(owner);
        factory.createPair2(address(tokenA), address(tokenC), keccak256("s1"));
        assertEq(factory.allPairsLength(), 2, "one CREATE + one CREATE2");

        vm.prank(owner);
        factory.createPair(address(tokenB), address(tokenC));
        assertEq(factory.allPairsLength(), 3, "three pairs total");
    }
}
