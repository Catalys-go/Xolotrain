# 🚂 Xolotrain

**Xolotrain** is an onchain, agent-driven game where players hatch and nurture axolotl companions. Their health and evolution are directly tied to the real-time performance of **Uniswap v4** liquidity positions.

It combines:

* 🐸 **Tamagotchi-style gameplay**
* 🧠 **Autonomous onchain agents**
* 💧 **Uniswap v4 LP management**
* 🚂 **Intent-based cross-chain travel** (The Compact + Li.Fi)

The result is a playable interface for learning and managing DeFi liquidity, where every onchain action has a clear visual and educational consequence.

---

## 🧠 Core Concept

> **LP Position Health ⇄ Axolotl Health ⇄ Player Actions**

* **Create a USDC/USDT LP** → An axolotl egg hatches.
* **LP earns fees** → Axolotl stays healthy.
* **LP goes out of range** → Axolotl becomes sad or critical.
* **Rebalance / Feed** → Axolotl recovers.
* **Bridge LP cross-chain** → Axolotl travels by train 🚂.

All mechanics are deterministic, verifiable, agent-driven, and deeply integrated with Uniswap v4.

---

## 🎮 Main Features

* 🐣 **Hatching:** Create a Uniswap v4 LP to mint an axolotl.
* ❤️ **Health System:** Deterministic health calculated from LP tick position.
* 🍽️ **Feeding & Rebalancing:** Add liquidity or adjust ranges to heal your pet.
* 🚂 **Cross-Chain Travel:** Intent-based LP migration via *The Compact*.
* 🤖 **Autonomous Agent:** * Monitors LP health and updates pet state onchain.
* Fulfills profitable travel intents.


* 🎨 **Visual Feedback:** Animations tied directly to LP state.
* 📚 **AI-Assisted Education:** Optional AI explanations of complex LP mechanics.

---

## ⚙️ Tech Stack

| Component | Technology |
| --- | --- |
| **Smart Contracts** | Solidity, Foundry |
| **DEX Protocol** | Uniswap v4 (PoolManager & PositionManager) |
| **Frontend** | Next.js, React, Scaffold-ETH 2 |
| **Web3 Tooling** | Viem, Wagmi |
| **Interoperability** | Li.Fi SDK, The Compact (Intent Layer) |
| **Backend/Agent** | Node.js, TypeScript |

---

## 📦 Requirements

Before starting, ensure you have the following installed:

* **Node.js** (≥ v20)
* **Yarn**
* **Foundry**
* **Git**

```bash
# Verify installations
forge --version
anvil --version

```

---

## 🚀 Quickstart (Local Mainnet Fork)

Xolotrain requires a mainnet fork because it depends on real USDC/USDT addresses and Uniswap v4 singleton contracts.

### 1. Install Dependencies

```bash
yarn install

```

### 2. Set up Mainnet RPC

Create an Alchemy, Infura, or QuickNode RPC and export it:

```bash
export MAINNET_RPC="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"

```

### 3. Start a Mainnet Fork (Anvil)

Run Anvil in its own terminal window:

```bash
anvil \
  --fork-url "$MAINNET_RPC" \
  --chain-id 31337 \
  --port 8545

```

### 4. Deploy Contracts

In a new terminal, deploy the suite to your local fork:

```bash
cd packages/foundry
yarn deploy --rpc-url http://127.0.0.1:8545

```

*This deploys `PetRegistry`, `AutoLpHelper`, `EggHatchHook`, and necessary Uniswap v4 integrations.*

### 5. Run the Frontend

```bash
cd packages/nextjs
yarn dev

```

Navigate to [http://localhost:3000](https://www.google.com/search?q=http://localhost:3000) to start your journey.

---

## 🤖 Running the Agent (Optional)

The agent monitors LP positions and updates axolotl health onchain.

```bash
cd packages/agent
yarn install
yarn build
yarn start

```

For more details on solver logic, see: [AGENT_DESIGN.md](https://www.google.com/search?q=docs/ai/design/AGENT_DESIGN.md).

---

## 🧪 Development Workflow

* **Contracts:** `cd packages/foundry && forge test`
* **Frontend:** `cd packages/nextjs && yarn dev`
* **Agent:** `cd packages/agent && yarn start`

---

## 🧭 Design Documentation

* **Game Loop & Mechanics:** [GAME_DESIGN.md](https://www.google.com/search?q=docs/ai/design/GAME_DESIGN.md)
* **User Interactions & UI Flows:** [INTERACTIONS.md](https://www.google.com/search?q=docs/ai/design/INTERACTIONS.md)
* **Agent Architecture:** [AGENT_DESIGN.md](https://www.google.com/search?q=docs/ai/design/AGENT_DESIGN.md)

---