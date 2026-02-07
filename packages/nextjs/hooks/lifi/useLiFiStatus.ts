/**
 * Li.FI Status Tracking Hook
 * Check status of ongoing bridge transactions
 */
import { useCallback, useState } from "react";
import type { LiFiStatusResponse } from "../../utils/lifi/types";
import { getStatus } from "@lifi/sdk";

export function useLiFiStatus() {
  const [loading, setLoading] = useState(false);

  /**
   * Check status of a bridge transaction
   */
  const checkStatus = useCallback(
    async (txHash: string, fromChainId: number, toChainId: number, bridge?: string): Promise<LiFiStatusResponse> => {
      setLoading(true);
      try {
        console.log("🔍 Checking bridge status:", {
          txHash,
          fromChainId,
          toChainId,
          bridge,
        });

        const status = await getStatus({
          txHash,
          fromChain: fromChainId,
          toChain: toChainId,
          bridge: bridge || "stargate", // Default bridge
        });

        console.log("📊 Status:", status);
        return status as LiFiStatusResponse;
      } catch (error) {
        console.error("❌ Error checking status:", error);
        throw error;
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  return {
    checkStatus,
    loading,
  };
}
