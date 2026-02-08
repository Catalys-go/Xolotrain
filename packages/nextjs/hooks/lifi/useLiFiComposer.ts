/**
 * Li.FI Composer Hook - USDC-ONLY APPROACH
 * Bridges USDC and calls mintLpFromUsdcOnly on destination
 */
import { useCallback, useState } from "react";
import { getContractAddress, getTokenAddress } from "../../utils/lifi/config";
import { autoLpHelperAbi } from "../../utils/lifi/contracts";
import type { BridgeState, LPRecreationParams } from "../../utils/lifi/types";
import { convertQuoteToRoute, executeRoute, getContractCallsQuote } from "@lifi/sdk";
import type { ContractCallsQuoteRequest, Route } from "@lifi/sdk";
import { encodeFunctionData } from "viem";
import { useAccount, useWalletClient } from "wagmi";

export function useLiFiComposer() {
  const { data: walletClient } = useWalletClient();
  const { address } = useAccount();
  const [state, setState] = useState<BridgeState>({ status: "idle" });

  /**
   * Bridge USDC + Recreate LP in ONE transaction using Li.FI Composer
   * User must have converted all tokens to USDC before calling this
   */
  const bridgeAndRecreateLP = useCallback(
    async (params: LPRecreationParams) => {
      if (!walletClient || !address) {
        throw new Error("Wallet not connected");
      }

      try {
        setState({ status: "preparing", message: "Preparing cross-chain LP recreation..." });

        // Calculate total USDC amount (user should have converted USDT to USDC already)
        const totalUsdcAmount = BigInt(params.usdcAmount) + BigInt(params.usdtAmount);

        // Get destination contract address
        const autoLpHelperAddress = getContractAddress("AutoLpHelper", params.toChainId);

        // Encode contract call for mintLpFromUsdcOnly
        const callData = encodeFunctionData({
          abi: autoLpHelperAbi,
          functionName: "mintLpFromUsdcOnly",
          args: [
            BigInt(params.petId),
            totalUsdcAmount,
            params.tickLower,
            params.tickUpper,
            params.userAddress as `0x${string}`,
          ],
        });

        console.log("📝 Contract call prepared:", {
          function: "mintLpFromUsdcOnly",
          petId: params.petId,
          totalUsdc: totalUsdcAmount.toString(),
          autoLpHelperAddress,
        });

        // Get USDC addresses
        const usdcFrom = getTokenAddress("USDC", params.fromChainId);
        const usdcTo = getTokenAddress("USDC", params.toChainId);

        // Prepare Li.FI Composer request
        const quoteRequest: ContractCallsQuoteRequest = {
          fromAddress: address,
          fromChain: params.fromChainId,
          fromToken: usdcFrom,
          fromAmount: totalUsdcAmount.toString(),
          toChain: params.toChainId,
          toToken: usdcTo,
          contractCalls: [
            {
              fromTokenAddress: usdcTo, // ← Token on destination chain
              toContractAddress: autoLpHelperAddress,
              toContractCallData: callData,
              fromAmount: totalUsdcAmount.toString(),
              toContractGasLimit: "500000",
            },
          ],
        };

        console.log("🔍 Getting Li.FI Composer quote...");
        const quote = await getContractCallsQuote(quoteRequest);
        console.log("✅ Quote received");

        // Convert to route
        const route: Route = convertQuoteToRoute(quote);

        // Execute
        setState({ status: "bridging", message: "Bridging and creating LP..." });

        const result = await executeRoute(route, {
          updateRouteHook: updatedRoute => {
            const txHash = updatedRoute.steps?.[0]?.execution?.process?.[0]?.txHash;
            if (txHash) {
              setState({
                status: "bridging",
                message: "Transaction submitted! Waiting for bridge...",
                txHash,
              });
            }
          },
        });

        console.log("✅ LP recreation complete!");

        setState({
          status: "success",
          message: "Pet traveled successfully!",
        });

        return result;
      } catch (error: any) {
        console.error("❌ Error:", error);
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
