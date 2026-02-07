/**
 * Li.FI Configuration
 * Chain IDs, Token Addresses, and Contract Addresses
 */

// Chain IDs
export const CHAINS = {
  ETHEREUM: 1,
  BASE: 8453,
  // For testing on localhost, we'll use mainnet fork
  LOCALHOST: 31337,
} as const;

// Token Addresses
export const TOKENS = {
  USDC: {
    [CHAINS.ETHEREUM]: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    [CHAINS.BASE]: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  },
} as const;

// Your Deployed Contract Addresses
// TODO: Update these when you deploy to mainnet!
export const CONTRACTS = {
  AutoLpHelper: {
    [CHAINS.ETHEREUM]: "0x0000000000000000000000000000000000000000", // UPDATE THIS!
    [CHAINS.BASE]: "0x0000000000000000000000000000000000000000", // UPDATE THIS!
    [CHAINS.LOCALHOST]: "0x432bdb1b79f5edd44db1cc8e5dc41fcfa55a163c", // Your local deployment
  },
  PetRegistry: {
    [CHAINS.ETHEREUM]: "0x0000000000000000000000000000000000000000", // UPDATE THIS!
    [CHAINS.BASE]: "0x0000000000000000000000000000000000000000", // UPDATE THIS!
    [CHAINS.LOCALHOST]: "0xb288315b51e6fac212513e1a7c70232fa584bbb9", // Your local deployment
  },
} as const;

// Li.FI Configuration
export const LIFI_CONFIG = {
  integrator: "xolotrain", // Your project name
  // Add API key later if needed for higher rate limits
  // apiKey: "your-api-key",
} as const;

// Helper to get token address for a chain
export function getTokenAddress(token: keyof typeof TOKENS, chainId: number): string {
  const tokenAddresses = TOKENS[token];
  const address = tokenAddresses[chainId as keyof typeof tokenAddresses];
  if (!address) {
    throw new Error(`${token} not supported on chain ${chainId}`);
  }
  return address;
}

// Helper to get contract address for a chain
export function getContractAddress(contract: keyof typeof CONTRACTS, chainId: number): string {
  const contractAddresses = CONTRACTS[contract];
  const address = contractAddresses[chainId as keyof typeof contractAddresses];
  if (!address || address === "0x0000000000000000000000000000000000000000") {
    throw new Error(`${contract} not deployed on chain ${chainId}`);
  }
  return address;
}
