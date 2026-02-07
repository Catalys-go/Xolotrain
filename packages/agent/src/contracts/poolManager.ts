/**
 * Uniswap v4 PoolManager Interface
 * For reading pool state (current tick, liquidity, etc.)
 */

import { Address, PublicClient } from "viem";

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

// Minimal ABI for reading pool state
export const poolManagerAbi = [
  {
    inputs: [{ name: "id", type: "bytes32" }],
    name: "getSlot0",
    outputs: [
      { name: "sqrtPriceX96", type: "uint160" },
      { name: "tick", type: "int24" },
      { name: "protocolFee", type: "uint24" },
      { name: "lpFee", type: "uint24" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "id", type: "bytes32" }],
    name: "getLiquidity",
    outputs: [{ name: "", type: "uint128" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

/**
 * Get current pool state (tick, price, fees)
 */
export async function getSlot0(
  client: PublicClient,
  poolManagerAddress: Address,
  poolId: `0x${string}`,
): Promise<Slot0> {
  const result = await client.readContract({
    address: poolManagerAddress,
    abi: poolManagerAbi,
    functionName: "getSlot0",
    args: [poolId],
  });

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
  return await client.readContract({
    address: poolManagerAddress,
    abi: poolManagerAbi,
    functionName: "getLiquidity",
    args: [poolId],
  });
}
