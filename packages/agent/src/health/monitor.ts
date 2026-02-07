/**
 * Health Monitoring Loop
 * Continuously monitors LP positions and calculates health
 */

import { PublicClient, WalletClient } from "viem";
import { config } from "../config";
import { logger, logError } from "../utils/logger";
import { getAllActivePets, getPet } from "../contracts/petRegistry";
import { getSlot0 } from "../contracts/poolManager";
import { getPositionInfo } from "../contracts/positionManager";
import {
  calculateHealthWithReason,
  shouldUpdateHealth,
  getHealthStatus,
} from "./calculator";
import { submitHealthUpdates, HealthUpdate } from "./updater";
import { retryAsync } from "../utils/retry";

// Module-level state for lifecycle management
let timeoutId: NodeJS.Timeout | undefined;
let isRunning = false;
let iterationCount = 0;

/**
 * Start health monitoring with lifecycle management
 */
export function startHealthMonitor(
  publicClient: PublicClient,
  walletClient: WalletClient,
): void {
  if (isRunning) {
    logger.warn("Health monitor already running");
    return;
  }

  isRunning = true;
  iterationCount = 0;

  logger.info("════════════════════════════════════════");
  logger.info("🏥 Health Monitor Started");
  logger.info(`   Check interval: ${config.healthCheckInterval / 1000}s`);
  logger.info(`   Min health change: ${config.minHealthChange}`);
  logger.info("════════════════════════════════════════\n");

  // Start self-scheduling monitoring loop
  scheduleNextIteration(publicClient, walletClient);
}

/**
 * Schedule the next monitoring iteration
 * Uses setTimeout instead of setInterval to prevent overlapping cycles
 */
function scheduleNextIteration(
  publicClient: PublicClient,
  walletClient: WalletClient,
): void {
  timeoutId = setTimeout(
    async () => {
      try {
        await runMonitoringIteration(publicClient, walletClient);
      } finally {
        // Schedule next iteration after current one completes
        scheduleNextIteration(publicClient, walletClient);
      }
    },
    iterationCount === 0 ? 0 : config.healthCheckInterval,
  );
}

/**
 * Stop health monitoring
 */
export function stopHealthMonitor(): void {
  if (!isRunning) {
    return;
  }

  if (timeoutId) {
    clearTimeout(timeoutId);
    timeoutId = undefined;
  }

  isRunning = false;
  logger.info("\n════════════════════════════════════════");
  logger.info("👋 Health Monitor Stopped");
  logger.info(`   Total iterations: ${iterationCount}`);
  logger.info("════════════════════════════════════════");
}

/**
 * Check if monitor is running
 */
export function isHealthMonitorRunning(): boolean {
  return isRunning;
}

/**
 * Manually check and update health for a specific pet
 * Useful for immediate updates after user actions (feed, adjust LP, etc.)
 *
 * @param publicClient - Viem public client
 * @param walletClient - Viem wallet client
 * @param petId - Pet ID to check
 * @returns Updated health value or null if no update needed
 */
export async function checkAndUpdatePetHealth(
  publicClient: PublicClient,
  walletClient: WalletClient,
  petId: bigint,
): Promise<{ oldHealth: number; newHealth: number; reason: string } | null> {
  logger.info(`\n🔍 Manual health check for Pet #${petId}...`);

  try {
    const update = await checkPetHealth(publicClient, petId);

    if (update) {
      const status = getHealthStatus(update.newHealth);
      const statusEmoji = getStatusEmoji(status);

      logger.info(
        `   ${statusEmoji} Health changed: ${update.oldHealth} → ${update.newHealth} (${status})`,
      );
      logger.info(`   Reason: ${update.reason}`);

      // Submit update immediately
      await submitHealthUpdates(publicClient, walletClient, [update]);

      return {
        oldHealth: update.oldHealth,
        newHealth: update.newHealth,
        reason: update.reason,
      };
    } else {
      logger.info(`   ✓ No health change detected (below threshold)`);
      return null;
    }
  } catch (error) {
    logError(`Failed to check Pet #${petId}`, error as Error);
    throw error;
  }
}

/**
 * Single monitoring iteration
 */
async function runMonitoringIteration(
  publicClient: PublicClient,
  walletClient: WalletClient,
): Promise<void> {
  const startTime = Date.now();
  iterationCount++;

  try {
    logger.info(
      `\n┌─ Cycle #${iterationCount} ─────────────────────────────────`,
    );

    // Fetch all active pets with retry
    const petIds = await retryAsync(
      () => getAllActivePets(publicClient, config.petRegistry),
      {
        maxAttempts: 3,
        delayMs: 1000,
        onRetry: (attempt, error) => {
          logger.warn(
            `  Retrying pet fetch (attempt ${attempt}): ${error.message}`,
          );
        },
      },
    );

    if (petIds.length === 0) {
      logger.info("│ No active pets found");
      logger.info("└─────────────────────────────────────────\n");
      return;
    }

    logger.info(`│ Checking ${petIds.length} pet(s)...`);

    // Process all pets in parallel with graceful failure handling
    const checkPromises = petIds.map((petId) =>
      checkPetHealth(publicClient, petId),
    );
    const results = await Promise.allSettled(checkPromises);

    // Collect successful updates
    const updates: HealthUpdate[] = [];
    const failures: { petId: bigint; error: string }[] = [];

    results.forEach((result, index) => {
      if (result.status === "fulfilled" && result.value !== null) {
        updates.push(result.value);
      } else if (result.status === "rejected") {
        failures.push({
          petId: petIds[index],
          error: result.reason?.message || "Unknown error",
        });
      }
    });

    // Log results grouped by outcome
    if (updates.length > 0) {
      logger.info("│");
      logger.info(`│ ⚡ Health Changes Detected: ${updates.length}`);
      updates.forEach((update) => {
        const status = getHealthStatus(update.newHealth);
        const statusEmoji = getStatusEmoji(status);
        logger.info(
          `│   ${statusEmoji} Pet #${update.petId}: ${update.oldHealth} → ${update.newHealth} (${status})`,
        );
      });

      // Submit updates
      await submitHealthUpdates(publicClient, walletClient, updates);
    }

    if (failures.length > 0) {
      logger.warn("│");
      logger.warn(`│ ⚠️  Failed to check ${failures.length} pet(s)`);
      failures.forEach(({ petId, error }) => {
        logger.warn(`│   Pet #${petId}: ${error}`);
      });
    }

    if (updates.length === 0 && failures.length === 0) {
      logger.info("│ ✓ All pets healthy (no changes)");
    }

    // Log cycle completion
    const duration = Date.now() - startTime;
    logger.info("│");
    logger.info(`└─ Completed in ${duration}ms ────────────────────\n`);
  } catch (error) {
    logger.error("│");
    logError("Monitoring cycle failed", error as Error);
    logger.error("└─────────────────────────────────────────\n");
  }
}

/**
 * Check a single pet's health and return update if needed
 */
async function checkPetHealth(
  client: PublicClient,
  petId: bigint,
): Promise<HealthUpdate | null> {
  // Fetch pet data with retry
  const pet = await retryAsync(
    () => getPet(client, config.petRegistry, petId),
    { maxAttempts: 2, delayMs: 500 },
  );

  // Fetch position and pool state in parallel with retry
  const [position, slot0] = await Promise.all([
    retryAsync(
      () => getPositionInfo(client, config.positionManager, pet.positionId),
      { maxAttempts: 2, delayMs: 500 },
    ),
    retryAsync(() => getSlot0(client, config.poolManager, pet.poolId), {
      maxAttempts: 2,
      delayMs: 500,
    }),
  ]);

  // Calculate new health
  const { health: newHealth, reason } = calculateHealthWithReason(
    slot0.tick,
    position.tickLower,
    position.tickUpper,
  );

  const oldHealth = Number(pet.health);

  // Return update if significant change detected
  if (shouldUpdateHealth(oldHealth, newHealth, config.minHealthChange)) {
    return {
      petId,
      oldHealth,
      newHealth,
      reason,
    };
  }

  return null;
}

/**
 * Get emoji for health status
 */
function getStatusEmoji(status: string): string {
  switch (status) {
    case "HEALTHY":
      return "🟢";
    case "ALERT":
      return "🟡";
    case "SAD":
      return "🟠";
    case "CRITICAL":
      return "🔴";
    default:
      return "⚪";
  }
}
