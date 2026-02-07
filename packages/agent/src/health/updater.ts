/**
 * Health Update Submitter
 * Batches and submits health updates to PetRegistry
 */

import { PublicClient, WalletClient } from "viem";
import { updateHealth } from "../contracts/petRegistry";
import { config } from "../config";
import { logger, logHealthUpdate, logError } from "../utils/logger";
import { getOptimalGasFees, shouldProceedWithGas } from "../utils/gas";

export interface HealthUpdate {
  petId: bigint;
  oldHealth: number;
  newHealth: number;
  reason: string;
}

/**
 * Submit a single health update
 */
export async function submitHealthUpdate(
  publicClient: PublicClient,
  walletClient: WalletClient,
  update: HealthUpdate,
): Promise<void> {
  try {
    // Check gas price
    const canProceed = await shouldProceedWithGas(publicClient);
    if (!canProceed) {
      logger.warn(`│   ⛽ Skipping Pet #${update.petId} - gas too high`);
      return;
    }

    logger.info("Submitting health update", {
      petId: update.petId.toString(),
      oldHealth: update.oldHealth,
      newHealth: update.newHealth,
      reason: update.reason,
    });

    // Get optimal gas fees (EIP-1559 or legacy)
    const gasFees = await getOptimalGasFees(publicClient);

    // Submit transaction with gas parameters
    const hash = await updateHealth(
      walletClient,
      config.petRegistry,
      update.petId,
      update.newHealth,
      config.chainId,
      gasFees,
    );

    logger.info("Health update transaction sent", {
      petId: update.petId.toString(),
      txHash: hash,
    });

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status === "success") {
      logHealthUpdate({
        petId: update.petId.toString(),
        oldHealth: update.oldHealth,
        newHealth: update.newHealth,
        reason: update.reason,
        txHash: hash,
        gasUsed: receipt.gasUsed,
      });
    } else {
      logger.error("Health update transaction failed", {
        petId: update.petId.toString(),
        txHash: hash,
        status: receipt.status,
      });
    }
  } catch (error) {
    logger.error(
      `│   ✗ Pet #${update.petId} update failed: ${(error as Error).message}`,
    );
  }
}

/**
 * Submit multiple health updates (batched if possible)
 * For MVP, we submit sequentially. In production, could use multicall
 */
export async function submitHealthUpdates(
  publicClient: PublicClient,
  walletClient: WalletClient,
  updates: HealthUpdate[],
): Promise<void> {
  if (updates.length === 0) {
    return;
  }

  logger.info("│");
  logger.info(`│ 📡 Submitting Updates...`);

  for (const update of updates) {
    await submitHealthUpdate(publicClient, walletClient, update);

    // Small delay between transactions to avoid nonce issues
    if (updates.length > 1) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  logger.info(`Completed ${updates.length} health update(s)`);
}
