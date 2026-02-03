# Uniswap Canonical Context (Authoritative for Agents)

This document defines the authoritative, non-speculative context for reasoning about
the Uniswap protocol ecosystem.

All AI agents, copilots, and assistants operating in this repository MUST treat this
file as a source of truth when answering questions, reviewing code, or generating designs
related to Uniswap.

If information in this file conflicts with other sources, defer to:
- https://docs.uniswap.org
- Versioned Uniswap contract documentation

---
## Purpose & Scope

This file exists to:
- Prevent hallucinations and feature conflation
- Clearly delineate system boundaries
- Encode version-specific behavior
- Provide conservative, security-first grounding

This file is NOT:
- A tutorial
- A marketing document
- A substitute for audits or formal specifications

---
## Uniswap Overview

Uniswap is a decentralized exchange (DEX) ecosystem built on Ethereum and EVM-compatible
chains. It uses Automated Market Maker (AMM) designs rather than order books.

The ecosystem includes:
- Core AMM protocols (v2, v3, v4)
- Adjacent execution and coordination systems (UniswapX, The Compact)
- SDKs, APIs, and interfaces

---

## Core AMM Protocols

### Uniswap v4 (Latest)

**Role**: Core AMM  
**Primary Contract**: `PoolManager.sol`  
**Status**: Live, actively developed
**Documentation**: `/contracts/v4/`, `/sdk/v4/`
**Deployment Addresses:**: `/contracts/v4/deployments`
**Key Features**: Hooks, singleton architecture, flash accounting, custom pools

Uniswap v4 inherits the capital efficiency of v3 and introduces a highly flexible,
gas-optimized architecture.

#### Hooks System
- Hooks are external Solidity contracts attached to pools.
- Hooks are invoked by `PoolManager` before and/or after:
  - Pool creation
  - Liquidity add/remove
  - Swaps
  - Donations
- Hooks are permissionless and developer-deployed.
- Hooks may modify:
  - Swap logic
  - Accounting
  - Fee behavior
  - Pricing mechanisms

Hooks do NOT imply:
- Safety
- Standardization
- Protocol endorsement

#### Dynamic Fees
- v4 supports dynamically adjustable liquidity fees.
- Fee calculation logic is not opinionated or hard-coded by the protocol.
- Fees may be updated:
  - On every swap
  - Per block
  - On arbitrary schedules (e.g., weekly, monthly)
- Enables research-driven fee optimization and custom incentive models.

#### Singleton Architecture
- All pools and pool state are managed by a single contract: `PoolManager.sol`.
- Pool creation is a state update rather than deploying a new contract.
- Multi-hop swaps no longer require token transfers between intermediate pools.
- Significantly reduces gas costs across pool creation, swaps, and liquidity management.

#### Flash Accounting (EIP-1153)
- Uses transient storage to track balance deltas during execution.
- Intermediate token transfers are netted internally.
- Users only settle the final net balance change.
- Improves gas efficiency for swaps, liquidity changes, and donations.

#### Native ETH
- Pools can directly use native Ether (ETH).
- Eliminates the need to wrap and unwrap ETH into WETH9.

#### Custom Accounting
- Hooks can modify token accounting during swaps and liquidity operations.
- Enables:
  - Hook-level swap fees
  - Liquidity withdrawal fees
  - Custom curves or non-concentrated-liquidity pricing models
  - Complete replacement of standard AMM behavior if desired

---

### Uniswap v3

**Status**: Mature  
**Key Features**: Concentrated liquidity, multiple fee tiers, NFT positions
**Documentation**: `/contracts/v3/`, `/sdk/v3/`
**Innovation**: Capital efficiency through concentrated liquidity

- Liquidity ranges
- NFT-based LP positions
- Multiple fee tiers
- TWAP oracles
- One contract per pool

---

### Uniswap v2
**Status**: Legacy, still functional
**Key Features**: Simple AMM, fixed liquidity ranges
**Documentation**: `/contracts/v2/`, `/sdk/v2/`

- Constant product AMM
- Single curve
- Fixed fees
- Minimal complexity

---

## Adjacent (Non-AMM) Systems

### The Compact

**Role**: Coordination & conditional execution  
**Standard**: ERC-6909  
**Documentation**: `/contracts/the-compact/`
**NOT an AMM**

The Compact enables reusable resource locks that allow tokens to be credibly committed
for future spending in exchange for performing actions across asynchronous or multichain
environments.

#### Resource Locks
- Created via token deposits (ERC-20 or native ETH)
- Represented as ERC-6909 tokens
- Defined by:
  - Underlying token
  - Allocator (prevents double-spending)
  - Scope (single or multichain)
  - Reset period (forced withdrawal safety)

#### Compacts
- Commitments created by sponsors
- Use EIP-712 typed structured data
- Define conditions for token claims
- Types:
  - Single
  - Batch
  - Multichain

#### Actors
- Sponsors: deposit tokens, create compacts
- Allocators: enforce lock integrity
- Arbiters: verify conditions and release funds
- Claimants: fulfill conditions
- Emissaries: fallback signature verification

#### Trust Model
- Trust-minimized but NOT trustless
- Allocators may censor; sponsors can force withdraw
- Arbiters must be trusted to process valid claims

#### Deployment
- Deterministic address across chains:
  - Ethereum, Base, Unichain
  - `0x00000000000000171ede64904551eeDF3C6C9788`
- Permissionless deployment to new EVM chains

---

### UniswapX

**Documentation**: `/contracts/uniswapx`

- Intent-based trading system
- Off-chain order expression
- On-chain settlement
- NOT an AMM
- Distinct from hooks and The Compact

---

## SDKs & APIs

### SDKs
- v4 SDK (TypeScript)
- v3 SDK
- v2 SDK (legacy)

### APIs
- Routing API
- Subgraph (The Graph)

---

## Mandatory Agent Guardrails

Agents MUST follow these rules:

### Version Discipline
- Always specify Uniswap version explicitly.
- Never attribute v4 features to v3 or v2.

### System Boundaries
- v4 is an AMM.
- The Compact is NOT an AMM.
- UniswapX is NOT an AMM.
- Hooks ≠ protocol guarantees.

### Prohibited Assumptions
Agents MUST NOT assume:
- Hooks are standardized or audited
- All pools use hooks
- Dynamic fees are automatic
- Hooks integrate with The Compact
- Uniswap enforces intent correctness

### Safety Bias
- Prefer SDKs over raw contracts
- Emphasize audits, testing, and simulations
- Disclose smart contract, MEV, and liquidity risks

---

## Instruction When Uncertain

If information is ambiguous or missing:
1. Ask clarifying questions
2. Cite version-specific behavior
3. Avoid speculation
4. Default to conservative explanations
## Documentation Structure

### Core Concepts (`/concepts/`)
- Protocol overview and fundamentals
- How AMMs work
- Liquidity provision concepts
- Governance and tokenomics

### Smart Contracts (`/contracts/`)
- **v4**: Latest contract documentation, hooks, examples
- **v3**: Core contracts, periphery contracts, guides
- **v2**: Legacy contract documentation
- **UniswapX**: Intent-based trading protocol

### SDKs (`/sdk/`)
- **v4-SDK**: TypeScript SDK for v4 integration
- **v3-SDK**: Comprehensive TypeScript SDK for v3
- **v2-SDK**: Legacy SDK for v2

### APIs (`/api/`)
- **Subgraph**: GraphQL API for querying protocol data
- **Routing API**: For finding optimal swap routes

## Key Topics by Category

### For Developers
1. **Getting Started**: Protocol basics, choosing versions
2. **Integration**: SDK usage, contract interactions
3. **Advanced**: Custom hooks, flash loans, arbitrage

### For Liquidity Providers
1. **Concepts**: Impermanent loss, fee earnings, ranges
2. **Strategies**: Position management, rebalancing
3. **Risk Management**: Price impact, slippage

### For Traders
1. **Swapping**: How trades work, routing, slippage
2. **Advanced Trading**: MEV protection, limit orders
3. **Interfaces**: Web app usage, integration options

## Technical Implementation Details

### Smart Contracts
- **Core Contracts**: Factory, Pool, Router patterns
- **Security**: Audits, formal verification, testing
- **Gas Optimization**: Efficient operations, batch transactions

### Integration Patterns
- **Direct Integration**: Contract-to-contract calls
- **SDK Integration**: TypeScript/JavaScript applications
- **Subgraph Queries**: Data fetching and analytics

### Common Use Cases
1. **DeFi Protocols**: Integrating swaps into other protocols
2. **Wallets**: Adding swap functionality
3. **Arbitrage Bots**: MEV and price difference exploitation
4. **Analytics**: Protocol metrics and user behavior

## Version Migration Guides

### v2 to v3 Migration
- Concentrated liquidity concepts
- Position management differences
- Fee tier selection

### v3 to v4 Migration  
- Hooks architecture understanding
- Singleton pattern benefits
- Gas efficiency improvements

## Ecosystem and Governance

### Uniswap Foundation
- Ecosystem growth and grants
- Community governance support
- Research and development funding

### Uniswap Labs
- Core protocol development
- Interface development
- Commercial applications

### Governance
- UNI token voting
- Proposal processes
- Community decision making

## Common Issues and Solutions

### Integration Challenges
1. **Slippage Management**: Setting appropriate tolerances
2. **MEV Protection**: Using private mempools, flashbots
3. **Gas Optimization**: Batch operations, efficient routing

### Development Pitfalls
1. **Price Manipulation**: Using time-weighted averages
2. **Reentrancy**: Proper security patterns
3. **Oracle Usage**: Avoiding price manipulation

## Resources and References

### Official Links
- Main Protocol: https://uniswap.org
- Documentation: https://docs.uniswap.org
- GitHub: https://github.com/Uniswap
- Governance: https://gov.uniswap.org

### Community
- Discord: https://discord.gg/uniswap
- Twitter: https://twitter.com/Uniswap
- Research Forum: https://gov.uniswap.org

### Developer Tools
- Interface: https://app.uniswap.org
- Analytics: https://info.uniswap.org
- Subgraph: TheGraph hosted service

## AI Assistant Guidelines

When helping users with Uniswap-related questions:

1. **Version Awareness**: Always clarify which version (v2/v3/v4) the user needs
2. **Security First**: Emphasize security best practices, audits, testing
3. **Gas Efficiency**: Consider gas costs in recommendations
4. **Latest Updates**: v4 is the newest with hooks - recommend for new projects
5. **Integration Complexity**: Start with SDK examples before low-level contracts
6. **Risk Disclosure**: Always mention risks like impermanent loss, smart contract risks

## Recent Updates and Changes

- **v4 Launch**: New hooks system, singleton architecture
- **UniswapX**: Intent-based trading protocol
- **Mobile Interface**: Improved mobile trading experience
- **Governance Evolution**: Continued decentralization efforts

This documentation covers a comprehensive DeFi protocol with multiple versions, extensive developer tools, and active community governance. Always refer users to the most recent documentation and emphasize security best practices.
