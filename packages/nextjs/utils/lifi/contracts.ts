/**
 * Contract ABIs for Li.FI Composer
 */

// AutoLpHelper ABI - USDC-only version
export const autoLpHelperAbi = [
  {
    inputs: [
      { name: "petId", type: "uint256" },
      { name: "usdcAmount", type: "uint256" },
      { name: "tickLower", type: "int24" },
      { name: "tickUpper", type: "int24" },
      { name: "recipient", type: "address" },
    ],
    name: "mintLpFromUsdcOnly",
    outputs: [{ name: "positionId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "petId", type: "uint256" },
      { name: "usdcAmount", type: "uint128" },
      { name: "usdtAmount", type: "uint128" },
      { name: "tickLower", type: "int24" },
      { name: "tickUpper", type: "int24" },
      { name: "recipient", type: "address" },
    ],
    name: "mintLpFromTokens",
    outputs: [{ name: "positionId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

/**
 * Calculate tick range
 */
export function calculateTickRange(): { tickLower: number; tickUpper: number } {
  const TICK_SPACING = 60;
  const TICK_LOWER_OFFSET = -6;
  const TICK_UPPER_OFFSET = 6;

  const tickLower = TICK_LOWER_OFFSET * TICK_SPACING;
  const tickUpper = TICK_UPPER_OFFSET * TICK_SPACING;

  return { tickLower, tickUpper };
}
