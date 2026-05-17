// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {MockAggregator} from "../../src/oracle/MockAggregator.sol";

contract PriceOracleTest is Test {
    PriceOracle internal oracle;
    MockAggregator internal mock;

    address internal owner;
    address internal alice;

    // ETH/USD: 8-decimal Chainlink feed, initial answer = $2 000.00000000
    uint8 internal constant DECIMALS = 8;
    int256 internal constant INITIAL_ANSWER = 2_000_00000000;
    uint256 internal constant DEFAULT_MAX_AGE = 3600;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");

        mock = new MockAggregator(DECIMALS, INITIAL_ANSWER);
        oracle = new PriceOracle(address(mock), DEFAULT_MAX_AGE, "ETH/USD", owner);
    }

    // ─── 1. getLatestPrice returns correct data ────────────────────────────────

    function test_GetLatestPrice_ReturnsCorrectData() public view {
        (int256 price, uint8 decimals, uint256 updatedAt) = oracle.getLatestPrice();

        assertEq(price, INITIAL_ANSWER, "price matches initial answer");
        assertEq(decimals, DECIMALS, "decimals match feed");
        assertEq(updatedAt, block.timestamp, "updatedAt is current");
    }

    // ─── 2. getPriceWithStalenessCheck passes for fresh price ─────────────────

    function test_GetPriceWithStalenessCheck_FreshPrice() public view {
        int256 price = oracle.getPriceWithStalenessCheck(DEFAULT_MAX_AGE);
        assertEq(price, INITIAL_ANSWER, "fresh price returned");
    }

    // ─── 3. getPriceWithStalenessCheck reverts for stale price ────────────────

    function test_GetPriceWithStalenessCheck_StalePrice_Reverts() public {
        uint256 priceUpdatedAt = mock.updatedAt();
        vm.warp(block.timestamp + 7200);

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracle.StalePrice.selector, priceUpdatedAt, block.timestamp, uint256(DEFAULT_MAX_AGE)
            )
        );
        oracle.getPriceWithStalenessCheck(DEFAULT_MAX_AGE);
    }

    // ─── 4. getPrice uses the default max age ─────────────────────────────────

    function test_GetPrice_UsesDefaultMaxAge() public view {
        int256 price = oracle.getPrice();
        assertEq(price, INITIAL_ANSWER, "getPrice returns initial answer when fresh");
    }

    // ─── 5. getPrice reverts when price is stale by default window ────────────

    function test_GetPrice_RevertWhen_StaleByDefault() public {
        uint256 priceUpdatedAt = mock.updatedAt();
        vm.warp(block.timestamp + DEFAULT_MAX_AGE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(PriceOracle.StalePrice.selector, priceUpdatedAt, block.timestamp, DEFAULT_MAX_AGE)
        );
        oracle.getPrice();
    }

    // ─── 6. getLatestPrice reverts on negative price ──────────────────────────

    function test_GetLatestPrice_RevertWhen_InvalidPrice() public {
        mock.setAnswer(-1);

        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, int256(-1)));
        oracle.getLatestPrice();
    }

    // ─── 7. getLatestPrice reverts on incomplete round ────────────────────────

    function test_GetLatestPrice_RevertWhen_IncompleteRound() public {
        mock.setIncompleteRound();

        vm.expectRevert(PriceOracle.IncompleteRound.selector);
        oracle.getLatestPrice();
    }

    // ─── 8. setPriceFeed is restricted to owner ───────────────────────────────

    function test_SetPriceFeed_OnlyOwner() public {
        MockAggregator newMock = new MockAggregator(DECIMALS, INITIAL_ANSWER);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        oracle.setPriceFeed(address(newMock));
    }

    // ─── 9. setDefaultMaxAge is restricted to owner ───────────────────────────

    function test_SetDefaultMaxAge_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        oracle.setDefaultMaxAge(7200);
    }

    // ─── 10. setDefaultMaxAge reverts on zero ─────────────────────────────────

    function test_SetDefaultMaxAge_RevertWhen_Zero() public {
        vm.prank(owner);
        vm.expectRevert(PriceOracle.InvalidMaxAge.selector);
        oracle.setDefaultMaxAge(0);
    }

    // ─── 11. setPriceFeed updates the feed and emits event ────────────────────

    function test_SetPriceFeed_UpdatesAndEmits() public {
        MockAggregator newMock = new MockAggregator(DECIMALS, 3_000_00000000);
        address oldFeed = address(mock);

        vm.expectEmit(true, true, false, false);
        emit PriceOracle.PriceFeedUpdated(oldFeed, address(newMock));

        vm.prank(owner);
        oracle.setPriceFeed(address(newMock));

        assertEq(address(oracle.priceFeed()), address(newMock), "feed updated");
    }

    // ─── 12. setDefaultMaxAge updates and emits event ─────────────────────────

    function test_SetDefaultMaxAge_UpdatesAndEmits() public {
        uint256 newAge = 7200;

        vm.expectEmit(false, false, false, true);
        emit PriceOracle.DefaultMaxAgeUpdated(DEFAULT_MAX_AGE, newAge);

        vm.prank(owner);
        oracle.setDefaultMaxAge(newAge);

        assertEq(oracle.defaultMaxAge(), newAge, "defaultMaxAge updated");
    }
}
