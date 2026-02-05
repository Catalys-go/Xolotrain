# Xolotrain Agent System Design

## 🎯 Agent Mission Statement

**The Xolotrain Agent is an autonomous system that manages the complete lifecycle of Uniswap v4 LP positions** through two core responsibilities:

1. **Health Monitoring**: Continuously tracks LP performance and updates pet health
2. **Intent Fulfillment**: Autonomously executes cross-chain LP migrations

This unified agent architecture demonstrates **deep Uniswap v4 integration** for the bounty requirement: _"agent-driven systems that manage, optimize, or interact with v4 positions"_.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    UNIFIED AGENT SERVICE                         │
│                    (Single Process, Dual Roles)                  │
└─────────────┬───────────────────────────┬───────────────────────┘
              │                           │
              ▼                           ▼
    ┌─────────────────────┐    ┌──────────────────────┐
    │  HEALTH MONITOR     │    │  INTENT FULFILLER    │
    │  (Continuous)       │    │  (Event-Driven)      │
    └─────────┬───────────┘    └──────────┬───────────┘
              │                           │
              │                           │
    ┌─────────▼────────────┐    ┌────────▼────────────┐
    │  Uniswap v4          │    │  Uniswap v4         │
    │  IPoolManager        │    │  AutoLpHelper       │
    │  (Read LP state)     │    │  (Create LPs)       │
    └──────────────────────┘    └─────────────────────┘
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

### Responsibility #2: Intent Fulfillment (Solver)

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
async function healthMonitoringLoop() {
  while (true) {
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

✅ **Optimize & Manage**:

- **Optimize**: Agent chooses optimal bridge routes (Li.FI)
- **Manage**: Agent maintains pet health metadata
- **Interact**: 6+ Uniswap v4 calls per user journey

✅ **Reliability**:

- Deterministic health calculations
- Transparent on-chain logging
- Fail-safe design (users can act manually if agent fails)

---

## 🛠️ Technical Implementation

### Agent Service Structure

```
packages/agent/
├── src/
│   ├── index.ts                    # Main entry point
│   ├── config.ts                   # Chain configs, RPC endpoints
│   ├── health/
│   │   ├── monitor.ts              # Health monitoring loop
│   │   ├── calculator.ts           # Deterministic health formula
│   │   └── updater.ts              # Submit health txs
│   ├── solver/
│   │   ├── listener.ts             # Intent event listener
│   │   ├── profitability.ts        # Profitability evaluation
│   │   ├── fulfiller.ts            # Intent fulfillment logic
│   │   └── lifi.ts                 # Li.FI SDK integration
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

---

### Key Dependencies

```json
{
  "dependencies": {
    "@lifi/sdk": "^2.0.0", // Cross-chain routing
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

# Li.FI
LIFI_API_KEY=...

# Config
HEALTH_CHECK_INTERVAL=60000      # 60 seconds
MIN_HEALTH_CHANGE=5              # Update if ≥5 point change
MIN_PROFIT_MARGIN=0.001          # 0.1%
CAPITAL_FLOAT_PER_CHAIN=10       # 10 ETH
```

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

**SYSTEM_ARCHITECTURE.md**:

- Merge "Health Monitoring Agent" and "Solver Bot" sections
- Update component architecture to show unified agent
- Add "Agent Service" subsection with dual responsibilities

**INTERACTIONS.md**:

- Update "Agent Behaviors" section to include intent fulfillment
- Add workflow for agent detecting and fulfilling intents
- Clarify agent is single service with dual roles

**GAME_DESIGN.md**:

- Update "What Agent Does" to include solver functionality
- Add explanation of autonomous intent fulfillment
- Emphasize agent-driven cross-chain migration

**BOUNTY_STRATEGY.md**:

- Update agent description to highlight unified approach
- Add metrics: "Agent makes 6+ Uniswap v4 interactions per journey"
- Emphasize autonomous LP lifecycle management

---

## 🎖️ Success Criteria

For this agent system to qualify for **Uniswap Bounty: Agent-Driven Systems**:

✅ **Deep v4 Integration**: Agent makes 6+ interactions with Uniswap v4 per user  
✅ **Autonomous Behavior**: No human intervention required for 95% of operations  
✅ **Reliability**: 99% uptime, deterministic calculations  
✅ **Optimization**: Finds optimal bridge routes, minimizes gas costs  
✅ **Transparency**: All actions logged on-chain with events  
✅ **Educational**: Demonstrates best practices for v4 agent systems

---

## 📝 Summary

The **Xolotrain Agent** is a unified system that:

1. **Continuously monitors** Uniswap v4 LP positions for health tracking
2. **Autonomously fulfills** cross-chain LP migration intents
3. **Deeply integrates** with Uniswap v4 (IPoolManager, AutoLpHelper, position creation)
4. **Operates deterministically** with transparent, verifiable logic
5. **Scales efficiently** with batched operations and gas optimization

This agent-first architecture makes Xolotrain a **strong candidate** for the Uniswap bounty while providing an excellent user experience through autonomous DeFi management.
