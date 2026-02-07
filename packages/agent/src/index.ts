/**
 * Xolotrain Health Monitoring Agent
 * Main entry point
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet } from "viem/chains";
import { config, validateConfig } from "./config";
import { logger } from "./utils/logger";
import { startHealthMonitor, stopHealthMonitor } from "./health/monitor";

async function main() {
  console.log("\n🦎 Xolotrain Health Monitoring Agent");
  console.log("════════════════════════════════════════\n");

  try {
    // Validate configuration
    validateConfig();

    // Create account from private key
    const account = privateKeyToAccount(config.agentPrivateKey);
    console.log(`🔑 Agent: ${account.address}`);
    console.log(`🌐 Chain: ${config.chainId} (${config.rpcUrl})`);

    // Create clients
    const publicClient = createPublicClient({
      chain: {
        ...mainnet,
        id: config.chainId,
        rpcUrls: {
          default: { http: [config.rpcUrl] },
          public: { http: [config.rpcUrl] },
        },
      },
      transport: http(config.rpcUrl),
    });

    const walletClient = createWalletClient({
      account,
      chain: {
        ...mainnet,
        id: config.chainId,
        rpcUrls: {
          default: { http: [config.rpcUrl] },
          public: { http: [config.rpcUrl] },
        },
      },
      transport: http(config.rpcUrl),
    });

    // Check agent balance
    const balance = await publicClient.getBalance({ address: account.address });
    const ethBalance = formatEther(balance);
    // Format to 4 decimal places for display (preserves bigint precision internally)
    const ethBalanceFormatted = parseFloat(ethBalance).toFixed(4);
    console.log(`💰 Balance: ${ethBalanceFormatted} ETH`);

    if (balance === 0n) {
      console.warn(
        "⚠️  Warning: No ETH for gas. Fund agent wallet before starting.\n",
      );
    }

    console.log("\n📋 Contracts:");
    console.log(`   PetRegistry: ${config.petRegistry}`);
    console.log(`   PoolManager: ${config.poolManager}`);
    console.log(`   PositionManager: ${config.positionManager}`);

    // Start health monitoring
    startHealthMonitor(publicClient, walletClient);

    console.log("\n✅ Xolotrain Agent is now running!");
    console.log("Press Ctrl+C to stop\n");
  } catch (error) {
    logger.error("Failed to start agent", {
      error: error instanceof Error ? error.message : String(error),
    });
    process.exit(1);
  }
}

// Handle graceful shutdown
const shutdown = (signal: string) => {
  logger.info(`\nReceived ${signal}, shutting down gracefully...`);
  stopHealthMonitor();
  process.exit(0);
};

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

// Handle uncaught errors
process.on("uncaughtException", (error) => {
  logger.error("Uncaught exception", {
    error: error.message,
    stack: error.stack,
  });
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  logger.error("Unhandled rejection", {
    reason: reason instanceof Error ? reason.message : String(reason),
  });
  process.exit(1);
});

// Start agent
main().catch((error) => {
  logger.error("Fatal startup error", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exit(1);
});
