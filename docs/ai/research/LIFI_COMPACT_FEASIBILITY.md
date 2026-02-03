# Cross-Chain LP Migration: Li.FI + The Compact Feasibility Analysis

## 🎯 Objective

Evaluate using **Li.FI Protocol** (cross-chain bridge aggregator) and **The Compact** (Uniswap's intent-based settlement protocol) to migrate LP positions across chains instead of traditional bridging.

---

## 📊 Current Approach vs. Proposed Approach

### Traditional Bridging (Current Plan)

```
Source Chain:
1. Close LP position → USDC + USDT
2. Swap to ETH
3. Bridge ETH to destination

Destination Chain:
4. Receive ETH
5. Swap to USDC + USDT
6. Create new LP position
```

**Problems**:

- 6 separate transactions (high failure points)
- Slippage on each swap
- Multiple gas costs
- Bridge wait time (5-30 minutes)
- User must manually execute each step

### Li.FI + The Compact (Proposed)

```
Source Chain:
1. Create "intent" via The Compact: "I want LP on destination chain"
2. Lock current LP assets in The Compact
3. Sign compact with cross-chain conditions

Solver/Filler (Off-chain):
4. Sees intent, provides liquidity on destination chain first
5. Submits proof of fulfillment to arbiter

Destination Chain:
6. New LP position created atomically

Source Chain:
7. Compact claims settled, solver receives locked assets
```

**Benefits**:

- Near-atomic cross-chain execution
- User signs once, solver handles complexity
- Competitive pricing (solvers compete for fills)
- Better UX (appears instant to user)
- Reduced failure modes

---

## 🔍 Technical Analysis

### The Compact Overview

**What it is**: An intent-based protocol for credibly committing tokens to be spent across asynchronous environments.

**Key Components**:

1. **Resource Locks** (ERC6909 tokens)
   - User deposits tokens → receives ERC6909 "lock" tokens
   - Lock properties: token, allocator, scope (single/multi-chain), reset period

2. **Compacts** (EIP-712 signed commitments)
   - `MultichainCompact`: Perfect for cross-chain LP migration
   - Defines: arbiter, expires, chain IDs, token commitments, witness data

3. **Allocators** (Smart contracts)
   - Prevent double-spending of locked resources
   - Validate that claims are legitimate
   - Custom logic for different use cases

4. **Arbiters** (Verification agents)
   - Verify conditions are met (e.g., LP created on destination)
   - Submit claims to The Compact
   - Often operated by fillers/solvers

5. **Claimants** (Solvers/Fillers)
   - Fulfill the intent off-chain
   - Provide proof to arbiter
   - Claim locked assets as payment

**Trust Model**:

- User trusts allocator won't censor valid claims
- User trusts arbiter will verify conditions correctly
- Filler trusts allocator won't double-spend locked funds

---

### Li.FI Protocol Overview

**What it is**: Multi-chain routing aggregator that finds optimal paths for cross-chain swaps/transfers.

**Key Features**:

- Aggregates 20+ bridges (Stargate, Across, Hop, etc.)
- Aggregates DEX aggregators (1inch, 0x, Paraswap)
- Smart routing finds cheapest + fastest path
- Unified API for all chains
- Redundancy (fallback routes if primary fails)

**How it works**:

```typescript
// Li.FI API call
const quote = await lifi.getQuote({
  fromChain: 1, // Ethereum
  toChain: 8453, // Base
  fromToken: "USDC",
  toToken: "USDC",
  fromAmount: "1000",
  fromAddress: user,
});

// Execute route
await lifi.executeRoute(quote);
```

**Relevance to LP Migration**:

- Can handle complex multi-step routes
- Supports contract calls on destination
- Can coordinate swaps + bridges + LP creation

---

## 🏗️ Proposed Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User (Source Chain - Sepolia)                               │
└────────────┬────────────────────────────────────────────────┘
             │
             │ 1. Close LP → USDC + USDT
             │ 2. Deposit into The Compact (resource locks)
             │ 3. Sign MultichainCompact
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ The Compact (Sepolia)                                       │
│  - Resource locks created (ERC6909)                         │
│  - Compact registered with witness:                         │
│    "Create LP on Base with X liquidity at ticks Y-Z"        │
└────────────┬────────────────────────────────────────────────┘
             │
             │ 4. Event emitted: IntentCreated
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Solver (Off-chain)                                          │
│  - Monitors The Compact events                              │
│  - Sees profitable intent                                   │
│  - Executes fulfillment:                                    │
│    a) Bridge own funds to Base via Li.FI                    │
│    b) Swap to USDC + USDT                                   │
│    c) Create LP position on behalf of user                  │
│    d) Generate proof of LP creation                         │
└────────────┬────────────────────────────────────────────────┘
             │
             │ 5. Submit proof to Arbiter
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ Arbiter (Destination Chain - Base)                          │
│  - Verifies LP position exists                              │
│  - Verifies position matches compact conditions             │
│  - Calls The Compact to process claim                       │
└────────────┬────────────────────────────────────────────────┘
             │
             │ 6. Claim approved
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ The Compact (Sepolia) - Settlement                          │
│  - Releases locked USDC + USDT to solver                    │
│  - Emits ClaimProcessed event                               │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ User sees: Axolotl traveled to Base! 🎉                     │
│  - LP position on Base verified                             │
│  - PetRegistry updated with new chain + positionId          │
└─────────────────────────────────────────────────────────────┘
```

---

## 💻 Implementation Details

### 1. Smart Contracts Required

#### Custom Allocator for Xolotrain

```solidity
// XolotrainAllocator.sol
contract XolotrainAllocator is IAllocator {
    mapping(address => mapping(uint256 => bool)) public noncesConsumed;

    function attest(
        bytes calldata attestation,
        address allocator
    ) external view returns (bytes4) {
        // Validate that compact hasn't been double-spent
        // Return success signature
        return IAllocator.attest.selector;
    }

    function authorizeClaim(
        Claim calldata claim,
        FunctionReference calldata claimPayload
    ) external returns (bytes4) {
        // Verify nonce not reused
        // Mark nonce as consumed
        // Validate claim parameters
        return IAllocator.authorizeClaim.selector;
    }
}
```

#### Custom Arbiter for LP Verification

```solidity
// LPMigrationArbiter.sol
contract LPMigrationArbiter {
    IPoolManager public immutable poolManager;
    ITheCompact public immutable compact;

    function verifyAndClaim(
        bytes32 positionId,
        uint256 sourceChainCompactId,
        address claimant
    ) external {
        // 1. Verify LP position exists on destination chain
        (uint128 liquidity, int24 tickLower, int24 tickUpper)
            = poolManager.getPosition(positionId);

        require(liquidity > 0, "Position not found");

        // 2. Decode compact witness to get expected params
        // 3. Verify position matches expectations
        // 4. Submit claim to The Compact

        compact.processClaim(/* claim data */);
    }
}
```

#### AutoLpHelper Extension

```solidity
// Add to AutoLpHelper.sol
function travelToChain(
    uint256 petId,
    uint256 destinationChainId
) external returns (bytes32 compactId) {
    // 1. Close existing LP position
    (uint256 usdcAmount, uint256 usdtAmount) = _closeLiquidity(petId);

    // 2. Approve The Compact to spend tokens
    IERC20(USDC).approve(address(theCompact), usdcAmount);
    IERC20(USDT).approve(address(theCompact), usdtAmount);

    // 3. Deposit into The Compact (create resource locks)
    uint256 usdcLockId = theCompact.deposit(
        USDC,
        ALLOCATOR_ID,
        RESET_PERIOD,
        usdcAmount
    );

    uint256 usdtLockId = theCompact.deposit(
        USDT,
        ALLOCATOR_ID,
        RESET_PERIOD,
        usdtAmount
    );

    // 4. Create and sign MultichainCompact
    MultichainCompact memory compact = MultichainCompact({
        sponsor: msg.sender,
        nonce: nextNonce++,
        expires: block.timestamp + 1 hours,
        elements: [
            Element({
                arbiter: LP_MIGRATION_ARBITER,
                chainId: destinationChainId,
                commitments: [
                    Lock({
                        lockTag: getLockTag(),
                        token: USDC,
                        amount: usdcAmount
                    }),
                    Lock({
                        lockTag: getLockTag(),
                        token: USDT,
                        amount: usdtAmount
                    })
                ],
                mandate: Mandate({
                    tickLower: desiredTickLower,
                    tickUpper: desiredTickUpper,
                    minLiquidity: minimumLiquidity,
                    petId: petId
                })
            })
        ]
    });

    // 5. Emit event for solvers
    emit TravelIntentCreated(petId, destinationChainId, compactId);

    return compactId;
}
```

### 2. Solver/Filler Infrastructure

**Solver Bot** (Off-chain):

```typescript
// solver.ts
class XolotrainSolver {
  async monitorIntents() {
    // Listen for TravelIntentCreated events
    theCompact.on("CompactRegistered", async (event) => {
      const compact = parseCompact(event);

      // Evaluate profitability
      if (await this.isProfitable(compact)) {
        await this.fulfillIntent(compact);
      }
    });
  }

  async fulfillIntent(compact: MultichainCompact) {
    const { destinationChain, usdcAmount, usdtAmount, mandate } = compact;

    // 1. Use Li.FI to bridge assets to destination
    const lifiRoute = await lifi.getQuote({
      fromChain: SOURCE_CHAIN,
      toChain: destinationChain,
      fromToken: "USDC",
      toToken: "USDC",
      fromAmount: usdcAmount.toString(),
      fromAddress: this.wallet.address,
    });

    await lifi.executeRoute(lifiRoute);

    // 2. Create LP position on destination
    const tx = await autoLpHelper.swapEthToUsdcUsdtAndMint({
      value: 0, // Using USDC/USDT directly
      tickLower: mandate.tickLower,
      tickUpper: mandate.tickUpper,
    });

    const receipt = await tx.wait();
    const positionId = receipt.events.find((e) => e.event === "PositionCreated")
      .args.positionId;

    // 3. Submit proof to arbiter
    await arbiter.verifyAndClaim(positionId, compact.id, this.wallet.address);

    // 4. Profit = locked assets on source chain
  }

  async isProfitable(compact: MultichainCompact): Promise<boolean> {
    // Calculate costs:
    // - Li.FI bridge fees
    // - Gas on both chains
    // - LP creation slippage

    // Calculate revenue:
    // - Locked USDC + USDT value

    const costs = await this.estimateCosts(compact);
    const revenue = this.calculateRevenue(compact);

    return revenue > costs * 1.05; // 5% profit margin minimum
  }
}
```

### 3. Frontend Integration

```typescript
// TravelModal.tsx
export function TravelModal({ petId, onClose }: Props) {
  const { writeContractAsync } = useScaffoldWriteContract("AutoLpHelper");

  async function handleTravel(destinationChain: number) {
    // 1. User signs MultichainCompact
    const signature = await signTypedData({
      domain: COMPACT_DOMAIN,
      types: MultichainCompactTypes,
      value: compactData
    });

    // 2. Submit travel intent
    const tx = await writeContractAsync({
      functionName: "travelToChain",
      args: [petId, destinationChain, signature]
    });

    // 3. Show progress UI
    setTravelStatus('waiting_for_solver');

    // 4. Listen for claim processed event
    const claimEvent = await waitForEvent('ClaimProcessed');

    // 5. Update UI - Axolotl arrived!
    setTravelStatus('arrived');
    playArrivalAnimation();
  }

  return (
    <Modal>
      <h2>Travel to {chainName}</h2>
      <p>Estimated time: ~2-5 minutes</p>
      <p>Cost: Bridge fees covered by solver competition</p>
      <button onClick={handleTravel}>Confirm Travel</button>
    </Modal>
  );
}
```

---

## ✅ Feasibility Assessment

### Technical Feasibility: **HIGH** ✅

| Component               | Status      | Complexity                                     |
| ----------------------- | ----------- | ---------------------------------------------- |
| The Compact integration | ✅ Possible | Medium - Well documented, audited contracts    |
| Custom allocator        | ✅ Possible | Low - Simple interface implementation          |
| Custom arbiter          | ✅ Possible | Medium - Needs LP verification logic           |
| Li.FI integration       | ✅ Possible | Low - Mature API/SDK                           |
| Solver infrastructure   | ✅ Possible | High - Requires off-chain bot + capital        |
| Frontend UX             | ✅ Possible | Medium - EIP-712 signatures + event monitoring |

**Verdict**: All technical components are achievable with existing tools.

---

### Economic Feasibility: **MEDIUM** ⚠️

**Challenges**:

1. **Solver Liquidity**: Solvers need capital to fulfill intents upfront
   - For MVP: Single solver (you) with modest capital
   - For production: Attract professional solver network

2. **Profitability**: Margins might be thin
   - Bridge fees: ~$0.10-1.00 depending on chain
   - Gas costs: ~$0.50-2.00 per chain
   - Solver profit: Needs ~5-10% markup
   - **Total cost to user**: ~$2-5 per travel (comparable to manual)

3. **Liquidity Fragmentation**:
   - If few users on destination chain, hard for solver to convert back
   - Mitigation: Start with popular chains (Sepolia, Base)

**Verdict**: Economically viable if solver competition develops. For hackathon, single solver is sufficient.

---

### UX Feasibility: **HIGH** ✅

**Pros**:

- ✅ One-click travel (sign once, done)
- ✅ No manual bridging steps
- ✅ Appears near-instant (2-5 min vs 10-30 min)
- ✅ Automatic LP recreation
- ✅ Transparent pricing (solver bids visible)

**Cons**:

- ⚠️ Requires EIP-712 signature (but users are used to this)
- ⚠️ "Trust" in solver (mitigated by The Compact's guarantees)
- ⚠️ Slight delay waiting for solver (but still faster than manual)

**Verdict**: Significant UX improvement over traditional bridging.

---

### Timeline Feasibility: **MEDIUM** ⚠️

**For Hackathon MVP**:

| Task                                     | Estimated Time            | Priority |
| ---------------------------------------- | ------------------------- | -------- |
| Deploy The Compact (already deployed)    | ✅ Done                   | High     |
| Build custom allocator                   | 4-6 hours                 | High     |
| Build custom arbiter                     | 6-8 hours                 | High     |
| Extend AutoLpHelper with travel function | 3-4 hours                 | High     |
| Build simple solver bot                  | 8-12 hours                | High     |
| Integrate Li.FI                          | 2-3 hours                 | Medium   |
| Frontend travel modal + events           | 4-6 hours                 | High     |
| Testing end-to-end                       | 6-8 hours                 | Critical |
| **TOTAL**                                | **33-47 hours** (~1 week) |          |

**Shortcuts for Hackathon**:

1. Use simplified allocator (no complex nonce management)
2. Single solver (your own bot) instead of marketplace
3. Li.FI can be optional (solver uses simple bridge)
4. Test on testnets only (Sepolia → Base Sepolia)

**Verdict**: Tight but achievable for hackathon if prioritized. Consider as stretch goal.

---

## 🎯 Recommendation

### Option A: Full Li.FI + The Compact (Recommended for Production)

**Implement if**:

- You have 1 week+ of development time
- You want to demonstrate cutting-edge intent-based UX
- You can run a solver bot during demo
- You want to impress judges with novel architecture

**Pros**:

- ✨ Best-in-class UX
- 🏆 High technical impressive factor
- 🚀 Production-ready foundation
- 📈 Scalable to multiple chains/solvers

**Cons**:

- ⏰ Higher development time
- 🧪 More testing needed
- 💰 Requires solver capital
- 🐛 More failure modes to handle

---

### Option B: Simplified Intent-Based (Recommended for Hackathon)

**Use The Compact WITHOUT Li.FI**:

- User signs compact for cross-chain LP migration
- **Single trusted solver** (your backend) fulfills intents
- Solver uses **simple bridge** (not Li.FI aggregation)
- Proof of concept for intent-based migration

**Pros**:

- ⏰ Faster to implement (~20-25 hours)
- 🎯 Demonstrates core concept
- 🧪 Less complexity to test
- 🏆 Still impressive for hackathon

**Cons**:

- ⚠️ Not fully decentralized (single solver)
- 📊 No optimal routing (just one bridge)
- 💸 Potentially higher costs

---

### Option C: Traditional Bridging with Li.FI (Easiest)

**Use Li.FI WITHOUT The Compact**:

- User clicks "Travel"
- Frontend calls Li.FI API for quote
- User approves Li.FI tx
- Li.FI handles bridge + destination LP creation

**Pros**:

- ⚡ Fastest to implement (~10-15 hours)
- 🛡️ Lower risk
- 📚 Well documented
- ✅ Guaranteed to work

**Cons**:

- 👎 Multiple user signatures required
- 😕 Less impressive technically
- 🐌 Slower UX (manual steps)
- ❌ Not leveraging The Compact innovation

---

## 🎖️ Final Verdict

**For EthGlobal Hackathon: Implement Option B (Simplified Intent-Based)**

### Why:

1. **Novelty**: Shows understanding of intent-based architecture (judges love innovation)
2. **UX**: One-click travel is magical for users
3. **Feasible**: Can be completed in hackathon timeframe with shortcuts
4. **Scalable**: Foundation for adding Li.FI routing + multi-solver later
5. **Story**: "Traditional LP migration requires 6 transactions. With intents, it's 1 click."

### Implementation Plan:

```
Week 1 (MVP):
- Day 1-2: Build allocator + arbiter contracts
- Day 3-4: Extend AutoLpHelper with travel function
- Day 5: Build simple solver bot (your backend)
- Day 6: Frontend integration + testing
- Day 7: Demo preparation

Post-Hackathon (Production):
- Add Li.FI for optimal routing
- Open solver network (allow anyone to fulfill)
- Support more chains
- Add solver competition UI
```

### Updated GAME_DESIGN.md Section:

```markdown
### 4. Travel (Cross-Chain) [Intent-Based]

**User Experience**: Click "Travel to Base" → Sign once → Done!

**Behind the Scenes** (Intent-Based Architecture):

1. User signs "compact" (intent): "I want my LP on Base"
2. Assets locked in The Compact on source chain
3. Solver sees intent, provides liquidity on Base immediately
4. LP position created on destination
5. Solver claims locked assets as payment
6. Axolotl appears on new chain (2-5 minutes)

**User Sees**:

- ✨ One signature, no manual steps
- 🚂 Travel progress: "Boarding → In Transit → Arrived"
- ⚡ Faster than traditional bridging
- 💰 Competitive pricing (solvers compete)
```

---

**Want me to update GAME_DESIGN.md and SYSTEM_ARCHITECTURE.md with this intent-based approach?**
