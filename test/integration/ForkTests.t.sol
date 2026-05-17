// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceOracle} from "../../src/oracle/PriceOracle.sol";
import {AMM} from "../../src/amm/AMM.sol";
import {MockERC20} from "../../src/amm/MockERC20.sol";
import {GovernanceToken} from "../../src/token/GovernanceToken.sol";

/// @notice Fork tests that pin specific mainnet blocks and interact with live contracts.
///         Each test calls _forkOrSkip() first; if the RPC is unavailable the test is
///         marked SKIP rather than FAIL so CI never breaks on a network outage.
contract ForkTest is Test {
    // ─── Mainnet constants ────────────────────────────────────────────────────

    /// @dev Real USDC on Ethereum mainnet (6 decimals, upgradeable proxy).
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev Chainlink ETH/USD aggregator on mainnet.
    address constant CHAINLINK_ETH_USD_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev Block to pin for all fork tests — ~Sep 2024, ETH ≈ $2 400.
    uint256 constant FORK_BLOCK = 21_000_000;

    // ─── Helper ───────────────────────────────────────────────────────────────

    /// @dev Creates and selects a fork, or skips the test if the RPC is unreachable.
    ///      Uses try/catch on the external vm.createFork call so a downed public RPC
    ///      never turns a fork test into a hard failure.
    function _forkOrSkip(uint256 blockNumber) internal {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        try vm.createFork(rpcUrl, blockNumber) returns (uint256 forkId) {
            vm.selectFork(forkId);
        } catch {
            emit log_string("SKIP: mainnet fork unavailable - set MAINNET_RPC_URL or check connectivity");
            vm.skip(true);
        }
    }

    // ─── 1. PriceOracle reads a live Chainlink ETH/USD feed ──────────────────

    /// @notice Deploys PriceOracle against the real Chainlink ETH/USD aggregator
    ///         and verifies the price is within a sane ETH range.
    function test_Fork_PriceOracle_ReadsRealChainlinkETHUSD() public {
        _forkOrSkip(FORK_BLOCK);

        // Use a generous 1-day staleness window since the fork's block.timestamp
        // and the feed's updatedAt can differ from wall-clock time.
        PriceOracle oracle = new PriceOracle(CHAINLINK_ETH_USD_MAINNET, 86_400, "ETH/USD", address(this));

        (int256 price, uint8 decimals, uint256 updatedAt) = oracle.getLatestPrice();

        emit log_named_decimal_int("ETH/USD price (raw 8-decimal)", price, 8);
        emit log_named_uint("Updated at (unix)", updatedAt);

        assertEq(decimals, 8, "Chainlink ETH/USD uses 8 decimals");
        assertGt(price, 1_000e8, "ETH price sanity: must be > $1 000");
        assertLt(price, 10_000e8, "ETH price sanity: must be < $10 000");
    }

    // ─── 2. AMM swap with real USDC on mainnet ────────────────────────────────

    /// @notice Adds liquidity with real mainnet USDC and a freshly deployed MockERC20,
    ///         then executes a swap and verifies the output matches getAmountOut.
    ///         Uses vm.deal to fund USDC without requiring whale approvals or blacklist checks.
    function test_Fork_AMM_SwapWithRealUSDC() public {
        _forkOrSkip(FORK_BLOCK);

        IERC20 usdc = IERC20(USDC_MAINNET);

        // Deploy a second token to pair with USDC.
        MockERC20 mockWETH = new MockERC20("Wrapped Ether Mock", "mWETH");

        // Fund test contract with USDC via deal (bypasses USDC blacklist / access controls).
        deal(USDC_MAINNET, address(this), 200_000e6);
        mockWETH.mint(address(this), 200_000e18);

        // Deploy AMM — constructor sorts pair by address.
        AMM amm = new AMM(USDC_MAINNET, address(mockWETH));
        bool usdcIsToken0 = (USDC_MAINNET == address(amm.token0()));

        usdc.approve(address(amm), type(uint256).max);
        mockWETH.approve(address(amm), type(uint256).max);

        // Add initial liquidity (first deposit → any ratio is valid).
        if (usdcIsToken0) {
            amm.addLiquidity(100_000e6, 100_000e18, 0, 0, address(this));
        } else {
            amm.addLiquidity(100_000e18, 100_000e6, 0, 0, address(this));
        }

        // Compute expected output for 1 000 USDC in.
        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 amountIn = 1_000e6;
        uint256 reserveIn = usdcIsToken0 ? uint256(r0) : uint256(r1);
        uint256 reserveOut = usdcIsToken0 ? uint256(r1) : uint256(r0);

        uint256 expectedOut = amm.getAmountOut(amountIn, reserveIn, reserveOut);
        assertGt(expectedOut, 0, "non-zero expected output");

        // Optimistic-swap: transfer input first, then call swap.
        usdc.transfer(address(amm), amountIn);

        uint256 beforeBal = mockWETH.balanceOf(address(this));
        if (usdcIsToken0) {
            amm.swap(0, expectedOut, address(this));
        } else {
            amm.swap(expectedOut, 0, address(this));
        }
        uint256 received = mockWETH.balanceOf(address(this)) - beforeBal;

        assertEq(received, expectedOut, "received amount must match getAmountOut");
        emit log_named_uint("mockWETH received", received);
    }

    // ─── 3. GovernanceToken EIP-2612 permit in a forked environment ──────────

    /// @notice Deploys GovernanceToken on a forked mainnet, generates an EIP-2612
    ///         off-chain signature, calls permit(), and verifies the allowance.
    ///         Proves ERC20Permit works with real chain IDs and block contexts.
    function test_Fork_GovernanceToken_PermitFlow() public {
        _forkOrSkip(FORK_BLOCK);

        address trsAddr = makeAddr("trs");
        address airAddr = makeAddr("air");
        address liqAddr = makeAddr("liq");
        address spender = makeAddr("spender");

        // Deployer (address(this)) receives the 40 % team allocation.
        GovernanceToken govToken = new GovernanceToken(trsAddr, airAddr, liqAddr);

        // Alice uses a deterministic private key so we can sign off-chain.
        uint256 aliceKey = 0xA11CE;
        address alice = vm.addr(aliceKey);

        // Give alice some tokens to permit against.
        govToken.transfer(alice, 1_000e18);

        uint256 value = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = govToken.nonces(alice);

        // Build the EIP-2612 permit digest manually.
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", govToken.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        govToken.permit(alice, spender, value, deadline, v, r, s);

        assertEq(govToken.allowance(alice, spender), value, "permit must set allowance");
        assertEq(govToken.nonces(alice), nonce + 1, "nonce must increment after permit");
    }
}
