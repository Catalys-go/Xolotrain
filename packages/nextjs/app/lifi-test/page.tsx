"use client";

import { useState } from "react";
import { useLiFi } from "../../hooks/lifi";
import { CHAINS, TOKENS } from "../../utils/lifi/config";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { formatUnits, parseEther, parseUnits } from "viem";
import { useAccount, useBalance, useChainId, useSwitchChain } from "wagmi";

export default function LiFiTestPage() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const { getSwapQuote, executeSwap, getBridgeQuote, executeBridge, bridgeState, resetBridge } = useLiFi();

  const [swapAmount, setSwapAmount] = useState("0.001"); // ETH amount for swap
  const [bridgeAmount, setBridgeAmount] = useState("1"); // USDC amount for bridge
  const [isSwapping, setIsSwapping] = useState(false);
  const [isBridging, setIsBridging] = useState(false);
  const [activeTab, setActiveTab] = useState<"swap" | "bridge">("swap");

  const isOnEthereum = chainId === CHAINS.ETHEREUM;

  // Get balances
  const { data: ethBalance } = useBalance({
    address,
    chainId: CHAINS.ETHEREUM,
    query: { enabled: !!address },
  });

  const { data: usdcBalance } = useBalance({
    address,
    token: TOKENS.USDC[CHAINS.ETHEREUM] as `0x${string}`,
    chainId: CHAINS.ETHEREUM,
    query: { enabled: !!address },
  });

  // Swap ETH → USDC
  const handleSwap = async () => {
    if (!address || !isOnEthereum) return;

    try {
      setIsSwapping(true);
      resetBridge();

      const amountWei = parseEther(swapAmount);

      console.log("💱 Starting swap...");
      console.log("ETH Amount:", swapAmount);

      // ETH address is 0x0000000000000000000000000000000000000000
      const ETH_ADDRESS = "0x0000000000000000000000000000000000000000";

      const route = await getSwapQuote({
        chainId: CHAINS.ETHEREUM,
        fromToken: ETH_ADDRESS,
        toToken: TOKENS.USDC[CHAINS.ETHEREUM],
        fromAmount: amountWei.toString(),
        fromAddress: address,
      });

      console.log("✅ Route received");

      await executeSwap(route);

      console.log("🎉 Swap complete!");
    } catch (error: any) {
      console.error("❌ Swap failed:", error);
    } finally {
      setIsSwapping(false);
    }
  };

  // Bridge USDC → Base
  const handleBridge = async () => {
    if (!address || !isOnEthereum) return;

    try {
      setIsBridging(true);
      resetBridge();

      const amountWei = parseUnits(bridgeAmount, 6);

      console.log("🌉 Starting bridge...");

      const route = await getBridgeQuote({
        fromChainId: CHAINS.ETHEREUM,
        toChainId: CHAINS.BASE,
        fromAddress: address,
        toAddress: address,
        fromTokenAddress: TOKENS.USDC[CHAINS.ETHEREUM], // ← Ethereum USDC
        toTokenAddress: TOKENS.USDC[CHAINS.BASE], // ← Base USDC
        amount: amountWei.toString(),
      });

      console.log("✅ Route received");

      await executeBridge(route);

      console.log("🎉 Bridge complete!");
    } catch (error: any) {
      console.error("❌ Bridge failed:", error);
    } finally {
      setIsBridging(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-900 via-purple-900 to-pink-900 p-8">
      <div className="max-w-2xl mx-auto">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-6xl font-bold text-white mb-4">🚀 Li.FI Test</h1>
          <p className="text-xl text-white/80">Swap ETH → USDC, then Bridge to Base</p>
        </div>

        {/* Main Card */}
        <div className="bg-white/10 backdrop-blur-lg rounded-3xl p-8 shadow-2xl border border-white/20">
          {!isConnected ? (
            // Not Connected State
            <div className="text-center py-20">
              <div className="text-8xl mb-6">🔌</div>
              <h2 className="text-3xl font-bold text-white mb-4">Connect Your Wallet</h2>
              <p className="text-white/70 text-lg mb-8">Click the button below to get started</p>
              <div className="flex justify-center">
                <ConnectButton />
              </div>
            </div>
          ) : !isOnEthereum ? (
            // Wrong Network State
            <div className="text-center py-20">
              <div className="text-8xl mb-6">⚠️</div>
              <h2 className="text-3xl font-bold text-white mb-4">Wrong Network</h2>
              <p className="text-white/70 text-lg mb-8">Please switch to Ethereum Mainnet</p>
              <button
                onClick={() => switchChain?.({ chainId: CHAINS.ETHEREUM })}
                className="btn btn-warning btn-lg text-xl px-12"
              >
                Switch to Ethereum
              </button>
            </div>
          ) : (
            // Main Interface
            <div>
              {/* Balances */}
              <div className="bg-white/5 rounded-2xl p-6 mb-6">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <div className="text-white/70 text-sm mb-1">ETH Balance</div>
                    <div className="text-2xl font-bold text-white">
                      {ethBalance ? parseFloat(formatUnits(ethBalance.value, 18)).toFixed(4) : "0"} ETH
                    </div>
                  </div>
                  <div>
                    <div className="text-white/70 text-sm mb-1">USDC Balance</div>
                    <div className="text-2xl font-bold text-white">
                      {usdcBalance ? formatUnits(usdcBalance.value, 6) : "0"} USDC
                    </div>
                  </div>
                </div>
              </div>

              {/* Tabs */}
              <div className="flex gap-2 mb-6">
                <button
                  onClick={() => setActiveTab("swap")}
                  className={`flex-1 py-4 rounded-xl font-bold text-lg transition-all ${
                    activeTab === "swap" ? "bg-white/20 text-white" : "bg-white/5 text-white/50 hover:bg-white/10"
                  }`}
                >
                  💱 Swap ETH → USDC
                </button>
                <button
                  onClick={() => setActiveTab("bridge")}
                  className={`flex-1 py-4 rounded-xl font-bold text-lg transition-all ${
                    activeTab === "bridge" ? "bg-white/20 text-white" : "bg-white/5 text-white/50 hover:bg-white/10"
                  }`}
                >
                  🌉 Bridge to Base
                </button>
              </div>

              {/* SWAP TAB */}
              {activeTab === "swap" && (
                <div>
                  <div className="mb-6">
                    <label className="block text-white mb-3 text-lg font-semibold">ETH Amount</label>
                    <div className="flex gap-3">
                      <input
                        type="number"
                        value={swapAmount}
                        onChange={e => setSwapAmount(e.target.value)}
                        placeholder="0.01"
                        disabled={isSwapping}
                        step="0.001"
                        className="flex-1 bg-white/10 text-white text-3xl font-bold px-6 py-4 rounded-xl border-2 border-white/20 focus:border-white/50 outline-none"
                      />
                      <div className="bg-white/10 px-6 py-4 rounded-xl border-2 border-white/20 flex items-center">
                        <span className="text-2xl font-bold text-white">ETH</span>
                      </div>
                    </div>
                  </div>

                  {/* Quick ETH Amounts */}
                  <div className="grid grid-cols-3 gap-3 mb-8">
                    <button
                      onClick={() => setSwapAmount("0.01")}
                      disabled={isSwapping}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      0.01 ETH
                    </button>
                    <button
                      onClick={() => setSwapAmount("0.05")}
                      disabled={isSwapping}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      0.05 ETH
                    </button>
                    <button
                      onClick={() => setSwapAmount("0.1")}
                      disabled={isSwapping}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      0.1 ETH
                    </button>
                  </div>

                  <button
                    onClick={handleSwap}
                    disabled={isSwapping || !swapAmount || parseFloat(swapAmount) <= 0}
                    className="w-full btn btn-success btn-lg text-2xl py-6 h-auto"
                  >
                    {isSwapping ? (
                      <>
                        <span className="loading loading-spinner loading-lg"></span>
                        Swapping...
                      </>
                    ) : (
                      <>💱 Swap to USDC</>
                    )}
                  </button>
                </div>
              )}

              {/* BRIDGE TAB */}
              {activeTab === "bridge" && (
                <div>
                  <div className="mb-6">
                    <label className="block text-white mb-3 text-lg font-semibold">USDC Amount</label>
                    <div className="flex gap-3">
                      <input
                        type="number"
                        value={bridgeAmount}
                        onChange={e => setBridgeAmount(e.target.value)}
                        placeholder="10"
                        disabled={isBridging}
                        className="flex-1 bg-white/10 text-white text-3xl font-bold px-6 py-4 rounded-xl border-2 border-white/20 focus:border-white/50 outline-none"
                      />
                      <div className="bg-white/10 px-6 py-4 rounded-xl border-2 border-white/20 flex items-center">
                        <span className="text-2xl font-bold text-white">USDC</span>
                      </div>
                    </div>
                  </div>

                  {/* Quick USDC Amounts */}
                  <div className="grid grid-cols-3 gap-3 mb-8">
                    <button
                      onClick={() => setBridgeAmount("10")}
                      disabled={isBridging}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      10 USDC
                    </button>
                    <button
                      onClick={() => setBridgeAmount("50")}
                      disabled={isBridging}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      50 USDC
                    </button>
                    <button
                      onClick={() => setBridgeAmount("100")}
                      disabled={isBridging}
                      className="btn btn-outline btn-lg text-white border-white/30 hover:bg-white/20"
                    >
                      100 USDC
                    </button>
                  </div>

                  <button
                    onClick={handleBridge}
                    disabled={isBridging || !bridgeAmount || parseFloat(bridgeAmount) <= 0}
                    className="w-full btn btn-primary btn-lg text-2xl py-6 h-auto"
                  >
                    {isBridging ? (
                      <>
                        <span className="loading loading-spinner loading-lg"></span>
                        Bridging...
                      </>
                    ) : (
                      <>🌉 Bridge to Base</>
                    )}
                  </button>
                </div>
              )}

              {/* Status Display */}
              {bridgeState.status !== "idle" && (
                <div className="mt-6 bg-white/5 rounded-2xl p-6">
                  <div className="flex items-center gap-4 mb-4">
                    {(bridgeState.status === "preparing" || bridgeState.status === "bridging") && (
                      <span className="loading loading-spinner loading-lg"></span>
                    )}
                    {bridgeState.status === "success" && <span className="text-5xl">✅</span>}
                    {bridgeState.status === "error" && <span className="text-5xl">❌</span>}
                    <div>
                      <div className="text-2xl font-bold text-white">{bridgeState.status.toUpperCase()}</div>
                      {bridgeState.message && <div className="text-white/70 mt-1">{bridgeState.message}</div>}
                    </div>
                  </div>

                  {bridgeState.txHash && (
                    <div className="bg-black/30 rounded-xl p-4">
                      <div className="text-white/70 mb-2">Transaction:</div>
                      <code className="text-xs text-white/90 break-all">{bridgeState.txHash}</code>
                    </div>
                  )}
                </div>
              )}

              {/* Info */}
              <div className="mt-6 bg-blue-500/20 rounded-2xl p-6 border-2 border-blue-500/30">
                <div className="text-white font-bold mb-3 text-lg">ℹ️ Instructions</div>
                <ul className="text-white/80 space-y-2">
                  <li>1️⃣ First: Swap ETH to USDC</li>
                  <li>2️⃣ Then: Bridge USDC to Base</li>
                  <li>⏱️ Swap: ~30 seconds</li>
                  <li>⏱️ Bridge: 5-15 minutes</li>
                </ul>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
