/**
 * Uniswap v4 Position Manager Interface
 * For reading LP position details (tick range, liquidity)
 */

import { Address, PublicClient } from "viem";

export interface Position {
  liquidity: bigint;
  tickLower: number;
  tickUpper: number;
  feeGrowthInside0LastX128: bigint;
  feeGrowthInside1LastX128: bigint;
}

// Position Manager ABI (NFT-based positions in v4)
export const positionManagerAbi = [
  {
    inputs: [{ name: "tokenId", type: "uint256" }],
    name: "getPositionInfo",
    outputs: [
      { name: "poolId", type: "bytes32" },
      { name: "tickLower", type: "int24" },
      { name: "tickUpper", type: "int24" },
      { name: "liquidity", type: "uint128" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "tokenId", type: "uint256" }],
    name: "ownerOf",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

/**
 * Get position information from NFT tokenId
 */
export async function getPositionInfo(
  client: PublicClient,
  positionManagerAddress: Address,
  tokenId: bigint,
): Promise<{
  poolId: `0x${string}`;
  tickLower: number;
  tickUpper: number;
  liquidity: bigint;
}> {
  const result = await client.readContract({
    address: positionManagerAddress,
    abi: positionManagerAbi,
    functionName: "getPositionInfo",
    args: [tokenId],
  });

  return {
    poolId: result[0],
    tickLower: Number(result[1]),
    tickUpper: Number(result[2]),
    liquidity: result[3],
  };
}

/**
 * Get position owner
 */
export async function getPositionOwner(
  client: PublicClient,
  positionManagerAddress: Address,
  tokenId: bigint,
): Promise<Address> {
  return await client.readContract({
    address: positionManagerAddress,
    abi: positionManagerAbi,
    functionName: "ownerOf",
    args: [tokenId],
  });
}
