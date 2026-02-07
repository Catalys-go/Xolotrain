# Xolotrain Agent - Quick Setup Guide

## ✅ What's Complete

The health monitoring agent (Phase 1) is fully implemented:

- ✅ Health calculator with deterministic formula
- ✅ Contract interfaces (PetRegistry, PoolManager, PositionManager)
- ✅ Health monitoring with lifecycle management (start/stop/isRunning)
- ✅ Parallel pet processing with Promise.allSettled()
- ✅ Retry logic with exponential backoff for RPC calls
- ✅ Gas-optimized transaction submission
- ✅ Clean grouped logging with visual separators
- ✅ Graceful error handling and shutdown

## 🚀 Next Steps to Test

### 1. Install Dependencies

```bash
cd packages/agent
yarn install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and set:

```bash
# Your agent wallet private key (needs ETH for gas)
AGENT_PRIVATE_KEY=0x...

# Contract addresses from your local deployment
PET_REGISTRY=0xB288315B51e6FAc212513E1a7C70232fa584Bbb9
POOL_MANAGER=0x000000000004444c5dc75cB358380D2e3dE08A90
POSITION_MANAGER=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e
```

### 3. Start Local Anvil Fork

In separate terminal:

```bash
yarn fork mainnet # or other fork/chain if desired
```

### 4. Deploy Contracts (if not already deployed)

```bash
yarn deploy --rpc-url localhost
```

### 5. Fund Agent Wallet

```bash
# Get agent address from the agent startup logs
# Then send ETH to that address via frontend or cast
cast send <AGENT_ADDRESS> --value 1ether --private-key <DEPLOYER_KEY>
```

### 6. Build and Run Agent

```bash
# Build
yarn agent:build

# Run
yarn agent:start

# Or run in development mode (with hot reload)
yarn agent:dev
```

### 7. Test with Real LP Position

Create a test LP position via:

- Frontend: Use the "Hatch Your Axolotl" flow
- Or manually via script

The agent will:

1. Detect the new pet
2. Query Uniswap v4 for position state
3. Calculate health (100 if in-range)
4. Monitor every 60 seconds
5. Update health if it changes by ≥5 points

### 8. Simulate Health Change

To test health updates, you can:

- Manually change pool price via swap
- Or call `PetRegistry.updateHealthManual()` to test the event emission

## 📊 Expected Output

```

🦎 Xolotrain Health Monitoring Agent
════════════════════════════════════════

🔑 Agent: 0x1234...5678
🌐 Chain: 31337 (http://127.0.0.1:8545)
💰 Balance: 100.0000 ETH

📋 Contracts:
   PetRegistry: 0xB288...Bbb9
   PoolManager: 0x0000...8A90
   PositionManager: 0xbD21...e9e

════════════════════════════════════════
🏥 Health Monitor Started
   Check interval: 60s
   Min health change: 5
════════════════════════════════════════

┌─ Cycle #1 ─────────────────────────────────
│ Checking 3 pet(s)...
│
│ ⚡ Health Changes Detected: 2
│   🟡 Pet #1: 100 → 75 (ALERT)
│   🔴 Pet #2: 45 → 15 (CRITICAL)
│
│ 📡 Submitting Updates...
│   ✓ Pet #1: 100 → 75
│     Reason: position_below_range | Gas: 85234 | Tx: 0x1a2b3c4d...
│   ✓ Pet #2: 45 → 15
│     Reason: position_above_range | Gas: 85189 | Tx: 0x5e6f7g8h...
│
└─ Completed in 1850ms ────────────────────

┌─ Cycle #2 ─────────────────────────────────
│ Checking 3 pet(s)...
│ ✓ All pets healthy (no changes)
│
└─ Completed in 850ms ────────────────────

^C
👋 Shutting down...
════════════════════════════════════════
👋 Health Monitor Stopped
   Total iterations: 2
════════════════════════════════════════
```

## 🔐 Production Security

Before deploying to testnet/mainnet:

1. **Set agent address in PetRegistry**:

   ```bash
   cast send <PET_REGISTRY> "setAgent(address)" <AGENT_ADDRESS> \
     --private-key <OWNER_KEY> --rpc-url <RPC_URL>
   ```

2. **Uncomment onlyAgent modifier** in `PetRegistry.updateHealth()`:

   ```solidity
   if (msg.sender != agent) revert NotAgent(msg.sender);
   ```

3. **Secure private key**: Use hardware wallet or key management service

## 📝 Files Created

```
packages/agent/
├── src/
│   ├── index.ts                    ✅ Main entry point with lifecycle management
│   ├── config.ts                   ✅ Environment configuration
│   ├── health/
│   │   ├── calculator.ts           ✅ Health formula + status categorization
│   │   ├── monitor.ts              ✅ Monitoring loop (start/stop/isRunning)
│   │   └── updater.ts              ✅ Transaction submission
│   ├── contracts/
│   │   ├── petRegistry.ts          ✅ PetRegistry interface
│   │   ├── poolManager.ts          ✅ Uniswap v4 PoolManager
│   │   └── positionManager.ts      ✅ Position Manager
│   ├── utils/
│   │   ├── logger.ts               ✅ Winston logging (clean format)
│   │   ├── gas.ts                  ✅ Gas optimization
│   │   └── retry.ts                ✅ Retry logic with exponential backoff
│   └── solver/                     🔵 Phase 2 (placeholders)
│       ├── listener.ts
│       ├── profitability.ts
│       ├── fulfiller.ts
│       └── lifi.ts
├── package.json
├── tsconfig.json
├── .env.example
└── README.md
```

## 🐛 Troubleshooting

**Error: "Missing required environment variable"**

- Make sure `.env` file exists with all required variables

**Error: "Agent has no ETH for gas"**

- Fund the agent wallet with ETH: `cast send <AGENT_ADDRESS> --value 1ether`

**Error: "No pets found"**

- Create a test LP position first via frontend or script

**Error: "NotAgent(address)"**

- Agent address not set in PetRegistry yet
- Or onlyAgent modifier is enabled (comment it out for testing)

**Agent not detecting health changes**

- Check `MIN_HEALTH_CHANGE` threshold (default: 5)
- Verify pool price has changed enough to affect health

## 🎯 Next: Phase 2 (Intent Fulfillment)

After health monitoring is working:

1. Add contract functions: `mintLpFromTokens()`, `travelToChain()`
2. Implement solver bot with Li.FI integration
3. Add The Compact integration for trustless settlement

---

**Status**: ✅ Phase 1 Complete - Ready for Testing  
**Next Step**: Install dependencies and configure `.env`
