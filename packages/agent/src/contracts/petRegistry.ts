/**
 * PetRegistry Contract Interface
 * Manages pet NFT metadata and health state
 */

import { Address, PublicClient, WalletClient } from "viem";
import deployedContracts from "../../../nextjs/contracts/deployedContracts";

export interface Pet {
  owner: Address;
  health: bigint;
  birthBlock: bigint;
  lastUpdate: bigint;
  chainId: bigint;
  poolId: `0x${string}`;
  positionId: bigint;
}

// Import ABI from auto-generated deployedContracts (single source of truth)
// Falls back to localhost (31337) deployment - adjust chainId as needed
export const petRegistryAbi = deployedContracts[31337].PetRegistry.abi;

/* Fallback minimal ABI for PetRegistry agent operations (updated Feb 2026)
 * Use this if auto-generated ABI is unavailable
export const petRegistryAbi = [
  // Read functions
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "getActivePetId",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "petId", type: "uint256" }],
    name: "getPet",
    outputs: [
      {
        components: [
          { name: "owner", type: "address" },
          { name: "health", type: "uint256" },
          { name: "birthBlock", type: "uint256" },
          { name: "lastUpdate", type: "uint256" },
          { name: "chainId", type: "uint256" },
          { name: "poolId", type: "bytes32" },
          { name: "positionId", type: "uint256" },
        ],
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "getPetsByOwner",
    outputs: [{ name: "", type: "uint256[]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "petId", type: "uint256" }],
    name: "exists",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },

  // Write functions
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "chainId", type: "uint256" },
      { name: "poolId", type: "bytes32" },
      { name: "positionId", type: "uint256" },
    ],
    name: "hatchFromHook",
    outputs: [{ name: "petId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "petId", type: "uint256" },
      { name: "health", type: "uint256" },
      { name: "chainId", type: "uint256" },
    ],
    name: "updateHealth",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "petId", type: "uint256" },
      { name: "health", type: "uint256" },
    ],
    name: "updateHealthManual",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },

  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "petId", type: "uint256" },
      { indexed: false, name: "health", type: "uint256" },
      { indexed: false, name: "chainId", type: "uint256" },
    ],
    name: "HealthUpdated",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "petId", type: "uint256" },
      { indexed: true, name: "owner", type: "address" },
      { indexed: false, name: "chainId", type: "uint256" },
      { indexed: false, name: "poolId", type: "bytes32" },
      { indexed: false, name: "positionId", type: "uint256" },
    ],
    name: "PetHatchedFromLp",
    type: "event",
  },
] as const;
*/

/**
 * Read pet data from PetRegistry
 */
export async function getPet(
  client: PublicClient,
  registryAddress: Address,
  petId: bigint,
): Promise<Pet> {
  const pet = await client.readContract({
    address: registryAddress,
    abi: petRegistryAbi,
    functionName: "getPet",
    args: [petId],
  });

  return {
    owner: pet.owner,
    health: pet.health,
    birthBlock: pet.birthBlock,
    lastUpdate: pet.lastUpdate,
    chainId: pet.chainId,
    poolId: pet.poolId,
    positionId: pet.positionId,
  };
}

/**
 * Get all active pets (optimized with parallel batching)
 * In production, should use event logs or indexing for best performance
 */
export async function getAllActivePets(
  client: PublicClient,
  registryAddress: Address,
): Promise<bigint[]> {
  // Get total supply
  const totalSupply = await client.readContract({
    address: registryAddress,
    abi: petRegistryAbi,
    functionName: "totalSupply",
  });

  if (totalSupply === 0n) {
    return [];
  }

  // Batch exists checks in parallel with concurrency limit
  const BATCH_SIZE = 10; // Prevent rate limiting
  const activePets: bigint[] = [];

  for (let start = 1n; start <= totalSupply; start += BigInt(BATCH_SIZE)) {
    const end = start + BigInt(BATCH_SIZE) - 1n;
    const batchEnd = end > totalSupply ? totalSupply : end;

    // Create batch of promises for this chunk
    const batchPromises: Promise<{ id: bigint; exists: boolean }>[] = [];
    for (let i = start; i <= batchEnd; i++) {
      batchPromises.push(
        client
          .readContract({
            address: registryAddress,
            abi: petRegistryAbi,
            functionName: "exists",
            args: [i],
          })
          .then((exists) => ({ id: i, exists })),
      );
    }

    // Wait for batch to complete
    const results = await Promise.all(batchPromises);

    // Collect active pets from this batch
    for (const result of results) {
      if (result.exists) {
        activePets.push(result.id);
      }
    }
  }

  return activePets;
}

/**
 * Update pet health (agent only)
 */
export interface UpdateHealthOptions {
  maxFeePerGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  gasPrice?: bigint;
}

export async function updateHealth(
  client: WalletClient,
  registryAddress: Address,
  petId: bigint,
  health: number,
  chainId: number,
  gasOptions?: UpdateHealthOptions,
): Promise<`0x${string}`> {
  if (!client.account) {
    throw new Error("Wallet client must have an account");
  }

  // Build write params with appropriate gas parameters
  const baseParams = {
    address: registryAddress,
    abi: petRegistryAbi,
    functionName: "updateHealth" as const,
    args: [petId, BigInt(health), BigInt(chainId)] as const,
    account: client.account,
    chain: client.chain,
  };

  // Add EIP-1559 params if available, otherwise legacy gasPrice
  const hash = gasOptions?.maxFeePerGas
    ? await client.writeContract({
        ...baseParams,
        maxFeePerGas: gasOptions.maxFeePerGas,
        maxPriorityFeePerGas: gasOptions.maxPriorityFeePerGas,
      })
    : gasOptions?.gasPrice
      ? await client.writeContract({
          ...baseParams,
          gasPrice: gasOptions.gasPrice,
        })
      : await client.writeContract(baseParams);

  return hash;
}
