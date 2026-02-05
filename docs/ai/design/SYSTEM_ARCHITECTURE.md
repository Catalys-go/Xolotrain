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

**Unified Agent with Dual Responsibilities**:

**1. Health Monitoring (Continuous)**:
- ✅ Monitors blockchain events continuously
- ✅ Watches LP position state (in-range/out-of-range)
- ✅ Calculates health deterministically
- ✅ Calls `PetRegistry.updateHealth()` when health changes
- ✅ Triggers alerts to user (via frontend)

**2. Intent Fulfillment (Event-Driven)**:
- ✅ Monitors `IntentCreated` events from travel requests
- ✅ Evaluates intent profitability
- ✅ Uses Li.FI SDK to find optimal bridge routes
- ✅ Creates LP positions on destination chains
- ✅ Submits claims to receive payment

**Agent Operational Principles**:
- ✅ Logs all actions transparently (health updates, intent fulfillments, errors)
- ✅ Maintains consistent state across chains (monitors both Sepolia and Base Sepolia)
- ✅ Batches updates for gas efficiency
- ✅ Uses low gas prices for non-urgent transactions

**What Agent Sees**:

- 🔍 All on-chain LP positions (6+ Uniswap v4 reads per user)
- 📡 Real-time pool price data via `IPoolManager`
- 🎯 Position ranges (tickLower, tickUpper)
- 📊 Current tick in pool
- 📝 Event logs (PetHatched, IntentCreated, etc.)
- ⏰ Block timestamps
- 🌉 Cross-chain travel intents

**What Agent CAN Do**:

- ✅ Update health metadata (read-only impact on funds)
- ✅ Create LP positions on behalf of users (via intents)
- ✅ Bridge assets using Li.FI for intent fulfillment
- ✅ Claim payments from The Compact

**What Agent CANNOT Do**:

- ❌ Move user funds directly (only via signed intents)
- ❌ Close user positions without permission
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
    uint256 positionId;  // PositionManager NFT tokenId (user-owned)
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
   │                                  │ 6. POSM.modifyLiquiditiesWithoutUnlock()│
   │                                  │    (MINT_POSITION_FROM_DELTAS)          │
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
   - Swap ETH → USDC (creates positive USDC delta)
   - Swap ETH → USDT (creates positive USDT delta)
   - Call `PositionManager.modifyLiquiditiesWithoutUnlock()` with `MINT_POSITION_FROM_DELTAS` action
   - POSM uses the deltas to mint NFT-based LP position to user
6. PoolManager triggers `EggHatchHook.afterAddLiquidity()` with hookData containing tokenId
7. Hook calls `PetRegistry.hatchFromHook(owner, chainId, poolId, tokenId)`
8. PetRegistry mints new pet with:
   - `owner = msg.sender`
   - `positionId = tokenId` (PositionManager NFT)
   - `health = 100`
   - `chainId = block.chainid`
9. Event emitted: `PetHatched(petId, owner, chainId, poolId, positionId)`
10. Frontend listens for event, displays axolotl animation

**Blockchain State Changes**:

- PoolManager: New LP position created in USDC/USDT pool
- PositionManager: NFT minted to user (tokenId = positionId)
- PetRegistry: New pet minted, linked to PositionManager NFT
- User wallet: ETH spent, PositionManager NFT received, leftover USDC/USDT received

**Key Architectural Note**: Positions are now **user-owned NFTs** via Uniswap v4 PositionManager, not owned by AutoLpHelper. Users can transfer, manage, or burn their positions independently. PetRegistry tracks which NFT corresponds to which pet.

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

### Flow 4: User Travels (Cross-Chain Bridge) - Intent-Based via The Compact + Li.FI

```
┌──────┐    ┌──────────┐    ┌──────────────┐    ┌────────────┐    ┌──────────────┐    ┌──────────────┐
│ User │───▶│ Frontend │───▶│ AutoLpHelper │───▶│ TheCompact │───▶│ Solver Bot   │───▶│ AutoLpHelper │
│      │    │          │    │ (Source)     │    │ (Source)   │    │ (Off-chain)  │    │ (Dest)       │
└──────┘    └──────────┘    └──────────────┘    └────────────┘    └──────────────┘    └──────────────┘
   │              │                  │                  │                  │                 │
   │ 1. Select    │                  │                  │                  │                 │
   │    dest chain│                  │                  │                  │                 │
   │              │                  │                  │                  │                 │
   │ 2. Sign      │                  │                  │                  │                 │
   │    compact ──┴─────────────────▶│                  │                  │                 │
   │    (EIP-712) │                  │                  │                  │                 │
   │              │                  │                  │                  │                 │
   │              │                  │ 3. Close LP      │                  │                 │
   │              │                  │    position      │                  │                 │
   │              │                  │                  │                  │                 │
   │              │                  │ 4. Deposit USDC  │                  │                 │
   │              │                  │    + USDT into   │                  │                 │
   │              │                  │    TheCompact ──▶│                  │                 │
   │              │                  │    (Resource locks)                │                 │
   │              │                  │                  │                  │                 │
   │              │                  │ 5. Register      │                  │                 │
   │              │                  │    MultichainCompact                │                 │
   │              │                  │    with witness  │                  │                 │
   │              │                  │                  │                  │                 │
   │              │                  │                  │ 6. Event:        │                 │
   │              │                  │                  │    IntentCreated │                 │
   │              │                  │                  │                  │                 │
   │              │                  │                  │                  │ 7. See intent   │
   │              │                  │                  │                  │    evaluates    │
   │              │                  │                  │                  │    profitability│
   │              │                  │                  │                  │                 │
   │              │                  │                  │                  │ 8. Use Li.FI SDK│
   │              │                  │                  │                  │    getRoutes()  │
   │              │                  │                  │                  │    (optimal     │
   │              │                  │                  │                  │    bridge)      │
   │              │                  │                  │                  │                 │
   │              │                  │                  │                  │ 9. Bridge own   │
   │              │                  │                  │                  │    funds via    │
   │              │                  │                  │                  │    Li.FI        │
   │              │                  │                  │                  │                 │
   │              │                  │                  │                  │ 10. Mint LP ─▶│
   │              │                  │                  │                  │    from USDC/   │
   │              │                  │                  │                  │    USDT tokens  │
   │              │                  │                  │                  │                 │
   │              │                  │                  │                  │◀────────────────┘
   │              │                  │                  │                  │ 11. Get positionId
   │              │                  │                  │                  │                 │
   │              │                  │                  │ 12. Submit claim │                 │
   │              │                  │                  │◀─────────────────┘                 │
   │              │                  │                  │    (proof of LP) │                 │
   │              │                  │                  │                  │                 │
   │              │                  │                  │ 13. Verify claim │                 │
   │              │                  │                  │     release locks│                 │
   │              │                  │                  │     to solver    │                 │
   │              │                  │                  │                  │                 │
   │              │                  │                  │ 14. Event:       │                 │
   │              │                  │                  │     ClaimProcessed                 │
   │              │◀─────────────────┴──────────────────┴──────────────────┘                 │
   │ 15. Travel complete → axolotl on new chain                                             │
   │                                                                                         │
   ▼                                                                                         │
┌──────────┐                                                                                │
│ Frontend │─────▶ Animate travel ("Boarding → In Transit → Arrived")                      │
└──────────┘
```

**Step-by-Step**:

1. User selects destination chain (e.g., "Travel to Base")
2. User signs **MultichainCompact** (EIP-712 signature - one click!)
   - Contains: destination chain, tick range, minimum liquidity
   - Witness data: petId, desired position params
3. `AutoLpHelper.travelToChain(petId, destinationChainId, signature)` executes:
   - Closes existing LP position → USDC + USDT
4. Deposits USDC + USDT into **The Compact** (creates resource locks - ERC6909 tokens)
5. Registers MultichainCompact with allocator + arbiter addresses
6. Emits `IntentCreated(compactId, destinationChain, petId)` event
7. **Solver bot** (off-chain) sees intent and evaluates:
   - Calculate costs (bridge fees + gas + slippage)
   - Calculate revenue (locked assets on source chain)
   - If profitable: proceed
8. **Solver uses Li.FI SDK** to find optimal bridge route:
   ```typescript
   const routes = await lifi.getRoutes({
     fromChainId: 11155111, // Sepolia
     toChainId: 84532,      // Base Sepolia
     fromTokenAddress: USDC_ADDRESS,
     toTokenAddress: USDC_ADDRESS,
     fromAmount: intent.usdcAmount,
   });
   // Li.FI returns best route (Across, Stargate, etc.)
   ```
9. Solver bridges own funds to destination using **Li.FI Composer**:
   ```typescript
   await lifi.executeRoute(routes[0]);
   // USDC and USDT arrive on destination chain
   ```
10. Solver calls `AutoLpHelper.mintLpFromTokens(usdcAmount, usdtAmount, userAddress)` on destination
    - Mints LP position using pre-bridged USDC/USDT tokens (no swapping needed)
    - Creates LP position on behalf of user
    - Gets positionId from transaction receipt
11. Solver receives positionId confirming LP creation
12. Solver calls `LPMigrationArbiter.verifyAndClaim(positionId, compactId, solver)`
13. Arbiter verifies:
    - LP position exists on destination
    - Position matches compact conditions (liquidity, tick range)
    - Arbiter calls `TheCompact.processClaim()` to release locked assets to solver
14. Emits `ClaimProcessed(compactId, solver, timestamp)`
15. Frontend detects event, shows "Arrived!" animation

**User Experience**:

- ✨ **One signature** - no manual bridging steps
- ⚡ **2-5 minutes** - faster than traditional bridge
- 🎭 **Animated journey** - "Boarding → In Transit → Arrived"
- 💰 **Optimal routing** - Li.FI finds cheapest bridge automatically
- 🤖 **Automated** - solver handles all complexity
- 🔒 **Trustless** - The Compact guarantees solver gets paid

**Trust Model**:

- User trusts The Compact protocol (audited)
- User trusts allocator won't censor valid claims
- User trusts arbiter will verify conditions correctly
- Solver trusts allocator won't double-spend locked funds
- **User doesn't need to trust solver** - funds are locked in smart contract
- **Solver trusts Li.FI SDK** - for optimal bridge routing

**Li.FI Integration Points**:

1. **Route Discovery**: `lifi.getRoutes()` finds optimal bridge (cheapest/fastest)
2. **Multi-Bridge Support**: Across, Stargate, Hop, Connext, etc.
3. **Execution**: `lifi.executeRoute()` handles bridge-specific logic
4. **Status Tracking**: `lifi.getStatus()` monitors bridge completion

**Why This Architecture?**

- **The Compact**: Provides intent layer and trustless settlement
- **Li.FI**: Provides optimal cross-chain routing for solver
- **Together**: User gets one-click UX, solver gets best execution

---

**Challenge**: Cross-chain state synchronization

- **Option A**: PetRegistry deployed on each chain independently (separate pets per chain)
- **Option B**: Use cross-chain messaging (LayerZero, Axelar) to sync pet state
- **MVP (Hackathon)**: Option A - simpler, new pet on each chain with reference to original
- **Production**: Option B - single pet travels between chains

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
│   ├── swapEthToUsdcUsdtAndMint()    // For users: ETH → USDC/USDT → LP
│   ├── mintLpFromTokens()             // For solver: USDC/USDT → LP (no swap)
│   └── travelToChain()                // Intent creation
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

### Agent Service (Unified)

```
agent/
├── index.ts                   // Main agent entry point (runs both loops)
├── config.ts                  // Chain configs, RPC endpoints, agent wallet, Li.FI API key
├── health/
│   ├── monitor.ts             // Health monitoring loop
│   ├── calculator.ts          // Deterministic health formula
│   └── updater.ts             // Submit health txs to PetRegistry
├── solver/
│   ├── listener.ts            // Intent event listener
│   ├── profitability.ts       // Profitability evaluation
│   ├── fulfiller.ts           // Intent fulfillment logic
│   └── lifi.ts                // Li.FI SDK integration
├── contracts/
│   ├── poolManager.ts         // IPoolManager interface
│   ├── positionManager.ts     // IPositionManager interface
│   ├── petRegistry.ts         // PetRegistry interface
│   └── autoLpHelper.ts        // AutoLpHelper interface
└── utils/
    ├── logger.ts              // Structured logging
    ├── gas.ts                 // Gas price optimization
    └── multicall.ts           // Batched RPC calls
```

**Unified Agent Responsibilities**:

**1. Health Monitoring (Continuous Loop)**:
- Watches `PositionCreated`, `PositionModified`, `PositionClosed` events
- Queries Uniswap v4 position state every 60 seconds via `IPoolManager`
- Calculates health based on in-range vs out-of-range time
- Calls `PetRegistry.updateHealth()` when health changes ≥5 points
- Batches updates for multiple pets (gas optimization)
- Logs all actions with timestamps for auditability

**2. Intent Fulfillment (Event-Driven)**:
- Listens for `IntentCreated` events from `AutoLpHelper`
- Evaluates profitability: `lockedAssets - (bridgeCost + gasCost)`
- Uses **Li.FI SDK** to find optimal bridge route
- Bridges own capital to destination chain
- Calls `AutoLpHelper.mintLpFromTokens()` to create LP on destination
- Submits claim via `LPMigrationArbiter.verifyAndClaim()`
- Receives payment from The Compact on source chain

**Main Agent Workflow**:

```typescript
// Unified agent entry point
async function runAgent() {
  console.log('🤖 Xolotrain Agent Starting...');
  
  // Run both responsibilities concurrently
  await Promise.all([
    healthMonitoringLoop(),
    intentFulfillmentLoop()
  ]);
}

// Health monitoring loop
async function healthMonitoringLoop() {
  while (true) {
    const pets = await petRegistry.getAllActivePets();
    const updates = [];
    
    for (const pet of pets) {
      const { tick } = await poolManager.getSlot0(pet.poolKey);
      const position = await positionManager.getPosition(pet.positionId);
      const newHealth = calculateHealth(tick, position.tickLower, position.tickUpper);
      
      if (Math.abs(newHealth - pet.health) >= 5) {
        updates.push({ petId: pet.id, health: newHealth });
      }
    }
    
    if (updates.length > 0) {
      await petRegistry.batchUpdateHealth(updates);
      console.log(`✅ Updated ${updates.length} pets`);
    }
    
    await sleep(60_000); // 60 seconds
  }
}

// Intent fulfillment loop
async function intentFulfillmentLoop() {
  autoLpHelper.on('IntentCreated', async (event) => {
    const { compactId, usdcAmount, usdtAmount } = event.args;
    
    // 1. Evaluate profitability
    const cost = await estimateCosts(event);
    const revenue = usdcAmount + usdtAmount;
    if (revenue < cost) return;
    
    // 2. Find optimal bridge route via Li.FI
    const routes = await lifi.getRoutes({
      fromChainId: sourceChainId,
      toChainId: destinationChainId,
      fromTokenAddress: USDC,
      fromAmount: usdcAmount,
    });
    
    // 3. Bridge assets
    await lifi.executeRoute(routes[0]);
    await waitForBridgeCompletion(routes[0].id);
    
    // 4. Create LP on destination (Uniswap v4 interaction)
    const tx = await autoLpHelper.mintLpFromTokens(
      usdcAmount,
      usdtAmount,
      event.args.userAddress
    );
    const positionId = tx.events.LPCreated.args.positionId;
    
    // 5. Submit claim
    await arbiter.verifyAndClaim(positionId, compactId, AGENT_ADDRESS);
    
    console.log(`✅ Intent ${compactId} fulfilled`);
  });
}
```

**Li.FI Integration Details**:

- **Route Discovery**: Finds cheapest/fastest bridge (Across, Stargate, Hop, etc.)
- **Multi-Bridge Support**: Automatically selects optimal bridge per route
- **Gas Estimation**: Calculates total cost including bridge fees
- **Status Monitoring**: Tracks bridge completion via `lifi.getStatus()`
- **Error Handling**: Retries with different routes if bridge fails

**Solver Economics**:

- Maintains capital float on each chain (e.g., 10 ETH per chain)
- Calculates: `profit = lockedAssets - (bridgeFees + gasCost + slippage)`
- Only fulfills if `profit > minThreshold` (e.g., 0.1%)
- Rebalances liquidity between chains periodically using Li.FI

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
