/**
 * Uniswap v4 PoolManager Interface
 * For reading pool state (current tick, liquidity, etc.)
 */

import { Address, PublicClient } from "viem";
import externalContracts from "../../../nextjs/contracts/externalContracts";

export interface PoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

export interface Slot0 {
  sqrtPriceX96: bigint;
  tick: number;
  protocolFee: number;
  lpFee: number;
}

// Import ABI from externalContracts (Uniswap v4 is external)
// Note: Adjust chainId as needed for your deployment
export const poolManagerAbi =
  (externalContracts as any)[1]?.IPoolManager?.abi ||
  ([
    // Fallback minimal ABI for Uniswap v4 PoolManager (updated Feb 2026)
    // Note: Uniswap v4 uses low-level extsload for pool state access
    // In production, use StateLibrary.sol helpers or proper IPoolManager ABI
    /* Minimal ABI for direct storage access via extsload:
  {
    inputs: [{ name: "slot", type: "bytes32" }],
    name: "extsload",
    outputs: [{ name: "value", type: "bytes32" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "startSlot", type: "bytes32" },
      { name: "nSlots", type: "uint256" },
    ],
    name: "extsload",
    outputs: [{ name: "values", type: "bytes32[]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "slots", type: "bytes32[]" }],
    name: "extsload",
    outputs: [{ name: "values", type: "bytes32[]" }],
    stateMutability: "view",
    type: "function",
  },
  */
  ] as const);

/**
 * Get current pool state (tick, price, fees)
 */
export async function getSlot0(
  client: PublicClient,
  poolManagerAddress: Address,
  poolId: `0x${string}`,
): Promise<Slot0> {
  const result = (await client.readContract({
    address: poolManagerAddress,
    abi: poolManagerAbi,
    functionName: "getSlot0",
    args: [poolId],
  })) as [bigint, bigint, bigint, bigint];

  return {
    sqrtPriceX96: result[0],
    tick: Number(result[1]),
    protocolFee: Number(result[2]),
    lpFee: Number(result[3]),
  };
}

/**
 * Get pool liquidity
 */
export async function getPoolLiquidity(
  client: PublicClient,
  poolManagerAddress: Address,
  poolId: `0x${string}`,
): Promise<bigint> {
  return (await client.readContract({
    address: poolManagerAddress,
    abi: poolManagerAbi,
    functionName: "getLiquidity",
    args: [poolId],
  })) as bigint;
}
