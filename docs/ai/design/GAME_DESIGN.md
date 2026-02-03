# Xolotrain Game Design

## 🎮 Game Concept

**Xolotrain** is a blockchain-based Tamagotchi-style game where players nurture digital axolotl pets whose health is directly tied to the performance of their Uniswap v4 liquidity positions. Players earn rewards through active LP management while their pet companions react to and visualize their DeFi activity.

---

## 🎯 Core Game Loop

```
1. HATCH → User creates LP position → Axolotl egg hatches
2. NURTURE → LP position earns fees → Axolotl stays healthy
3. MONITOR → Agent tracks LP health → Updates axolotl state
4. MANAGE → User adjusts LP → Axolotl reacts to changes
5. TRAVEL → User bridges assets via Compact (intents)→ Axolotl moves to new chain
```

---

## 🐣 Game Mechanics

### 1. Hatching (Birth)

**Trigger**: User creates a USDC/USDT liquidity position via AutoLpHelper

**What Happens**:

- User deposits ETH (e.g., 0.1 ETH)
- Contract atomically swaps: ETH → 50% USDC + 50% USDT
- LP position created in Uniswap v4 USDC/USDT pool
- `EggHatchHook` fires on `afterAddLiquidity`
- **Axolotl hatches** with initial traits:
  - **Chain**: Current blockchain (Sepolia, Base, etc.)
  - **Health**: 100 (perfect health at birth)
  - **Position ID**: Linked to LP position
  - **Birth Block**: Timestamp of creation

**User Sees**:

- Egg cracking animation
- New axolotl appears with unique visual traits
- LP position details displayed
- Initial health bar (100%)

---

### 2. Health System

**Health Mechanics**:

Axolotl health is **deterministically calculated** based on LP position performance:

| LP State                       | Health Impact | Visual State                             |
| ------------------------------ | ------------- | ---------------------------------------- |
| **In Range** (earning fees)    | Health 80-100 | 🟢 Happy, animated, vibrant colors       |
| **Near Edge** (5% from range)  | Health 50-79  | 🟡 Alert, slower animation, warning glow |
| **Out of Range** (not earning) | Health 20-49  | 🟠 Sad, sluggish, dimmed colors          |
| **Far Out of Range** (>10%)    | Health 0-19   | 🔴 Critical, barely moving, monochrome   |

**Health Formula** (Deterministic):

```
health = 100 - (distance_from_range_center * penalty_multiplier)

Where:
- distance_from_range_center = 0 if in range, else tick distance
- penalty_multiplier = configurable per pool (default: 2)
- health clamped to [0, 100]
```

**What User Sees**:

- Real-time health bar
- Visual state changes (color, animation speed, mood)
- Tooltip explaining current LP status
- Notification when health drops below thresholds

**What Agent Does**:

- Monitors LP position state every N blocks
- Calculates health deterministically
- Calls `PetRegistry.updateHealth(petId, newHealth)` when changed
- Emits event logs for transparency

---

### 3. Feeding (LP Management)

**Actions**:

#### Add Liquidity (Feed)

- User deposits more ETH via AutoLpHelper
- Increases liquidity in existing position
- **Effect**: Health boost +10-20 points (temporary)
- **Visual**: Axolotl eats, grows slightly larger, sparkle effect

#### Adjust Range (Rebalance)

- User closes old position, opens new position with better range
- Resets health to optimal if new range is in-range
- **Visual**: Axolotl stretches, repositions, renewed energy

#### Collect Fees (Reward)

- User claims accumulated trading fees
- Converts to treats/rewards (tracked off-chain or on-chain)
- **Visual**: Axolotl celebrates, confetti effect, happiness boost

#### Remove Liquidity (Starve)

- User withdraws partial liquidity
- **Effect**: Health penalty -10-30 points
- **Visual**: Axolotl shrinks, looks hungry, sad animation

#### Close Position (Release)

- User fully exits LP position
- Axolotl enters "retirement" state (frozen, nostalgic mode)
- Can be "revived" by creating new LP position

---

### 4. Travel (Cross-Chain) [Intent-Based via The Compact]

**Trigger**: User clicks "Travel" and signs intent

**The Magic** (Intent-Based Architecture):

1. **User signs once**: Creates "compact" (intent) saying "I want my LP on Base"
2. **Assets locked**: Current LP closed, tokens locked in The Compact on source chain
3. **Solver fulfills**: Off-chain solver provides liquidity on destination chain FIRST
4. **LP created**: New position appears on destination (user's wallet)
5. **Solver paid**: Claims locked assets from source chain as payment
6. **Complete**: Entire process takes 2-5 minutes

**What Happens Behind the Scenes**:

**Source Chain (Sepolia)**:

- LP position closed → USDC + USDT
- Tokens deposited into The Compact (resource locks created)
- MultichainCompact signed with witness data:
  ```
  {
    arbiter: LPMigrationArbiter,
    destinationChain: Base,
    mandate: {
      tickLower: -10,
      tickUpper: 10,
      minLiquidity: 300B,
      petId: 1
    }
  }
  ```
- Event emitted: `TravelIntentCreated(petId, destinationChain, compactId)`

**Solver (Off-chain Bot)**:

- Sees intent, evaluates profitability
- Uses own capital to bridge to destination
- Creates LP position on destination matching specs
- Submits proof to arbiter

**Destination Chain (Base)**:

- Arbiter verifies LP position exists and matches compact
- Calls The Compact to process claim
- Solver receives locked USDC + USDT as payment

**User Sees**:

- ✨ Sign once, no manual steps
- 🚂 "Boarding train" animation
- 📊 Travel progress: Locked → Solver Filling → LP Created → Claimed
- 🎉 Arrival animation on new chain
- 🟣 Updated chain badge (Sepolia 🔵 → Base 🟣)

**Agent Does**:

- Monitors `ClaimProcessed` event
- Updates `PetRegistry` with new chain + position ID
- Recalculates health for new position
- Maintains health continuity

---

### 5. Evolution (Stretch Goal)

**Concept**: Axolotls evolve based on LP performance history

**Evolution Tiers**:

- **Egg** (0 days): Just hatched
- **Tadpole** (1-7 days): Learning to swim
- **Juvenile** (8-30 days): Active and growing
- **Adult** (31-90 days): Mature and experienced
- **Elder** (90+ days): Legendary status

**Evolution Triggers**:

- Time-based (days LP position active)
- Performance-based (cumulative fees earned)
- Health-based (average health > 70)

**Visual Changes**:

- Size increases
- New color variations
- Special effects (glow, sparkles)
- Accessories (crown, medals)

---

## 👤 User Experience Flow

### First Time User

```
1. CONNECT → Wallet connection prompt
2. FUND → Get testnet ETH via faucet
3. CREATE → Click "Hatch Your Axolotl"
4. INPUT → Enter ETH amount (e.g., 0.1 ETH)
5. CONFIRM → Approve transaction
6. HATCH → Watch egg crack animation
7. MEET → See your new axolotl
8. MONITOR → Health bar and LP stats displayed
```

### Returning User

```
1. CONNECT → Auto-connects wallet
2. VIEW → Dashboard shows all axolotls
3. SELECT → Click on an axolotl to see details
4. MANAGE → Options: Feed, Adjust, Travel, Close
5. OBSERVE → Health updates from agent
6. EARN → Collect fees periodically
```

---

## 🎨 Visual Design

### Axolotl Appearance

**Base Traits**:

- **Color**: Varies by chain (Sepolia = Blue, Base = Purple, etc.)
- **Eyes**: Expressive, react to health state
- **Gills**: External gills that flutter (animated)
- **Body**: Smooth, salamander-like body
- **Tail**: Long, wavy tail (animation speed = health)

**Health States**:

```
100-80: Full color, fast animation, sparkles
79-50:  Muted color, normal speed, occasional blinks
49-20:  Dim color, slow movement, droopy posture
19-0:   Grayscale, minimal movement, "zzz" sleep indicator
```

**Special Effects**:

- **Feeding**: Food animation, belly grows, happy bounce
- **Travel**: Train/portal effect, position shift
- **Level Up**: Glow effect, size increase, celebration
- **Critical Health**: Alert icon, pulsing red border

---

## 🏆 Rewards & Incentives

### Player Rewards

1. **Trading Fees**: Earned from LP position (Uniswap v4 native)
2. **Loyalty Bonus**: Extra rewards for maintaining health > 70
3. **Evolution Milestones**: Unlock special traits/accessories
4. **Multi-Chain Bonus**: Rewards for traveling to 3+ chains

### Leaderboard (Future)

- **Healthiest Axolotls**: Ranked by average health
- **Most Traveled**: Ranked by chains visited
- **Top Earners**: Ranked by total fees collected
- **Longest Lived**: Ranked by position age

---

## 🎲 Game Scenarios

### Scenario 1: Perfect Player

- Creates LP position in tight range around current price
- Price stays stable → Health stays 90-100
- Agent confirms health every hour → No action needed
- Player collects fees weekly → Axolotl celebrates

### Scenario 2: Market Moves

- Price shifts 5% away from LP range
- Health drops to 60 → Axolotl looks worried
- Agent notifies player of health drop
- Player rebalances position → Health restored to 95

### Scenario 3: Neglectful Player

- Creates LP, never checks back
- Price moves 20% out of range
- Health drops to 10 → Axolotl nearly fainted
- Agent sends urgent notification
- Player returns, adjusts position → Axolotl revives slowly

### Scenario 4: Chain Traveler (Intent-Based)

- Player starts on Sepolia (Blue Axolotl)
- Performs well, collects fees
- Decides to travel to Base Sepolia
- **Signs travel intent (one click)**
- Solver bot notices intent within seconds
- Solver provides liquidity on Base (uses own capital)
- **2 minutes later**: Axolotl appears on Base!
- Axolotl becomes Purple (Base color)
- Player signs ONE transaction total
- Solver gets paid from locked assets on Sepolia
- LP continues on new chain with similar health

---

## 🔮 Future Enhancements

1. **Social Features**:
   - Axolotl trading/gifting
   - Breeding (combine two positions → new axolotl)
   - Friend leaderboards

2. **Mini-Games**:
   - "Feed Frenzy": Quick collect fees game
   - "Range Runner": Optimal range prediction game

3. **Customization**:
   - Buy accessories with earned fees
   - Name your axolotl
   - Custom color palettes

4. **Integration**:
   - Support more Uniswap v4 pools
   - Multi-position axolotls (one pet, many LPs)
   - DeFi primitives (lending, staking)

---

## 📊 Success Metrics

- **Engagement**: Daily active users, return rate
- **LP Health**: Average position health across all players
- **Fee Generation**: Total fees earned by all positions
- **Retention**: Players active after 7, 30, 90 days
- **Cross-Chain**: % of players who have traveled

---

## 🎯 Design Principles

1. **LP First**: Health system incentivizes good LP management
2. **Deterministic**: Agent actions are transparent and verifiable
3. **Visual Feedback**: Every action has immediate visual response
4. **No Grinding**: Progress tied to time + performance, not clicks
5. **Educational**: Players learn DeFi concepts through gameplay
