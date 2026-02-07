# Xolotrain User Interactions Reference

This document catalogs all possible user interactions, agent behaviors, and blockchain responses in the Xolotrain system.

---

## 🎮 User Actions

### 1. Connect Wallet

**User Action**: Click "Connect Wallet" button

**Frontend Flow**:

```typescript
// Using RainbowKit
<ConnectButton />
// Triggers wallet selection modal
```

**What Happens**:

- RainbowKit modal opens with wallet options
- User selects wallet (MetaMask, WalletConnect, etc.)
- Wallet prompts for connection approval
- Frontend receives wallet address + chain

**State Changes**:

- Frontend: `isConnected = true`, `address = 0x...`
- Frontend: checks if user has pet hatched
  ```typescript
  const { data: userPetIds } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPetsByOwner",
    args: [connectedAddress],
    query: { enabled: Boolean(petRegistry?.address && connectedAddress) },
  });
  const hasPet = Boolean(
    petData &&
    petData.owner &&
    petData.owner !== "0x0000000000000000000000000000000000000000",
  );
  const isEggHatched = hasPet && hasLpPosition;
  ```
- User sees: Connected address in header
- User sees: Egg waiting to be hatched
- Available actions: All buttons now active

**Edge Cases**:

- Wrong network → Show network switch prompt
- Wallet locked → Prompt to unlock
- No wallet installed → Show installation instructions
- Egg not displaying properly

---

### 2. Get Testnet ETH (Faucet)

**User Action**: Click "Get Test ETH" button

**Frontend Flow**:

```typescript
const { sendFaucetETH } = useScaffoldWriteContract("Faucet");
await sendFaucetETH({ args: [userAddress] });
```

**What Happens**:

- Frontend calls faucet contract
- Faucet sends 1 ETH to user
- Transaction confirmed

**State Changes**:

- User balance: +1 ETH
- User sees: Updated balance in UI

**Edge Cases**:

- Faucet empty → Show error message

---

### 3. Hatch Axolotl (Create LP)

**User Action**: Click "Hatch Your Axolotl" → Input ETH amount → Confirm

**Frontend Flow**:

```typescript
const { writeContractAsync } = useScaffoldWriteContract({
  contractName: "AutoLpHelper",
});

await writeContractAsync({
  functionName: "swapEthToUsdcUsdtAndMint",
  value: parseEther(ethAmount), // e.g., "0.1"
});
```

**What Happens**:

1. User inputs ETH amount (e.g., 0.1 ETH)
2. Wallet prompts for transaction approval
3. AutoLpHelper executes:
   - Swap 50% ETH → USDC (creates positive delta)
   - Swap 50% ETH → USDT (creates positive delta)
   - Call PositionManager to mint NFT-based LP position using deltas
   - LP position NFT minted to user (user-owned, transferable)
4. EggHatchHook triggers on LP creation with hookData containing NFT tokenId
5. PetRegistry mints pet linked to PositionManager NFT tokenId
6. Event emitted: `PetHatched(petId, owner, chainId, poolId, positionId)`

**State Changes**:

- Blockchain: New LP position + PositionManager NFT + Pet created
- User balance: -0.1 ETH, +PositionManager NFT, +dust USDC/USDT (leftovers)
- User sees: Egg cracking animation → Axolotl appears

**Key Architectural Change**: LP positions are now **user-owned NFTs** (Uniswap v4 PositionManager), not controlled by AutoLpHelper. Users can transfer, manage, or burn their positions independently.

**Data Returned**:

```solidity
event PetHatched(
    uint256 indexed petId,
    address indexed owner,
    bytes32 positionId,
    uint256 health,      // Always 100 at birth
    uint256 chainId,
    uint256 timestamp
);
```

**Frontend Updates**:

```typescript
// Listen for event
const { data: events } = useScaffoldEventHistory({
  contractName: "PetRegistry",
  eventName: "PetHatched",
  watch: true
});

// Display axolotl with initial state
<Axolotl
  health={100}
  chainId={chainId}
  isHatching={true}  // Trigger animation
/>
```

**Edge Cases**:

- Insufficient ETH → Revert with error message
- Slippage too high → Revert with `InsufficientOutput`
- Hook not installed → LP created but no pet (error)
- User cancels tx → No state change

**Validation**:

- Minimum ETH: 0.01 (configurable)
- Maximum ETH: No limit (but warn if >1 ETH)
- Check user has enough gas

---

### 4. View Axolotl Dashboard

**User Action**: Landing on homepage (already hatched pet)

**Frontend Flow**:

```typescript
// Read user's pets
const { data: petIds } = useScaffoldReadContract({
  contractName: "PetRegistry",
  functionName: "getPetsByOwner",
  args: [userAddress],
});

// For each petId, read pet data
const { data: pet } = useScaffoldReadContract({
  contractName: "PetRegistry",
  functionName: "getPet",
  args: [petId],
});

// Read LP position data
const { data: lpPosition } = useScaffoldReadContract({
  contractName: "PoolManager",
  functionName: "getPosition",
  args: [positionId],
});
```

**What User Sees**:

```
┌─────────────────────────────────┐
│  Your Axolotl #1                │
│                                 │
│     🐸 [Animated Axolotl]      │
│                                 │
│  Health: ████████░░ 85%        │
│  Chain: Sepolia 🔵             │
│  Age: 3 days                   │
│                                 │
│  LP Position:                  │
│  Liquidity: 338B               │
│  Fees Earned: $2.34            │
│  Range: 0.998 - 1.002          │
│  Status: 🟢 In Range           │
│                                 │
│  [Feed] [Adjust] [Travel]      │
└─────────────────────────────────┘
```

**Data Displayed**:

- Pet metadata (health, age, chain)
- LP position details (liquidity, range, fees)
- Current pool price + position status
- Action buttons (Feed, Adjust Range, Travel, Close)

**Real-time Updates**:

- Health updates via `HealthUpdated` event listener
- LP fees update every block
- Animation speed tied to health value

---

### 5. Feed Axolotl (Add Liquidity)

**User Action**: Click "Feed" button → Input additional ETH → Confirm

**Frontend Flow**:

```typescript
await writeContractAsync({
  functionName: "feedAxolotl",
  args: [petId],
  value: parseEther("0.05"), // Additional ETH
});
```

**What Happens**:

1. User inputs additional ETH
2. Transaction creates NEW LP position (MVP approach)
   - OR increases liquidity in existing position (future)
3. PetRegistry updates pet metadata (optional health boost)
4. Event emitted: `PetFed(petId, ethAdded, liquidityIncrease)`

**State Changes**:

- Blockchain: More liquidity in LP position
- Pet health: Temporary +10 point boost (capped at 100)
- User sees: Feeding animation, health bar increases

**Animation**:

- Axolotl opens mouth
- Food particle animation
- Belly grows slightly
- Happy bounce effect
- Sparkles appear

**Edge Cases**:

- Position out of range → Still adds liquidity but warns user
- Very small amount (<0.01 ETH) → Warning about gas costs
- Position closed → Error: "Cannot feed retired pet"

---

### 6. Adjust Range (Rebalance LP)

**User Action**: Click "Adjust" → See current price → Input new range → Confirm

**Frontend Flow**:

```typescript
// Close old position
await writeContractAsync({
  functionName: "closeLiquidity",
  args: [petId],
});

// Create new position with better range
await writeContractAsync({
  functionName: "swapEthToUsdcUsdtAndMint",
  value: receivedEth,
});
```

**What Happens**:

1. Frontend shows current pool price + suggested ranges
2. User adjusts tickLower and tickUpper sliders
3. Transaction closes old LP position
4. New LP position created with new range
5. PetRegistry updates pet's positionId
6. Health recalculated based on new range

**State Changes**:

- Old position closed (liquidity → USDC + USDT)
- New position opened (USDC + USDT → liquidity)
- Pet positionId updated
- Health potentially restored if new range is better

**Visual Feedback**:

```
Old Range:  ├────[OUT]────█─────┤  (Price moved away)
New Range:  ├─────────█[IN]─────┤  (Recentered)
```

**Animation**:

- Axolotl stretches and repositions
- Range visualization updates
- Health bar fills if improved

**Edge Cases**:

- Price moved significantly → Offer "auto-range" suggestion
- Gas cost > potential fees → Warning
- Multiple failed attempts → Offer help/tutorial

---

### 7. Collect Fees

**User Action**: Click "Collect Fees" button

**Frontend Flow**:

```typescript
// Read uncollected fees
const { data: fees } = useScaffoldReadContract({
  contractName: "PoolManager",
  functionName: "getPositionFees",
  args: [positionId],
});

// Collect fees
await writeContractAsync({
  functionName: "collectFees",
  args: [petId],
});
```

**What Happens**:

1. PoolManager transfers accumulated fees to user
2. Fees received in USDC + USDT
3. PetRegistry logs collection (optional: convert to treats)
4. Event emitted: `FeesCollected(petId, usdcAmount, usdtAmount)`

**State Changes**:

- User receives USDC + USDT
- Accumulated fees reset to 0
- Pet "happiness" increases (visual only)

**Animation**:

- Coins fly from pool to wallet
- Axolotl celebrates with confetti
- Counter shows amount collected

**Display**:

```
Fees Collected!
💰 $2.34 in fees
   (1.17 USDC + 1.17 USDT)
```

**Edge Cases**:

- No fees accumulated → Button disabled
- Very small amount → Warn about gas costs
- Position out of range → Can still collect past fees

---

### 8. Travel to Another Chain (Intent-Based via The Compact + Li.FI)

**User Action**: Click "Travel" → Select destination chain → Sign intent (1 signature!)

**Frontend Flow**:

```typescript
// Step 1: User selects destination chain from dropdown
const selectedChain = destinationChain; // User picks from: Sepolia, Base, etc.

// Step 2: Prepare MultichainCompact parameters
const travelParams = {
  petId: userPet.id,
  destinationChainId: selectedChain.id, // e.g., 84532 (Base Sepolia), 11155111 (Sepolia), 8453 (Base), 1 (Ethereum)
  tickLower: userPet.tickLower, // Keep same range
  tickUpper: userPet.tickUpper,
  minLiquidity: userPet.liquidity * 0.95, // Allow 5% slippage
  deadline: Date.now() + 3600, // 1 hour expiry
};

// Step 3: User signs EIP-712 compact
const signature = await signTypedData({
  domain: COMPACT_DOMAIN,
  types: MULTICHAIN_COMPACT_TYPES,
  value: travelParams,
});

// Step 4: Single transaction creates intent
await writeContractAsync({
  contractName: "AutoLpHelper",
  functionName: "travelToChain",
  args: [travelParams, signature],
});

// ✅ Done! Solver bot handles everything else
```

**What Happens**:

**On Source Chain (Sepolia)**:

1. `AutoLpHelper.travelToChain()` closes LP position → USDC + USDT
2. Deposits USDC + USDT into The Compact (creates resource locks)
3. Registers MultichainCompact with witness data
4. Emits `IntentCreated(compactId, petId, destinationChainId)` event

**Solver Bot Sees Intent**:

5. Monitors `IntentCreated` events
6. Calculates profitability: `lockedAssets - (bridgeFees + gas)`
7. Uses **Li.FI SDK** to find optimal bridge route:

```typescript
const routes = await lifi.getRoutes({
  fromChainId: 11155111, // Sepolia
  toChainId: 84532, // Base
  fromTokenAddress: USDC,
  toTokenAddress: USDC,
  fromAmount: intent.usdcAmount,
});
```

**Solver Fulfills (Off-Chain)**:
**Settlement (Back to Source Chain)**: 13. Arbiter verifies LP exists and matches conditions 14. Calls `TheCompact.processClaim()` to release locked USDC + USDT to solver 15. Emits `ClaimProcessed(compactId, solver, timestamp)` 9. Creates LP position on Base on behalf of user using bridged tokens

**On Destination Chain (Base)**: 10. Solver calls `AutoLpHelper.mintLpFromTokens(usdcAmount, usdtAmount, userAddress)` on destination - Mints LP position using pre-bridged USDC/USDT tokens (no swapping needed) - Gets positionId from transaction receipt 11. Solver receives positionId confirming LP creation 12. Calls `LPMigrationArbiter.verifyAndClaim(positionId, compactId, solverAddress)`

**Settlement (Back to Source Chain)**: 13. Arbiter verifies LP exists and matches conditions 14. Calls `TheCompact.processClaim()` to release locked USDC + USDT to solver 15. Emits `ClaimProcessed(compactId, solver, timestamp)`

**State Changes**:

- Source chain: LP closed, assets locked in The Compact, then released to solver
- Destination chain: New LP created, new pet minted (Option A: separate pet per chain)
- User sees: "Arrived!" notification when `ClaimProcessed` event detected

**Animation**:

```
User signs → "Boarding train..."
          ↓
Solver working → "In Transit..." (show progress bar)
          ↓
LP created → "Arrived!" (celebration animation)
          ↓
Chain badge updates (Sepolia 🔵 → Base 🟣)
```

**UI Flow**:

```
┌─────────────────────────────────────────┐
│  Travel to Base Sepolia?                │
│                                         │
│  Current: Sepolia 🔵                    │
│  Destination: Base 🟣                   │
│                                         │
│  Position: $300 USDC/USDT LP            │
│  Estimated Time: 2-5 minutes ⚡        │
│  Cost: Solver finds best route via Li.FI│
│                                         │
│  ✨ One signature - automatic travel! │
│                                         │
│  [Cancel]  [Sign & Travel] 🚀          │
└─────────────────────────────────────────┘

After signing:
┌─────────────────────────────────────────┐
│  🚂 Travel in Progress                  │
│                                         │
│  ▓▓▓▓▓▓▓▓▓░░░░░░░ 60%                   │
│                                         │
│  ✅ Intent created on Sepolia          │
│  ⏳ Solver bridging via Li.FI...        │
│  ⏳ Creating LP on Base...              │
│                                         │
│  Solver: 0x1234...5678                  │
└─────────────────────────────────────────┘
```

**User Experience Benefits**:

- ✨ **One signature** - no manual bridging steps
- ⚡ **2-5 minutes** - faster than traditional multi-tx flow
- 💰 **Optimal pricing** - Li.FI finds cheapest bridge automatically
- 🔒 **Trustless** - The Compact guarantees execution
- 🤖 **Automated** - Solver handles all complexity

**Edge Cases**:

- No solver available → Intent expires after deadline, refund available
- Bridge fails → Solver retries with different Li.FI route
- Slippage too high → Arbiter rejects claim, solver doesn't get paid
- **MVP limitation**: Separate pet on each chain (no cross-chain state sync)
- **Future**: Support intent cancellation before fulfillment

**Technical Details**:

- **The Compact**: Intent settlement layer (trustless escrow)
- **Li.FI**: Bridge routing layer (finds optimal path for solver)
- **Solver Economics**: Only profitable intents get fulfilled
- **Witness Data**: Encodes LP creation requirements (tick range, min liquidity)

---

### 9. Close Position (Retire Axolotl)

**User Action**: Click "Close Position" → Confirm warning

**Frontend Flow**:

```typescript
await writeContractAsync({
  functionName: "closeLiquidity",
  args: [petId],
});
```

**What Happens**:

1. LP position closed
2. User receives USDC + USDT (auto-swapped to ETH)
3. Pet marked as "retired" (frozen state)
4. Event emitted: `PositionClosed(petId, owner, timestamp)`

**State Changes**:

- LP position removed from PoolManager
- Pet health frozen at final value
- Pet NFT still exists but in "retired" state

**Animation**:

- Axolotl falls asleep
- Fades to grayscale
- "Retired" badge appears

**Warning Modal**:

```
⚠️ Close Position?

This will:
- Remove your LP position
- Return your USDC + USDT
- Retire your Axolotl (frozen state)

You can create a new Axolotl anytime!

[Cancel]  [Yes, Close Position]
```

**Edge Cases**:

- Accidental close → Confirmation modal required
- Large position → Extra warning about fees
- Can "revive" by creating new position later

---

## 🤖 Agent Behaviors (Unified System)

The Agent is a **single unified service** with dual responsibilities:

1. **Health Monitoring** (continuous polling)
2. **Intent Fulfillment** (event-driven solver)

Both run concurrently in the same process.

---

### 1. Monitor LP Positions (Health Monitoring)

**Trigger**: Every N blocks (e.g., every 10 blocks = ~2 minutes)

**Agent Logic**:

```typescript
// Fetch all active pets
const pets = await petRegistry.getAllPets();

for (const pet of pets) {
  // Read LP position state
  const position = await poolManager.getPosition(pet.positionId);
  const pool = await poolManager.getPool(poolKey);

  // Calculate health
  const newHealth = calculateHealth(
    pool.currentTick,
    position.tickLower,
    position.tickUpper,
  );

  // Update if changed significantly
  if (Math.abs(newHealth - pet.health) >= 5) {
    await petRegistry.updateHealth(pet.petId, newHealth);
  }
}
```

**When Agent Acts**:

- Health change ≥5 points
- Position moves in/out of range
- Significant price movement (>1%)

**When Agent Does NOT Act**:

- Health change <5 points (avoid gas waste)
- Position already at min/max health
- Recent update (avoid spam)

---

### 2. Calculate Health Deterministically

**Algorithm**:

```typescript
function calculateHealth(
  currentTick: number,
  tickLower: number,
  tickUpper: number,
): number {
  // In range → perfect health
  if (currentTick >= tickLower && currentTick <= tickUpper) {
    return 100;
  }

  // Out of range → calculate distance penalty
  const distanceFromLower = Math.abs(currentTick - tickLower);
  const distanceFromUpper = Math.abs(currentTick - tickUpper);
  const distance = Math.min(distanceFromLower, distanceFromUpper);

  // Penalty: 2 health points per tick distance
  const penalty = distance * 2;
  const health = Math.max(0, 100 - penalty);

  return health;
}
```

**Example Scenarios**:

```
Scenario 1: In Range
tickLower: -10, tickUpper: 10, currentTick: 0
→ health = 100 ✅

Scenario 2: Slightly Out
tickLower: -10, tickUpper: 10, currentTick: 15
→ distance = min(|15 - (-10)|, |15 - 10|) = 5
→ health = 100 - (5 * 2) = 90 🟡

Scenario 3: Far Out
tickLower: -10, tickUpper: 10, currentTick: 50
→ distance = min(|50 - (-10)|, |50 - 10|) = 40
→ health = 100 - (40 * 2) = 20 (clamped to 0-100) 🔴
```

**Why Deterministic**:

- User can verify calculation off-chain
- No randomness or agent discretion
- Transparent and auditable

---

### 3. Submit Health Updates

**Transaction Flow**:

```typescript
// Agent signs transaction
const tx = await petRegistry.updateHealth(petId, newHealth, {
  gasLimit: 100000,
  maxFeePerGas: lowGasPrice, // Use low gas for non-urgent
});

await tx.wait();

console.log(`✅ Updated Pet #${petId}: ${oldHealth} → ${newHealth}`);
```

**Gas Optimization**:

- Use low gas price (agent is not time-sensitive)
- Batch multiple updates in single tx (future)
- Only update when change is significant

**Logging**:

```
[2026-02-03 10:15:23] Agent Monitor Started
[2026-02-03 10:15:30] Checking 5 active pets...
[2026-02-03 10:15:32] Pet #1: health 85 (no change)
[2026-02-03 10:15:33] Pet #2: health 72 → 65 (submitting update)
[2026-02-03 10:15:45] ✅ Tx confirmed: 0xabc123...
[2026-02-03 10:15:46] Pet #3: health 100 (no change)
```

---

### 4. Handle Errors Gracefully

**Error Types**:

```typescript
try {
  await petRegistry.updateHealth(petId, newHealth);
} catch (error) {
  if (error.code === "INSUFFICIENT_FUNDS") {
    // Agent wallet needs gas
    console.error("⚠️ Agent out of gas!");
    notifyAdmin();
  } else if (error.message.includes("OnlyAgent")) {
    // Wrong agent address
    console.error("🚫 Not authorized");
  } else if (error.message.includes("revert")) {
    // Contract revert (e.g., invalid petId)
    console.error("❌ Contract revert:", error.message);
  } else {
    // Network error
    console.error("🌐 Network error, retrying...");
    await sleep(5000);
    retry();
  }
}
```

**Agent Reliability**:

- Automatic retries for network errors
- Monitoring of agent wallet balance
- Alerts if agent stops responding
- Fallback: Users can view "stale" health warnings

---

### 5. Alert User of Health Changes

**Notification Flow**:

```typescript
// Agent emits event after updating health
await petRegistry.updateHealth(petId, newHealth);
// → emits HealthUpdated(petId, oldHealth, newHealth, timestamp)

// Frontend listens and shows notification
const { data: events } = useScaffoldEventHistory({
  contractName: "PetRegistry",
  eventName: "HealthUpdated",
  watch: true,
});

useEffect(() => {
  if (events?.length > 0) {
    const latest = events[0];
    if (latest.args.newHealth < 50) {
      showNotification({
        type: "warning",
        title: "Your Axolotl needs attention!",
        message: `Health dropped to ${latest.args.newHealth}%`,
        action: "Rebalance LP",
      });
    }
  }
}, [events]);
```

**Notification Thresholds**:

- Health < 80: 🟡 Info notification
- Health < 50: 🟠 Warning notification
- Health < 20: 🔴 Critical alert + sound

---

### 6. Monitor Travel Intents (Intent Fulfillment)

**Trigger**: `IntentCreated` event emitted by `AutoLpHelper`

**Agent Logic**:

```typescript
// Listen for travel intents
autoLpHelper.on("IntentCreated", async (event) => {
  const { compactId, destinationChainId, usdcAmount, usdtAmount, userAddress } =
    event.args;

  // 1. Evaluate profitability
  const bridgeCost = await estimateLiFiBridgeCost(usdcAmount + usdtAmount);
  const gasEstimate = await estimateGasCost(destinationChainId);
  const revenue = usdcAmount + usdtAmount;
  const profit = revenue - bridgeCost - gasEstimate;

  if (profit < MIN_PROFIT_THRESHOLD) {
    console.log(`⏭️ Skipping intent ${compactId}: unprofitable (${profit})`);
    return;
  }

  // 2. Find optimal bridge route via Li.FI
  const routes = await lifi.getRoutes({
    fromChainId: sourceChainId,
    toChainId: destinationChainId,
    fromTokenAddress: USDC_ADDRESS,
    fromAmount: usdcAmount,
  });

  // 3. Execute bridge for both tokens
  await lifi.executeRoute(routes[0]); // USDC
  await lifi.executeRoute({ ...routes[0], fromAmount: usdtAmount }); // USDT

  // Wait for bridge completion
  await waitForBridgeCompletion(routes[0].id);

  // 4. Create LP on destination chain (Uniswap v4 interaction)
  const tx = await autoLpHelper.mintLpFromTokens(
    usdcAmount,
    usdtAmount,
    userAddress,
  );

  const receipt = await tx.wait();
  const positionId = receipt.events.find((e) => e.event === "LPCreated").args
    .positionId;

  // 5. Submit claim to receive payment
  await arbiter.verifyAndClaim(positionId, compactId, AGENT_ADDRESS);

  console.log(
    `✅ Intent ${compactId} fulfilled, LP created on chain ${destinationChainId}`,
  );
});
```

**When Agent Fulfills**:

- Intent is profitable (revenue > costs)
- Agent has sufficient capital on source chain
- Destination chain is supported (Sepolia ↔ Base Sepolia)
- Li.FI route is available

**When Agent Does NOT Fulfill**:

- Unprofitable intent (costs exceed revenue)
- Agent capital depleted
- Unsupported destination chain
- Li.FI bridge route unavailable

**Uniswap v4 Interactions per Journey**:

1. **Read pool state** (source chain) - `IPoolManager.getSlot0()`
2. **Read position details** (source chain) - `IPositionManager.getPosition()`
3. **Decrease liquidity** (source chain) - via `AutoLpHelper.travelToChain()`
4. **Read pool state** (destination chain) - `IPoolManager.getSlot0()`
5. **Mint LP position** (destination chain) - `AutoLpHelper.mintLpFromTokens()`
6. **Read new position** (destination chain) - `IPositionManager.getPosition()`

**Total: 6+ Uniswap v4 interactions per user journey** 🎯

---

### 7. Handle Solver Errors

**Error Types**:

```typescript
try {
  await fulfillIntent(intent);
} catch (error) {
  if (error.message.includes("LiFi bridge failed")) {
    // Retry with different route
    const alternateRoute = routes[1];
    await lifi.executeRoute(alternateRoute);
  } else if (error.message.includes("Insufficient capital")) {
    // Agent needs rebalancing
    console.error("⚠️ Agent capital depleted on chain", destinationChainId);
    notifyAdmin("Rebalance needed");
  } else if (error.message.includes("Claim rejected")) {
    // Arbiter rejected claim (LP didn't meet conditions)
    console.error("❌ Claim rejected for intent", compactId);
    // Agent loses bridged capital (risk of solver role)
  }
}
```

**Agent Economics**:

- Maintains capital float on each chain (e.g., 10 ETH worth)
- Only fulfills profitable intents (profit > 0.1%)
- Rebalances liquidity between chains using Li.FI periodically
- Monitors gas prices to avoid unprofitable execution

---

## 🔗 Blockchain Responses

### Event: PetHatched

**Emitted When**: New LP position created + pet minted

**Event Definition**:

```solidity
event PetHatched(
    uint256 indexed petId,
    address indexed owner,
    bytes32 positionId,
    uint256 health,
    uint256 chainId,
    uint256 timestamp
);
```

**Frontend Action**:

- Display egg hatching animation
- Load pet data from PetRegistry
- Show initial health bar (100)
- Enable pet management buttons

---

### Event: HealthUpdated

**Emitted When**: Agent updates pet health

**Event Definition**:

```solidity
event HealthUpdated(
    uint256 indexed petId,
    uint256 oldHealth,
    uint256 newHealth,
    uint256 timestamp
);
```

**Frontend Action**:

- Animate health bar change
- Update axolotl visual state
- Show notification if significant drop
- Log update in activity feed

---

### Event: LiquidityAdded

**Emitted When**: User adds more liquidity (feeds)

**Event Definition**:

```solidity
event LiquidityAdded(
    uint256 indexed petId,
    address indexed owner,
    uint128 liquidityAdded,
    uint256 timestamp
);
```

**Frontend Action**:

- Play feeding animation
- Update LP position display
- Boost health bar temporarily
- Show success message

---

### Event: PositionClosed

**Emitted When**: User closes LP position

**Event Definition**:

```solidity
event PositionClosed(
    uint256 indexed petId,
    address indexed owner,
    uint256 timestamp
);
```

**Frontend Action**:

- Play retirement animation
- Freeze axolotl in final state
- Display "Retired" badge
- Show final stats summary

---

## 🎨 Animation States

| Health Range | Animation Speed  | Color          | Mood     | Special FX  |
| ------------ | ---------------- | -------------- | -------- | ----------- |
| 100-80       | Fast (1x)        | Vibrant        | Happy    | Sparkles    |
| 79-50        | Normal (0.8x)    | Slightly muted | Alert    | Gentle glow |
| 49-20        | Slow (0.5x)      | Dim            | Sad      | Droopy      |
| 19-0         | Very slow (0.2x) | Grayscale      | Critical | "Zzz" icon  |

---

## 📱 Responsive Behavior

**Desktop**:

- Full dashboard with multiple pets
- Detailed LP stats visible
- Side-by-side comparison

**Mobile**:

- Single pet view with swipe navigation
- Collapsed LP details (expand on tap)
- Bottom sheet for actions

**Tablet**:

- 2-column grid layout
- Medium detail level

---

This interaction reference should guide implementation of all user-facing features and agent behaviors.
