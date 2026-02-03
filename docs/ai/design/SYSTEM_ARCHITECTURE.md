# Xolotrain System Architecture

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER (Browser)                           │
│  - Connects wallet (RainbowKit)                                 │
│  - Views axolotl state & LP positions                           │
│  - Initiates transactions (hatch, feed, travel)                 │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FRONTEND (Next.js)                            │
│  - React components for UI/UX                                   │
│  - Wagmi hooks for contract interactions                       │
│  - Real-time state updates via events                          │
│  - Animation engine for axolotl visuals                        │
└────────────┬──────────────────────┬─────────────────────────────┘
             │                      │
             ▼                      ▼
┌──────────────────────┐  ┌─────────────────────────────┐
│   AGENT (Backend)    │  │   BLOCKCHAIN (EVM)          │
│  - Monitors events   │  │  - Smart contracts          │
│  - Calculates health │  │  - Uniswap v4 pools         │
│  - Updates registry  │  │  - Position state           │
│  - Deterministic     │  │  - Event logs               │
└──────────────────────┘  └─────────────────────────────┘
```

---

## 🎭 Responsibility Matrix

### USER (Human Player)

**What User Does**:

- ✅ Connects wallet to dApp
- ✅ Initiates LP creation (hatch)
- ✅ Decides when to feed (add liquidity)
- ✅ Decides when to rebalance (adjust range)
- ✅ Initiates travel (cross-chain bridge)
- ✅ Views axolotl state and health
- ✅ Collects trading fees manually

**What User Sees**:

- 🎨 Axolotl visual state (color, animation, mood)
- 📊 Health bar with percentage
- 💰 LP position details (liquidity, fees earned, range)
- 📍 Current chain location
- 🔔 Notifications (health alerts, fee milestones)
- 📜 Transaction history
- 🏆 Stats (age, total fees, evolution tier)

**What User Cannot Do**:

- ❌ Manually update health (agent-only)
- ❌ Directly modify PetRegistry (except via contracts)
- ❌ See other users' private data

---

### AGENT (Automated System)

**What Agent Does**:

- ✅ Monitors blockchain events continuously
- ✅ Watches LP position state (in-range/out-of-range)
- ✅ Calculates health deterministically
- ✅ Calls `PetRegistry.updateHealth()` when health changes
- ✅ Triggers alerts to user (via frontend)
- ✅ Logs all actions transparently
- ✅ Maintains consistent state across chains

**What Agent Sees**:

- 🔍 All on-chain LP positions
- 📡 Real-time pool price data
- 🎯 Position ranges (tickLower, tickUpper)
- 📊 Current tick in pool
- 📝 Event logs from contracts
- ⏰ Block timestamps

**What Agent Cannot Do**:

- ❌ Move user funds
- ❌ Create/close positions on behalf of user
- ❌ Change game rules arbitrarily
- ❌ Access user's private keys
- ❌ Make non-deterministic decisions

**Agent Design Principles**:

1. **Read-Only Access to User Funds**: Agent can read LP state but never custody funds
2. **Deterministic Logic**: Same inputs → same outputs (verifiable)
3. **Transparent Operations**: All agent actions logged on-chain
4. **Fail-Safe**: If agent fails, user can still interact manually
5. **Event-Driven**: Reacts to blockchain events, not arbitrary schedules

---

### BLOCKCHAIN (Smart Contracts)

**What Blockchain Does**:

- ✅ Stores LP position state (Uniswap v4 PoolManager)
- ✅ Executes atomic swaps + LP minting (AutoLpHelper)
- ✅ Triggers hook on LP events (EggHatchHook)
- ✅ Stores pet metadata (PetRegistry)
- ✅ Emits events for transparency
- ✅ Enforces access control (onlyOwner, onlyAgent)

**What Blockchain Stores**:

```solidity
// Uniswap v4 PoolManager (External)
- LP positions (tickLower, tickUpper, liquidity)
- Pool state (currentTick, sqrtPrice, fees)

// PetRegistry (Xolotrain)
struct Pet {
    address owner;
    uint256 positionId;  // Link to LP position
    uint256 chainId;     // Current chain
    uint256 health;      // 0-100
    uint256 birthBlock;
    uint256 lastUpdate;
}
mapping(uint256 => Pet) public pets;  // petId → Pet

// EggHatchHook (Xolotrain)
- Hook configuration
- Authorized registry address
```

**What Blockchain Cannot Do**:

- ❌ Automatically update health (requires agent tx)
- ❌ Monitor off-chain data
- ❌ Trigger actions without transactions

---

## 🔄 System Flows

### Flow 1: Hatch Axolotl (Create LP)

```
┌──────┐     ┌──────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
│ User │────▶│ Frontend │────▶│ AutoLpHelper │────▶│ PoolManager │────▶│ EggHatchHook│
└──────┘     └──────────┘     └──────────────┘     └─────────────┘     └─────────────┘
   │                                  │                     │                    │
   │ 1. Click "Hatch"                 │                     │                    │
   │                                  │                     │                    │
   │ 2. Input: 0.1 ETH ──────────────▶│                     │                    │
   │                                  │                     │                    │
   │ 3. Tx: swapEthToUsdcUsdtAndMint()│                     │                    │
   │                                  │                     │                    │
   │                                  │ 4. unlock() ───────▶│                    │
   │                                  │                     │                    │
   │                                  │ 5. swap() ETH→USDC  │                    │
   │                                  │    swap() ETH→USDT  │                    │
   │                                  │ 6. modifyLiquidity()│                    │
   │                                  │                     │                    │
   │                                  │                     │ 7. afterAddLiquidity()
   │                                  │                     │                    │
   │                                  │                     │                    ▼
   │                                  │                     │          ┌─────────────────┐
   │                                  │                     │          │  PetRegistry    │
   │                                  │                     │          │  .hatchFromHook()│
   │                                  │                     │          └─────────────────┘
   │                                  │                     │                    │
   │                                  │◀────────────────────┴────────────────────┘
   │                                  │                     emit PetHatched(petId)
   │◀─────────────────────────────────┘
   │  8. Tx success → petId returned
   │
   ▼
┌──────────┐
│ Frontend │─────▶ Animate egg hatch, display axolotl
└──────────┘
```

**Step-by-Step**:

1. User clicks "Hatch Your Axolotl" button
2. User inputs ETH amount (e.g., 0.1 ETH)
3. Frontend calls `AutoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ETH}()`
4. AutoLpHelper calls `PoolManager.unlock()` with encoded params
5. Inside unlock callback:
   - Swap ETH → USDC
   - Swap ETH → USDT
   - Call `PoolManager.modifyLiquidity()` to create LP position
6. PoolManager triggers `EggHatchHook.afterAddLiquidity()`
7. Hook calls `PetRegistry.hatchFromHook(owner, positionId, tickLower, tickUpper)`
8. PetRegistry mints new pet NFT with:
   - `owner = msg.sender`
   - `positionId = hash(owner, tickLower, tickUpper, salt)`
   - `health = 100`
   - `chainId = block.chainid`
9. Event emitted: `PetHatched(petId, owner, positionId)`
10. Frontend listens for event, displays axolotl animation

**Blockchain State Changes**:

- PoolManager: New LP position created
- PetRegistry: New pet NFT minted
- User wallet: ETH spent, leftover USDC/USDT received

---

### Flow 2: Agent Updates Health

```
┌───────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
│ Agent │────▶│ PoolManager │────▶│ PetRegistry │────▶│ Frontend │
└───────┘     └─────────────┘     └─────────────┘     └──────────┘
    │               │                     │                  │
    │ 1. Monitor    │                     │                  │
    │    events     │                     │                  │
    │               │                     │                  │
    │ 2. Read LP    │                     │                  │
    │    position   │                     │                  │
    │◀──────────────┘                     │                  │
    │                                     │                  │
    │ 3. Calculate                        │                  │
    │    newHealth                        │                  │
    │                                     │                  │
    │ 4. updateHealth(petId, newHealth) ─▶│                  │
    │                                     │                  │
    │                                     │ 5. emit          │
    │                                     │    HealthUpdated │
    │                                     │                  │
    │                                     └─────────────────▶│
    │                                                        │
    │                                                        ▼
    │                                              Update UI animation
```

**Step-by-Step**:

1. Agent monitors blockchain events (every N blocks)
2. Agent reads LP position state from PoolManager:
   - `currentTick` in pool
   - `tickLower`, `tickUpper` of position
3. Agent calculates health deterministically:
   ```javascript
   if (currentTick >= tickLower && currentTick <= tickUpper) {
     health = 100; // In range
   } else {
     distance = Math.min(
       Math.abs(currentTick - tickLower),
       Math.abs(currentTick - tickUpper),
     );
     health = Math.max(0, 100 - distance * 2); // 2 = penalty multiplier
   }
   ```
4. If health changed by ≥5 points, agent calls:
   ```solidity
   PetRegistry.updateHealth(petId, newHealth)
   ```
5. PetRegistry emits `HealthUpdated(petId, oldHealth, newHealth, timestamp)`
6. Frontend listens for event, updates axolotl visual state

**Gas Optimization**:

- Agent only submits tx if health change is significant (≥5 points)
- Agent batches updates for multiple pets in single tx
- Agent uses low gas price for non-urgent updates

---

### Flow 3: User Feeds Axolotl (Add Liquidity)

```
┌──────┐     ┌──────────┐     ┌──────────────┐     ┌─────────────┐
│ User │────▶│ Frontend │────▶│ AutoLpHelper │────▶│ PoolManager │
└──────┘     └──────────┘     └──────────────┘     └─────────────┘
   │                                  │                     │
   │ 1. Click "Feed" (add liquidity)  │                     │
   │                                  │                     │
   │ 2. Input: 0.05 ETH ──────────────▶│                     │
   │                                  │                     │
   │ 3. Tx: feedAxolotl(petId, amount)│                     │
   │                                  │                     │
   │                                  │ 4. Increase liquidity
   │                                  │    in existing position
   │                                  │                     │
   │                                  │ 5. modifyLiquidity()│
   │                                  │    (positive delta) │
   │                                  │                     │
   │◀─────────────────────────────────┴─────────────────────┘
   │  6. Tx success → liquidity added
   │
   ▼
┌──────────┐
│ Frontend │─────▶ Animate feeding, health boost +10
└──────────┘
```

**Note**: For MVP, we may use **new position creation** instead of modifying existing position (simpler implementation).

---

### Flow 4: User Travels (Cross-Chain Bridge)

```
┌──────┐    ┌──────────┐    ┌──────────┐    ┌───────┐    ┌──────────────┐    ┌──────────┐
│ User │───▶│ Frontend │───▶│  LI.FI   │───▶│Bridge│───▶│ AutoLpHelper │───▶│ Frontend │
└──────┘    └──────────┘    └──────────┘    └───────┘    └──────────────┘    └──────────┘
   │              │               │             │  (Dest Chain)    │               │
   │ 1. Select    │               │             │                  │               │
   │    dest chain│               │             │                  │               │
   │              │               │             │                  │               │
   │ 2. Close LP  │               │             │                  │               │
   │    on source │               │             │                  │               │
   │              │               │             │                  │               │
   │ 3. Initiate  │               │             │                  │               │
   │    bridge ───┴──────────────▶│             │                  │               │
   │                               │             │                  │               │
   │                               │ 4. Bridge  │                  │               │
   │                               │    assets ─▶│                  │               │
   │                               │             │                  │               │
   │                               │             │ 5. Tx on dest:  │               │
   │                               │             │    Create LP ───▶│               │
   │                               │             │                  │               │
   │                               │             │                  │ 6. Update    │
   │                               │             │                  │    PetRegistry│
   │                               │             │                  │    (new chain)│
   │                               │             │                  │               │
   │◀──────────────────────────────┴─────────────┴──────────────────┴───────────────┘
   │  7. Travel complete → axolotl on new chain
   │
   ▼
┌──────────┐
│ Frontend │─────▶ Animate travel, update chain badge
└──────────┘
```

**Challenge**: Cross-chain state synchronization

- **Option A**: PetRegistry deployed on each chain independently
- **Option B**: Use cross-chain messaging (LayerZero, Axelar)
- **MVP**: Option A (simpler, new pet on each chain)

---

## 📦 Component Architecture

### Frontend Components

```typescript
app/
├── page.tsx                    // Homepage with axolotl display
├── components/
│   ├── Axolotl.tsx            // Main axolotl visual component
│   ├── HealthBar.tsx          // Health display
│   ├── LPPositionCard.tsx     // LP stats display
│   ├── HatchModal.tsx         // LP creation modal
│   ├── FeedModal.tsx          // Add liquidity modal
│   ├── TravelModal.tsx        // Cross-chain bridge modal
│   └── ActionButtons.tsx      // Feed, Adjust, Travel, Close
├── hooks/
│   ├── useAxolotlState.ts     // Read pet data from PetRegistry
│   ├── useHealthUpdates.ts    // Listen for health events
│   ├── useLPPosition.ts       // Read LP data from PoolManager
│   └── useContractWrite.ts    // Write transactions
└── utils/
    ├── healthCalculator.ts    // Client-side health preview
    └── animations.ts          // Axolotl animation logic
```

### Smart Contracts

```
contracts/
├── AutoLpHelper.sol           // Atomic ETH → LP creation + travel intents
├── EggHatchHook.sol           // Uniswap v4 hook (afterAddLiquidity)
├── PetRegistry.sol            // Pet NFT + metadata storage
├── XolotrainAllocator.sol     // The Compact allocator (prevents double-spend)
├── LPMigrationArbiter.sol     // Verifies LP creation on destination chain
└── interfaces/
    ├── IEggHatchHook.sol
    ├── IPetRegistry.sol
    ├── ITheCompact.sol         // The Compact protocol interface
    └── IAllocator.sol          // Allocator interface
```

### Agent Service

```
agent/
├── index.ts                   // Main agent entry point
├── monitor.ts                 // Event monitoring
├── healthCalculator.ts        // Deterministic health logic
├── updateService.ts           // Submit health updates to chain
├── solver.ts                  // Fulfill travel intents (The Compact)
├── bridgeService.ts           // Handle cross-chain bridging
└── config.ts                  // Chain configs, RPC endpoints, solver wallet
```

---

## 🔐 Security Model

### Access Control

| Action         | Who Can Do It | Contract Function                         | Access Control  |
| -------------- | ------------- | ----------------------------------------- | --------------- |
| Create LP      | Anyone        | `AutoLpHelper.swapEthToUsdcUsdtAndMint()` | Public          |
| Hatch Pet      | EggHatchHook  | `PetRegistry.hatchFromHook()`             | `onlyHook`      |
| Update Health  | Agent         | `PetRegistry.updateHealth()`              | `onlyAgent`     |
| Add Liquidity  | Pet Owner     | `AutoLpHelper.feedAxolotl()`              | Owner check     |
| Close Position | Pet Owner     | `AutoLpHelper.closePosition()`            | Owner check     |
| Transfer Pet   | Pet Owner     | `PetRegistry.transferFrom()`              | ERC721 standard |

### Agent Trust Model

**Agent Capabilities**:

- ✅ Read all on-chain data
- ✅ Write to `PetRegistry.updateHealth()` only
- ❌ Cannot move user funds
- ❌ Cannot modify LP positions
- ❌ Cannot transfer pet NFTs

**Verification**:

- All agent health updates are logged on-chain
- Users can verify health calculations off-chain
- Health formula is public and deterministic
- If agent misbehaves, owner can replace agent address

---

## 📊 Data Flow Summary

```
User Input (ETH)
    ↓
AutoLpHelper (Atomic Swaps + LP Mint)
    ↓
PoolManager (LP Position Created)
    ↓
EggHatchHook (Triggered on LP creation)
    ↓
PetRegistry (Pet NFT Minted, health = 100)
    ↓
Event Emitted (PetHatched)
    ↓
Frontend Updates (Display Axolotl)
    ↓
Agent Monitors (Read LP state)
    ↓
Agent Calculates (health = f(LP state))
    ↓
Agent Updates (Call updateHealth if changed)
    ↓
Event Emitted (HealthUpdated)
    ↓
Frontend Updates (Animate health change)
```

---

## 🚀 Deployment Architecture

### Testnet Deployment

```
Chain: Sepolia (chainId: 11155111)
├── Uniswap v4 PoolManager: 0x000000000004444c5dc75cB358380D2e3dE08A90
├── Uniswap v4 PositionManager: 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e
├── The Compact: 0x00000000000000171ede64904551eeDF3C6C9788
├── AutoLpHelper: [deployed address]
├── EggHatchHook: [deployed address]
├── PetRegistry: [deployed address]
├── XolotrainAllocator: [deployed address]
└── LPMigrationArbiter: [deployed address]

Chain: Base Sepolia (chainId: 84532)
├── Uniswap v4 PoolManager: [address]
├── The Compact: 0x00000000000000171ede64904551eeDF3C6C9788
├── AutoLpHelper: [deployed address]
├── EggHatchHook: [deployed address]
├── PetRegistry: [deployed address]
├── XolotrainAllocator: [deployed address]
└── LPMigrationArbiter: [deployed address]
```

### Frontend Deployment

- **Hosting**: Vercel
- **RPC**: Alchemy/Infura
- **Wallet**: RainbowKit
- **State**: React + Wagmi hooks

### Agent Deployment

- **Hosting**: Railway/Render/Self-hosted VPS
- **Monitoring**: Ethers.js event listeners
- **Transactions**: Ethers.js signer with dedicated wallet
- **Logging**: Console + file logs for transparency

---

## 🔧 Technical Stack

**Frontend**:

- Next.js 14 (App Router)
- React 18
- TypeScript
- Wagmi v2 (React hooks for Ethereum)
- Viem (Ethereum library)
- RainbowKit (Wallet connection)
- Framer Motion (Animations)

**Contracts**:

- Solidity 0.8.26
- Foundry (Build/test/deploy)
- Uniswap v4 Core
- Uniswap v4 Periphery
- OpenZeppelin Contracts

**Agent**:

- Node.js / TypeScript
- Ethers.js v6
- Event monitoring via `eth_getLogs`
- Deterministic health calculation

**Infrastructure**:

- Vercel (Frontend hosting)
- Alchemy/Infura (RPC nodes)
- IPFS (NFT metadata - future)
- The Graph (Event indexing - future)

---

## 📐 Scalability Considerations

### Multi-User Scaling

- Agent batches health updates for multiple pets
- Frontend uses efficient event filtering
- Contract uses gas-optimized storage patterns

### Multi-Chain Scaling

- Each chain has independent contracts
- Agent monitors multiple chains concurrently
- Frontend switches context based on connected network

### Event Monitoring Scaling

- Agent uses indexed event parameters for fast queries
- Pagination for large event sets
- Checkpoint system to avoid re-scanning blocks

---

## 🎯 Design Principles (Recap)

1. **User Controls Funds**: Only user can create/close LP positions
2. **Agent Reads, Doesn't Write Funds**: Agent only updates metadata
3. **Deterministic Logic**: All calculations are verifiable
4. **On-Chain Truth**: Blockchain is source of truth, not agent
5. **Fail-Safe**: If agent dies, game still playable (user can act manually)
6. **Event-Driven**: Real-time updates via blockchain events
7. **Gas Efficient**: Minimize on-chain storage and computation
