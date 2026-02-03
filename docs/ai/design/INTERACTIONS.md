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
- User sees: Connected address in header
- Available actions: All buttons now active

**Edge Cases**:

- Wrong network → Show network switch prompt
- Wallet locked → Prompt to unlock
- No wallet installed → Show installation instructions

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
- Faucet sends 0.1 ETH to user
- Transaction confirmed

**State Changes**:

- User balance: +0.1 ETH
- User sees: Updated balance in UI
- Button state: Disabled for cooldown period

**Edge Cases**:

- Cooldown active → Show countdown timer
- Faucet empty → Show error message
- Already has ETH → Optional skip

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
   - Swap 50% ETH → USDC
   - Swap 50% ETH → USDT
   - Create LP position in USDC/USDT pool
4. EggHatchHook triggers on LP creation
5. PetRegistry mints pet NFT
6. Event emitted: `PetHatched(petId, owner, positionId, health, chainId)`

**State Changes**:

- Blockchain: New LP position + Pet NFT created
- User balance: -0.1 ETH, +dust USDC/USDT (leftovers)
- User sees: Egg cracking animation → Axolotl appears

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

- Old position closed (liquidity → USDC + USDT → ETH)
- New position opened (ETH → USDC + USDT → liquidity)
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

### 8. Travel to Another Chain

**User Action**: Click "Travel" → Select destination chain → Confirm

**Frontend Flow**:

```typescript
// Step 1: Close LP on source chain
await writeContractAsync({
  functionName: "closeLiquidity",
  args: [petId],
});

// Step 2: Bridge via LI.FI (or manual bridge)
const lifiQuote = await getLifiQuote({
  fromChain: currentChain,
  toChain: destinationChain,
  fromToken: "ETH",
  toToken: "ETH",
  amount: ethAmount,
});

await executeLifiBridge(lifiQuote);

// Step 3: Create new LP on destination chain
// (User must switch network and execute manually for MVP)
```

**What Happens**:

1. LP position closed on source chain
2. Assets (ETH) bridged to destination chain
3. User manually creates new LP on destination
4. PetRegistry on new chain mints new pet (OR updates via cross-chain message)

**State Changes**:

- Source chain: LP closed, pet marked as "traveling"
- Destination chain: New LP created, pet appears

**Animation**:

- Axolotl boards a train/portal
- Travel progress bar (bridge in progress)
- Arrival animation on destination
- Chain badge updates (Sepolia → Base)

**UI Flow**:

```
┌─────────────────────────────┐
│  Travel to Base Sepolia?    │
│                             │
│  Current: Sepolia 🔵        │
│  Destination: Base 🟣       │
│                             │
│  Bridge Time: ~10 minutes   │
│  Gas Cost: ~$0.50           │
│                             │
│  [Cancel]  [Confirm Travel] │
└─────────────────────────────┘
```

**Edge Cases**:

- Bridge unavailable → Show error
- Insufficient gas on destination → Warn before bridging
- Bridge stuck → Show support instructions
- **MVP limitation**: Separate pet on each chain (no cross-chain state sync)

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

## 🤖 Agent Behaviors

### 1. Monitor LP Positions

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
