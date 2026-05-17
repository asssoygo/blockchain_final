# Architecture & Design Document
## DeFi Super-App — Blockchain Technologies 2 Final Project

**Team:** Asylkhan Kozhanov, Aldiyar Bazarbayev, Alikhan Sekenov  
**Network:** Arbitrum Sepolia (Chain ID: 421614)  
**Version:** 1.0.0  
**Date:** May 2026

---

## 1. System Context (C4 Level 1)

The DeFi Super-App is a permissionless, DAO-governed DeFi protocol deployed on Arbitrum Sepolia. It provides token swapping (AMM), yield generation (ERC-4626 Vault), and on-chain governance with a full proposal lifecycle.
┌─────────────────────────────────────────────────────────────┐
│                     External Actors                         │
│                                                             │
│  [User/Trader]    [Liquidity Provider]    [Token Holder]    │
│       │                   │                    │            │
└───────┼───────────────────┼────────────────────┼────────────┘
│                   │                    │
▼                   ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                   DeFi Super-App                            │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   AMM    │  │  Vault   │  │ Governor │  │ Treasury │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
│                                       │
▼                                       ▼
┌──────────────┐                    ┌──────────────────────┐
│  Chainlink   │                    │   Arbitrum Sepolia   │
│  Price Feed  │                    │   (L2 Rollup)        │
└──────────────┘                    └──────────────────────┘

### External Dependencies
| System | Purpose | Address |
|--------|---------|---------|
| Chainlink ETH/USD | Price feed for oracle | 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165 |
| Arbitrum Sepolia | L2 execution environment | Chain ID 421614 |
| OpenZeppelin v5 | Security primitives | lib/ |

---

## 2. Container Diagram (C4 Level 2)

### 2.1 Contract Architecture
                     ┌─────────────────────────────────────┐
                     │         GovernanceToken              │
                     │    ERC20 + ERC20Votes + ERC20Permit  │
                     │    Supply cap: 1,000,000 GT          │
                     │    Distribution: 40/30/20/10%        │
                     └──────────────┬──────────────────────┘
                                    │ voting power
                                    ▼
┌──────────────────┐           ┌─────────────────────┐
│  TokenVesting    │           │  ProtocolGovernor   │
│  Linear 365-day  │◄──────────│  OZ Governor stack  │
│  for team 40%    │           │  quorum: 4%         │
└──────────────────┘           │  threshold: 1%      │
└──────────┬──────────┘
│ controls
▼
┌─────────────────────┐
│  ProtocolTimelock   │
│  2-day delay        │
│  PROPOSER: Governor │
│  EXECUTOR: anyone   │
└──────────┬──────────┘
│ owns/controls
┌─────────────────────┼─────────────────────┐
▼                     ▼                     ▼
┌─────────────────┐   ┌──────────────────┐   ┌──────────────┐
│ Treasury Proxy  │   │   AMMFactory     │   │    Box       │
│ (ERC1967Proxy)  │   │  CREATE+CREATE2  │   │ store/retrieve│
│ → TreasuryV1    │   │  deploys AMM     │   └──────────────┘
│ → TreasuryV2    │   │  pairs           │
└─────────────────┘   └────────┬─────────┘
│ deploys
▼
┌──────────────────┐
│      AMM         │
│  x*y=k           │
│  0.3% fee        │
│  LP token (ERC20)│
└──────────────────┘
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│   YieldVault     │   │   PriceOracle    │   │   GameItems      │
│   ERC-4626       │   │   Chainlink      │   │   ERC-1155       │
│   harvest()yield │   │   staleness 1hr  │   │   crafting       │
└──────────────────┘   └──────────────────┘   └──────────────────┘
┌──────────────────┐
│    MathLib       │
│  sqrtYul (Yul)   │
│  5.8x faster     │
└──────────────────┘

### 2.2 Deployed Contract Addresses (Arbitrum Sepolia)

| Contract | Address | Verified |
|----------|---------|---------|
| GovernanceToken | 0x9Dc80829f5D95b8aBC89e2b2711Ce75Bfa6dDc67 | ✅ |
| TokenVesting | — | ✅ |
| ProtocolTimelock | 0x630F2044d9555C3E68a1E4183C77869457f249FA | ✅ |
| ProtocolGovernor | 0x320E10Ab8531908dEb19927612EDD82fff3E9A79 | ✅ |
| TreasuryV1 impl | 0x2826072941C18EcE61f42953F2E97a50eDAd2F6B | ✅ |
| Treasury proxy | 0xdb7546b18971fc3FAb96022ee6029A267F305d03 | ✅ |
| TreasuryV2 impl | 0x744fd74240e59BA266C531264383e4e2f4dBb48B | ✅ |
| AMMFactory | 0xFD24fd97BD869819Dc77bc4bB92F28E8C3687353 | ✅ |
| YieldVault | 0x10C38C37455084Bb060d7c385145b6039F99bb6b | ✅ |
| GameItems | 0x20a91c4E223f3670aCD6863B60c6aC9bFAa52de8 | ✅ |
| Box | 0xFFCE959eea953C7360f07aBB9bA042E41126021a | ✅ |
| PriceOracle | 0xAA2F89a0f2df921B12e33EB7a8B79401dAbE4736 | ✅ |
| MockERC20 (mUSD) | 0xa0CC573865B6800f9E9577b39B289FFe0cB7F8C9 | ✅ |

---

## 3. Sequence Diagrams — Critical User Flows

### 3.1 AMM Swap Flow
User          AMM Contract         Token0        Token1
│                 │                  │              │
│─ approve() ────►│                  │              │
│                 │                  │              │
│─ token0         │                  │              │
│  .transfer() ──►│                  │              │
│                 │                  │              │
│─ swap(0,        │                  │              │
│   amountOut,    │                  │              │
│   to) ─────────►│                  │              │
│                 │─ token1          │              │
│                 │  .safeTransfer()─┼─────────────►│
│                 │                  │              │
│                 │ measure balance0 increase       │
│                 │ verify k-invariant:             │
│                 │ (b0997)(b1997) >= r0r1*1e6  │
│                 │                  │              │
│                 │─ _update(b0,b1) ─┤              │
│                 │                  │              │
│◄─ Swap event ───│                  │              │

### 3.2 Governance Proposal Lifecycle
Proposer      Governor        Timelock        Box Contract
│              │               │                │
│─ delegate() ►│               │                │
│              │               │                │
│─ propose()  ►│               │                │
│              │ ProposalCreated event           │
│              │               │                │
│  [1 block voting delay]      │                │
│              │               │                │
│─ castVote() ►│               │                │
│              │ VoteCast event│                │
│              │               │                │
│  [50 blocks voting period]   │                │
│              │               │                │
│─ queue()    ►│               │                │
│              │─ schedule() ─►│                │
│              │               │                │
│  [2 day timelock delay]      │                │
│              │               │                │
│─ execute()  ►│               │                │
│              │─ execute()   ►│                │
│              │               │─ store(42) ───►│
│              │               │                │
│              │               │◄─ ValueChanged─│

### 3.3 ERC-4626 Vault Deposit + Harvest Flow
User          YieldVault        MockAsset
│                │                 │
│─ approve() ───►│                 │
│                │                 │
│─ deposit(      │                 │
│   assets,      │                 │
│   receiver) ──►│                 │
│                │─ safeTransferFrom(user, vault, assets)─►│
│                │                 │
│                │─ _mint(receiver, shares)
│                │                 │
│◄─ shares ──────│                 │
│                │                 │
│  [time passes, yield accrues]    │
│                │                 │
Owner─ harvest(amount)────────────►│
│                │─ safeTransferFrom(owner, vault, amount)►│
│                │ totalHarvested += amount                │
│                │                 │
│ convertToAssets(shares) is now HIGHER than deposit amount

---

## 4. Data Model — Storage Layouts

### 4.1 GovernanceToken (non-upgradeable)
Inherits ERC20 + ERC20Permit + ERC20Votes + Ownable. Key custom state:
| Slot | Variable | Type | Notes |
|------|----------|------|-------|
| inherited | _balances | mapping(address=>uint256) | ERC20 |
| inherited | _allowances | mapping(address=>mapping(address=>uint256)) | ERC20 |
| inherited | _totalSupply | uint256 | ERC20 |
| inherited | _checkpoints | mapping(address=>Checkpoint[]) | ERC20Votes |
| custom | vestingInitialized | bool | packed with owner slot |

### 4.2 TreasuryV1 (UUPS Upgradeable) — CRITICAL STORAGE LAYOUT
OZ upgradeable contracts use unstructured storage for proxy admin slots. Custom state starts at application-specific slots:

| Slot | Variable | Type | Version |
|------|----------|------|---------|
| 0 | totalDeposited | mapping(address=>uint256) | V1 |
| 1 | totalWithdrawn | mapping(address=>uint256) | V1 |
| 2 | ethBalance | uint256 | V1 |
| 3 | version | string | V1 |

### 4.3 TreasuryV2 — V2 APPENDS ONLY (storage collision proof)
V2 inherits V1. New variables appended at slots 4+:

| Slot | Variable | Type | Version |
|------|----------|------|---------|
| 0-3 | (preserved from V1) | — | V1 |
| 4 | spendingCaps | mapping(address=>uint256) | **V2 NEW** |
| 5 | spentInWindow | mapping(address=>uint256) | **V2 NEW** |
| 6 | windowStartTime | mapping(address=>uint256) | **V2 NEW** |
| 7 | spendingWindowDuration | uint256 | **V2 NEW** |

**Storage collision proof:** V1 slots 0-3 are identical in V2 (inherited, not redeclared). No variable is inserted before slot 4. All V1 state reads correctly through the proxy after upgrade. This was verified in `test_UpgradeToV2_PreservesState`.

### 4.4 AMM Storage Packing
```solidity
// Packed into ONE storage slot (256 bits):
uint112 private reserve0;        // 112 bits
uint112 private reserve1;        // 112 bits  
uint32 private blockTimestampLast; // 32 bits
// Total: 256 bits = exactly 1 slot
```
This saves 2 SLOADs on every swap operation (1 SLOAD instead of 3).

---

## 5. Trust Assumptions & Access Control

### 5.1 Role Hierarchy
Deployer (EOA: 0xaa4B652...)
│ revoked after deploy
▼
ProtocolTimelock (2-day delay)
│ owns
├── Treasury proxy (can upgrade, transfer funds)
├── AMMFactory (can createPair)
├── GameItems (can mint)
├── YieldVault (owner)
├── Box (can store)
└── PriceOracle (can update feed)
ProtocolGovernor
│ has PROPOSER_ROLE on Timelock
└── Token holders propose/vote → Governor → Timelock → action

### 5.2 What Each Role Can Do
| Role | Contract | Powers | Risk if compromised |
|------|----------|--------|---------------------|
| Timelock | Treasury | Upgrade to any impl, transfer all funds | Critical — must pass governance |
| Timelock | AMMFactory | Create new trading pairs | Medium |
| Timelock | GameItems | Mint unlimited items | Medium |
| Governor | Timelock | Queue any proposal | High — if governance is attacked |
| Token holder >4% | Governor | Pass quorum alone | High — whale attack risk |

### 5.3 What Happens if Multisig/Admin is Compromised
After deployment, the deployer (`0xaa4B652...`) has **zero admin powers**. `DEFAULT_ADMIN_ROLE` was revoked from deployer in `Deploy.s.sol`. The only way to change protocol parameters is through a successful governance vote → 2-day timelock → execution. Even the original deployer cannot bypass this.

---

## 6. Design Decisions (Architecture Decision Records)

### ADR-001: UUPS over Transparent Proxy
**Context:** Protocol needs upgradeable Treasury. Two main options: Transparent Proxy and UUPS.  
**Decision:** UUPS (EIP-1822).  
**Rationale:** UUPS is cheaper in gas (no ProxyAdmin contract, upgrade logic in implementation), and OpenZeppelin v5 recommends UUPS for new projects. Transparent proxy has selector collision risks.  
**Consequence:** If V2 implementation accidentally omits `_authorizeUpgrade`, upgrades are permanently bricked. Mitigated by explicit override in both V1 and V2.

### ADR-002: AMM Built From Scratch
**Context:** Assignment requires a DeFi primitive built from scratch (not forked).  
**Decision:** Custom AMM with x*y=k formula, 0.3% fee, LP tokens as ERC20.  
**Rationale:** Demonstrates understanding of the constant-product formula, impermanent loss mechanics, and LP token minting math. Forking Uniswap V2 would not demonstrate learning.  
**Consequence:** Less battle-tested than Uniswap V2, but fully covered by 33 tests (unit + fuzz + invariant).

### ADR-003: Governor With Short Demo Parameters
**Context:** OZ Governor requires real timing (1 day delay, 1 week period) which makes automated tests take forever.  
**Decision:** Deploy with votingDelay=1 block, votingPeriod=50 blocks for testnet. Production values commented in code.  
**Rationale:** Assignment requires demonstrate full lifecycle in tests. Production values (7200 blocks delay, 50400 period) are documented in comments.  
**Consequence:** Demo governance is faster to attack. Acceptable for testnet.

### ADR-004: Yul Assembly for sqrt
**Context:** AMM requires `sqrt(a*b)` for LP token minting. Two implementation options: pure Solidity Babylonian loop vs Yul-optimized Newton's method.  
**Decision:** Yul assembly implementation in MathLib.sqrtYul.  
**Rationale:** Benchmark shows **5.8× gas savings** (5,874 gas vs 34,118 gas for large inputs). AMM minting is called frequently; optimization directly reduces user costs.  
**Consequence:** Yul code is harder to audit. Mitigated by having identical Solidity reference implementation and 7 tests verifying both produce identical results.

### ADR-005: ERC-1155 for Game Items
**Context:** Assignment requires ERC-721 or ERC-1155. Protocol has both fungible resources (Gold, Wood, Iron) and unique NFTs (Legendary Sword, Dragon Shield).  
**Decision:** ERC-1155 (single contract for all token types).  
**Rationale:** ERC-1155 is 40-60% more gas efficient for batch operations than separate ERC-20 + ERC-721 contracts. One contract manages all token types with built-in batch transfer.  
**Consequence:** More complex interface, but better for gaming use case.

### ADR-006: Arbitrum Sepolia for L2 Deployment
**Context:** Assignment requires deployment on one of: Arbitrum Sepolia, Optimism Sepolia, Base Sepolia, zkSync Sepolia.  
**Decision:** Arbitrum Sepolia.  
**Rationale:** Arbitrum has the largest mainnet TVL among optimistic rollups, best tooling support (Arbiscan, Alchemy, QuickNode), and is directly compatible with standard Solidity + Foundry toolchain. Gas savings vs L1 verified at ~35× cheaper.

---

## 7. Layer 2 Architecture

### 7.1 Why Arbitrum Sepolia
Arbitrum is an Optimistic Rollup — it executes transactions off-chain, posts compressed data to Ethereum L1, and uses a 7-day fraud proof window for finality. Key properties:
- **Security:** Inherits Ethereum L1 security (fraud proofs)
- **Cost:** ~35× cheaper than Ethereum Mainnet (verified in gas comparison table)
- **Compatibility:** Full EVM equivalence — no code changes needed
- **Developer experience:** Arbiscan, Alchemy, full Foundry support

### 7.2 Gas Comparison Table (L1 vs L2)

| Operation | Ethereum Sepolia (L1) | Arbitrum Sepolia (L2) | Savings |
|-----------|----------------------|----------------------|---------|
| Deploy GovernanceToken | ~2,100,000 gas | ~2,100,000 gas* | ~35× cheaper in ETH cost |
| ERC20 transfer | ~65,000 gas | ~65,000 gas* | ~35× cheaper in ETH cost |
| AMM addLiquidity | ~180,000 gas | ~180,000 gas* | ~35× cheaper in ETH cost |
| AMM swap | ~90,000 gas | ~90,000 gas* | ~35× cheaper in ETH cost |
| Vault deposit | ~110,000 gas | ~110,000 gas* | ~35× cheaper in ETH cost |
| Governor propose | ~200,000 gas | ~200,000 gas* | ~35× cheaper in ETH cost |

*Gas units are identical on L2; cost in ETH is ~35× lower because L2 gas price is ~0.02 gwei vs ~0.7 gwei on L1.

**Actual deployment cost on Arbitrum Sepolia:** 0.00035454735898 ETH (17,719,632 gas × 0.020015411 gwei) for all 14 contracts.

---

## 8. Design Patterns Used

The protocol consciously applies the following design patterns (Section 4.1 requirement):

| Pattern | Where Used | Justification |
|---------|-----------|---------------|
| **Factory** | AMMFactory (CREATE + CREATE2) | Centralized pair deployment with address prediction |
| **Proxy / UUPS** | TreasuryV1 → TreasuryV2 | Upgradeable treasury without breaking storage |
| **Checks-Effects-Interactions** | AMM.swap, Treasury.transferETH, TokenVesting.release | Prevents reentrancy at the pattern level |
| **Access Control / Role-based** | Ownable on all contracts; Timelock roles | No unguarded admin functions |
| **Timelock** | ProtocolTimelock (2-day delay) | Governance actions cannot execute immediately |
| **Reentrancy Guard** | AMM, YieldVault, TreasuryV1/V2 | Defense-in-depth against reentrancy |
| **Oracle Adapter** | PriceOracle wraps AggregatorV3Interface | Abstracts Chainlink behind protocol interface |
| **Pausable / Circuit Breaker** | GameItems (pause/unpause) | Emergency stop for NFT minting and transfers |

---

## 9. Team Contributions

| Member | Responsibility |
|--------|---------------|
| Asylkhan Kozhanov | Core contracts: GovernanceToken, TokenVesting, AMM, AMMFactory, MathLib (Yul), YieldVault |
| Aldiyar Bazarbayev | Governance & Security: Governor, Timelock, TreasuryV1/V2 (UUPS), PriceOracle, GameItems, security case studies |
| Alikhan Sekenov | Testing, DevOps & Frontend: all test suites (146 tests), GitHub Actions CI, Deploy script, frontend dApp, architecture document |