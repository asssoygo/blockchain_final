# Gas Optimization Report
## DeFi Super-App — Blockchain Technologies 2 Final Project

---

## 1. Yul Assembly Benchmark: sqrtYul vs sqrtSolidity

The most significant optimization in the protocol is the inline Yul assembly
implementation of the square root function in `src/libraries/MathLib.sol`.
This function is used in AMM LP token minting (`sqrt(amount0 * amount1)`).

| Implementation | Gas Used | Method |
|----------------|----------|--------|
| `sqrtYul` (Yul assembly) | **5,874** | Newton's method, 7 fixed iterations, MSB initial guess |
| `sqrtSolidity` (pure Solidity) | **34,118** | Babylonian loop, O(log x) iterations |
| **Savings** | **28,244 gas (5.8×)** | |

**Why Yul is faster:** The Yul implementation uses a binary search for the
initial guess (finding the most significant bit position), then runs exactly
7 Newton iterations — guaranteed to converge for any uint256. The Solidity
version uses a while loop that runs up to 128 iterations for large inputs.
The Yul version eliminates loop overhead, boundary checks, and stack management.

---

## 2. Storage Packing Optimization (AMM)

In `src/amm/AMM.sol`, the reserve variables are packed into a single storage slot:

```solidity
// BEFORE (naive): 3 separate storage slots = 3 SLOADs per swap
uint256 private reserve0;        // slot N
uint256 private reserve1;        // slot N+1
uint256 private blockTimestampLast; // slot N+2

// AFTER (optimized): 1 storage slot = 1 SLOAD per swap
uint112 private reserve0;           // 112 bits
uint112 private reserve1;           // 112 bits
uint32  private blockTimestampLast; // 32 bits
// Total: 256 bits = exactly 1 storage slot
```

**Gas saving per swap:** ~4,200 gas (2 fewer cold SLOADs × 2,100 gas each)

---

## 3. Key Function Gas Costs (from forge test --gas-report)

### AMM Contract

| Function | Min | Avg | Max | Notes |
|----------|-----|-----|-----|-------|
| addLiquidity | 30,507 | 87,662 | 198,010 | Higher on first call (mints LP) |
| swap | ~90,000 | ~95,000 | ~110,000 | Includes k-invariant check |
| removeLiquidity | ~80,000 | ~110,000 | ~150,000 | Burns LP tokens |
| getAmountOut | 6,781 | 6,781 | 6,781 | Pure view, zero SLOAD |

### Treasury (via ERC1967Proxy)

| Function | Min | Avg | Max | Notes |
|----------|-----|-----|-----|-------|
| depositERC20 | 50,879 | 57,591 | 89,951 | Includes safeTransferFrom |
| transferERC20 | 29,672 | 58,253 | 119,552 | V2: includes cap check |
| transferETH | 36,539 | 54,611 | 72,683 | CEI pattern |
| upgradeToAndCall | 29,845 | 63,630 | 74,892 | UUPS upgrade |

### Other Operations

| Operation | Gas | Notes |
|-----------|-----|-------|
| Vault deposit | 135,392 | ERC-4626 compliant |
| Vault withdraw | 129,470 | Includes share burn |
| GameItems mint | 42,948 | Single fungible token |
| GameItems mintBatch | 105,722 | 3 tokens in one tx |
| GameItems craft | ~92,000 | Burns resources, mints NFT |
| Governor propose | ~255,679 | Includes threshold check |
| Governor castVote | ~291,973 | Records vote |
| TokenVesting release | 100,320 | CEI pattern |

---

## 4. L1 vs L2 Gas Cost Comparison (Arbitrum Sepolia)

Gas units are identical on L1 and L2. The cost difference comes from
the gas price: Ethereum Mainnet ~0.7 gwei vs Arbitrum Sepolia ~0.02 gwei
(~35× cheaper).

| Operation | Gas Units | L1 Cost (0.7 gwei) | L2 Cost (0.02 gwei) | Savings |
|-----------|-----------|-------------------|---------------------|---------|
| ERC20 transfer | 65,000 | 0.0000455 ETH | 0.0000013 ETH | **35×** |
| AMM addLiquidity | 87,662 | 0.0000614 ETH | 0.0000018 ETH | **35×** |
| AMM swap | 95,000 | 0.0000665 ETH | 0.0000019 ETH | **35×** |
| Vault deposit | 135,392 | 0.0000948 ETH | 0.0000027 ETH | **35×** |
| Governor propose | 255,679 | 0.000179 ETH | 0.0000051 ETH | **35×** |
| Governor castVote | 291,973 | 0.000204 ETH | 0.0000058 ETH | **35×** |
| Deploy all 14 contracts | 17,719,632 | ~0.0124 ETH (~$27) | ~0.000355 ETH (~$0.77) | **35×** |

**Actual deployment cost on Arbitrum Sepolia:**
`0.00035454735898 ETH` (17,719,632 gas × 0.020015411 gwei avg)

---

## 5. Custom Errors vs require Strings

All contracts use custom errors instead of require strings:

```solidity
// BEFORE: require string costs ~40 gas extra per revert
require(amount > 0, "ZeroAmount");

// AFTER: custom error is cheaper and more informative  
if (amount == 0) revert ZeroAmount();
```

**Saving:** ~40 gas per revert path. More importantly, custom errors
carry typed parameters (e.g., `MaxSupplyExceeded(requested, available)`)
enabling better error handling in frontend and tests.

---

## 6. Test Coverage Summary
Lines:      91.64% (504/550)  
Statements: 83.60% (581/695)
Branches:   45.52% (61/134)
Functions:  91.58% (87/95)   

Contracts with 100% line coverage: TreasuryV1, AMM, Box, YieldVault.