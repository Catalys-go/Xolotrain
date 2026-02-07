/**
 * Uniswap v4 Position Manager Interface
 * For reading LP position details (tick range, liquidity)
 */

import { Address, PublicClient } from "viem";
import externalContracts from "../../../nextjs/contracts/externalContracts";

export interface Position {
  liquidity: bigint;
  tickLower: number;
  tickUpper: number;
  feeGrowthInside0LastX128: bigint;
  feeGrowthInside1LastX128: bigint;
}

// Import ABI from externalContracts (Uniswap v4 PositionManager is external)
// Note: Adjust chainId as needed for your deployment
export const positionManagerAbi =
  (externalContracts as any)[1]?.IPositionManager?.abi ||
  ([
    // Fallback minimal ABI for Uniswap v4 PositionManager (updated Feb 2026)
    // PositionManager is an ERC721 NFT with position metadata
    /* Minimal ABI for position reads:
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
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  */
  ] as const);

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
  const result = (await client.readContract({
    address: positionManagerAddress,
    abi: positionManagerAbi,
    functionName: "getPositionInfo",
    args: [tokenId],
  })) as [`0x${string}`, bigint, bigint, bigint];

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
  return (await client.readContract({
    address: positionManagerAddress,
    abi: positionManagerAbi,
    functionName: "ownerOf",
    args: [tokenId],
  })) as Address;
}
