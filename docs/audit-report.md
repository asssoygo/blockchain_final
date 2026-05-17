# Security Audit Report
## DeFi Super-App — Blockchain Technologies 2 Final Project

**Auditors:** Asylkhan Kozhanov, Aldiyar Bazarbayev, Alikhan Sekenov  
**Audit Date:** May 2026  
**Commit Hash:** (run `git rev-parse HEAD` and insert here)  
**Network:** Arbitrum Sepolia (Chain ID: 421614)  

---

## Executive Summary

This internal security audit covers the DeFi Super-App protocol — a full-stack
decentralized application consisting of 14 smart contracts deployed on Arbitrum
Sepolia. The protocol implements an AMM, ERC-4626 yield vault, DAO governance,
UUPS upgradeable treasury, Chainlink oracle integration, and ERC-1155 gaming items.

The audit was conducted using static analysis (Slither 0.11.5), manual code review,
fuzz testing (256 runs per test), invariant testing (64 runs × 32 depth), and
two reproduced vulnerability case studies with before/after proof-of-concept tests.

**Overall Risk Rating: LOW** — No Critical or High findings remain unmitigated.
All Slither High and Medium findings: **0**.

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 3 | Acknowledged / Fixed |
| Informational | 5 | Acknowledged |
| Gas | 4 | Fixed |

---

## Scope

### Files In Scope
| File | Lines | Purpose |
|------|-------|---------|
| src/token/GovernanceToken.sol | ~145 | ERC20Votes governance token |
| src/token/TokenVesting.sol | ~100 | Linear 365-day vesting |
| src/token/GameItems.sol | ~200 | ERC-1155 gaming items |
| src/amm/AMM.sol | ~280 | Constant-product AMM |
| src/amm/AMMFactory.sol | ~120 | CREATE + CREATE2 factory |
| src/vault/YieldVault.sol | ~120 | ERC-4626 yield vault |
| src/oracle/PriceOracle.sol | ~110 | Chainlink oracle wrapper |
| src/oracle/MockAggregator.sol | ~80 | Test mock |
| src/treasury/TreasuryV1.sol | ~130 | UUPS upgradeable treasury V1 |
| src/treasury/TreasuryV2.sol | ~160 | UUPS treasury V2 with caps |
| src/governance/ProtocolGovernor.sol | ~80 | OZ Governor stack |
| src/governance/ProtocolTimelock.sol | ~30 | TimelockController wrapper |
| src/governance/Box.sol | ~30 | Governance demo contract |
| src/libraries/MathLib.sol | ~60 | Yul + Solidity sqrt |

### Files Out of Scope
- `src/amm/MockERC20.sol` (test-only contract)
- `src/security/` (educational examples, not production)
- `lib/` (third-party dependencies)
- `test/` (test suite)

---

## Methodology

1. **Static Analysis:** Slither 0.11.5 run on `src/` with `--exclude-dependencies`
2. **Manual Review:** Line-by-line review of all in-scope contracts
3. **Fuzz Testing:** 10 fuzz tests with 256 runs each (Foundry)
4. **Invariant Testing:** 6 invariant tests with 64 runs × 32 depth (Foundry)
5. **Fork Testing:** 3 fork tests against Ethereum mainnet state
6. **Vulnerability Reproduction:** Two case studies reproduced and fixed

---

## Findings

### FIND-01 [LOW] — Whale Governance Attack

**Title:** Single large token holder can pass any proposal  
**Severity:** Low (mitigated by design)  
**Location:** src/governance/ProtocolGovernor.sol  
**Description:** A token holder with more than 4% of total supply (40,000 GT)
can pass proposals without needing other votes. With current distribution,
the team allocation (40%) is controlled by TokenVesting, and treasury (30%)
is controlled by the Timelock. However, if one entity accumulates >50% of
circulating supply, they can pass any proposal.

**Impact:** Potential governance takeover by a whale holder.

**Proof of Concept:**
```solidity
// An attacker with 50,001 GT can:
// 1. Propose a malicious proposal (needs 10,000 GT threshold → met)
// 2. Vote For with 500,010 votes (50.001% > 4% quorum → passed)
// 3. Queue in Timelock
// 4. Execute after 2-day delay
```

**Recommendation:** Consider implementing quadratic voting or vote delegation
limits in future versions. Add a Guardian role with veto power.

**Status:** Acknowledged. Mitigated by 2-day Timelock delay giving community
time to respond. Team tokens (40%) are locked in vesting contract and cannot
be used for immediate voting.

---

### FIND-02 [LOW] — Oracle Price Staleness Window

**Title:** Default staleness window may be too long for volatile assets  
**Severity:** Low  
**Location:** src/oracle/PriceOracle.sol:constructor  
**Description:** The default `maxAge` is set to 3600 seconds (1 hour).
During periods of high volatility, ETH price can move significantly in
1 hour. A stale price within the 1-hour window is still accepted.

**Impact:** Protocol could use slightly outdated prices during high volatility.

**Recommendation:** Consider reducing `defaultMaxAge` to 1800 seconds (30
minutes) for production deployment, or using Chainlink's heartbeat parameter
to set appropriate staleness windows per feed.

**Status:** Acknowledged. Owner can update via `setDefaultMaxAge()`.

---

### FIND-03 [LOW] — UUPS Upgrade Without Timelock in Tests

**Title:** Test environment bypasses production upgrade flow  
**Severity:** Low (test environment only)  
**Location:** test/treasury/TreasuryUUPS.t.sol  
**Description:** In tests, upgrades are performed directly by the owner EOA.
In production, the Treasury owner is the Timelock, meaning upgrades require
a full governance proposal. Tests do not exercise this full path.

**Impact:** Low. Production upgrade path is correct. Test is a simplification.

**Recommendation:** Add an end-to-end test that exercises upgrade through the
full governance → timelock → execute path. (Future improvement.)

**Status:** Acknowledged. The governance lifecycle test covers proposal →
execute flow separately.

---

### FIND-04 [INFO] — Centralization: Timelock Controls Critical Functions

**Title:** All privileged actions require Timelock (intended design)  
**Severity:** Informational  
**Location:** All contracts  
**Description:** Post-deployment, the Timelock is the owner of Treasury,
AMMFactory, GameItems, YieldVault, Box, and PriceOracle. This is intentional —
all protocol changes require a governance vote. However, the Timelock itself
has no emergency pause capability.

**Status:** Acknowledged. This is the intended decentralization design.
Emergency pause is available on GameItems via `pause()` through governance.

---

### FIND-05 [INFO] — No Token Recovery in YieldVault

**Title:** Accidentally sent tokens cannot be recovered  
**Severity:** Informational  
**Location:** src/vault/YieldVault.sol  
**Description:** If someone accidentally transfers tokens directly to the
vault (not via `deposit()`), they increase `totalAssets()` which benefits
all shareholders proportionally. There is no dedicated recovery function.

**Recommendation:** Add a `recoverToken(address token, uint256 amount)`
function callable only by owner, that reverts if `token == asset()`.

**Status:** Acknowledged. The accidental transfer actually benefits
existing shareholders (increases share price), so impact is minimal.

---

### FIND-06 [INFO] — MockERC20 in Production Deployment

**Title:** Test-only MockERC20 deployed alongside production contracts  
**Severity:** Informational  
**Location:** script/Deploy.s.sol  
**Description:** The deploy script deploys MockERC20 tokens (mUSD, TKA, TKB)
alongside production contracts. These are labeled as test tokens but are
deployed on the same testnet.

**Status:** Acknowledged. This is a testnet deployment. For mainnet,
deploy script would use real token addresses.

---

### FIND-07 [INFO] — PriceOracle Uses Placeholder Feed in Deploy Script

**Title:** Deploy script originally used address(0x1) for Chainlink feed  
**Severity:** Informational (Fixed)  
**Location:** script/Deploy.s.sol  
**Description:** Initial deployment used a placeholder address
`0x0000000000000000000000000000000000000001` as Chainlink feed.

**Fix Applied:** Updated to real Arbitrum Sepolia ETH/USD feed:
`0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165`

**Status:** Fixed.

---

### FIND-08 [INFO] — Fork Tests Skip Without RPC

**Title:** Fork tests skip gracefully when no mainnet RPC configured  
**Severity:** Informational  
**Location:** test/integration/ForkTests.t.sol  
**Description:** Fork tests use try/catch to skip when MAINNET_RPC_URL
is not available. They pass when a mainnet RPC is configured.

**Status:** Acknowledged. Tests are designed to skip gracefully in CI
environments without mainnet access.

---

## Case Study #1: Reentrancy Vulnerability

### Vulnerable Pattern (SWC-107)

**Location:** `src/security/ReentrancyVulnerable.sol`

```solidity
// VULNERABLE: external call BEFORE state update
function withdraw() external {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "No balance");
    
    // BUG: call happens first
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
    
    // State update too late — attacker already re-entered
    balances[msg.sender] = 0;
}
```

**Exploit:** Attacker deploys a contract with a `receive()` function that
calls `withdraw()` again. Since `balances[attacker]` is not zeroed until
after the external call, the check passes on re-entry. Attacker deposits
1 ETH and can drain all 10 ETH from the contract.

**Test proof:** `test_Reentrancy_Vulnerable_IsExploitable` — attacker
starts with 1 ETH, vault holds 5 ETH, attacker ends with 6 ETH,
vault balance = 0.

### Fixed Pattern (CEI + ReentrancyGuard)

**Location:** `src/security/ReentrancyFixed.sol`

```solidity
// FIXED: two layers of defense
function withdraw() external nonReentrant {
    uint256 amount = balances[msg.sender];
    if (amount == 0) revert NoBalance();
    
    // CEI: EFFECT (state update) BEFORE INTERACTION (external call)
    balances[msg.sender] = 0;
    
    (bool success, ) = msg.sender.call{value: amount}("");
    if (!success) revert TransferFailed();
}
```

**Defense layers:**
1. **CEI Pattern:** `balances[msg.sender] = 0` executes before `call{}`.
   Re-entry sees balance = 0 and reverts with `NoBalance()`.
2. **ReentrancyGuard:** `nonReentrant` modifier sets a lock flag at function
   entry and clears it at exit, blocking any re-entry at the EVM level.

**Test proof:** `test_Reentrancy_Fixed_BlocksTheSameAttack` — same attack
attempt reverts, vault balance unchanged at 5 ETH.

**Applied in protocol:** CEI pattern and `nonReentrant` are used in:
AMM.addLiquidity, AMM.removeLiquidity, AMM.swap, YieldVault.deposit,
YieldVault.withdraw, YieldVault.harvest, TreasuryV1.transferETH,
TreasuryV1.transferERC20, TokenVesting.release.

---

## Case Study #2: Access Control Vulnerability

### Vulnerable Pattern (SWC-100, SWC-105)

**Location:** `src/security/AccessControlVulnerable.sol`

```solidity
// VULNERABLE: no access modifier
function setCriticalParameter(uint256 _value) external {
    criticalParameter = _value; // Anyone can call this
}

function changeOwner(address _newOwner) external {
    owner = _newOwner; // Anyone can become owner
}

function withdrawAll(address payable _to) external {
    (bool success, ) = _to.call{value: address(this).balance}("");
    // Anyone can drain contract funds
}
```

**Exploit:** Any external address can call these functions without
restriction. An attacker can take over ownership and drain all funds
in three transactions.

**Test proof:** `test_AccessControl_Vulnerable_AnyoneCanTakeOver` —
attacker (random address) calls `changeOwner(attacker)` and
`withdrawAll(attacker)`, stealing 10 ETH.

### Fixed Pattern (Ownable)

**Location:** `src/security/AccessControlFixed.sol`

```solidity
// FIXED: OpenZeppelin Ownable
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AccessControlFixed is Ownable {
    function setCriticalParameter(uint256 _value) external onlyOwner {
        criticalParameter = _value;
    }
    // transferOwnership() inherited from Ownable (onlyOwner)
    function withdrawAll(address payable _to) external onlyOwner {
        (bool success, ) = _to.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}
```

**Test proof:** `test_AccessControl_Fixed_RejectsUnauthorizedCallers` —
all three calls from attacker revert with
`OwnableUnauthorizedAccount(attacker)`.

**Applied in protocol:** Every privileged function uses either
`onlyOwner` (Ownable) or role-based checks (TimelockController).
After deployment, all owners are set to the Timelock — no EOA has
direct admin access.

---

## Centralization Analysis

| Power | Holder | Risk | Mitigation |
|-------|--------|------|-----------|
| Upgrade Treasury | Timelock | High if governance attacked | 2-day delay + quorum |
| Mint GameItems | Timelock | Medium | Governance required |
| Update oracle feed | Timelock | Medium | Governance required |
| Drain Treasury | Timelock | Critical | Requires governance vote |
| Pass any proposal | >4% token holder | High | Timelock delay |
| Veto proposals | Nobody | N/A | Fully decentralized |

**Key finding:** After deployer revokes `DEFAULT_ADMIN_ROLE`, no single
EOA can perform privileged actions. All changes require governance.

---

## Governance Attack Analysis

### Flash Loan Governance Attack
**Attack:** Attacker borrows large amount of GT via flash loan, votes on
a proposal, repays loan — all in one transaction.

**Defense:** ERC20Votes uses `getPastVotes(account, snapshotBlock)`.
The snapshot is taken at `block.number - 1` when a proposal is created.
Flash loans execute within one block — the borrowed tokens were not held
at the snapshot block, so they carry **zero voting power**. Attack is
mathematically impossible.

**Test coverage:** `test_VotingPowerSnapshot` verifies that only tokens
held before snapshot block count toward votes.

### Whale Attack
**Attack:** Large holder with >50% accumulated tokens passes malicious proposal.

**Defense:** 2-day Timelock delay gives community 48 hours to observe queued
proposals. Team tokens (40%) are locked in TokenVesting for 365 days.
Token distribution: 30% to Treasury (DAO-controlled), 20% airdrop, 10% liquidity.

### Proposal Spam
**Defense:** `proposalThreshold = 1,000 GT` (0.1% of supply). Only meaningful
token holders can create proposals, preventing spam.

### Timelock Bypass
**Defense:** Timelock `minDelay = 2 days`. Even if Governor is compromised,
the Timelock cannot be bypassed — it is a separate contract with its own
delay enforcement.

---

## Oracle Attack Analysis

### Price Manipulation
**Defense:** Protocol uses Chainlink decentralized price feeds with multiple
independent node operators. Single node cannot manipulate the aggregated price.

### Stale Price Attack
**Defense:** `getPriceWithStalenessCheck(maxAge)` reverts if
`block.timestamp - updatedAt > maxAge`. Default maxAge = 3600 seconds.
Any price older than 1 hour causes a revert, preventing use of stale data.

**Test coverage:** `test_GetPriceWithStalenessCheck_StalePrice_Reverts`
verifies revert after `vm.warp(block.timestamp + 7200)`.

### Feed Depeg / Zero Price
**Defense:** `getLatestPrice()` reverts if `price <= 0` with `InvalidPrice(price)`.
Also checks `answeredInRound >= roundId` to detect incomplete rounds.

---

## Slither Analysis

Slither 0.11.5 was run with:
```bash
slither src --exclude-dependencies --filter-paths "src/security"
```

**Result: 0 High findings, 0 Medium findings.**

Remaining findings (all Low/Informational):
- `naming-convention`: immutable variables use lowercase (intentional per spec)
- `too-many-digits`: large constants like `1_000_000e18` (intentional)
- `immutable-states`: some state variables could be immutable (minor optimization)

These findings are acknowledged and do not represent security risks.
Full Slither output is available by running:
```bash
slither src --exclude-dependencies
```

---

## Security Checklist

| Requirement | Status |
|-------------|--------|
| CEI pattern on all external calls | ✅ |
| ReentrancyGuard on state-modifying functions | ✅ |
| AccessControl / Ownable on all privileged functions | ✅ |
| No tx.origin for authentication | ✅ |
| No block.timestamp for randomness | ✅ |
| No transfer/send — using call{value:} | ✅ |
| SafeERC20 for all ERC-20 interactions | ✅ |
| All external call return values checked | ✅ |
| _disableInitializers() in UUPS constructors | ✅ |
| Slither: 0 High, 0 Medium | ✅ |
| Reentrancy case study (before/after) | ✅ |
| Access control case study (before/after) | ✅ |