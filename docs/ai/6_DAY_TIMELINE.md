# Xolotrain 6-Day Hackathon Timeline

**Deadline**: 6 days from now  
**Goal**: Functional MVP with intent-based cross-chain LP travel

---


## 🚨 CRITICAL: Egg Delivery Flow (DESIGN DECISION)

**Status**: ❓ Unclear how users acquire eggs before hatching

**Current Implementation**:

- AutoLpHelper `swapEthToUsdcUsdtAndMint()` creates LP position
- EggHatchHook fires `afterAddLiquidity` and mints pet NFT
- But conceptually: where's the "egg" in this flow?

**Options to Consider**:

1. **No Egg NFT** (Simplest - Current)
   - User clicks "Hatch" → LP created + pet minted atomically
   - "Egg" is just UI metaphor, not on-chain asset
   - ✅ Simplest, fewer contracts
   - ❌ Can't gift/trade eggs separately

2. **Egg NFT Pre-Mint**
   - User mints egg NFT first (separate transaction)
   - When creating LP, burn egg + mint pet
   - ✅ Eggs are tradeable assets
   - ❌ Extra transaction, more gas, egg contract needed

3. **Egg Auto-Airdrop on Wallet Connect**
   - Every new user gets 1 egg automatically
   - Hook burns egg when hatching
   - ✅ Simple onboarding
   - ❌ Requires automation, potential abuse

**Decision Needed**: Pick option and implement before hook address is fixed

**Priority**: 🟡 MEDIUM - Affects UX but not blocking

---

## 🎯 MVP Scope (What We're Building)

### Core Features ✅

1. **Wallet Connection** - Already done ✅
2. **Faucet Flow** - Already done ✅
3. **LP Creation (Hatch)** - AutoLpHelper working ✅
4. **Health System** - Agent monitors + updates health
5. **Pet Display** - Axolotl visual with health states
6. **Travel (Intent-Based)** - The Compact + Li.FI Composer + solver
7. **Li.FI Integration** - Solver uses Li.FI SDK for optimal cross-chain routing 🎯

### Out of Scope for Hackathon ❌

- Multiple solvers / solver marketplace
- Feed/Rebalance/Close actions (focus on create + travel)
- Evolution system
- Leaderboards
- Mobile optimization

---

## 📅 Day-by-Day Breakdown

### **Day 1 (Today): Contracts Foundation** ⏱️ 8-10 hours

**Morning (4 hours)**:

- [x] Review architecture documents
- [x] Design PetRegistry contract
  - Pet struct: owner, positionId, chainId, health, birthBlock
  - Minting logic: `hatchFromHook()`
  - Health update: `updateHealth()` with `onlyAgent` modifier
  - Events: `PetHatched`, `HealthUpdated`
- [x] Design EggHatchHook contract
  - Implement `afterAddLiquidity()` hook
  - Call `PetRegistry.hatchFromHook()`
  - Pass position data from hook params

**Afternoon (4-6 hours)**:

- [x] Implement PetRegistry contract
- [x] Implement EggHatchHook contract
- [x] Write basic tests (Foundry)
- [x] Update packages/nextjs/app/liquidity/page.tsx to properly show needed info from contracts
- [x] Deploy to local Anvil fork

**Evening Review**:

- Contracts compile ✅
- Tests pass ✅
- Can hatch pet from LP creation ✅

---

### **Day 2: The Compact Integration** ⏱️ 8-10 hours

**Morning (4 hours)**:

- [ ] Design XolotrainAllocator contract
  ```solidity
  - Implement IAllocator interface
  - Simple nonce management (mapping)
  - attest() for transfers
  - authorizeClaim() for travel intents
  ```
- [ ] Implement XolotrainAllocator
- [ ] Write tests for allocator

**Afternoon (4-6 hours)**:

- [ ] Design LPMigrationArbiter contract
  ```solidity
  - verifyAndClaim() function
  - Verify LP position exists on destination
  - Match with compact witness data
  - Call TheCompact.processClaim()
  ```
- [ ] Implement LPMigrationArbiter
- [ ] Add travel function to AutoLpHelper
  ```solidity
  travelToChain(petId, destinationChainId):
    - Close LP
    - Deposit to The Compact
    - Sign MultichainCompact
    - Emit TravelIntentCreated event
  ```

**Evening Review**:

- Allocator tests pass ✅
- Can create travel intent ✅
- Arbiter logic implemented ✅

---

### **Day 3: Solver Bot + Agent + Li.FI Integration** ⏱️ 9-11 hours

**❓ How The Compact + Li.FI Work Together**:

- **The Compact**: Provides intent layer (user signs once, assets locked, trustless settlement)
- **Li.FI**: Provides bridge routing layer (solver uses SDK to find optimal bridge)
- **Flow**: User creates intent → Solver uses Li.FI to bridge own capital → Solver creates LP → Solver claims locked assets
- **Why Both?**: The Compact handles **what** to do (intent), Li.FI handles **how** to do it (routing)

**Morning (4-5 hours)**:

- [ ] Set up agent/solver infrastructure
  ```
  agent/
  ├── monitor.ts      // Event monitoring
  ├── solver.ts       // Fulfill travel intents
  ├── lifi.ts         // Li.FI SDK integration 🎯
  ├── health.ts       // Health calculation + updates
  └── config.ts       // RPC, wallets, contracts
  ```
- [ ] **Li.FI SDK Setup** 🎯
  - Install `@lifi/sdk`
  - Initialize Li.FI client
  - Test quote fetching (Sepolia → Base)
- [ ] Implement health monitoring
  - Read LP positions from PoolManager
  - Calculate health deterministically
  - Submit `updateHealth()` when changed

**Afternoon (5-6 hours)**:

- [ ] Implement solver bot with Li.FI
  - Monitor `TravelIntentCreated` events
  - Read compact details from The Compact
  - **Use Li.FI Composer for bridging**: 🎯
    ```typescript
    // Get optimal route
    const route = await lifi.getRoutes({
      fromChainId: 11155111, // Sepolia
      toChainId: 84532, // Base Sepolia
      fromTokenAddress: USDC,
      toTokenAddress: USDC,
      fromAmount: amount,
    });
    // Execute multi-step bridge+swap
    await lifi.executeRoute(route);
    ```
  - Create LP position on destination
  - Submit proof to arbiter
- [ ] Test solver on Anvil fork
- [ ] Handle error cases (bridge failures, insufficient liquidity)

**Evening Review**:

- Agent monitors events ✅
- Health updates working ✅
- Solver fulfills intents via Li.FI ✅
- Cross-chain routing optimized ✅

---

### **Day 4: Frontend Core** ⏱️ 8-10 hours

**Morning (4 hours)**:

- [ ] Design Axolotl component

  ```tsx
  <Axolotl health={85} chainId={11155111} isHatching={false} />
  ```

  - Visual states based on health
  - Animation speed tied to health
  - Color based on chain

**Afternoon (4-6 hours)**:

- [ ] Implement Hatch flow
  ```tsx
  HatchModal:
    - Input ETH amount
    - Call AutoLpHelper.swapEthToUsdcUsdtAndMint()
    - Listen for PetHatched event
    - Animate egg → axolotl
  ```
- [ ] Dashboard page
  - Read user's pets from PetRegistry
  - Display axolotl with health bar
  - Show LP position details
  - Real-time health updates via events

**Evening Review**:

- Can hatch axolotl from UI ✅
- Axolotl displays with health ✅
- LP stats visible ✅

---

### **Day 5: Travel Feature** ⏱️ 8-10 hours

**Morning (4 hours)**:

- [ ] TravelModal component
  ```tsx
  - Select destination chain
  - Sign MultichainCompact (EIP-712)
  - Call AutoLpHelper.travelToChain()
  - Show progress: Locked → Filling → Claimed
  ```
- [ ] Implement EIP-712 signing
  - MultichainCompact typehash
  - Witness data (mandate)
  - User signs with wallet

**Afternoon (4-6 hours)**:

- [ ] Travel animations
  - "Boarding train" when intent created
  - Progress bar tracking solver fulfillment
  - "Arrival" animation when ClaimProcessed event
  - Chain badge updates
- [ ] Deploy contracts to Sepolia + Base Sepolia
- [ ] Test full flow on testnets

**Evening Review**:

- Travel flow works end-to-end ✅
- Animations polished ✅
- Deployed on testnets ✅

---

### **Day 6: Polish + Demo Prep** ⏱️ 8-10 hours

**Morning (4 hours)**:

- [ ] Bug fixes from testing
- [ ] Error handling + user feedback
  - Transaction pending states
  - Error messages
  - Retry logic
- [ ] Gas optimizations

**Afternoon (3 hours)**:

- [ ] Visual polish
  - Health bar styling
  - Animations smoothing
  - Responsive layout (desktop focus)
  - Loading states

**Late Afternoon (3-4 hours)**:

- [ ] Demo preparation
  - Script demo flow
  - Prepare talking points
  - Record demo video
  - Test on fresh wallet
  - Prepare fallback (if testnet issues)

**Evening**: Submit! 🎉

---

## 🏆 Bounty Qualification Checklist

### **Li.FI Bounty: Best Use of LI.FI Composer** 💰

**Theme**: Multi-step DeFi workflow in single user experience

**Our Approach**: Cross-chain LP migration with one signature

- User signs intent → Solver uses Li.FI Composer to bridge → LP created on destination

**Requirements**:

- [ ] ✅ Use Li.FI SDK/APIs for cross-chain action
  - **Where**: Solver bot uses Li.FI to bridge USDC+USDT from source to destination
  - **How**: `lifi.getRoutes()` + `lifi.executeRoute()` for optimal routing
- [ ] ✅ Support at least two EVM chains
  - **Chains**: Sepolia ↔ Base Sepolia (testnet)
  - **Future**: Easily add Optimism, Arbitrum
- [ ] ✅ Working frontend that judges can click through
  - **Demo**: Hatch axolotl → Travel to Base → See arrival
  - **UI**: Clean Next.js interface with wallet connection
- [ ] ✅ GitHub repo + video demo
  - **Repo**: Full source code with README
  - **Video**: 3-minute demo (see script below)

**Unique Selling Point**:

> "First intent-based LP migration. User signs once, Li.FI finds optimal route, LP appears on destination chain. No manual bridging, no multiple transactions."

---

### **Uniswap Bounty: Build on v4 with Agent-Driven Systems** 💰

**Theme**: Agent-driven financial systems with reliability & transparency

**Our Approach**: Agent monitors LP health, updates pet state deterministically

**Requirements**:

- [ ] ✅ Build on Uniswap v4
  - **AutoLpHelper**: Creates LP positions in v4 pools atomically
  - **EggHatchHook**: v4 hook that triggers pet hatching on `afterAddLiquidity`
  - **Direct Integration**: Uses `IPoolManager` for swaps + liquidity
- [ ] ✅ Agent-driven behavior
  - **Health Agent**: Monitors LP positions, calculates health, updates on-chain
  - **Deterministic**: Same LP state → same health (verifiable)
  - **Programmatic**: Reads pool state via `StateLibrary.getSlot0()`
- [ ] ✅ Reliability & Transparency
  - **Deterministic Formula**: `health = f(currentTick, tickLower, tickUpper)`
  - **On-chain Events**: All updates logged (`HealthUpdated`, `PetHatched`)
  - **Verifiable**: Users can audit agent calculations off-chain
- [ ] ✅ Composability
  - **Hooks**: Custom hook integrates with any v4 pool
  - **Standard Interfaces**: IPoolManager, IPositionManager
  - **Modular**: Health agent, solver bot, frontend are independent
- [ ] ✅ Optional Hooks used meaningfully
  - **EggHatchHook**: Automatically mints pet NFT when LP created
  - **Tight Integration**: Links LP position to pet via `afterAddLiquidity`

**Deliverables**:

- [ ] ✅ Functional code (contracts + agent)
- [ ] ✅ TxIDs on testnet (Sepolia + Base)
- [ ] ✅ GitHub repository
- [ ] ✅ README with setup instructions
- [ ] ✅ Demo video (3 min)

**Unique Selling Point**:

> "Educational DeFi through gamification. Agent teaches LP management by keeping your pet healthy. Built entirely on Uniswap v4 with hooks."

---

## 📊 Risk Mitigation

### High Risk Items

1. **The Compact Integration Complexity**
   - Mitigation: Start Day 2, allocate extra time
   - Fallback: Simplify to direct bridge (no intent layer)

2. **Solver Bot Reliability**
   - Mitigation: Test extensively Day 3
   - Fallback: Manual solver execution during demo

3. **Cross-Chain Testnet Instability**
   - Mitigation: Deploy early (Day 5)
   - Fallback: Anvil fork demo with simulated bridging

### Medium Risk Items

4. **EIP-712 Signing Issues**
   - Mitigation: Use existing libraries (viem)
   - Fallback: Pre-signed compacts

5. **Event Monitoring Delays**
   - Mitigation: Poll frequently, use websockets
   - Fallback: Manual refresh button

### Low Risk Items

6. **Animation Performance**
   - Mitigation: Simple CSS animations
   - Fallback: Static images with state changes

---

## ✅ Success Criteria

### Must Have (MVP)

- ✅ User can hatch axolotl by creating LP
- ✅ Axolotl displays with health tied to LP
- ✅ Agent updates health automatically
- ✅ User can travel to new chain with one signature
- ✅ Solver fulfills travel intent
- ✅ Demo works reliably

### Nice to Have (Stretch)

- ⭐ Multiple chain support (add Optimism Sepolia)
- ⭐ Smooth animations
- ⭐ Feed/Rebalance actions
- ⭐ Mobile responsive
- ⭐ Li.FI Widget integration (in addition to SDK)

### Judge Appeal

- 🏆 **Innovation**: Intent-based cross-chain (novel for LP migration)
- 🏆 **UX**: One-click travel vs traditional multi-step
- 🏆 **Technical**: Uniswap v4 hooks + The Compact + deterministic agent
- 🏆 **Story**: "DeFi Tamagotchi teaches LP management through play"

---

## 🛠️ Daily Standup Questions

**Every morning, answer**:

1. What did I complete yesterday?
2. What am I working on today?
3. Any blockers?
4. Am I on track for deadline?

**Every evening, review**:

1. Did I hit today's goals?
2. What's spilling to tomorrow?
3. Need to cut scope?

---

## 📦 Deliverables

### Code

- [ ] Smart contracts (5 contracts)
- [ ] Agent/Solver bot (TypeScript)
- [ ] Frontend (Next.js)
- [ ] Tests (Foundry + frontend)

### Documentation

- [x] GAME_DESIGN.md
- [x] SYSTEM_ARCHITECTURE.md
- [x] INTERACTIONS.md
- [x] LIFI_COMPACT_FEASIBILITY.md
- [ ] README.md (update with demo instructions)
- [ ] Demo script

### Demo Assets

- [ ] Demo video (2-3 minutes)
- [ ] Slides (5-10 slides)
- [ ] Deployed contracts (Sepolia + Base)
- [ ] Live demo link (Vercel)

---

## 🎬 Demo Script (3 minutes)

**Intro (30 sec)**:

- "Hi, I'm [name] presenting Xolotrain"
- "A DeFi Tamagotchi where your pet's health is your LP performance"
- "Built on Uniswap v4 with intent-based cross-chain travel"

**Demo Part 1: Hatch (45 sec)**:

- "Watch me hatch an axolotl by creating an LP position"
- _Click Hatch, input 0.1 ETH, confirm_
- _Egg cracks, axolotl appears_
- "My axolotl is healthy because my LP is in range"

**Demo Part 2: Health (30 sec)**:

- "An agent monitors my LP and updates health automatically"
- _Show health bar, explain in-range = healthy_
- "This teaches users to monitor LP positions"

**Demo Part 3: Travel (60 sec)**:

- "Now I want to travel to Base"
- _Click Travel, select Base, sign intent_
- "Instead of 6 manual transactions, I sign once"
- "A solver bot fulfills my intent in 2 minutes"
- _Show progress, arrival animation_
- "My axolotl is now on Base!"

**Tech Stack (15 sec)**:

- "Built with Uniswap v4 hooks for hatching"
- "The Compact for intent-based settlement"
- "**Li.FI Composer for optimal cross-chain routing**" 🎯
- "Deterministic agent for health updates"

**Bounty Highlights (15 sec)**:

- "For **Li.FI**: Multi-step DeFi in one click - cross-chain LP migration"
- "For **Uniswap**: Agent-driven LP health monitoring with v4 hooks"

**Closing (15 sec)**:

- "Xolotrain makes DeFi educational and fun"
- "Learn LP management by keeping your axolotl alive!"
- "Thank you!"

---

## 🚀 Go Time!

You have 6 days. You've got this! The architecture is solid, scope is realistic, and you have clear daily goals.

**Remember**:

- Done is better than perfect
- Cut scope aggressively if behind
- Test on real testnets early
- Have fun! 🎉

**Key Mantra**: "Intent-based LP travel in one click!"
