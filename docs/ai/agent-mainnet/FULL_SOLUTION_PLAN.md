# Agent Multi-Chain Full Solution Plan

**Goal**: Enable agent to simultaneously monitor pets on Ethereum Mainnet AND Base Mainnet, with automatic cross-chain pet discovery.

**Timeline**: 10-14 hours  
**Prerequisite**: Quick Fix must be completed first  
**Scope**: Multi-chain architecture with cross-chain tracking

---

## 📋 Implementation Checklist

- [ ] Phase 1: Multi-Chain Configuration (2-3 hours)
- [ ] Phase 2: Multi-Client Architecture (3-4 hours)
- [ ] Phase 3: Cross-Chain Pet Discovery (3-4 hours)
- [ ] Phase 4: Enhanced Monitoring & Resilience (2-3 hours)
- [ ] Phase 5: Testing & Deployment (2 hours)

---

## Phase 1: Multi-Chain Configuration (2-3 hours)

### Goal: Support multiple chains in a single agent instance

### 🎯 Leverage Scaffold-ETH Patterns (KEY OPTIMIZATION!)

**What we're reusing from existing infrastructure**:

1. ✅ **deployedContracts.ts auto-generation** - Already works multi-chain!
2. ✅ **foundry.toml rpc_endpoints** - Centralized RPC configuration
3. ✅ **Contract merging pattern** - Combine deployed + external contracts
4. ✅ **Type-safe ABIs** - Auto-generated with proper TypeScript types

**Key insight**: The `generateTsAbis.js` script already processes ALL chains from `broadcast/` folders and creates a multi-chain `deployedContracts.ts`. The agent can **import this directly** instead of manual configuration!

**Benefits**:

- 70% less manual configuration
- Zero address duplication
- Automatic ABI updates on redeploy
- One command to add new chain: `yarn deploy --network newchain`

---

### File: `packages/agent/src/utils/contractLoader.ts` (NEW FILE)

**Create this file first** - Reuses scaffold-eth's contract loading pattern:

```typescript
/**
 * Contract Loader - Reuses Scaffold-ETH's deployedContracts.ts pattern
 * This utility reads auto-generated contracts across all chains
 */

import type { Address, Abi } from "viem";

export interface ContractInfo {
  address: Address;
  abi: Abi;
  deployedOnBlock?: number;
}

/**
 * Load deployed contracts from auto-generated file
 * Same pattern as packages/nextjs/utils/scaffold-eth/contract.ts
 */
export function loadDeployedContracts(): Record<
  number,
  Record<string, ContractInfo>
> {
  try {
    // Import the auto-generated file (relative path from agent to nextjs)
    const deployedContracts =
      require("../../nextjs/contracts/deployedContracts").default;
    return deployedContracts || {};
  } catch (error) {
    console.warn(
      "⚠️  Could not load deployedContracts.ts - contracts not deployed yet?",
    );
    return {};
  }
}

/**
 * Load external contracts (Uniswap v4, etc.)
 */
export function loadExternalContracts(): Record<
  number,
  Record<string, ContractInfo>
> {
  try {
    const externalContracts =
      require("../../nextjs/contracts/externalContracts").default;
    return externalContracts || {};
  } catch (error) {
    return {};
  }
}

/**
 * Merge deployed and external contracts (scaffold-eth deepMerge pattern)
 */
export function getAllContracts(): Record<
  number,
  Record<string, ContractInfo>
> {
  const deployed = loadDeployedContracts();
  const external = loadExternalContracts();

  // Merge both, giving priority to deployed contracts
  const allChains = new Set([
    ...Object.keys(deployed),
    ...Object.keys(external),
  ]);
  const merged: Record<number, Record<string, ContractInfo>> = {};

  for (const chainId of allChains) {
    const chain = Number(chainId);
    merged[chain] = {
      ...external[chain],
      ...deployed[chain], // Deployed overrides external
    };
  }

  return merged;
}

/**
 * Get contract address for a specific chain
 * Returns null if contract not deployed on that chain
 */
export function getContractAddress(
  chainId: number,
  contractName: string,
): Address | null {
  const contracts = getAllContracts();
  return contracts[chainId]?.[contractName]?.address || null;
}

/**
 * Get contract ABI for a specific chain
 */
export function getContractAbi(
  chainId: number,
  contractName: string,
): Abi | null {
  const contracts = getAllContracts();
  return contracts[chainId]?.[contractName]?.abi || null;
}

/**
 * Get all contract names available on a chain
 */
export function getContractNames(chainId: number): string[] {
  const contracts = getAllContracts();
  return Object.keys(contracts[chainId] || {});
}

/**
 * Check if a contract is deployed on a chain
 */
export function isContractDeployed(
  chainId: number,
  contractName: string,
): boolean {
  return getContractAddress(chainId, contractName) !== null;
}
```

---

### File: `packages/agent/src/config.ts`

#### Change 1.1: Extend Config interface for multi-chain

**Location**: Lines 11-33 (replace entire interface)

**BEFORE**:

```typescript
interface Config {
  // Network
  rpcUrl: string;
  chainId: number;
  // ... single chain config
}
```

**AFTER**:

```typescript
interface ChainConfig {
  rpcUrl: string;
  contracts: {
    petRegistry: Address;
    eggHatchHook: Address;
    autoLpHelper: Address;
    poolManager: Address;
    positionManager: Address;
  };
}

interface Config {
  // Multi-chain support
  chains: Map<number, ChainConfig>; // chainId -> config

  // Agent wallet (shared across chains)
  agentPrivateKey: `0x${string}`;

  // Agent behavior
  healthCheckInterval: number;
  minHealthChange: number;

  // Gas settings (per-chain configurable)
  gasSettings: Map<
    number,
    {
      maxGasPriceGwei: bigint;
      gasLimitHealthUpdate: number;
    }
  >;

  // Logging
  logLevel: string;
}
```

#### Change 1.2: Create multi-chain config parser

**Location**: Replace lines 62-85 (entire config export)

**NEW** (with scaffold-eth patterns):

```typescript
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { parse } from "toml"; // yarn add toml
import { fileURLToPath } from "url";
import { getAllContracts, getContractAddress } from "./utils/contractLoader";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Load RPC URLs from foundry.toml (same pattern as parseArgs.js)
 */
function loadRpcEndpoints(): Record<string, string> {
  try {
    const foundryTomlPath = join(__dirname, "../../foundry/foundry.toml");
    const tomlString = readFileSync(foundryTomlPath, "utf-8");
    const parsedToml = parse(tomlString);
    return parsedToml.rpc_endpoints || {};
  } catch (error) {
    console.warn("⚠️  Could not load foundry.toml, using env vars only");
    return {};
  }
}

/**
 * Map network names to chain IDs (scaffold-eth pattern)
 */
const NETWORK_TO_CHAIN_ID: Record<string, number> = {
  mainnet: 1,
  sepolia: 11155111,
  base: 8453,
  baseSepolia: 84532,
  localhost: 31337,
};

/**
 * Get RPC URL for a chain (checks foundry.toml first, then env var)
 */
function getRpcUrl(chainId: number, prefix: string): string {
  // Try env var first (allows override)
  const envRpc = getEnvVar(`${prefix}_RPC_URL`, false);
  if (envRpc) return envRpc;

  // Fallback to foundry.toml
  const rpcEndpoints = loadRpcEndpoints();
  const networkName = Object.entries(NETWORK_TO_CHAIN_ID).find(
    ([_, id]) => id === chainId,
  )?.[0];

  if (networkName && rpcEndpoints[networkName]) {
    return rpcEndpoints[networkName];
  }

  throw new Error(
    `No RPC URL found for chain ${chainId}. ` +
      `Set ${prefix}_RPC_URL env var or add to foundry.toml [rpc_endpoints]`,
  );
}

/**
 * Parse chain configuration
 * Auto-loads contracts from deployedContracts.ts, with env var overrides
 */
function parseChainConfig(chainId: number, prefix: string): ChainConfig {
  const allContracts = getAllContracts();
  const chainContracts = allContracts[chainId] || {};

  // Helper to get address (env var > deployedContracts > error)
  const getAddress = (contractName: string, envKey: string): Address => {
    // Check env var override
    const envAddress = getEnvVar(envKey, false);
    if (envAddress) {
      return parseAddress(envAddress, envKey);
    }

    // Check deployedContracts.ts
    const deployedAddress = chainContracts[contractName]?.address;
    if (deployedAddress) {
      console.log(`   ✅ Auto-loaded ${contractName}: ${deployedAddress}`);
      return deployedAddress;
    }

    throw new Error(
      `Contract ${contractName} not found for chain ${chainId}. ` +
        `Deploy with 'yarn deploy --network <network>' or set ${envKey} manually.`,
    );
  };

  return {
    rpcUrl: getRpcUrl(chainId, prefix),
    contracts: {
      petRegistry: getAddress("PetRegistry", `${prefix}_PET_REGISTRY`),
      eggHatchHook: getAddress("EggHatchHook", `${prefix}_EGG_HATCH_HOOK`),
      autoLpHelper: getAddress("AutoLpHelper", `${prefix}_AUTO_LP_HELPER`),
      poolManager: getAddress("IPoolManager", `${prefix}_POOL_MANAGER`),
      positionManager: getAddress(
        "IPositionManager",
        `${prefix}_POSITION_MANAGER`,
      ),
    },
  };
}

/**
 * Parse gas settings for a chain
 */
function parseGasSettings(prefix: string) {
  return {
    maxGasPriceGwei: BigInt(
      getEnvVar(`${prefix}_MAX_GAS_PRICE_GWEI`, false) || "50",
    ),
    gasLimitHealthUpdate: parseInt(
      getEnvVar(`${prefix}_GAS_LIMIT_HEALTH_UPDATE`, false) || "100000",
    ),
  };
}

/**
 * Load all enabled chains from environment
 */
function loadEnabledChains(): Map<number, ChainConfig> {
  const chains = new Map<number, ChainConfig>();

  // Check which chains are enabled
  const enabledChainIds = getEnvVar("ENABLED_CHAINS", false) || "1,8453";
  const chainIds = enabledChainIds.split(",").map((id) => parseInt(id.trim()));

  for (const chainId of chainIds) {
    try {
      const prefix = getChainEnvPrefix(chainId);
      const chainConfig = parseChainConfig(chainId, prefix);
      chains.set(chainId, chainConfig);
      console.log(
        `✅ Loaded configuration for chain ${chainId} (${getChainName(chainId)})`,
      );
    } catch (error) {
      console.error(
        `❌ Failed to load config for chain ${chainId}: ${(error as Error).message}`,
      );
      console.error(
        `   Make sure all ${getChainEnvPrefix(chainId)}_* variables are set`,
      );
      process.exit(1);
    }
  }

  if (chains.size === 0) {
    throw new Error(
      "No chains configured! Set ENABLED_CHAINS and chain-specific variables.",
    );
  }

  return chains;
}

/**
 * Get environment variable prefix for a chain
 */
function getChainEnvPrefix(chainId: number): string {
  const prefixes: Record<number, string> = {
    1: "ETH_MAINNET",
    8453: "BASE_MAINNET",
    11155111: "SEPOLIA",
    84532: "BASE_SEPOLIA",
    31337: "ANVIL",
  };

  return prefixes[chainId] || `CHAIN_${chainId}`;
}

/**
 * Get human-readable chain name
 */
function getChainName(chainId: number): string {
  const names: Record<number, string> = {
    1: "Ethereum Mainnet",
    8453: "Base Mainnet",
    11155111: "Sepolia Testnet",
    84532: "Base Sepolia Testnet",
    31337: "Anvil Local",
  };

  return names[chainId] || `Chain ${chainId}`;
}

/**
 * Load gas settings for all chains
 */
function loadGasSettings(chainIds: number[]): Map<number, any> {
  const gasSettings = new Map();

  for (const chainId of chainIds) {
    const prefix = getChainEnvPrefix(chainId);
    gasSettings.set(chainId, parseGasSettings(prefix));
  }

  return gasSettings;
}

// Load multi-chain configuration
const enabledChains = loadEnabledChains();
const chainIds = Array.from(enabledChains.keys());

export const config: Config = {
  chains: enabledChains,

  // Agent wallet (shared across all chains)
  agentPrivateKey: parsePrivateKey(getEnvVar("AGENT_PRIVATE_KEY")),

  // Agent behavior
  healthCheckInterval: parseInt(
    getEnvVar("HEALTH_CHECK_INTERVAL", false) || "60000",
  ),
  minHealthChange: parseInt(getEnvVar("MIN_HEALTH_CHANGE", false) || "5"),

  // Gas settings per chain
  gasSettings: loadGasSettings(chainIds),

  // Logging
  logLevel: getEnvVar("LOG_LEVEL", false) || "info",
};

// Export helpers
export { getChainName, getChainEnvPrefix };
```

#### Change 1.3: Update validateConfig for multi-chain

**Location**: Lines 100-120 (replace validateConfig function)

**NEW**:

```typescript
/**
 * Validate multi-chain configuration
 */
export function validateConfig(): void {
  // Validate at least one chain is configured
  if (config.chains.size === 0) {
    throw new Error("No chains configured");
  }

  console.log("\n🔧 Agent Configuration:");
  console.log(`   Monitoring ${config.chains.size} chain(s):`);

  for (const [chainId, chainConfig] of config.chains) {
    console.log(`   • ${getChainName(chainId)} (${chainId})`);

    // Validate RPC URL
    if (
      !chainConfig.rpcUrl.startsWith("http://") &&
      !chainConfig.rpcUrl.startsWith("https://")
    ) {
      throw new Error(
        `Invalid RPC URL for chain ${chainId}: ${chainConfig.rpcUrl}`,
      );
    }
  }

  // Validate intervals
  if (config.healthCheckInterval < 10000) {
    console.warn(
      "⚠️  Warning: Health check interval < 10s may cause high RPC usage across all chains",
    );
  }

  if (config.minHealthChange < 1 || config.minHealthChange > 100) {
    throw new Error(
      `Invalid minHealthChange: ${config.minHealthChange}. Must be between 1 and 100.`,
    );
  }

  console.log(
    `   Health check interval: ${config.healthCheckInterval / 1000}s`,
  );
  console.log(`   Min health change: ${config.minHealthChange}`);
  console.log("");
}
```

### File: `packages/agent/.env.example`

#### Change 1.4: Update environment template (SIMPLIFIED with scaffold-eth patterns)

**REPLACE ENTIRE FILE**:

```dotenv
# ═══════════════════════════════════════════════════════════════════
# Xolotrain Multi-Chain Agent Configuration
# Leverages Scaffold-ETH Infrastructure for Simplified Setup
# ═══════════════════════════════════════════════════════════════════

# ===================================================================
# ENABLED CHAINS
# ===================================================================
# Comma-separated list of chain IDs to monitor
# 1 = Ethereum Mainnet, 8453 = Base Mainnet
# 11155111 = Sepolia, 84532 = Base Sepolia, 31337 = Anvil

# Example: Monitor both Ethereum and Base Mainnet
ENABLED_CHAINS=1,8453

# Example: Monitor both testnets
# ENABLED_CHAINS=11155111,84532

# Example: Single chain (backward compatible)
# ENABLED_CHAINS=31337

# ===================================================================
# RPC CONFIGURATION (Mostly Auto-Detected!)
# ===================================================================
# The agent automatically reads from foundry.toml [rpc_endpoints]
# You only need to override if you want different RPCs than deployment

# Alchemy API Key (used by foundry.toml)
# Get yours at: https://dashboard.alchemy.com
ALCHEMY_API_KEY=cR4WnXePioePZ5fFrnSiR

# Optional: Override specific RPCs (uncomment to override foundry.toml)
# ETH_MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
# BASE_MAINNET_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
# SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
# BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY

# ===================================================================
# CONTRACT ADDRESSES (Mostly Auto-Detected!)
# ===================================================================
# The agent automatically loads from packages/nextjs/contracts/deployedContracts.ts
# This file is auto-generated by: yarn deploy
#
# You only need to set these manually if:
# 1. Contracts are NOT in deployedContracts.ts yet
# 2. You want to override auto-detected addresses
# 3. You're using external/proxy contracts

# ─── Uniswap v4 Contracts (External - Set These!) ───
# These are NOT auto-deployed, must be set manually

# Ethereum Mainnet
ETH_MAINNET_POOL_MANAGER=0x000000000004444c5dc75cB358380D2e3dE08A90
ETH_MAINNET_POSITION_MANAGER=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e

# Base Mainnet (check official Uniswap v4 docs)
BASE_MAINNET_POOL_MANAGER=0x... # TODO: Get from Uniswap v4 deployment
BASE_MAINNET_POSITION_MANAGER=0x... # TODO: Get from Uniswap v4 deployment

# Sepolia Testnet
SEPOLIA_POOL_MANAGER=0x... # Uniswap v4 testnet
SEPOLIA_POSITION_MANAGER=0x... # Uniswap v4 testnet

# Base Sepolia Testnet
BASE_SEPOLIA_POOL_MANAGER=0x... # Uniswap v4 testnet
BASE_SEPOLIA_POSITION_MANAGER=0x... # Uniswap v4 testnet

# ─── Override Deployed Contracts (Optional) ───
# Uncomment only if you need to override auto-detected addresses
# ETH_MAINNET_PET_REGISTRY=0x...
# ETH_MAINNET_EGG_HATCH_HOOK=0x...
# ETH_MAINNET_AUTO_LP_HELPER=0x...
# BASE_MAINNET_PET_REGISTRY=0x... # Same as ETH if CREATE2
# BASE_MAINNET_EGG_HATCH_HOOK=0x... # Same as ETH if CREATE2
# BASE_MAINNET_AUTO_LP_HELPER=0x...

# ===================================================================
# GAS SETTINGS (Per-Chain)
# ===================================================================
ETH_MAINNET_MAX_GAS_PRICE_GWEI=50
ETH_MAINNET_GAS_LIMIT_HEALTH_UPDATE=100000

BASE_MAINNET_MAX_GAS_PRICE_GWEI=5  # Base is ~50x cheaper
BASE_MAINNET_GAS_LIMIT_HEALTH_UPDATE=100000

SEPOLIA_MAX_GAS_PRICE_GWEI=100
SEPOLIA_GAS_LIMIT_HEALTH_UPDATE=100000

BASE_SEPOLIA_MAX_GAS_PRICE_GWEI=10
BASE_SEPOLIA_GAS_LIMIT_HEALTH_UPDATE=100000

# ===================================================================
# AGENT WALLET
# ===================================================================
# Single wallet used across all chains
# Make sure this wallet has ETH on ALL enabled chains!
AGENT_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# ===================================================================
# AGENT BEHAVIOR
# ===================================================================
HEALTH_CHECK_INTERVAL=60000  # Check all chains every 60 seconds
MIN_HEALTH_CHANGE=5          # Update if health changes by 5+ points

# ===================================================================
# LOGGING
# ===================================================================
LOG_LEVEL=info  # Options: error, warn, info, debug

# ===================================================================
# NOTES FOR MULTI-CHAIN SETUP
# ===================================================================
#
# 🎯 KEY ADVANTAGE: Reuses Scaffold-ETH Infrastructure!
#
# 1. Deploy contracts to chains:
#    $ yarn deploy --network sepolia
#    $ yarn deploy --network baseSepolia
#    → Automatically updates deployedContracts.ts!
#
# 2. Contract addresses auto-loaded from:
#    - packages/nextjs/contracts/deployedContracts.ts (auto-generated)
#    - packages/foundry/broadcast/**/run-latest.json (deployment history)
#
# 3. RPCs auto-loaded from:
#    - packages/foundry/foundry.toml [rpc_endpoints]
#
# 4. Fund agent wallet on ALL enabled chains:
#    $ cast balance <ADDRESS> --rpc-url sepolia
#    $ cast send <ADDRESS> --value 0.1ether --rpc-url sepolia
#
# 5. CREATE2 deployments = same address across chains:
#    $ cast code <PET_REGISTRY> --rpc-url sepolia
#    $ cast code <PET_REGISTRY> --rpc-url baseSepolia
#    → Should return identical bytecode!
#
# 6. RPC rate limits scale with number of chains:
#    - 2 chains = 2x RPC calls
#    - Use Alchemy Growth tier or higher for production
#
# 7. To add a new chain:
#    a. Add RPC to foundry.toml [rpc_endpoints]
#    b. Deploy: yarn deploy --network <newchain>
#    c. Add chain ID to ENABLED_CHAINS
#    d. Set Uniswap v4 addresses if needed
#    e. Restart agent → new chain is monitored!
#
```

---

### File: `packages/agent/package.json`

#### Change 1.5: Add required dependencies

**Location**: Add to dependencies

```json
{
  "dependencies": {
    "dotenv": "^16.4.0",
    "viem": "^2.7.0",
    "winston": "^3.11.0",
    "toml": "^3.0.0" // NEW - for parsing foundry.toml
  }
}
```

**Run**: `cd packages/agent && yarn add toml`

---

### Phase 1 Summary

**What we built**:

1. ✅ `contractLoader.ts` - Auto-loads contracts from `deployedContracts.ts`
2. ✅ Updated `config.ts` - Reads RPCs from `foundry.toml`
3. ✅ Simplified `.env` - 70% less configuration needed
4. ✅ Type-safe ABIs - Reuses auto-generated types

**Configuration reduction**:

- **Before**: 15+ env vars per chain (RPCs + all contract addresses)
- **After**: 2-3 env vars per chain (Uniswap v4 contracts only)
- **Savings**: ~70% less manual configuration!

**Key files created/modified**:

- Created: `packages/agent/src/utils/contractLoader.ts`
- Modified: `packages/agent/src/config.ts`
- Modified: `packages/agent/.env.example`
- Modified: `packages/agent/package.json`

---

## Phase 2: Multi-Client Architecture (3-4 hours)

### Goal: Create Viem clients for each enabled chain

### File: `packages/agent/src/clients.ts` (NEW FILE)

**Create new file**:

```typescript
/**
 * Multi-Chain Client Manager
 * Creates and manages Viem clients for all enabled chains
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  PublicClient,
  WalletClient,
  Chain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet, base, sepolia, baseSepolia, foundry } from "viem/chains";
import { config } from "./config";
import { logger } from "./utils/logger";

/**
 * Client pair for a chain
 */
export interface ChainClients {
  publicClient: PublicClient;
  walletClient: WalletClient;
  chain: Chain;
}

/**
 * Map of chain ID to clients
 */
export type ClientsMap = Map<number, ChainClients>;

/**
 * Get Viem chain object for a chain ID
 */
function getViemChain(chainId: number): Chain {
  const chains: Record<number, Chain> = {
    1: mainnet,
    8453: base,
    11155111: sepolia,
    84532: baseSepolia,
    31337: foundry,
  };

  if (chains[chainId]) {
    return chains[chainId];
  }

  // Custom chain for unsupported chain IDs
  return {
    id: chainId,
    name: `Chain ${chainId}`,
    network: `chain-${chainId}`,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    rpcUrls: {
      default: { http: [] },
      public: { http: [] },
    },
  };
}

/**
 * Create clients for all enabled chains
 */
export function createMultiChainClients(): ClientsMap {
  const clients = new Map<number, ChainClients>();
  const account = privateKeyToAccount(config.agentPrivateKey);

  logger.info("\n🔗 Creating clients for all chains...");

  for (const [chainId, chainConfig] of config.chains) {
    try {
      const viemChain = getViemChain(chainId);

      const publicClient = createPublicClient({
        chain: viemChain,
        transport: http(chainConfig.rpcUrl, {
          timeout: 30_000, // 30 second timeout
          retryCount: 3,
          retryDelay: 1000,
        }),
      });

      const walletClient = createWalletClient({
        account,
        chain: viemChain,
        transport: http(chainConfig.rpcUrl, {
          timeout: 30_000,
          retryCount: 3,
          retryDelay: 1000,
        }),
      });

      clients.set(chainId, {
        publicClient,
        walletClient,
        chain: viemChain,
      });

      logger.info(`   ✅ Created clients for chain ${chainId}`);
    } catch (error) {
      logger.error(`   ❌ Failed to create clients for chain ${chainId}`, {
        error: (error as Error).message,
      });
      throw error;
    }
  }

  return clients;
}

/**
 * Check balances for agent wallet on all chains
 */
export async function checkAgentBalances(clients: ClientsMap): Promise<void> {
  const account = privateKeyToAccount(config.agentPrivateKey);

  logger.info("\n💰 Agent wallet balances:");
  logger.info(`   Address: ${account.address}`);
  logger.info("");

  for (const [chainId, { publicClient, chain }] of clients) {
    try {
      const balance = await publicClient.getBalance({
        address: account.address,
      });
      const ethBalance = (Number(balance) / 1e18).toFixed(4);

      logger.info(`   ${chain.name}: ${ethBalance} ETH`);

      if (balance === 0n) {
        logger.warn(
          `   ⚠️  No balance on ${chain.name} - agent cannot submit transactions!`,
        );
      }
    } catch (error) {
      logger.error(`   ❌ Failed to check balance on chain ${chainId}`, {
        error: (error as Error).message,
      });
    }
  }

  logger.info("");
}

/**
 * Test connectivity to all chains
 */
export async function testConnectivity(clients: ClientsMap): Promise<void> {
  logger.info("🔍 Testing RPC connectivity...");

  for (const [chainId, { publicClient, chain }] of clients) {
    try {
      const blockNumber = await publicClient.getBlockNumber();
      logger.info(`   ✅ ${chain.name}: Block ${blockNumber}`);
    } catch (error) {
      logger.error(`   ❌ ${chain.name}: Connection failed`, {
        error: (error as Error).message,
      });
      throw new Error(`Cannot connect to chain ${chainId}`);
    }
  }

  logger.info("");
}
```

### File: `packages/agent/src/index.ts`

#### Change 2.1: Update main entry point for multi-chain

**Location**: Lines 1-80 (replace main function)

**BEFORE**:

```typescript
async function main() {
  // Single chain setup
  const publicClient = createPublicClient(...);
  const walletClient = createWalletClient(...);
}
```

**AFTER**:

```typescript
import {
  createMultiChainClients,
  checkAgentBalances,
  testConnectivity,
} from "./clients";

async function main() {
  console.log("\n🦎 Xolotrain Multi-Chain Health Monitoring Agent");
  console.log("════════════════════════════════════════════════");
  console.log(`   Monitoring ${config.chains.size} chain(s)`);
  console.log("════════════════════════════════════════════════\n");

  try {
    // Validate configuration
    validateConfig();

    // Create clients for all enabled chains
    const clients = createMultiChainClients();

    // Test connectivity to all chains
    await testConnectivity(clients);

    // Check agent balances on all chains
    await checkAgentBalances(clients);

    // Display contract addresses for each chain
    console.log("📋 Monitored Contracts:");
    for (const [chainId, chainConfig] of config.chains) {
      console.log(`\n   ${getChainName(chainId)} (${chainId}):`);
      console.log(`      PetRegistry: ${chainConfig.contracts.petRegistry}`);
      console.log(`      PoolManager: ${chainConfig.contracts.poolManager}`);
      console.log(
        `      PositionManager: ${chainConfig.contracts.positionManager}`,
      );
    }
    console.log("");

    // Start multi-chain health monitoring
    startHealthMonitor(clients);

    console.log("\n✅ Xolotrain Multi-Chain Agent is now running!");
    console.log("   Press Ctrl+C to stop\n");
  } catch (error) {
    logger.error("Failed to start agent", {
      error: error instanceof Error ? error.message : String(error),
    });
    process.exit(1);
  }
}
```

---

## Phase 3: Cross-Chain Pet Discovery (3-4 hours)

### Goal: Find pets regardless of which chain they're on

### File: `packages/agent/src/health/monitor.ts`

#### Change 3.1: Update monitor to work with multi-chain clients

**Location**: Lines 1-50 (update imports and function signatures)

**BEFORE**:

```typescript
export function startHealthMonitor(
  publicClient: PublicClient,
  walletClient: WalletClient,
): void {
```

**AFTER**:

```typescript
import type { ClientsMap } from "../clients";

export function startHealthMonitor(clients: ClientsMap): void {
```

#### Change 3.2: Update monitoring iteration for multi-chain

**Location**: Lines 150-250 (replace runMonitoringIteration function)

**NEW**:

```typescript
/**
 * Single monitoring iteration across ALL chains
 */
async function runMonitoringIteration(clients: ClientsMap): Promise<void> {
  iterationCount++;

  logger.info("┌────────────────────────────────────────");
  logger.info(`│ 🔍 Iteration #${iterationCount}`);
  logger.info("│");

  try {
    // Step 1: Discover all pets across all chains
    const allPets = await discoverPetsAcrossChains(clients);

    logger.info(
      `│ 📊 Found ${allPets.length} active pet(s) across ${clients.size} chain(s)`,
    );
    logger.info("│");

    if (allPets.length === 0) {
      logger.info("│ ℹ️  No pets to monitor yet");
      logger.info("└────────────────────────────────────────\n");
      return;
    }

    // Step 2: Check health for each pet (parallel)
    const healthChecks = allPets.map((petInfo) =>
      checkPetHealthOnChain(petInfo, clients).catch((error) => {
        logError(`Failed to check Pet #${petInfo.petId}`, error as Error);
        return null;
      }),
    );

    const results = await Promise.allSettled(healthChecks);

    // Step 3: Collect updates that need to be submitted
    const updates: Array<{
      chainId: number;
      update: HealthUpdate;
    }> = [];

    for (const result of results) {
      if (result.status === "fulfilled" && result.value) {
        updates.push(result.value);
      }
    }

    // Step 4: Submit updates per chain
    if (updates.length > 0) {
      logger.info("│");
      logger.info(`│ 📡 Submitting ${updates.length} update(s)...`);

      await submitUpdatesPerChain(updates, clients);
    }

    const duration = "..."; // Calculate actual duration
    logger.info("│");
    logger.info(`│ ✅ Iteration #${iterationCount} complete (${duration})`);
    logger.info("└────────────────────────────────────────\n");
  } catch (error) {
    logError("Monitoring iteration failed", error as Error);
  }
}
```

#### Change 3.3: Add cross-chain pet discovery

**Location**: Add new functions at end of file

**ADD**:

```typescript
/**
 * Pet information with chain location
 */
interface PetInfo {
  petId: bigint;
  chainId: number;
  owner: Address;
  positionId: bigint;
  currentHealth: number;
}

/**
 * Discover all active pets across all chains
 */
async function discoverPetsAcrossChains(
  clients: ClientsMap,
): Promise<PetInfo[]> {
  const allPets: PetInfo[] = [];

  // Query each chain in parallel
  const discoveries = Array.from(clients.entries()).map(
    async ([chainId, { publicClient }]) => {
      try {
        const chainConfig = config.chains.get(chainId)!;
        const pets = await getAllActivePets(
          publicClient,
          chainConfig.contracts.petRegistry,
        );

        return pets.map((pet) => ({
          petId: pet.petId,
          chainId,
          owner: pet.owner,
          positionId: pet.positionId,
          currentHealth: pet.health,
        }));
      } catch (error) {
        logger.error(`Failed to discover pets on chain ${chainId}`, {
          error: (error as Error).message,
        });
        return [];
      }
    },
  );

  const results = await Promise.allSettled(discoveries);

  for (const result of results) {
    if (result.status === "fulfilled") {
      allPets.push(...result.value);
    }
  }

  return allPets;
}

/**
 * Check health for a pet on its current chain
 */
async function checkPetHealthOnChain(
  petInfo: PetInfo,
  clients: ClientsMap,
): Promise<{ chainId: number; update: HealthUpdate } | null> {
  const { publicClient } = clients.get(petInfo.chainId)!;
  const chainConfig = config.chains.get(petInfo.chainId)!;

  try {
    // Get position info
    const position = await getPositionInfo(
      publicClient,
      chainConfig.contracts.positionManager,
      petInfo.positionId,
    );

    // Get pool state
    const slot0 = await getSlot0(
      publicClient,
      chainConfig.contracts.poolManager,
      position.poolId,
    );

    // Calculate health
    const { health: newHealth, reason } = calculateHealthWithReason(
      slot0.tick,
      position.tickLower,
      position.tickUpper,
    );

    // Check if update needed
    if (
      !shouldUpdateHealth(
        petInfo.currentHealth,
        newHealth,
        config.minHealthChange,
      )
    ) {
      return null;
    }

    // Return update info
    return {
      chainId: petInfo.chainId,
      update: {
        petId: petInfo.petId,
        oldHealth: petInfo.currentHealth,
        newHealth,
        reason,
      },
    };
  } catch (error) {
    throw new Error(
      `Failed to check health for Pet #${petInfo.petId} on chain ${petInfo.chainId}: ${(error as Error).message}`,
    );
  }
}

/**
 * Submit health updates, grouped by chain
 */
async function submitUpdatesPerChain(
  updates: Array<{ chainId: number; update: HealthUpdate }>,
  clients: ClientsMap,
): Promise<void> {
  // Group updates by chain
  const updatesByChain = new Map<number, HealthUpdate[]>();

  for (const { chainId, update } of updates) {
    if (!updatesByChain.has(chainId)) {
      updatesByChain.set(chainId, []);
    }
    updatesByChain.get(chainId)!.push(update);
  }

  // Submit updates for each chain in parallel
  const submissions = Array.from(updatesByChain.entries()).map(
    async ([chainId, chainUpdates]) => {
      const { publicClient, walletClient } = clients.get(chainId)!;

      logger.info(`│   Chain ${chainId}: ${chainUpdates.length} update(s)`);

      await submitHealthUpdates(
        publicClient,
        walletClient,
        chainId,
        chainUpdates,
      );
    },
  );

  await Promise.allSettled(submissions);
}
```

### File: `packages/agent/src/health/updater.ts`

#### Change 3.4: Update submitter to accept chain ID

**Location**: Lines 20-55 (update function signatures)

**BEFORE**:

```typescript
export async function submitHealthUpdate(
  publicClient: PublicClient,
  walletClient: WalletClient,
  update: HealthUpdate,
): Promise<void> {
```

**AFTER**:

```typescript
export async function submitHealthUpdate(
  publicClient: PublicClient,
  walletClient: WalletClient,
  chainId: number,
  update: HealthUpdate,
): Promise<void> {
  try {
    const chainConfig = config.chains.get(chainId)!;
    const gasSettings = config.gasSettings.get(chainId)!;

    // Check gas price (use chain-specific settings)
    const canProceed = await shouldProceedWithGas(
      publicClient,
      gasSettings.maxGasPriceGwei,
    );
    // ... rest of function using chainConfig
```

**Similar updates needed for**:

- `submitHealthUpdates()` - add chainId parameter
- `updateHealth()` in petRegistry.ts - use chain-specific gas settings

---

## Phase 4: Enhanced Monitoring & Resilience (2-3 hours)

### Goal: Add error handling, retry logic, and monitoring

### File: `packages/agent/src/utils/resilience.ts` (NEW FILE)

**Create new file**:

```typescript
/**
 * Resilience utilities for multi-chain operations
 */

import { logger } from "./logger";

/**
 * Retry a function with exponential backoff
 */
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  options: {
    maxRetries: number;
    initialDelay: number;
    maxDelay: number;
    chainId?: number;
    operation?: string;
  },
): Promise<T> {
  let lastError: Error;

  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;

      if (attempt === options.maxRetries) {
        logger.error(
          `Operation failed after ${options.maxRetries + 1} attempts${options.chainId ? ` on chain ${options.chainId}` : ""}`,
          { operation: options.operation, error: lastError.message },
        );
        throw lastError;
      }

      const delay = Math.min(
        options.initialDelay * Math.pow(2, attempt),
        options.maxDelay,
      );

      logger.warn(`Attempt ${attempt + 1} failed, retrying in ${delay}ms...`, {
        operation: options.operation,
        error: lastError.message,
      });

      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError!;
}

/**
 * Circuit breaker for chain RPC connections
 */
export class CircuitBreaker {
  private failures = new Map<number, number>();
  private lastAttempt = new Map<number, number>();
  private readonly threshold = 5; // Open circuit after 5 failures
  private readonly timeout = 60000; // Try again after 1 minute

  isOpen(chainId: number): boolean {
    const failures = this.failures.get(chainId) || 0;
    if (failures < this.threshold) return false;

    const lastAttempt = this.lastAttempt.get(chainId) || 0;
    const now = Date.now();

    if (now - lastAttempt > this.timeout) {
      // Reset and try again
      this.failures.set(chainId, 0);
      return false;
    }

    return true;
  }

  recordFailure(chainId: number): void {
    const failures = (this.failures.get(chainId) || 0) + 1;
    this.failures.set(chainId, failures);
    this.lastAttempt.set(chainId, Date.now());

    if (failures >= this.threshold) {
      logger.error(
        `🚨 Circuit breaker OPEN for chain ${chainId} after ${failures} failures`,
      );
    }
  }

  recordSuccess(chainId: number): void {
    this.failures.set(chainId, 0);
  }
}
```

### File: `packages/agent/src/health/monitor.ts`

#### Change 4.1: Add circuit breaker to monitoring

**Location**: After module-level state variables

**ADD**:

```typescript
import { CircuitBreaker, retryWithBackoff } from "../utils/resilience";

// Circuit breaker for chain connectivity
const circuitBreaker = new CircuitBreaker();
```

#### Change 4.2: Update discovery to use circuit breaker

**Location**: In `discoverPetsAcrossChains` function

**BEFORE**:

```typescript
const discoveries = Array.from(clients.entries()).map(
  async ([chainId, { publicClient }]) => {
    try {
      // ... discover pets
```

**AFTER**:

```typescript
const discoveries = Array.from(clients.entries()).map(
  async ([chainId, { publicClient }]) => {
    // Skip if circuit breaker is open
    if (circuitBreaker.isOpen(chainId)) {
      logger.warn(`⚠️  Skipping chain ${chainId} - circuit breaker is OPEN`);
      return [];
    }

    try {
      const pets = await retryWithBackoff(
        async () => {
          const chainConfig = config.chains.get(chainId)!;
          return await getAllActivePets(
            publicClient,
            chainConfig.contracts.petRegistry,
          );
        },
        {
          maxRetries: 3,
          initialDelay: 1000,
          maxDelay: 5000,
          chainId,
          operation: "discover pets",
        },
      );

      circuitBreaker.recordSuccess(chainId);

      return pets.map((pet) => ({
        petId: pet.petId,
        chainId,
        owner: pet.owner,
        positionId: pet.positionId,
        currentHealth: pet.health,
      }));
    } catch (error) {
      circuitBreaker.recordFailure(chainId);
      logger.error(`Failed to discover pets on chain ${chainId}`, {
        error: (error as Error).message,
      });
      return [];
    }
  },
);
```

---

## Phase 5: Testing & Deployment (2 hours)

### Test Script: `packages/agent/test-multichain.ts` (NEW FILE)

```typescript
/**
 * Multi-chain agent test script
 * Run this before deploying to production
 */

import { config, validateConfig } from "./src/config";
import {
  createMultiChainClients,
  testConnectivity,
  checkAgentBalances,
} from "./src/clients";
import { logger } from "./src/utils/logger";

async function test() {
  console.log("🧪 Testing Multi-Chain Agent Setup\n");

  try {
    // Test 1: Configuration
    console.log("Test 1: Validating configuration...");
    validateConfig();
    console.log("✅ Configuration valid\n");

    // Test 2: Client creation
    console.log("Test 2: Creating clients...");
    const clients = createMultiChainClients();
    console.log(`✅ Created ${clients.size} client(s)\n`);

    // Test 3: RPC connectivity
    console.log("Test 3: Testing RPC connectivity...");
    await testConnectivity(clients);
    console.log("✅ All RPCs responding\n");

    // Test 4: Agent balances
    console.log("Test 4: Checking agent balances...");
    await checkAgentBalances(clients);
    console.log("✅ Balance check complete\n");

    // Test 5: Contract reads
    console.log("Test 5: Testing contract reads...");
    for (const [chainId, { publicClient }] of clients) {
      const chainConfig = config.chains.get(chainId)!;

      try {
        const code = await publicClient.getBytecode({
          address: chainConfig.contracts.petRegistry,
        });

        if (!code || code === "0x") {
          throw new Error("No contract code found");
        }

        console.log(`   ✅ Chain ${chainId}: PetRegistry contract verified`);
      } catch (error) {
        console.error(`   ❌ Chain ${chainId}: ${(error as Error).message}`);
        throw error;
      }
    }
    console.log("✅ All contracts accessible\n");

    console.log("🎉 All tests passed! Agent is ready to deploy.\n");
    process.exit(0);
  } catch (error) {
    console.error("\n❌ Tests failed:", (error as Error).message);
    process.exit(1);
  }
}

test();
```

### Update `packages/agent/package.json`

**Add test script**:

```json
{
  "scripts": {
    "test:multichain": "ts-node test-multichain.ts"
    // ... existing scripts
  }
}
```

### Deployment Checklist

```bash
# 1. Test multi-chain setup
cd packages/agent
cp .env.example .env
# Edit .env with your multi-chain configuration
yarn test:multichain

# 2. Build agent
yarn build

# 3. Test on testnets first
ENABLED_CHAINS=11155111,84532 yarn start

# Let it run for 24 hours, monitor for issues

# 4. Deploy to mainnet
ENABLED_CHAINS=1,8453 yarn start

# 5. Monitor logs
tail -f logs/agent.log

# 6. Set up monitoring dashboard (recommended)
# - Grafana + Prometheus
# - Track: RPC calls, health updates, gas costs, errors per chain
```

---

## 🎯 Success Criteria

Full solution is complete when:

✅ Agent monitors multiple chains simultaneously  
✅ Pets are discovered regardless of chain  
✅ Health updates are submitted to correct chain  
✅ Circuit breaker prevents cascade failures  
✅ Cross-chain travel doesn't break monitoring  
✅ Gas costs are optimized per chain  
✅ Agent survives RPC outages gracefully  
✅ All tests pass on testnets for 24+ hours

---

## 📊 Performance Expectations

With 2 chains enabled:

- **RPC calls**: ~2x single-chain (distributed across chains)
- **Memory usage**: ~1.5x single-chain
- **Gas costs**: Varies by chain (Base ~50x cheaper than Ethereum)
- **Latency**: Parallel execution keeps iteration time similar

With circuit breaker:

- **Resilience**: Agent continues working if one chain fails
- **Recovery**: Automatic retry after timeout period
- **Monitoring**: Clear logs when chains are unavailable

---

## 🚀 Future Enhancements (Post-Full Solution)

1. **Database Layer**: Persist pet locations to survive agent restarts
2. **WebSocket Subscriptions**: Real-time events instead of polling
3. **Dynamic Chain Addition**: Add new chains without restart
4. **Health Metrics API**: Expose agent stats via HTTP endpoint
5. **Solver Integration**: Add intent fulfillment for cross-chain travel

These can be added incrementally after full solution is stable.
