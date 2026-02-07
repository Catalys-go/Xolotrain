/**
 * TypeScript Types for Li.FI Integration
 */

// Bridge parameters
export interface BridgeParams {
  fromChainId: number;
  toChainId: number;
  fromAddress: string;
  toAddress: string;
  fromTokenAddress: string;
  toTokenAddress: string;
  amount: string;
}

// Bridge status
export type BridgeStatus = "idle" | "preparing" | "bridging" | "success" | "error";

export interface BridgeState {
  status: BridgeStatus;
  txHash?: string;
  message?: string;
  error?: Error;
}

// LP Recreation parameters (for Composer)
export interface LPRecreationParams {
  petId: number;
  fromChainId: number;
  toChainId: number;
  usdcAmount: string;
  usdtAmount: string;
  tickLower: number;
  tickUpper: number;
  userAddress: string;
}

// Li.FI Route Status
export type RouteStatus = "NOT_FOUND" | "INVALID" | "PENDING" | "DONE" | "FAILED";

// Li.FI Status Response (simplified)
export interface LiFiStatusResponse {
  status: RouteStatus;
  sending?: {
    txHash: string;
    amount: string;
    token: {
      symbol: string;
      address: string;
    };
  };
  receiving?: {
    txHash: string;
    amount: string;
    token: {
      symbol: string;
      address: string;
    };
  };
}
