# DeFi Super-App: AMM + Vault + DAO Governance

## Overview

A fully on-chain DeFi protocol built as a final assignment, combining an automated market maker, yield vault, and decentralised governance in a single composable system.

The protocol is deployed on Arbitrum Sepolia testnet and demonstrates:

- upgradeable smart contracts
- DAO governance
- ERC-4626 vaults
- AMM architecture
- Chainlink oracle integration
- advanced Solidity testing
- security practices
- gas optimization techniques

---

## Features

- UUPS upgradeable treasury architecture
- DAO governance using ERC20Votes + OpenZeppelin Governor
- ERC-4626 tokenized vault
- Custom x*y=k AMM with LP share minting
- CREATE and CREATE2 deterministic pair deployment
- Chainlink oracle integration with heartbeat/staleness protection
- ERC-1155 game assets with crafting mechanics
- Inline Yul assembly optimizations
- Fuzz, invariant, and fork testing
- Arbitrum Sepolia deployment with verified contracts
- Slither static analysis integration

---

## Architecture

| Contract | Domain | Description |
|---|---|---|
| GovernanceToken | Token | ERC20Votes governance token |
| AMMFactory | AMM | Deploys AMM pairs |
| AMM | AMM | Constant-product AMM |
| YieldVault | Vault | ERC-4626 vault |
| TreasuryV1 | Treasury | Upgradeable treasury |
| TreasuryV2 | Treasury | Extended treasury implementation |
| GameItems | Token | ERC-1155 crafting system |
| PriceOracle | Oracle | Chainlink oracle wrapper |
| ProtocolGovernor | Governance | DAO governance logic |
| ProtocolTimelock | Governance | Timelock controller |
| Box | Governance | Governance-controlled storage |
| MathLib | Library | Inline assembly math library |

---

## Project Structure

```text
src/
├── amm/
├── governance/
├── libraries/
├── oracle/
├── security/
├── token/
├── treasury/
└── vault/

test/
├── amm/
├── governance/
├── integration/
├── oracle/
├── security/
├── token/
├── treasury/
└── vault/

script/
└── Deploy.s.sol
```

---

## Tech Stack

- Solidity 0.8.24
- Foundry
- OpenZeppelin Contracts v5
- OpenZeppelin Upgradeable Contracts
- Chainlink Data Feeds
- Arbitrum Sepolia
- Cancun EVM

---

## Setup

```bash
git clone <repo-url>
cd blockchain_final

forge install

cp .env.example .env
```

---

## Environment Variables

```env
PRIVATE_KEY=
ARBITRUM_SEPOLIA_RPC_URL=
ARBISCAN_API_KEY=
```

---

## Build

```bash
forge build
```

---

## Testing

Run all tests:

```bash
forge test
```

Verbose tests:

```bash
forge test -vvvv
```

Coverage:

```bash
forge coverage
```

Gas report:

```bash
forge test --gas-report
```

---

## Test Metrics

| Metric | Result |
|---|---|
| Total Tests | 142 |
| Unit Tests | ~110 |
| Fuzz Tests | 10 |
| Invariant Tests | 6 |
| Fork Tests | 3 |
| Coverage | 91.64% |

---

## Deployment

Deploy to Arbitrum Sepolia:

```bash
forge script script/Deploy.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --via-ir
```

---

## Security

Implemented security mechanisms:

- ReentrancyGuard
- Checks-Effects-Interactions pattern
- SafeERC20
- Access control
- Timelock governance execution
- Oracle staleness checks
- Slither static analysis
- Vulnerability demonstrations and mitigations

Run Slither:

```bash
slither src --exclude-dependencies
```

---

## Verified Contracts (Arbitrum Sepolia)

| Contract | Address |
|---|---|
| GovernanceToken | 0x9Dc80829f5D95b8aBC89e2b2711Ce75Bfa6dDc67 |
| ProtocolGovernor | 0x320E10Ab8531908dEb19927612EDD82fff3E9A79 |
| ProtocolTimelock | 0x630F2044d9555C3E68a1E4183C77869457f249FA |
| Treasury Proxy | 0xdb7546b18971fc3FAb96022ee6029A267F305d03 |
| TreasuryV1 | 0x2826072941C18EcE61f42953F2E97a50eDAd2F6B |
| TreasuryV2 | 0x744fd74240e59BA266C531264383e4e2f4dBb48B |
| AMMFactory | 0xFD24fd97BD869819Dc77bc4bB92F28E8C3687353 |
| YieldVault | 0x10C38C37455084Bb060d7c385145b6039F99bb6b |
| GameItems | 0x20a91c4E223f3670aCD6863B60c6aC9bFAa52de8 |
| PriceOracle | 0xAA2F89a0f2df921B12e33EB7a8B79401dAbE4736 |
| Box | 0xFFCE959eea953C7360f07aBB9bA042E41126021a |

---

## Governance Flow

1. GovernanceToken holders create proposals
2. Voting occurs through ProtocolGovernor
3. Successful proposals are queued in Timelock
4. Timelock delay expires
5. Proposal execution occurs on-chain

---

## Upgradeability

Treasury uses UUPS upgradeability:

- TreasuryV1 deployed behind ERC1967 proxy
- TreasuryV2 upgrades implementation
- Storage layout preserved

---

## Gas Optimizations

Implemented optimizations:

- Inline Yul assembly
- Immutable variables
- Storage packing
- Custom errors
- Cached storage reads
- Efficient loop patterns
- Unchecked arithmetic where safe

---

## CI/CD

GitHub Actions pipeline automatically runs:

- forge build
- forge test
- forge coverage
- slither static analysis

---

## Authors
Asylkhan Kozhanov
Aldiyar Bazarbayev
Alikhan Sekenov