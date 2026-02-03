# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project Overview

Scaffold-ETH 2 (SE-2) is a starter kit for building dApps on Ethereum. It comes in **two flavors** based on the Solidity framework:

- **Hardhat flavor**: Uses `packages/hardhat` with hardhat-deploy plugin
- **Foundry flavor**: Uses `packages/foundry` with Forge scripts

Both flavors share the same frontend package:

- **packages/nextjs**: React frontend (Next.js App Router, not Pages Router, RainbowKit, Wagmi, Viem, TypeScript, Tailwind CSS with DaisyUI)

### Detecting Which Flavor You're Using

Check which package exists in the repository:

- If `packages/hardhat` exists → **Hardhat flavor** (follow Hardhat instructions)
- If `packages/foundry` exists → **Foundry flavor** (follow Foundry instructions)

## Common Commands

Commands work the same for both flavors unless noted otherwise:

```bash
# Development workflow (run each in separate terminal)
yarn chain          # Start local blockchain (Hardhat or Anvil)
yarn deploy         # Deploy contracts to local network
yarn start          # Start Next.js frontend at http://localhost:3000

# Code quality
yarn lint           # Lint both packages
yarn format         # Format both packages

# Building
yarn next:build     # Build frontend
yarn compile        # Compile Solidity contracts

# Contract verification (works for both)
yarn verify --network <network>

# Account management (works for both)
yarn generate            # Generate new deployer account
yarn account:import      # Import existing private key
yarn account             # View current account info

# Deploy to live network
yarn deploy --network <network>   # e.g., sepolia, mainnet, base

yarn vercel:yolo --prod # for deployment of frontend
```

## Architecture

### Smart Contract Development

#### Hardhat Flavor

- Contracts: `packages/hardhat/contracts/`
- Deployment scripts: `packages/hardhat/deploy/` (uses hardhat-deploy plugin)
- Tests: `packages/hardhat/test/`
- Config: `packages/hardhat/hardhat.config.ts`
- Deploying specific contract:
  - If the deploy script has:
    ```typescript
    // In packages/hardhat/deploy/01_deploy_my_contract.ts
    deployMyContract.tags = ["MyContract"];
    ```
  - `yarn deploy --tags MyContract`

#### Foundry Flavor

- Contracts: `packages/foundry/contracts/`
- Deployment scripts: `packages/foundry/script/` (uses custom deployment strategy)
  - Example: `packages/foundry/script/Deploy.s.sol` and `packages/foundry/script/DeployYourContract.s.sol`
- Tests: `packages/foundry/test/`
- Config: `packages/foundry/foundry.toml`
- Deploying a specific contract:
  - Create a separate deployment script and run `yarn deploy --file DeployYourContract.s.sol`

#### Both Flavors

- After `yarn deploy`, ABIs are auto-generated to `packages/nextjs/contracts/deployedContracts.ts`

### Frontend Contract Interaction

**Correct interact hook names (use these):**

- `useScaffoldReadContract` - NOT ~~useScaffoldContractRead~~
- `useScaffoldWriteContract` - NOT ~~useScaffoldContractWrite~~

Contract data is read from two files in `packages/nextjs/contracts/`:

- `deployedContracts.ts`: Auto-generated from deployments
- `externalContracts.ts`: Manually added external contracts

#### Reading Contract Data

```typescript
const { data: totalCounter } = useScaffoldReadContract({
  contractName: "YourContract",
  functionName: "userGreetingCounter",
  args: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"],
});
```

#### Writing to Contracts

```typescript
const { writeContractAsync, isPending } = useScaffoldWriteContract({
  contractName: "YourContract",
});

await writeContractAsync({
  functionName: "setGreeting",
  args: [newGreeting],
  value: parseEther("0.01"), // for payable functions
});
```

#### Reading Events

```typescript
const { data: events, isLoading } = useScaffoldEventHistory({
  contractName: "YourContract",
  eventName: "GreetingChange",
  watch: true,
  fromBlock: 31231n,
  blockData: true,
});
```

SE-2 also provides other hooks to interact with blockchain data: `useScaffoldWatchContractEvent`, `useScaffoldEventHistory`, `useDeployedContractInfo`, `useScaffoldContract`, `useTransactor`.

**IMPORTANT: Always use hooks from `packages/nextjs/hooks/scaffold-eth` for contract interactions. Always refer to the hook names as they exist in the codebase.**

### UI Components

**Always use `@scaffold-ui/components` library for web3 UI components:**

- `Address`: Display ETH addresses with ENS resolution, blockie avatars, and explorer links
- `AddressInput`: Input field with address validation and ENS resolution
- `Balance`: Show ETH balance in ether and USD
- `EtherInput`: Number input with ETH/USD conversion toggle
- `BaseInput`: A flexible, styled input component used as the foundation for custom inputs (e.g., EtherInput, AddressInput).

### Styling

**Use DaisyUI classes** for building frontend components.

```tsx
// ✅ Good - using DaisyUI classes
<button className="btn btn-primary">Connect</button>
<div className="card bg-base-100 shadow-xl">...</div>

// ❌ Avoid - raw Tailwind when DaisyUI has a component
<button className="px-4 py-2 bg-blue-500 text-white rounded">Connect</button>
```

### Configure Target Network before deploying to testnet / mainnet.

#### Hardhat

Add networks in `packages/hardhat/hardhat.config.ts` if not present.

#### Foundry

Add RPC endpoints in `packages/foundry/foundry.toml` if not present.

#### NextJs

Add networks in `packages/nextjs/scaffold.config.ts` if not present. This file also contains configuration for polling interval, API keys. Remember to decrease the polling interval for L2 chains.

## Code Style Guide

### Identifiers

| Style            | Category                                                                                                               |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `UpperCamelCase` | class / interface / type / enum / decorator / type parameters / component functions in TSX / JSXElement type parameter |
| `lowerCamelCase` | variable / parameter / function / property / module alias                                                              |
| `CONSTANT_CASE`  | constant / enum / global variables                                                                                     |
| `snake_case`     | for hardhat deploy files and foundry script files                                                                      |

### Import Paths

Use the `~~` path alias for imports in the nextjs package:

```tsx
import { useTargetNetwork } from "~~/hooks/scaffold-eth";
```

### Creating Pages

```tsx
import type { NextPage } from "next";

const Home: NextPage = () => {
  return <div>Home</div>;
};

export default Home;
```

### TypeScript Conventions

- Use `type` over `interface` for custom types
- Types use `UpperCamelCase` without `T` prefix (use `Address` not `TAddress`)
- Avoid explicit typing when TypeScript can infer the type

### Comments

Make comments that add information. Avoid redundant JSDoc for simple functions.

## Documentation

Use **Context7 MCP** tools to fetch up-to-date documentation for any library (Wagmi, Viem, RainbowKit, DaisyUI, Hardhat, Next.js, etc.). Context7 is configured as an MCP server and provides access to indexed documentation with code examples.

### Agent-First Design Principles

**Xolotrain is built for AI agents to operate autonomously.** Before implementing any feature, review:

- **[docs/ai/AGENT_FIRST_DESIGN.md](docs/ai/AGENT_FIRST_DESIGN.md)** - Core principles for building agent-friendly systems

Key philosophy: Prioritize **atomicity, simplicity, predictability, and observability** over human-friendly flexibility. Every decision point you add exponentially increases agent complexity. Default to single-transaction operations with zero intermediate state and comprehensive events.

## Specialized Agents

Use these specialized agents for specific tasks:

- **`grumpy-carlos-code-reviewer`**: Use this agent for code reviews before finalizing changes

## Canonical Protocol Context

All agents operating in this repository MUST use the following file as the authoritative
reference for Uniswap-related reasoning:

- **[docs/ai/protocols/UNISWAP_CANONICAL_CONTEXT.md](docs/ai/protocols/UNISWAP_CANONICAL_CONTEXT.md)** - Authoritative Uniswap v4 context

Agents must not:

- Infer features not explicitly described
- Conflate Uniswap v4 hooks with UniswapX or The Compact
- Attribute safety, guarantees, or endorsements where none are stated

If a task requires assumptions beyond this context, the agent must:

- Explicitly state the assumption, or
- Ask for clarification before proceeding

## Xolotrain Project Documentation

Xolotrain is a DeFi Tamagotchi game where axolotl pet health reflects Uniswap v4 LP position performance. The project uses Uniswap v4 hooks, The Compact for intent-based settlement, and Li.FI for cross-chain LP migration.

### Core Documentation

**Design Documents** (`docs/ai/design/`):
- **[GAME_DESIGN.md](docs/ai/design/GAME_DESIGN.md)** - Game mechanics, health system, travel flow, evolution system
- **[SYSTEM_ARCHITECTURE.md](docs/ai/design/SYSTEM_ARCHITECTURE.md)** - Component architecture, contract flows, agent services
- **[INTERACTIONS.md](docs/ai/design/INTERACTIONS.md)** - Detailed user/agent/blockchain interaction catalog

**Protocol Integration** (`docs/ai/protocols/`):
- **[UNISWAP_CANONICAL_CONTEXT.md](docs/ai/protocols/UNISWAP_CANONICAL_CONTEXT.md)** - Uniswap v4 hooks and IPoolManager reference
- **[LIFI_INTEGRATION_GUIDE.md](docs/ai/protocols/LIFI_INTEGRATION_GUIDE.md)** - Complete Li.FI SDK implementation with code examples
- **[COPILOT_UNISWAP_PROMPT.md](docs/ai/protocols/COPILOT_UNISWAP_PROMPT.md)** - Uniswap v4 development context

**Research & Planning** (`docs/ai/research/`):
- **[IMPLEMENTATION_PLAN.md](docs/ai/research/IMPLEMENTATION_PLAN.md)** - Original project implementation roadmap
- **[LIFI_COMPACT_FEASIBILITY.md](docs/ai/research/LIFI_COMPACT_FEASIBILITY.md)** - Technical feasibility analysis of intent-based architecture
- **[BOUNTY_STRATEGY.md](docs/ai/research/BOUNTY_STRATEGY.md)** - Dual bounty qualification strategy (Li.FI + Uniswap)


**Quick Reference** (`docs/ai/`):
- **[6_DAY_TIMELINE.md](docs/ai/6_DAY_TIMELINE.md)** - Day-by-day hackathon implementation schedule
- **[QUICK_REFERENCE.md](docs/ai/QUICK_REFERENCE.md)** - Elevator pitch, demo script, troubleshooting, talking points
- **[AGENT_FIRST_APPROACH.md](docs/ai/AGENT_FIRST_APPROACH.md)** - Core principles for agent-friendly system design

### Key Architecture Decisions

- **Uniswap v4**: AutoLpHelper for atomic LP creation, EggHatchHook for pet minting on LP creation
- **The Compact**: Intent-based settlement for cross-chain LP migration (single signature UX)
- **Li.FI Composer**: Solver uses Li.FI SDK for optimal cross-chain routing
- **Agent System**: Deterministic health monitoring + solver bot for travel intent fulfillment
- **Target Chains**: Sepolia (11155111) ↔ Base Sepolia (84532)

### Integration Checklist

- [x] Version selected: Uniswap v4
- [x] Hook requirements: EggHatchHook (afterAddLiquidity)
- [x] SDK integration: Li.FI Composer for cross-chain bridging
- [ ] Security audit: Planned post-hackathon
