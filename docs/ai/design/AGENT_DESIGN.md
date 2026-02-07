# Xolotrain Agent System Design

## 🎯 Agent Mission Statement

**The Xolotrain Agent is an AI-enhanced autonomous system that manages the complete lifecycle of Uniswap v4 LP positions** through three core responsibilities:

1. **Health Monitoring**: Continuously tracks LP performance and updates pet health
2. **AI-Enhanced Advice**: Generates personalized educational explanations of LP mechanics
3. **Intent Fulfillment**: Autonomously executes cross-chain LP migrations

This unified agent architecture demonstrates **deep Uniswap v4 integration** for the bounty requirement: _"agent-driven systems that manage, optimize, or interact with v4 positions"_, enhanced with AI to provide educational value.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    UNIFIED AGENT SERVICE                         │
│              (Single Process, Three Responsibilities)            │
└───────────┬─────────────────────┬─────────────────┬─────────────┘
            │                     │                 │
            ▼                     ▼                 ▼
  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
  │ HEALTH MONITOR   │  │  AI ADVISOR      │  │ INTENT FULFILLER │
  │ (Continuous)     │  │  (On-Demand)     │  │ (Event-Driven)   │
  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
           │                     │                      │
           │                     │                      │
  ┌────────▼────────┐   ┌───────▼────────┐   ┌────────▼─────────┐
  │  Uniswap v4     │   │  Claude Haiku  │   │  Uniswap v4      │
  │  IPoolManager   │   │  (LLM API)     │   │  AutoLpHelper    │
  │  (Read state)   │   │  ($0.0003/req) │   │  (Create LPs)    │
  └─────────────────┘   └────────────────┘   └──────────────────┘
```

---

## 🎭 Agent Responsibilities

### Responsibility #1: Health Monitoring

**Trigger**: Every N blocks (configurable, default: 60 seconds)

**Workflow**:

1. Query all active pets from `PetRegistry`
2. For each pet, read LP position state from `IPoolManager`
3. Calculate health deterministically: `health = f(currentTick, tickLower, tickUpper)`
4. If health changed by ≥5 points: Call `PetRegistry.updateHealth(petId, newHealth)`
5. Emit transaction receipt for transparency

**Uniswap v4 Interactions**:

- `IPoolManager.getPoolState()` - Read current tick
- `IPositionManager.getPosition()` - Read position bounds
- Continuous monitoring of pool price movements

**Agent-First Principles Applied**:

- ✅ **Atomic**: Each health update is a single transaction
- ✅ **Deterministic**: Same pool state → same health calculation
- ✅ **Observable**: All updates logged via `HealthUpdated` events
- ✅ **Predictable**: Health formula is public and verifiable

---

### Responsibility #2: AI-Enhanced Advice (Educational)

**Trigger**: User clicks "Ask AI" button on pet detail page (frontend-initiated)

**Location**: Next.js frontend (NOT in agent service)

**Workflow**:

1. User requests advice via frontend button
2. Frontend fetches current pet state from contracts (or uses cached data)
3. Next.js API route calls Claude Haiku with position metrics
4. Returns friendly 2-3 sentence explanation
5. Frontend displays advice in chat bubble

**Implementation** (Next.js API Route):

```typescript
// app/api/pet/[id]/advice/route.ts
import { NextRequest, NextResponse } from "next/server";
import Anthropic from "@anthropic-ai/sdk";

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } },
) {
  try {
    const petId = params.id;

    // 1. Fetch pet data (from your existing hooks/contracts)
    const pet = await fetchPetData(petId);
    const position = await fetchPositionData(pet.positionId);

    // 2. Generate advice with Claude Haiku
    const anthropic = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY,
    });

    const message = await anthropic.messages.create({
      model: "claude-3-haiku-20240307",
      max_tokens: 150,
      messages: [
        {
          role: "user",
          content: `LP Position Analysis:
- Pet Health: ${pet.health}/100
- Current Tick: ${position.currentTick}
- Position Range: [${position.tickLower}, ${position.tickUpper}]
- In Range: ${position.inRange ? "Yes ✅" : "No ❌"}
- Fees Earned: ${position.feesEarned} USDC

Provide friendly advice (2-3 sentences) for a beginner learning about Uniswap v4 LP positions.`,
        },
      ],
    });

    return NextResponse.json({
      advice: message.content[0].text,
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to generate advice" },
      { status: 500 },
    );
  }
}
```

**Frontend Usage**:

```typescript
// In pet detail component
const { data: advice, isLoading } = useQuery({
  queryKey: ['petAdvice', petId],
  queryFn: async () => {
    const res = await fetch(`/api/pet/${petId}/advice`);
    return res.json();
  },
  staleTime: 5 * 60 * 1000, // 5 minute cache
  enabled: showAdvice // Only fetch when user clicks "Ask AI"
});

// Display
{showAdvice && (
  <div className="chat chat-start">
    <div className="chat-bubble">
      {isLoading ? 'Thinking...' : advice?.advice}
    </div>
  </div>
)}
```

**Cost Analysis**:

- Input: ~200 tokens = $0.00005
- Output: ~100 tokens = $0.000125
- **Total per request**: ~$0.0002 (negligible)
- **1000 users × 10 requests**: ~$2 total

**Example Output**:

> "Your axolotl is healthy at 85/100! Your LP is currently earning fees because the USDC/USDT price is within your range. Think of it like a fisherman casting a net - you catch fees when the price swims through your range. Nice work! 🎣"

**Benefits**:

- ✅ Educational value (explains LP concepts)
- ✅ "AI-powered" for bounty pitch
- ✅ Personalized to each position
- ✅ Minimal cost (<$5 for hackathon)
- ✅ Easy to implement (one API call)

**Agent-First Principles Applied**:

- ✅ **Observable**: Advice generation optional (user-triggered)
- ✅ **Predictable**: Advice quality is consistent
- ✅ **Simple**: Lives in frontend, no agent complexity
- ✅ **Independent**: No dependency on agent service

---

### Responsibility #3: Intent Fulfillment (Solver)

**Trigger**: `IntentCreated` event from `AutoLpHelper`

**Workflow**:

1. Monitor `IntentCreated(compactId, petId, destinationChainId)` events
2. Evaluate profitability: `lockedAssets - (bridgeCost + gasCost)`
3. If profitable:
   - Use Li.FI SDK to find optimal bridge route
   - Bridge own USDC/USDT to destination chain via Li.FI
   - Call `AutoLpHelper.mintLpFromTokens()` on destination
   - Submit proof to `LPMigrationArbiter.verifyAndClaim()`
4. Receive payment from locked assets on source chain

**Uniswap v4 Interactions**:

- Monitors LP position closures (source chain)
- Creates new LP positions (destination chain) via `mintLpFromTokens()`
- Uses `IPoolManager` to verify LP creation success
- Ensures tick ranges match intent specifications

**Agent-First Principles Applied**:

- ✅ **Atomic**: Intent fulfillment is all-or-nothing
- ✅ **Deterministic**: Profitability calculation is transparent
- ✅ **Observable**: All steps emit events (IntentCreated, ClaimProcessed)
- ✅ **Predictable**: Solver logic is publicly auditable

---

## 📊 Uniswap v4 Integration Depth

### Read Operations (Health Monitoring)

```typescript
// Agent continuously queries Uniswap v4 state
interface IPoolManager {
  getSlot0(PoolKey) returns (tick, sqrtPriceX96, ...);
  getLiquidity(PoolKey) returns (uint128);
  getPosition(PoolKey, positionId) returns (liquidity, tickLower, tickUpper);
}

// Agent uses this data to calculate health
const currentTick = await poolManager.getSlot0(poolKey).tick;
const position = await positionManager.getPosition(positionId);
const health = calculateHealth(currentTick, position.tickLower, position.tickUpper);
```

**Frequency**: Every 60 seconds per active pet
**Scale**: Monitors 100+ positions simultaneously

---

### Write Operations (Intent Fulfillment)

```typescript
// Agent creates LP positions on destination chains
interface IAutoLpHelper {
  mintLpFromTokens(
    uint256 usdcAmount,
    uint256 usdtAmount,
    address recipient,
    int24 tickLower,
    int24 tickUpper
  ) returns (uint256 positionId);
}

// Agent calls this after bridging assets via Li.FI
const positionId = await autoLpHelper.mintLpFromTokens(
  intent.usdcAmount,
  intent.usdtAmount,
  intent.userAddress,
  intent.tickLower,
  intent.tickUpper
);
```

**Frequency**: On-demand per travel intent
**Scale**: Executes cross-chain migrations in 2-5 minutes

---

## 🔄 Agent Workflows

### Workflow A: Health Update Loop

```typescript
// Module-level state for lifecycle management
let intervalId: NodeJS.Timeout | undefined;
let isRunning = false;
let iterationCount = 0;

export function startHealthMonitor(publicClient, walletClient) {
  if (isRunning) return;
  isRunning = true;
  
  // Run immediately, then on interval
  runMonitoringIteration(publicClient, walletClient);
  intervalId = setInterval(() => {
    runMonitoringIteration(publicClient, walletClient);
  }, config.healthCheckInterval);
}

export function stopHealthMonitor() {
  if (intervalId) clearInterval(intervalId);
  isRunning = false;
}

async function runMonitoringIteration(publicClient, walletClient) {
  try {
    // Fetch all active pets with retry
    const petIds = await retryAsync(
      () => getAllActivePets(publicClient, config.petRegistry),
      { maxAttempts: 3, delayMs: 1000 }
    );
    
    // Process all pets in parallel
    const checkPromises = petIds.map(petId => checkPetHealth(publicClient, petId));
    const results = await Promise.allSettled(checkPromises);
    
    // Collect successful updates
    const updates = results
      .filter(r => r.status === 'fulfilled' && r.value !== null)
      .map(r => r.value);
    
    // Submit updates
    if (updates.length > 0) {
      await submitHealthUpdates(publicClient, walletClient, updates);
    }
  } catch (error) {
    logError('Monitoring cycle failed', error);
  }
}

async function checkPetHealth(client, petId) {
    try {
      // 1. Fetch all active pets
      const pets = await petRegistry.getAllActivePets();

      // 2. Read Uniswap v4 state for each pet
      const updates = [];
      for (const pet of pets) {
        const poolKey = getPoolKey(pet.poolId);
        const { tick: currentTick } = await poolManager.getSlot0(poolKey);
        const position = await positionManager.getPosition(pet.positionId);

        // 3. Calculate new health
        const newHealth = calculateHealth(
          currentTick,
          position.tickLower,
          position.tickUpper,
        );

        // 4. Queue update if changed significantly
        if (Math.abs(newHealth - pet.health) >= 5) {
          updates.push({ petId: pet.id, health: newHealth });
        }
      }

      // 5. Batch submit updates (gas optimization)
      if (updates.length > 0) {
        await petRegistry.batchUpdateHealth(updates, {
          gasPrice: await getOptimalGasPrice(),
        });

        logger.info(`✅ Updated ${updates.length} pets`);
      }

      // 6. Wait before next iteration
      await sleep(60_000); // 60 seconds
    } catch (error) {
      logger.error("Health monitoring error:", error);
      await sleep(10_000); // Retry after 10s
    }
  }
}
```

**Key Features**:

- Batched updates for gas efficiency
- Configurable health change threshold
- Automatic retry on failure
- Low gas price for non-urgent updates

---

### Workflow B: Intent Fulfillment

```typescript
async function intentFulfillmentLoop() {
  // Listen for IntentCreated events
  autoLpHelper.on("IntentCreated", async (event) => {
    const { compactId, petId, destinationChainId, usdcAmount, usdtAmount } =
      event.args;

    try {
      logger.info(`🔔 New intent: ${compactId}`);

      // 1. Evaluate profitability
      const bridgeCost = await estimateBridgeCost(
        sourceChainId,
        destinationChainId,
        usdcAmount + usdtAmount,
      );
      const gasCost = await estimateGasCost(destinationChainId);
      const revenue = usdcAmount + usdtAmount;
      const profit = revenue - bridgeCost - gasCost;

      if (profit < MIN_PROFIT_THRESHOLD) {
        logger.info(`⏭️  Not profitable: ${profit} < ${MIN_PROFIT_THRESHOLD}`);
        return;
      }

      logger.info(`✅ Profitable: ${profit}. Fulfilling...`);

      // 2. Find optimal bridge route via Li.FI
      const routes = await lifi.getRoutes({
        fromChainId: sourceChainId,
        toChainId: destinationChainId,
        fromTokenAddress: USDC_ADDRESS,
        toTokenAddress: USDC_ADDRESS,
        fromAmount: usdcAmount,
      });

      // 3. Execute bridge (USDC and USDT)
      logger.info(`🌉 Bridging via Li.FI: ${routes[0].tool}`);
      await lifi.executeRoute(routes[0]);
      await waitForBridgeCompletion(routes[0].id);

      // 4. Create LP on destination (Uniswap v4)
      logger.info(`🏊 Creating LP on destination chain...`);
      const autoLpHelperDest = getAutoLpHelperContract(destinationChainId);
      const tx = await autoLpHelperDest.mintLpFromTokens(
        usdcAmount,
        usdtAmount,
        event.args.userAddress,
        event.args.tickLower,
        event.args.tickUpper,
      );
      const receipt = await tx.wait();

      // 5. Extract positionId from events
      const positionId = receipt.events.find((e) => e.event === "LPCreated")
        .args.positionId;

      logger.info(`✅ LP created: positionId=${positionId}`);

      // 6. Submit claim to arbiter
      const arbiter = getLPMigrationArbiter(sourceChainId);
      await arbiter.verifyAndClaim(positionId, compactId, SOLVER_ADDRESS, {
        gasLimit: 500_000,
      });

      logger.info(`💰 Claim submitted, awaiting payment...`);
    } catch (error) {
      logger.error(`❌ Intent fulfillment failed: ${error.message}`);
      // Note: Intent will expire naturally if not fulfilled
    }
  });
}
```

**Key Features**:

- Profitability check before action
- Li.FI integration for optimal routing
- Automated LP creation on destination
- Trustless claim settlement

---

### Workflow C: AI-Powered Intent Optimization (OPTIONAL)

**Status**: 🔵 Optional enhancement if time permits

**Purpose**: Use Claude Sonnet to optimize tick ranges for destination chain based on market conditions

```typescript
async function optimizeTickRange(
  sourcePosition: Position,
  destChainId: number,
  marketConditions: MarketData,
): Promise<{ tickLower: number; tickUpper: number; reasoning: string }> {
  const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const message = await anthropic.messages.create({
    model: "claude-3-5-sonnet-20241022", // Smarter model for optimization
    max_tokens: 300,
    messages: [
      {
        role: "user",
        content: `Optimize LP tick range for cross-chain migration:

Source Position:
- Tick Range: [${sourcePosition.tickLower}, ${sourcePosition.tickUpper}]
- Utilization: ${sourcePosition.inRange ? "Active (earning fees)" : "Inactive (out of range)"}
- Total Fees Earned: ${sourcePosition.feesUsd} USD
- Time In Range: ${sourcePosition.timeInRange}%

Destination Chain: ${getChainName(destChainId)}
Market Conditions:
- 24h Volatility: ${marketConditions.volatility}%
- Volume Trend: ${marketConditions.volumeTrend}
- Current USDC/USDT Price: ${marketConditions.price}

Suggest optimal tick range for destination. Format as JSON:
{
  "tickLower": number,
  "tickUpper": number,
  "reasoning": "1-2 sentence explanation"
}

Consider:
- Higher volatility → wider range
- Low volume → tighter range (more fee per trade)
- User's past performance`,
      },
    ],
  });

  // Parse AI response
  const response = JSON.parse(message.content[0].text);

  logger.info({
    type: "ai_optimization",
    source: sourcePosition,
    destination: response,
    cost: 0.001, // ~$0.001 per optimization
  });

  return response;
}
```

**Cost**: ~$0.001 per optimization (only called on travel, rare event)

**Benefits**:

- Shows advanced AI integration
- Actually useful (adapts to market conditions)
- Strong demo point: "AI suggests optimal ranges based on volatility"

**Why Optional**:

- Not required for core functionality
- Can use fixed tick ranges initially
- Adds complexity to demo
- Would take 2-3 hours to implement properly

**Implementation Priority**: Low (only if time permits after core features done)

---

## 🔐 Security & Trust Model

### Agent Capabilities (What It CAN Do)

✅ **Read LP State**: Query Uniswap v4 PoolManager for position data  
✅ **Update Health Metadata**: Call `PetRegistry.updateHealth()` (onlyAgent modifier)  
✅ **Create LPs for Users**: Mint positions on destination chains (intent fulfillment)  
✅ **Claim Intent Payments**: Receive locked assets after successful LP creation

### Agent Constraints (What It CANNOT Do)

❌ **Move User Funds**: Agent never has custody of user assets  
❌ **Modify User Positions**: Only users can close/adjust their LPs  
❌ **Transfer Pet NFTs**: Only owners control pet ownership  
❌ **Change Game Rules**: Health formula is immutable in code

### Trust Requirements

**Users Trust**:

- Agent will monitor health accurately (formula is public)
- Agent will fulfill intents if profitable (economic incentive)
- Agent won't steal funds (doesn't have custody)

**Agent Trusts**:

- The Compact won't double-spend locked assets (protocol guarantee)
- Arbiter will verify claims correctly (on-chain verification)
- Li.FI SDK provides correct routing (reputation-based)

**Verification Mechanisms**:

- All health updates logged as events (auditability)
- Health formula is open-source (reproducibility)
- Intent fulfillment uses The Compact (trustless settlement)

---

## 📈 Performance & Scalability

### Health Monitoring Scale

| Metric                  | Value      | Notes                               |
| ----------------------- | ---------- | ----------------------------------- |
| **Pets per Scan**       | 100-500    | Current capacity                    |
| **Scan Frequency**      | 60 seconds | Configurable                        |
| **RPC Calls per Scan**  | 3 per pet  | getSlot0, getPosition, updateHealth |
| **Gas Cost per Update** | ~50k gas   | Batched updates cheaper             |
| **Concurrent Chains**   | 2-5        | Multi-chain support                 |

**Optimization Strategies**:

- Batch read calls using `multicall`
- Batch write calls for multiple pets
- Use low gas price for non-urgent updates
- Cache pool state for 30 seconds

---

### Intent Fulfillment Scale

| Metric                 | Value             | Notes                    |
| ---------------------- | ----------------- | ------------------------ |
| **Concurrent Intents** | 5-10              | Limited by capital float |
| **Fulfillment Time**   | 2-5 minutes       | Depends on bridge speed  |
| **Capital Required**   | ~10 ETH per chain | For solver operations    |
| **Min Profit Margin**  | 0.1%              | Configurable threshold   |

**Economic Model**:

- Agent maintains liquidity float on each chain
- Only fulfills profitable intents
- Rebalances capital using Li.FI periodically
- Break-even point: ~10 intents per day

---

## 🎯 Bounty Alignment: "Agent-Driven Systems"

### How This Qualifies

✅ **Deep v4 Integration**:

- Continuous reading of `IPoolManager` state
- Creating LP positions via `mintLpFromTokens()`
- Monitoring pool ticks, liquidity, and positions

✅ **Autonomous Management**:

- No human intervention required for health updates
- Self-sufficient intent fulfillment system
- Deterministic decision-making

✅ **AI-Enhanced (Differentiator!)**:

- **Educational**: Explains LP concepts in plain English
- **Personalized**: Advice tailored to each position's performance
- **Accessible**: Makes DeFi approachable for beginners
- **Bounty Buzzword**: "AI-powered agent system"

✅ **Optimize & Manage**:

- **Optimize**: Agent chooses optimal bridge routes (Li.FI), optional AI tick range optimization
- **Manage**: Agent maintains pet health metadata
- **Interact**: 6+ Uniswap v4 calls per user journey
- **Educate**: AI generates custom advice per position

✅ **Reliability**:

- Deterministic health calculations
- Transparent on-chain logging
- Fail-safe design (users can act manually if agent fails)
- AI advice has graceful fallback

---

## 🛠️ Technical Implementation

### Agent Service Structure

```
packages/agent/
├── src/
│   ├── index.ts                    # Main entry point (runs both health + solver loops)
│   ├── config.ts                   # Chain configs, RPC endpoints, Li.FI API key
│   ├── health/
│   │   ├── monitor.ts              # Health monitoring loop
│   │   ├── calculator.ts           # Deterministic health formula
│   │   └── updater.ts              # Submit health txs
│   ├── solver/
│   │   ├── listener.ts             # Intent event listener (TODO: Phase 2)
│   │   ├── profitability.ts        # Profitability evaluation (TODO: Phase 2)
│   │   ├── fulfiller.ts            # Intent fulfillment logic (TODO: Phase 2)
│   │   └── lifi.ts                 # Li.FI SDK integration (TODO: Phase 2)
│   ├── contracts/
│   │   ├── poolManager.ts          # IPoolManager interface
│   │   ├── positionManager.ts      # IPositionManager interface
│   │   ├── petRegistry.ts          # PetRegistry interface
│   │   └── autoLpHelper.ts         # AutoLpHelper interface
│   └── utils/
│       ├── logger.ts               # Structured logging
│       ├── gas.ts                  # Gas price optimization
│       └── multicall.ts            # Batched RPC calls
├── package.json
├── tsconfig.json
└── README.md
```

**Note**: AI advice lives in `packages/nextjs/app/api/pet/[id]/advice/route.ts` (frontend), NOT in agent.

---

### Key Dependencies

```json
{
  "dependencies": {
    "@lifi/sdk": "^2.0.0", // Cross-chain routing
    "@anthropic-ai/sdk": "^0.20.0", // Claude API for AI advice
    "ethers": "^6.0.0", // Ethereum interactions
    "viem": "^1.0.0", // Alternative to ethers
    "@uniswap/v4-core": "^1.0.0", // Uniswap v4 ABIs
    "winston": "^3.0.0", // Logging
    "dotenv": "^16.0.0" // Environment variables
  }
}
```

---

### Environment Configuration

```bash
# Chain RPCs
SEPOLIA_RPC_URL=https://...
BASE_SEPOLIA_RPC_URL=https://...

# Agent Wallet
AGENT_PRIVATE_KEY=0x...

# Contract Addresses (per chain)
SEPOLIA_POOL_MANAGER=0x...
SEPOLIA_POSITION_MANAGER=0x...
SEPOLIA_PET_REGISTRY=0x...
SEPOLIA_AUTO_LP_HELPER=0x...

BASE_POOL_MANAGER=0x...
BASE_POSITION_MANAGER=0x...
BASE_PET_REGISTRY=0x...
BASE_AUTO_LP_HELPER=0x...

# Li.Fi
LIFI_API_KEY=...

# Config
HEALTH_CHECK_INTERVAL=60000      # 60 seconds
MIN_HEALTH_CHANGE=5              # Update if ≥5 point change
MIN_PROFIT_MARGIN=0.001          # 0.1% minimum profit for intent fulfillment
```

**Note**: `ANTHROPIC_API_KEY` goes in `packages/nextjs/.env.local` (frontend), NOT in agent env.

---

## 🔍 Observability & Monitoring

### Logging Strategy

```typescript
// Structured logging for all agent actions
logger.info({
  type: "health_update",
  petId: 123,
  oldHealth: 85,
  newHealth: 72,
  reason: "position_out_of_range",
  txHash: "0xabc...",
  gasUsed: 48234,
  timestamp: Date.now(),
});

logger.info({
  type: "intent_fulfilled",
  compactId: "0x123...",
  sourceChain: "sepolia",
  destChain: "base",
  profit: 0.0025,
  bridgeTool: "across",
  duration: 142000, // 142 seconds
  timestamp: Date.now(),
});
```

---

### Metrics to Track

**Health Monitoring**:

- Total pets monitored
- Health updates submitted (per hour)
- Average gas cost per update
- Failed updates (with reasons)
- RPC errors / rate limits

**Intent Fulfillment**:

- Intents detected
- Intents fulfilled vs. skipped
- Average fulfillment time
- Profit margins achieved
- Capital utilization rate

**System Health**:

- Agent uptime
- RPC latency
- Memory usage
- Error rates

---

## 🧪 Testing Strategy

### Unit Tests

- Health calculation logic
- Profitability evaluation
- Error handling scenarios

### Integration Tests

- Mock Uniswap v4 PoolManager
- Simulate LP position states
- Test batched updates

### End-to-End Tests

- Deploy to testnet
- Create real LP positions
- Monitor health updates
- Execute travel intents

---

## 🚀 Deployment & Operations

### Initial Setup

1. **Deploy Contracts** (per chain):
   - PetRegistry, AutoLpHelper, EggHatchHook, etc.
2. **Configure Agent**:
   - Set RPC endpoints
   - Fund agent wallet with gas
   - Set contract addresses
   - Configure Li.FI API key

3. **Start Agent Service**:

   ```bash
   cd packages/agent
   yarn install
   yarn build
   yarn start
   ```

4. **Monitor Logs**:
   ```bash
   tail -f logs/agent.log
   ```

---

### Operational Runbook

**Health Monitoring Issues**:

- RPC rate limit → Add backup RPC, implement retry logic
- Gas too high → Increase batch size, wait for lower gas
- Missed update → Check agent uptime, verify RPC connectivity

**Intent Fulfillment Issues**:

- Not profitable → Check capital float, review profit margins
- Bridge failure → Li.FI will retry automatically
- Arbiter rejects claim → Verify LP position matches specs

**Recovery Procedures**:

- Agent crash → Systemd auto-restart, no state loss
- RPC failure → Fallback to secondary RPC
- Capital depletion → Alert admin, pause fulfillment

---

## 📋 Integration with Existing Docs

### Updates Needed

**SYSTEM_ARCHITECTURE.md**: (COMPLETED)

- Merge "Health Monitoring Agent" and "Solver Bot" sections
- Update component architecture to show unified agent
- Add "Agent Service" subsection with dual responsibilities

**INTERACTIONS.md**: (COMPLETED)

- Update "Agent Behaviors" section to include intent fulfillment
- Add workflow for agent detecting and fulfilling intents
- Clarify agent is single service with dual roles

**GAME_DESIGN.md**: (COMPLETED)

- Update "What Agent Does" to include solver functionality
- Add explanation of autonomous intent fulfillment
- Emphasize agent-driven cross-chain migration

**BOUNTY_STRATEGY.md**: (COMPLETED)

- Update agent description to highlight unified approach
- Add metrics: "Agent makes 6+ Uniswap v4 interactions per journey"
- Emphasize autonomous LP lifecycle management

---

## 🎖️ Success Criteria

For this agent system to qualify for **Uniswap Bounty: Agent-Driven Systems**:

✅ **Deep v4 Integration**: Agent makes 6+ interactions with Uniswap v4 per user  
✅ **Autonomous Behavior**: No human intervention required for 95% of operations  
✅ **AI-Enhanced**: Claude Haiku generates personalized LP advice (<$5 hackathon cost)  
✅ **Reliability**: 99% uptime, deterministic calculations  
✅ **Optimization**: Finds optimal bridge routes, minimizes gas costs  
✅ **Transparency**: All actions logged on-chain with events  
✅ **Educational**: AI explains LP concepts in plain English, making DeFi accessible

---

## 📝 Summary

The **Xolotrain Agent** is an AI-enhanced unified system that:

1. **Continuously monitors** Uniswap v4 LP positions for health tracking
2. **AI-powered education** via Claude Haiku (personalized LP advice, <$5 cost)
3. **Autonomously fulfills** cross-chain LP migration intents via Li.Fi + The Compact
4. **Deeply integrates** with Uniswap v4 (IPoolManager, AutoLpHelper, position creation)
5. **Operates deterministically** with transparent, verifiable logic
6. **Scales efficiently** with batched operations and gas optimization

This **AI-enhanced agent-first architecture** makes Xolotrain a **strong candidate** for the Uniswap bounty while providing an excellent user experience through autonomous DeFi management and accessible education.

**Demo Pitch**: _"Our AI agent doesn't just manage your LP - it teaches you why your health changed and what 'in range' means, making DeFi education fun through gameplay."_
