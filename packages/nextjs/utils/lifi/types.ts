/**
 * TypeScript Types for Li.FI Integration
 */

export interface BridgeParams {
  fromChainId: number;
  toChainId: number;
  fromAddress: string;
  toAddress: string;
  fromTokenAddress: string;
  toTokenAddress: string;
  amount: string;
}

export type BridgeStatus = "idle" | "preparing" | "bridging" | "success" | "error";

export interface BridgeState {
  status: BridgeStatus;
  txHash?: string;
  message?: string;
  error?: Error;
}

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

export type RouteStatus = "NOT_FOUND" | "INVALID" | "PENDING" | "DONE" | "FAILED";

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
