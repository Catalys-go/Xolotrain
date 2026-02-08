/**
 * Li.FI Configuration - MAINNET ONLY
 * ✅ ALL ADDRESSES VERIFIED AGAINST OFFICIAL SOURCES
 * Chain IDs, Token Addresses, and Contract Addresses
 */

// Chain IDs
export const CHAINS = {
  ETHEREUM: 1,
  BASE: 8453,
} as const;

// ✅ VERIFIED TOKEN ADDRESSES (Mainnet)
export const TOKENS = {
  // USDC - Verified from Etherscan & BaseScan
  USDC: {
    [CHAINS.ETHEREUM]: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // ✅ VERIFIED: Circle official USDC on Ethereum
    [CHAINS.BASE]: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // ✅ VERIFIED: Native USDC on Base (NOT bridged)
  },
  // USDT - Verified from Etherscan & BaseScan
  USDT: {
    [CHAINS.ETHEREUM]: "0xdAC17F958D2ee523a2206206994597C13D831ec7", // ✅ VERIFIED: Tether official USDT on Ethereum
    [CHAINS.BASE]: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2", // ✅ VERIFIED: Bridged USDT on Base
  },
} as const;

// Your Deployed Contract Addresses
// ⚠️ TODO: Update these after deployment!
export const CONTRACTS = {
  AutoLpHelper: {
    [CHAINS.ETHEREUM]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
    [CHAINS.BASE]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
  },
  PetRegistry: {
    [CHAINS.ETHEREUM]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
    [CHAINS.BASE]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
  },
  EggHatchHook: {
    [CHAINS.ETHEREUM]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
    [CHAINS.BASE]: "0x0000000000000000000000000000000000000000", // ⚠️ DEPLOY & UPDATE
  },
} as const;

// Li.FI Configuration
export const LIFI_CONFIG = {
  integrator: "xolotrain",
  // Add API key if needed for higher rate limits:
  // apiKey: "your-api-key-here",
} as const;

// Tick Configuration (for LP positions)
export const TICK_CONFIG = {
  TICK_SPACING: 60,
  TICK_LOWER_OFFSET: -360, // -6 * TICK_SPACING
  TICK_UPPER_OFFSET: 360, // 6 * TICK_SPACING
} as const;

// Helper: Get token address for a chain
export function getTokenAddress(token: keyof typeof TOKENS, chainId: number): string {
  const tokenAddresses = TOKENS[token];
  const address = tokenAddresses[chainId as keyof typeof tokenAddresses];
  if (!address) {
    throw new Error(`${token} not supported on chain ${chainId}`);
  }
  return address;
}

// Helper: Get contract address for a chain
export function getContractAddress(contract: keyof typeof CONTRACTS, chainId: number): string {
  const contractAddresses = CONTRACTS[contract];
  const address = contractAddresses[chainId as keyof typeof contractAddresses];
  if (!address || address === "0x0000000000000000000000000000000000000000") {
    throw new Error(`${contract} not deployed on chain ${chainId}. Please deploy and update config.ts`);
  }
  return address;
}

// Helper: Check if chain is supported
export function isSupportedChain(chainId: number): boolean {
  return chainId === CHAINS.ETHEREUM || chainId === CHAINS.BASE;
}

// Helper: Get chain name
export function getChainName(chainId: number): string {
  switch (chainId) {
    case CHAINS.ETHEREUM:
      return "Ethereum";
    case CHAINS.BASE:
      return "Base";
    default:
      return `Unknown Chain (${chainId})`;
  }
}

// Type exports
export type ChainId = (typeof CHAINS)[keyof typeof CHAINS];
export type TokenSymbol = keyof typeof TOKENS;
export type ContractName = keyof typeof CONTRACTS;
