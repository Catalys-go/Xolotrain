# Xolotrain Health Monitoring Agent

Autonomous agent that continuously monitors Uniswap v4 LP position health and updates pet metadata.

## 🎯 What This Agent Does

1. **Monitors LP Positions**: Queries Uniswap v4 IPoolManager every 60 seconds
2. **Calculates Health**: Deterministic formula based on in-range/out-of-range position status
3. **Categorizes Status**: Maps health to visual states (HEALTHY/ALERT/SAD/CRITICAL)
4. **Parallel Processing**: Checks all pets simultaneously using Promise.allSettled()
5. **Resilient RPC Calls**: Automatic retry with exponential backoff
6. **Updates On-Chain**: Calls `PetRegistry.updateHealth()` when health changes ≥5 points
7. **Gas Optimized**: Batches updates and uses low gas prices for non-urgent transactions
8. **Lifecycle Management**: Clean start/stop with graceful shutdown

## 🏗️ Architecture

```
src/
├── index.ts                 # Main entry point with lifecycle management
├── config.ts                # Configuration from environment variables
├── health/
│   ├── monitor.ts           # Health monitoring (start/stop/isRunning)
│   ├── calculator.ts        # Deterministic health + status categorization
│   └── updater.ts           # Batch health updates to PetRegistry
├── contracts/
│   ├── petRegistry.ts       # PetRegistry contract interface
│   ├── poolManager.ts       # Uniswap v4 IPoolManager interface
│   └── positionManager.ts   # Uniswap v4 IPositionManager interface
├── utils/
│   ├── logger.ts            # Winston structured logging (clean format)
│   ├── gas.ts               # Gas price optimization
│   └── retry.ts             # Retry logic with exponential backoff
└── solver/                  # Phase 2 (placeholders)
    ├── listener.ts
    ├── profitability.ts
    ├── fulfiller.ts
    └── lifi.ts
```

## 🚀 Quick Start

### Prerequisites

1. Local Anvil fork running:

   ```bash
   yarn fork mainnet # or yarn chain
   ```

2. Contracts deployed to local fork:
   ```bash
   yarn deploy --rpc-url localhost
   ```

### Setup

1. Install dependencies:

   ```bash
   yarn install
   ```

2. Configure environment:

   ```bash
   cd packages/agent
   cp .env.example .env
   # Edit .env with your agent private key and contract addresses
   ```

3. Build and run:

   ```bash
   yarn agent:build
   yarn agent:start
   ```

   Or run in development mode:

   ```bash
   yarn agent:dev
   ```

## 🔧 Configuration

All configuration is done via `.env` file:

| Variable                | Description                  | Default                                      |
| ----------------------- | ---------------------------- | -------------------------------------------- |
| `MAINNET_FORK_RPC_URL`  | Anvil RPC endpoint           | `http://127.0.0.1:8545`                      |
| `AGENT_PRIVATE_KEY`     | Private key for agent wallet | Required                                     |
| `PET_REGISTRY`          | PetRegistry contract address | From deployment                              |
| `POOL_MANAGER`          | Uniswap v4 PoolManager       | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| `HEALTH_CHECK_INTERVAL` | Monitoring frequency (ms)    | `60000` (60s)                                |
| `MIN_HEALTH_CHANGE`     | Minimum change to update     | `5`                                          |

## 📊 Health Calculation Formula

```typescript
function calculateHealth(
  currentTick, 
  tickLower, 
  tickUpper,
  penaltyMultiplier = 2  // Configurable, default: 2
): number {
  const inRange = currentTick >= tickLower && currentTick <= tickUpper;

  if (inRange) {
    // Position is earning fees - perfect health
    return 100;
  }

  // Out of range - health degrades based on distance
  const tickRange = tickUpper - tickLower;
  const distanceFromRange = Math.min(
    Math.abs(currentTick - tickLower),
    Math.abs(currentTick - tickUpper),
  );

  // Health decreases proportionally to distance
  // Uses configurable penalty multiplier (default: 2)
  const healthPenalty = (distanceFromRange / tickRange) * 100 * penaltyMultiplier;

  // Clamp to [0, 100] as per game design
  const health = Math.max(0, Math.min(100, 100 - healthPenalty));

  return Math.floor(health); // Return integer for consistency
}
```

### Health Status Categories

| Health Range | Status     | Visual  | Description                     |
| ------------ | ---------- | ------- | ------------------------------- |
| 80-100       | `HEALTHY`  | 🟢      | Happy, animated, vibrant        |
| 50-79        | `ALERT`    | 🟡      | Alert, slower animation         |
| 20-49        | `SAD`      | 🟠      | Sad, sluggish, dimmed           |
| 0-19         | `CRITICAL` | 🔴      | Critical, barely moving         |


## 📈 Monitoring

Agent logs all actions with structured logging:

```json
{
  "level": "info",
  "message": "Health update submitted",
  "petId": 1,
  "oldHealth": 85,
  "newHealth": 72,
  "reason": "position_out_of_range",
  "txHash": "0xabc...",
  "gasUsed": 48234,
  "timestamp": 1707177600000
}
```

## 🔐 Security

- Agent only has permission to call `PetRegistry.updateHealth()`
- Cannot move user funds or modify LP positions
- All actions are logged on-chain via events
- Health formula is deterministic and publicly verifiable

## 🧪 Testing

1. Start local fork with deployed contracts
2. Create test LP position via frontend or script
3. Watch agent logs for health monitoring
4. Manually change pool price to trigger health update

## 📝 Related Docs

- [AGENT_DESIGN.md](../../docs/ai/design/AGENT_DESIGN.md) - Full agent architecture
- [CONTRACT_AGENT_READINESS.md](../../docs/ai/CONTRACT_AGENT_READINESS.md) - Contract status
- [SYSTEM_ARCHITECTURE.md](../../docs/ai/design/SYSTEM_ARCHITECTURE.md) - Complete system flows

---

**Status**: Phase 1 - Health Monitoring Only  
**Network**: Local Anvil fork (Chain ID 31337)  
**Next Phase**: Intent fulfillment (solver bot) - Coming later
