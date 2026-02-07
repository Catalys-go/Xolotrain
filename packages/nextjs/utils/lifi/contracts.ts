/**
 * Contract ABI and Encoding Utilities for Li.FI Composer
 */
import { encodeFunctionData, parseAbi } from "viem";

// Minimal ABI for AutoLpHelper.mintLpFromTokens
export const AUTO_LP_HELPER_ABI = parseAbi([
  "function mintLpFromTokens(uint128 usdcAmount, uint128 usdtAmount, int24 tickLower, int24 tickUpper, address recipient) external returns (uint256)",
]);

/**
 * Encode mintLpFromTokens function call for Li.FI Composer
 * @param usdcAmount - USDC amount (with 6 decimals)
 * @param usdtAmount - USDT amount (with 6 decimals)
 * @param tickLower - Lower tick boundary
 * @param tickUpper - Upper tick boundary
 * @param recipient - Address to receive the LP position
 * @returns Encoded function data as hex string
 */
export function encodeMintLpFromTokens(
  usdcAmount: bigint,
  usdtAmount: bigint,
  tickLower: number,
  tickUpper: number,
  recipient: string,
): `0x${string}` {
  return encodeFunctionData({
    abi: AUTO_LP_HELPER_ABI,
    functionName: "mintLpFromTokens",
    args: [
      usdcAmount as any, // uint128
      usdtAmount as any, // uint128
      tickLower, // int24
      tickUpper, // int24
      recipient as `0x${string}`,
    ],
  });
}

/**
 * Calculate tick range (simplified version)
 * In production, you'd read current tick from the pool
 */
export function calculateTickRange(): { tickLower: number; tickUpper: number } {
  // Using same defaults as your AutoLpHelper contract
  const TICK_SPACING = 60;
  const TICK_LOWER_OFFSET = -6;
  const TICK_UPPER_OFFSET = 6;

  // For simplicity, using fixed ticks
  // In production, read current tick and calculate from there
  const tickLower = TICK_LOWER_OFFSET * TICK_SPACING; // -360
  const tickUpper = TICK_UPPER_OFFSET * TICK_SPACING; // 360

  return { tickLower, tickUpper };
}
