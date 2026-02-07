/**
 * Gas price optimization utilities
 */

import { PublicClient, formatGwei, parseGwei } from "viem";
import { config } from "../config";
import { logger } from "./logger";

export interface GasFees {
  // EIP-1559 fields (for chains that support it)
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  // Legacy field (for chains that don't support EIP-1559)
  gasPrice?: bigint;
}

/**
 * Get optimal gas fees for non-urgent transactions
 * Prefers EIP-1559 (base fee + priority fee), falls back to legacy gas price
 */
export async function getOptimalGasFees(
  client: PublicClient,
): Promise<GasFees> {
  try {
    const maxGasPrice = parseGwei(config.maxGasPriceGwei.toString());

    // Try EIP-1559 first
    try {
      const feeData = await client.estimateFeesPerGas();

      if (feeData.maxFeePerGas && feeData.maxPriorityFeePerGas) {
        // Cap maxFeePerGas at configured maximum
        let maxFeePerGas = feeData.maxFeePerGas;
        let maxPriorityFeePerGas = feeData.maxPriorityFeePerGas;

        if (maxFeePerGas > maxGasPrice) {
          logger.warn(
            `│   Max fee ${formatGwei(maxFeePerGas)} > max ${formatGwei(maxGasPrice)}, capping`,
          );
          maxFeePerGas = maxGasPrice;
          // Also cap priority fee if needed
          maxPriorityFeePerGas =
            maxPriorityFeePerGas > maxGasPrice
              ? maxGasPrice
              : maxPriorityFeePerGas;
        }

        // For non-urgent updates, use 90% of estimated fees
        return {
          maxFeePerGas: (maxFeePerGas * 90n) / 100n,
          maxPriorityFeePerGas: (maxPriorityFeePerGas * 90n) / 100n,
        };
      }
    } catch (eip1559Error) {
      // EIP-1559 not supported, fall through to legacy
    }

    // Fallback to legacy gas price
    const gasPrice = await client.getGasPrice();

    if (gasPrice > maxGasPrice) {
      logger.warn(
        `│   Gas price ${formatGwei(gasPrice)} > max ${formatGwei(maxGasPrice)}, capping`,
      );
      return { gasPrice: maxGasPrice };
    }

    // For non-urgent updates, use 90% of current gas price
    return { gasPrice: (gasPrice * 90n) / 100n };
  } catch (error) {
    logger.error("Failed to get gas fees", { error });
    // Fallback to a safe default (10 gwei legacy)
    return { gasPrice: parseGwei("10") };
  }
}

/**
 * Get optimal gas price for non-urgent transactions (legacy helper)
 * Returns maxFeePerGas for EIP-1559 chains, gasPrice for legacy chains
 * @deprecated Use getOptimalGasFees() for full EIP-1559 support
 */
export async function getOptimalGasPrice(
  client: PublicClient,
): Promise<bigint> {
  const fees = await getOptimalGasFees(client);
  // Return the effective max fee (EIP-1559 maxFeePerGas or legacy gasPrice)
  return fees.maxFeePerGas ?? fees.gasPrice ?? parseGwei("10");
}

/**
 * Wait for lower gas prices if current price is too high
 * Returns true if we should proceed, false if we should wait
 * Supports both EIP-1559 and legacy gas pricing
 */
export async function shouldProceedWithGas(
  client: PublicClient,
): Promise<boolean> {
  const maxGasPrice = parseGwei(config.maxGasPriceGwei.toString());

  try {
    // Try EIP-1559 first
    try {
      const feeData = await client.estimateFeesPerGas();

      if (feeData.maxFeePerGas) {
        if (feeData.maxFeePerGas <= maxGasPrice) {
          return true;
        }
        logger.warn(
          `│   Max fee ${formatGwei(feeData.maxFeePerGas)} > threshold ${formatGwei(maxGasPrice)}, skipping`,
        );
        return false;
      }
    } catch (eip1559Error) {
      // EIP-1559 not supported, fall through to legacy
    }

    // Fallback to legacy gas price
    const gasPrice = await client.getGasPrice();

    if (gasPrice <= maxGasPrice) {
      return true;
    }

    logger.warn(
      `│   Gas ${formatGwei(gasPrice)} > threshold ${formatGwei(maxGasPrice)}, skipping`,
    );
    return false;
  } catch (error) {
    logger.error("Failed to check gas price", { error });
    // On error, proceed cautiously
    return true;
  }
}

/**
 * Estimate gas for a transaction with safety margin
 */
export function addGasSafetyMargin(
  estimatedGas: bigint,
  margin: number = 20,
): bigint {
  // Add margin percentage (default 20%)
  return (estimatedGas * BigInt(100 + margin)) / 100n;
}
