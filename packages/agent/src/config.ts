/**
 * Agent Configuration
 * Loads and validates environment variables
 */

import dotenv from "dotenv";
import { Address } from "viem";

// Load environment variables
dotenv.config();

interface Config {
  // Network
  rpcUrl: string;
  chainId: number;

  // Agent
  agentPrivateKey: `0x${string}`;

  // Contracts
  petRegistry: Address;
  eggHatchHook: Address;
  autoLpHelper: Address;
  poolManager: Address;
  positionManager: Address;

  // Agent behavior
  healthCheckInterval: number;
  minHealthChange: number;

  // Gas settings
  maxGasPriceGwei: bigint;
  gasLimitHealthUpdate: number;

  // Logging
  logLevel: string;
}

function getEnvVar(name: string, required: boolean = true): string {
  const value = process.env[name];
  if (required && !value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value || "";
}

function parseAddress(value: string, name: string): Address {
  if (!value.startsWith("0x") || value.length !== 42) {
    throw new Error(`Invalid address for ${name}: ${value}`);
  }
  return value as Address;
}

function parsePrivateKey(value: string): `0x${string}` {
  if (!value.startsWith("0x")) {
    return `0x${value}` as `0x${string}`;
  }
  return value as `0x${string}`;
}

export const config: Config = {
  // Network
  rpcUrl: getEnvVar("MAINNET_FORK_RPC_URL"),
  chainId: parseInt(getEnvVar("CHAIN_ID", false) || "31337"),

  // Agent
  agentPrivateKey: parsePrivateKey(getEnvVar("AGENT_PRIVATE_KEY")),

  // Contracts
  petRegistry: parseAddress(getEnvVar("PET_REGISTRY"), "PET_REGISTRY"),
  eggHatchHook: parseAddress(getEnvVar("EGG_HATCH_HOOK"), "EGG_HATCH_HOOK"),
  autoLpHelper: parseAddress(getEnvVar("AUTO_LP_HELPER"), "AUTO_LP_HELPER"),
  poolManager: parseAddress(getEnvVar("POOL_MANAGER"), "POOL_MANAGER"),
  positionManager: parseAddress(
    getEnvVar("POSITION_MANAGER"),
    "POSITION_MANAGER",
  ),

  // Agent behavior
  healthCheckInterval: parseInt(
    getEnvVar("HEALTH_CHECK_INTERVAL", false) || "60000",
  ),
  minHealthChange: parseInt(getEnvVar("MIN_HEALTH_CHANGE", false) || "5"),

  // Gas settings
  maxGasPriceGwei: BigInt(getEnvVar("MAX_GAS_PRICE_GWEI", false) || "50"),
  gasLimitHealthUpdate: parseInt(
    getEnvVar("GAS_LIMIT_HEALTH_UPDATE", false) || "100000",
  ),

  // Logging
  logLevel: getEnvVar("LOG_LEVEL", false) || "info",
};

// Validate configuration
export function validateConfig(): void {
  // Check RPC URL is accessible
  if (
    !config.rpcUrl.startsWith("http://") &&
    !config.rpcUrl.startsWith("https://")
  ) {
    throw new Error(`Invalid RPC URL: ${config.rpcUrl}`);
  }

  // Validate intervals
  if (config.healthCheckInterval < 10000) {
    console.warn(
      "⚠️  Warning: Health check interval < 10s may cause high RPC usage",
    );
  }

  if (config.minHealthChange < 1 || config.minHealthChange > 100) {
    throw new Error(
      `Invalid minHealthChange: ${config.minHealthChange}. Must be between 1 and 100.`,
    );
  }
}
