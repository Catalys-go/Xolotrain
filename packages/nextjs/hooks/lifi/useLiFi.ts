/**
 * Main Li.FI SDK Hook - PROPER WAGMI INTEGRATION
 */
import { useCallback, useEffect, useState } from "react";
import { LIFI_CONFIG } from "../../utils/lifi/config";
import type { BridgeParams, BridgeState } from "../../utils/lifi/types";
import { EVM, convertQuoteToRoute, createConfig, executeRoute, getQuote } from "@lifi/sdk";
import type { Route } from "@lifi/sdk";
import { getWalletClient, switchChain } from "@wagmi/core";
import { useAccount } from "wagmi";
import { wagmiConfig } from "~~/services/web3/wagmiConfig";

let isConfigured = false;

export function useLiFi() {
  const { isConnected } = useAccount();
  const [bridgeState, setBridgeState] = useState<BridgeState>({
    status: "idle",
  });

  // Initialize Li.FI with EVM provider using wagmi
  useEffect(() => {
    if (!isConfigured) {
      createConfig({
        integrator: LIFI_CONFIG.integrator,
        providers: [
          EVM({
            getWalletClient: async () => {
              const client = await getWalletClient(wagmiConfig as any);
              return client;
            },
            switchChain: async chainId => {
              await switchChain(wagmiConfig as any, { chainId });
              const client = await getWalletClient(wagmiConfig as any, { chainId });
              return client;
            },
          }),
        ],
      });
      isConfigured = true;
      console.log("✅ Li.FI SDK initialized with wagmi EVM provider");
    }
  }, []);

  /**
   * Get quote for swapping tokens on same chain
   */
  const getSwapQuote = useCallback(
    async (params: {
      chainId: number;
      fromToken: string;
      toToken: string;
      fromAmount: string;
      fromAddress: string;
    }) => {
      try {
        console.log("🔍 Getting swap quote...", params);

        const quote = await getQuote({
          fromChain: params.chainId,
          toChain: params.chainId,
          fromToken: params.fromToken,
          toToken: params.toToken,
          fromAmount: params.fromAmount,
          fromAddress: params.fromAddress,
        });

        console.log("✅ Swap quote received:", quote);

        // Convert to route
        const route = convertQuoteToRoute(quote);
        return route;
      } catch (error) {
        console.error("❌ Error getting swap quote:", error);
        throw error;
      }
    },
    [],
  );

  /**
   * Execute swap transaction
   */
  const executeSwap = useCallback(
    async (route: Route) => {
      if (!isConnected) {
        throw new Error("Wallet not connected");
      }

      try {
        setBridgeState({ status: "preparing", message: "Preparing swap..." });

        console.log("💱 Executing swap with Li.FI...");

        const executedRoute = await executeRoute(route, {
          updateRouteHook: updatedRoute => {
            console.log("📊 Swap update:", updatedRoute);

            const txHash = updatedRoute.steps?.[0]?.execution?.process?.[0]?.txHash;
            if (txHash) {
              setBridgeState({
                status: "bridging",
                message: "Swapping...",
                txHash,
              });
            }
          },
        });

        console.log("✅ Swap complete:", executedRoute);

        setBridgeState({
          status: "success",
          message: "Swap successful!",
        });

        return executedRoute;
      } catch (error: any) {
        console.error("❌ Swap error:", error);
        setBridgeState({
          status: "error",
          message: error.message || "Swap failed",
          error,
        });
        throw error;
      }
    },
    [isConnected],
  );
  /**
   * Get quote for bridging tokens
   */
  const getBridgeQuote = useCallback(async (params: BridgeParams) => {
    try {
      console.log("🔍 Getting bridge quote...", params);

      const quote = await getQuote({
        fromChain: params.fromChainId,
        toChain: params.toChainId,
        fromToken: params.fromTokenAddress, // ← Use fromTokenAddress
        toToken: params.toTokenAddress, // ← Use toTokenAddress
        fromAmount: params.amount,
        fromAddress: params.fromAddress,
        toAddress: params.toAddress,
      });

      console.log("✅ Bridge quote received:", quote);

      const route = convertQuoteToRoute(quote);
      return route;
    } catch (error) {
      console.error("❌ Error getting bridge quote:", error);
      throw error;
    }
  }, []);

  /**
   * Execute bridge transaction
   */
  const executeBridge = useCallback(
    async (route: Route) => {
      if (!isConnected) {
        throw new Error("Wallet not connected");
      }

      try {
        setBridgeState({ status: "preparing", message: "Preparing bridge..." });

        console.log("🌉 Executing bridge...");

        const executedRoute = await executeRoute(route, {
          updateRouteHook: updatedRoute => {
            console.log("📊 Bridge update:", updatedRoute);

            const txHash = updatedRoute.steps?.[0]?.execution?.process?.[0]?.txHash;
            if (txHash) {
              setBridgeState({
                status: "bridging",
                message: "Bridge transaction submitted!",
                txHash,
              });
            }
          },
        });

        console.log("✅ Bridge complete:", executedRoute);

        setBridgeState({
          status: "success",
          message: "Bridge successful!",
        });

        return executedRoute;
      } catch (error: any) {
        console.error("❌ Bridge error:", error);
        setBridgeState({
          status: "error",
          message: error.message || "Bridge failed",
          error,
        });
        throw error;
      }
    },
    [isConnected],
  );

  const resetBridge = useCallback(() => {
    setBridgeState({ status: "idle" });
  }, []);

  return {
    bridgeState,
    getSwapQuote,
    executeSwap,
    getBridgeQuote,
    executeBridge,
    resetBridge,
    isReady: isConnected && isConfigured,
  };
}
