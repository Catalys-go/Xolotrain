/**
 * Li.FI Composer Hook
 * Handles bridge + contract call (LP recreation) in one transaction
 */
import { useCallback, useState } from "react";
import { getContractAddress, getTokenAddress } from "../../utils/lifi/config";
import { calculateTickRange, encodeMintLpFromTokens } from "../../utils/lifi/contracts";
import type { BridgeState, LPRecreationParams } from "../../utils/lifi/types";
import { convertQuoteToRoute, executeRoute, getContractCallsQuote } from "@lifi/sdk";
import type { ContractCallsQuoteRequest, Route } from "@lifi/sdk";
import { useAccount, useWalletClient } from "wagmi";

export function useLiFiComposer() {
  const { data: walletClient } = useWalletClient();
  const { address } = useAccount();
  const [state, setState] = useState<BridgeState>({ status: "idle" });

  /**
   * Bridge tokens + Recreate LP in ONE transaction using Li.FI Composer
   */
  const bridgeAndRecreateLP = useCallback(
    async (params: LPRecreationParams) => {
      if (!walletClient || !address) {
        throw new Error("Wallet not connected");
      }

      try {
        setState({ status: "preparing", message: "Preparing cross-chain LP recreation..." });

        // Step 1: Calculate tick range
        const { tickLower, tickUpper } = calculateTickRange();

        // Step 2: Get destination contract address
        const autoLpHelperAddress = getContractAddress("AutoLpHelper", params.toChainId);

        // Step 3: Encode contract call data
        const callData = encodeMintLpFromTokens(
          BigInt(params.usdcAmount),
          BigInt(params.usdtAmount),
          tickLower,
          tickUpper,
          params.userAddress,
        );

        console.log("📝 Contract call data prepared:", {
          autoLpHelperAddress,
          callData,
          tickLower,
          tickUpper,
        });

        // Step 4: Get USDC address on both chains
        const usdcAddressFrom = getTokenAddress("USDC", params.fromChainId);
        const usdcAddressTo = getTokenAddress("USDC", params.toChainId);

        // Step 5: Prepare Li.FI Composer request
        const quoteRequest: ContractCallsQuoteRequest = {
          fromAddress: address,
          fromChain: params.fromChainId,
          fromToken: usdcAddressFrom,
          fromAmount: params.usdcAmount,

          toChain: params.toChainId,
          toToken: usdcAddressTo,
          toAmount: params.usdcAmount, // We want to receive same amount

          // COMPOSER MAGIC! 🎩✨
          contractCalls: [
            {
              fromAmount: params.usdcAmount,
              fromTokenAddress: usdcAddressTo, // Token on destination
              toContractAddress: autoLpHelperAddress,
              toContractCallData: callData,
              toContractGasLimit: "500000", // Estimated gas for mintLpFromTokens
            },
          ],
        };

        console.log("🔍 Getting Li.FI Composer quote...");
        const quote = await getContractCallsQuote(quoteRequest);
        console.log("✅ Quote received:", quote);

        // Step 6: Convert quote to route
        const route: Route = convertQuoteToRoute(quote);

        // Step 7: Execute!
        setState({ status: "bridging", message: "Executing cross-chain LP recreation..." });

        const result = await executeRoute(route, {
          updateRouteHook: updatedRoute => {
            console.log("📊 Route update:", updatedRoute);

            const txHash = updatedRoute.steps?.[0]?.execution?.process?.[0]?.txHash;
            if (txHash) {
              setState({
                status: "bridging",
                message: "Transaction submitted! Waiting for confirmation...",
                txHash,
              });
            }
          },
        });

        console.log("✅ Cross-chain LP recreation complete!", result);

        setState({
          status: "success",
          message: "Pet traveled successfully! LP recreated on destination chain.",
        });

        return result;
      } catch (error: any) {
        console.error("❌ Error in bridgeAndRecreateLP:", error);
        setState({
          status: "error",
          message: error.message || "Failed to recreate LP",
          error,
        });
        throw error;
      }
    },
    [walletClient, address],
  );

  /**
   * Reset state
   */
  const reset = useCallback(() => {
    setState({ status: "idle" });
  }, []);

  return {
    state,
    bridgeAndRecreateLP,
    reset,
    isReady: !!walletClient && !!address,
  };
}
