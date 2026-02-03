# Li.FI Integration Guide for Xolotrain

## 🎯 Goal

Integrate Li.FI Composer into the solver bot to enable optimal cross-chain routing when fulfilling travel intents. This satisfies the **Li.FI Bounty** requirement while maintaining our intent-based UX.

---

## 🏗️ Architecture Overview

```
User (Sepolia)                 Solver Bot                    Destination (Base)
     │                              │                               │
     │ 1. Signs travel intent       │                               │
     │ (Lock USDC+USDT in Compact) │                               │
     │──────────────────────────────▶│                               │
     │                              │                               │
     │                              │ 2. Monitor event              │
     │                              │    TravelIntentCreated        │
     │                              │                               │
     │                              │ 3. Use Li.FI SDK:             │
     │                              │    Get optimal route          │
     │                              │    Sepolia USDC → Base USDC   │
     │                              │                               │
     │                              │ 4. Execute Li.FI route        │
     │                              │    (Bridge via best path)     │
     │                              │───────────────────────────────▶│
     │                              │                               │
     │                              │                               │ 5. Create LP
     │                              │                               │    on Base
     │                              │                               │
     │                              │ 6. Submit proof to arbiter    │
     │                              │───────────────────────────────▶│
     │                              │                               │
     │                              │◀───────────────────────────────│
     │                              │ 7. Claim locked assets        │
     │◀──────────────────────────────│    (Settlement on Sepolia)   │
     │                              │                               │
```

**Key Innovation**: User doesn't know/care about Li.FI - they just sign an intent. The solver intelligently uses Li.FI to fulfill it optimally.

---

## 📦 Installation

```bash
cd agent
npm install @lifi/sdk ethers@^6
```

---

## 🔧 Implementation

### 1. Li.FI Service (`agent/lifi.ts`)

```typescript
import { LiFi, type RouteOptions, type Route } from "@lifi/sdk";
import { ethers } from "ethers";

export class LiFiService {
  private lifi: LiFi;
  private solverWallet: ethers.Wallet;

  constructor(privateKey: string, rpcProviders: Map<number, string>) {
    // Initialize Li.FI SDK
    this.lifi = new LiFi({
      integrator: "xolotrain", // Your project name
    });

    this.solverWallet = new ethers.Wallet(privateKey);
  }

  /**
   * Get optimal route for cross-chain token transfer
   */
  async getOptimalRoute(
    fromChainId: number,
    toChainId: number,
    fromTokenAddress: string,
    toTokenAddress: string,
    amount: string,
    fromAddress: string,
    toAddress: string,
  ): Promise<Route> {
    const routeOptions: RouteOptions = {
      fromChainId,
      toChainId,
      fromTokenAddress,
      toTokenAddress,
      fromAmount: amount,
      fromAddress,
      toAddress,
      options: {
        slippage: 0.03, // 3% slippage tolerance
        order: "RECOMMENDED", // Use Li.FI's recommendation
      },
    };

    const routes = await this.lifi.getRoutes(routeOptions);

    if (!routes.routes || routes.routes.length === 0) {
      throw new Error("No routes found");
    }

    // Return the best route (Li.FI already sorts by quality)
    return routes.routes[0];
  }

  /**
   * Execute the route (bridge + swap if needed)
   */
  async executeRoute(
    route: Route,
    signer: ethers.Signer,
  ): Promise<{ txHash: string; success: boolean }> {
    try {
      // Li.FI executes the entire multi-step route
      const execution = await this.lifi.executeRoute(signer, route);

      // Wait for completion
      await execution.waitForExecution();

      return {
        txHash: execution.transactionHash || "",
        success: true,
      };
    } catch (error) {
      console.error("Li.FI execution failed:", error);
      return { txHash: "", success: false };
    }
  }

  /**
   * Estimate gas and fees for a route
   */
  async estimateCosts(route: Route): Promise<{
    gasCost: bigint;
    bridgeFees: bigint;
    totalCost: bigint;
  }> {
    let gasCost = 0n;
    let bridgeFees = 0n;

    // Sum up costs from all steps
    for (const step of route.steps) {
      if (step.estimate?.gasCosts) {
        gasCost += BigInt(step.estimate.gasCosts[0]?.amount || "0");
      }
      if (step.estimate?.feeCosts) {
        bridgeFees += BigInt(step.estimate.feeCosts[0]?.amount || "0");
      }
    }

    return {
      gasCost,
      bridgeFees,
      totalCost: gasCost + bridgeFees,
    };
  }

  /**
   * Check if a bridge is supported between chains
   */
  async checkChainSupport(
    fromChainId: number,
    toChainId: number,
  ): Promise<boolean> {
    try {
      const connections = await this.lifi.getConnections({
        fromChain: fromChainId.toString(),
        toChain: toChainId.toString(),
      });
      return connections.connections.length > 0;
    } catch {
      return false;
    }
  }
}
```

---

### 2. Solver with Li.FI Integration (`agent/solver.ts`)

```typescript
import { ethers } from "ethers";
import { LiFiService } from "./lifi";
import { TheCompact, AutoLpHelper, LPMigrationArbiter } from "./contracts";

interface TravelIntent {
  petId: bigint;
  compactId: string;
  sourceChainId: number;
  destinationChainId: number;
  usdcAmount: bigint;
  usdtAmount: bigint;
  tickLower: number;
  tickUpper: number;
  minLiquidity: bigint;
}

export class SolverBot {
  private lifi: LiFiService;
  private sourceProvider: ethers.JsonRpcProvider;
  private destProvider: ethers.JsonRpcProvider;
  private solverWallet: ethers.Wallet;

  constructor(
    lifiService: LiFiService,
    solverPrivateKey: string,
    rpcUrls: { source: string; dest: string },
  ) {
    this.lifi = lifiService;
    this.sourceProvider = new ethers.JsonRpcProvider(rpcUrls.source);
    this.destProvider = new ethers.JsonRpcProvider(rpcUrls.dest);
    this.solverWallet = new ethers.Wallet(solverPrivateKey);
  }

  /**
   * Monitor for travel intents and fulfill them
   */
  async monitorAndFulfill() {
    const autoLpHelper = new ethers.Contract(
      AUTO_LP_HELPER_ADDRESS,
      AUTO_LP_HELPER_ABI,
      this.sourceProvider,
    );

    // Listen for travel intents
    autoLpHelper.on(
      "TravelIntentCreated",
      async (petId, destinationChainId, compactId, event) => {
        console.log(
          `🔔 Travel intent detected: Pet #${petId} → Chain ${destinationChainId}`,
        );

        try {
          const intent = await this.parseIntent(compactId);
          const isProfitable = await this.evaluateProfitability(intent);

          if (isProfitable) {
            await this.fulfillIntent(intent);
          } else {
            console.log("⚠️  Not profitable, skipping");
          }
        } catch (error) {
          console.error("❌ Failed to fulfill intent:", error);
        }
      },
    );

    console.log("👀 Solver monitoring for travel intents...");
  }

  /**
   * Fulfill a travel intent using Li.FI
   */
  async fulfillIntent(intent: TravelIntent) {
    console.log(`🚀 Fulfilling intent for Pet #${intent.petId}`);

    // Step 1: Get optimal routes for both tokens using Li.FI
    console.log("📊 Fetching Li.FI routes...");

    const [usdcRoute, usdtRoute] = await Promise.all([
      this.lifi.getOptimalRoute(
        intent.sourceChainId,
        intent.destinationChainId,
        USDC_ADDRESS_SOURCE,
        USDC_ADDRESS_DEST,
        intent.usdcAmount.toString(),
        this.solverWallet.address,
        this.solverWallet.address,
      ),
      this.lifi.getOptimalRoute(
        intent.sourceChainId,
        intent.destinationChainId,
        USDT_ADDRESS_SOURCE,
        USDT_ADDRESS_DEST,
        intent.usdtAmount.toString(),
        this.solverWallet.address,
        this.solverWallet.address,
      ),
    ]);

    console.log("✅ Routes found:");
    console.log(
      `   USDC: ${usdcRoute.steps.length} steps via ${usdcRoute.steps[0].tool}`,
    );
    console.log(
      `   USDT: ${usdtRoute.steps.length} steps via ${usdtRoute.steps[0].tool}`,
    );

    // Step 2: Execute Li.FI routes (bridge funds to destination)
    console.log("🌉 Executing Li.FI bridges...");

    const sourceSigner = this.solverWallet.connect(this.sourceProvider);

    const [usdcResult, usdtResult] = await Promise.all([
      this.lifi.executeRoute(usdcRoute, sourceSigner),
      this.lifi.executeRoute(usdtRoute, sourceSigner),
    ]);

    if (!usdcResult.success || !usdtResult.success) {
      throw new Error("Bridge execution failed");
    }

    console.log("✅ Funds bridged to destination");
    console.log(`   USDC tx: ${usdcResult.txHash}`);
    console.log(`   USDT tx: ${usdtResult.txHash}`);

    // Step 3: Create LP position on destination chain
    console.log("💧 Creating LP position on destination...");

    const destSigner = this.solverWallet.connect(this.destProvider);
    const autoLpHelperDest = new ethers.Contract(
      AUTO_LP_HELPER_DEST_ADDRESS,
      AUTO_LP_HELPER_ABI,
      destSigner,
    );

    // Create LP with exact amounts we bridged
    const createLpTx = await autoLpHelperDest.createLiquidityPosition(
      intent.usdcAmount,
      intent.usdtAmount,
      intent.tickLower,
      intent.tickUpper,
      intent.minLiquidity,
    );

    const receipt = await createLpTx.wait();
    const positionId = receipt.logs[0].args.positionId; // Extract from event

    console.log("✅ LP created:", positionId);

    // Step 4: Submit proof to arbiter on destination
    console.log("📝 Submitting proof to arbiter...");

    const arbiter = new ethers.Contract(
      LP_MIGRATION_ARBITER_ADDRESS,
      ARBITER_ABI,
      destSigner,
    );

    const proofTx = await arbiter.verifyAndClaim(
      positionId,
      intent.compactId,
      this.solverWallet.address,
    );

    await proofTx.wait();

    console.log("✅ Proof submitted, claim processed on source chain");
    console.log("🎉 Intent fulfilled successfully!");
  }

  /**
   * Evaluate if fulfilling this intent is profitable
   */
  async evaluateProfitability(intent: TravelIntent): Promise<boolean> {
    // Get routes to estimate costs
    const [usdcRoute, usdtRoute] = await Promise.all([
      this.lifi.getOptimalRoute(
        intent.sourceChainId,
        intent.destinationChainId,
        USDC_ADDRESS_SOURCE,
        USDC_ADDRESS_DEST,
        intent.usdcAmount.toString(),
        this.solverWallet.address,
        this.solverWallet.address,
      ),
      this.lifi.getOptimalRoute(
        intent.sourceChainId,
        intent.destinationChainId,
        USDT_ADDRESS_SOURCE,
        USDT_ADDRESS_DEST,
        intent.usdtAmount.toString(),
        this.solverWallet.address,
        this.solverWallet.address,
      ),
    ]);

    // Calculate total costs
    const usdcCosts = await this.lifi.estimateCosts(usdcRoute);
    const usdtCosts = await this.lifi.estimateCosts(usdtRoute);
    const totalCosts = usdcCosts.totalCost + usdtCosts.totalCost;

    // Revenue = locked assets we'll claim
    const revenue = intent.usdcAmount + intent.usdtAmount;

    // Need at least 5% profit margin
    const profitMargin = Number(revenue - totalCosts) / Number(revenue);
    const isProfitable = profitMargin > 0.05;

    console.log(`💰 Profitability check:`);
    console.log(`   Revenue: ${ethers.formatUnits(revenue, 6)} USD`);
    console.log(`   Costs: ${ethers.formatUnits(totalCosts, 6)} USD`);
    console.log(`   Margin: ${(profitMargin * 100).toFixed(2)}%`);
    console.log(`   Profitable: ${isProfitable ? "✅" : "❌"}`);

    return isProfitable;
  }

  private async parseIntent(compactId: string): Promise<TravelIntent> {
    // Parse compact from The Compact contract
    // Extract mandate witness data
    // Return structured intent
    // ... implementation ...
    throw new Error("Not implemented");
  }
}
```

---

### 3. Main Agent Entry Point (`agent/index.ts`)

```typescript
import { LiFiService } from "./lifi";
import { SolverBot } from "./solver";
import { HealthMonitor } from "./health";

async function main() {
  console.log("🚀 Xolotrain Agent Starting...\n");

  // Initialize Li.FI service
  const lifi = new LiFiService(
    process.env.SOLVER_PRIVATE_KEY!,
    new Map([
      [11155111, process.env.SEPOLIA_RPC!],
      [84532, process.env.BASE_SEPOLIA_RPC!],
    ]),
  );

  // Initialize solver bot
  const solver = new SolverBot(lifi, process.env.SOLVER_PRIVATE_KEY!, {
    source: process.env.SEPOLIA_RPC!,
    dest: process.env.BASE_SEPOLIA_RPC!,
  });

  // Initialize health monitor
  const healthMonitor = new HealthMonitor(/* ... */);

  // Start services
  await Promise.all([solver.monitorAndFulfill(), healthMonitor.start()]);

  console.log("✅ All services running\n");
}

main().catch(console.error);
```

---

## 🧪 Testing Strategy

### Local Testing (Anvil Fork)

```bash
# Terminal 1: Fork Sepolia
anvil --fork-url $SEPOLIA_RPC --chain-id 11155111

# Terminal 2: Fork Base Sepolia
anvil --fork-url $BASE_SEPOLIA_RPC --chain-id 84532 --port 8546

# Terminal 3: Run solver
npm run solver:dev
```

### Testnet Testing

```bash
# Deploy contracts to Sepolia + Base Sepolia
yarn deploy:sepolia
yarn deploy:base

# Run solver on testnets
SEPOLIA_RPC=https://... BASE_SEPOLIA_RPC=https://... npm run solver

# Create travel intent from frontend
# Watch solver logs for fulfillment
```

---

## 📊 Monitoring & Logging

```typescript
// Add structured logging
import winston from "winston";

const logger = winston.createLogger({
  level: "info",
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: "solver.log" }),
    new winston.transports.Console(),
  ],
});

// Log all Li.FI operations
logger.info("Li.FI route found", {
  fromChain: intent.sourceChainId,
  toChain: intent.destinationChainId,
  tool: route.steps[0].tool,
  estimatedTime: route.steps[0].estimate.executionDuration,
  costs: costs,
});
```

---

## 🎯 Bounty Compliance

### Li.FI Bounty Checklist:

✅ **Use Li.FI SDK for cross-chain action**

- Solver uses `@lifi/sdk` for all bridging
- `getRoutes()` for optimal path finding
- `executeRoute()` for multi-step execution

✅ **Support at least two EVM chains**

- Sepolia (11155111) ↔ Base Sepolia (84532)
- Easy to add more chains

✅ **Working frontend**

- User signs travel intent
- Progress tracking via events
- Arrival animation

✅ **Multi-step workflow**

- Step 1: User signs intent (lock assets)
- Step 2: Li.FI bridges solver funds
- Step 3: LP created on destination
- Step 4: Solver claims locked assets

---

## 🚀 Demo Flow for Judges

1. **Show intent creation**: User clicks "Travel to Base", signs once
2. **Show Li.FI in action**: Solver logs show route fetching + execution
3. **Show result**: Axolotl appears on Base, health maintained
4. **Highlight efficiency**: Compare 1 signature vs traditional 6+ transactions

---

## 📚 Resources

- [Li.FI SDK Docs](https://docs.li.fi/integrate-li.fi-js-sdk)
- [Li.FI API Reference](https://docs.li.fi/li.fi-api)
- [Supported Chains](https://docs.li.fi/list-chains-bridges-dexs-solvers)
- [Route Execution](https://docs.li.fi/integrate-li.fi-js-sdk/executing-routes)

---

## 💡 Pro Tips

1. **Cache routes**: Don't re-fetch routes unnecessarily (they're valid for ~30s)
2. **Slippage tolerance**: 3% for testnets, can be tighter on mainnet
3. **Error handling**: Li.FI can fail if liquidity is low - have fallback
4. **Gas estimation**: Always check `estimateCosts()` before executing
5. **Monitoring**: Log all Li.FI calls for debugging

---

**This integration makes you competitive for BOTH bounties while maintaining the intent-based UX!**
