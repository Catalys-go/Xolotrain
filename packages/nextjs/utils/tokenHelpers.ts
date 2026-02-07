import { Tokens } from "./contractAddresses";
import type { Chain } from "viem";

export const getTokenAddress = (token: "USDC" | "USDT", targetNetwork: Chain): `0x${string}` => {
  const networkName = targetNetwork.name?.toLowerCase();

  if (networkName === "mainnet" || networkName === "ethereum" || networkName === "foundry") {
    return Tokens.mainnet[token].address as `0x${string}`;
  } else if (networkName === "sepolia") {
    return Tokens.sepolia[token].address as `0x${string}`;
  } else if (networkName === "base") {
    return Tokens.base[token].address as `0x${string}`;
  }

  // Default to mainnet for local/fork
  return Tokens.mainnet[token].address as `0x${string}`;
};
