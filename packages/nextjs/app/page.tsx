"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { EtherInput } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const Home: NextPage = () => {
  const { isConnected, address: connectedAddress } = useAccount();

  // input state
  const [ethAmountInput, setEthAmountInput] = useState("");

  // contracts
  const { data: petRegistry } = useDeployedContractInfo({ contractName: "PetRegistry" });
  const { data: autoLpHelper } = useDeployedContractInfo({ contractName: "AutoLpHelper" });

  // read pets
  const { data: userPetIds } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPetsByOwner",
    args: [connectedAddress],
    query: { enabled: Boolean(petRegistry?.address && connectedAddress) },
  });

  const userPetCount = (userPetIds as bigint[])?.length ?? 0;
  const firstPetId = userPetCount > 0 ? (userPetIds as bigint[])[0] : undefined;

  const { data: firstPetData } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPet",
    args: [firstPetId],
    query: { enabled: Boolean(petRegistry?.address && firstPetId) },
  });

  const hasPetOnchain = Boolean(firstPetData?.positionId && firstPetData.positionId !== 0n);

  // local transition state (egg -> pet immediately on success without waiting for reads)
  const [localHatched, setLocalHatched] = useState(false);
  const [revealActive, setRevealActive] = useState(false);
  const prevShowPetRef = useRef(false);
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (hasPetOnchain) setLocalHatched(true);
  }, [hasPetOnchain]);

  const showPet = localHatched || hasPetOnchain;
  useEffect(() => {
    const prev = prevShowPetRef.current;

    // Transition: egg -> pet
    if (!prev && showPet) {
      setRevealActive(true);
      if (revealTimerRef.current) clearTimeout(revealTimerRef.current);

      // Run reveal for ~2.2s then stop flashing/stretching
      revealTimerRef.current = setTimeout(() => setRevealActive(false), 2200);
    }

    prevShowPetRef.current = showPet;

    return () => {
      if (revealTimerRef.current) clearTimeout(revealTimerRef.current);
    };
  }, [showPet]);

  // quote for min-outs (same as liquidity page)
  const { data: quoteData } = useScaffoldReadContract({
    contractName: "AutoLpHelper",
    functionName: "quoteSwapOutputs",
    args: [parseEther(ethAmountInput || "0")],
    query: { enabled: Boolean(autoLpHelper?.address) },
  });

  const { writeContractAsync, isPending } = useScaffoldWriteContract({
    contractName: "AutoLpHelper",
  });

  const isHatching = !showPet && isPending;

  const handleAutoLp = async () => {
    if (!writeContractAsync) return;

    try {
      const value = parseEther(ethAmountInput || "0");

      // min-outs from quote with 10% slippage
      let minUsdcOut: bigint;
      let minUsdtOut: bigint;

      if (quoteData) {
        const [quotedUsdc, quotedUsdt] = quoteData as readonly [bigint, bigint];
        const slippageTolerance = 0.9;

        // (keep same approach as liquidity page)
        minUsdcOut = BigInt(Math.floor(Number(quotedUsdc) * slippageTolerance));
        minUsdtOut = BigInt(Math.floor(Number(quotedUsdt) * slippageTolerance));
      } else {
        // conservative fallback
        minUsdcOut = 100_000n; // 0.1 USDC (6 decimals)
        minUsdtOut = 100_000n; // 0.1 USDT (6 decimals)
      }

      await writeContractAsync({
        functionName: "swapEthToUsdcUsdtAndMint",
        args: [minUsdcOut, minUsdtOut],
        value,
      });

      // if tx succeeded, flip visual immediately
      setLocalHatched(true);
    } catch (error: any) {
      console.error("Transaction error:", error);

      if (error?.message?.includes("User rejected") || error?.message?.includes("User denied")) return;

      if (error?.message?.includes("replacement transaction underpriced")) {
        console.error("⚠️ NONCE ERROR - MetaMask → Settings → Advanced → Clear activity tab data");
        return;
      }

      console.error("❌ TRANSACTION FAILED");
      console.error(error?.message ?? error);
    }
  };

  // 1) LOCKED: title screen (no wallet connected)
  if (!isConnected) {
    return (
      <div className="min-h-screen flex items-center justify-center px-5 bg-primary">
        <div className="bg-primary rounded-3xl  max-w-xl w-full text-center p-8">
          <div className="flex flex-col items-center justify-center gap-6">
            <Image src="/logo.png" alt="Xolotrain logo" width={800} height={100} priority />
            <p className="text-base-content/80 font-della text-lg">
              An onchain virtual axolotl pet that lives, evolves, and travels across networks
            </p>
            <div className="pt-2">
              <RainbowKitCustomConnectButton />
            </div>
          </div>
        </div>
      </div>
    );
  }

  // 2) UNLOCKED: hatch screen
  return (
    <div className="min-h-screen flex items-center justify-center px-5 pt-16 pb-28 bg-primary">
      <div className="w-full max-w-xl">
        <div className="bg-base-100 rounded-3xl p-6">
          <div className="flex flex-col items-center justify-center gap-6">
            {/* Main visual */}
            <div className="w-full flex items-center justify-center">
              <div
                className={[
                  "relative flex items-center justify-center",
                  showPet || revealActive ? "w-[450px] h-[450px]" : "w-[256px] h-[256px]",
                ].join(" ")}
              >
                {/* Bubble pops (only during reveal) */}
                {revealActive && (
                  <>
                    {[
                      { left: "10%", top: "18%", delay: "0ms", size: 18 },
                      { left: "22%", top: "70%", delay: "120ms", size: 14 },
                      { left: "78%", top: "22%", delay: "180ms", size: 16 },
                      { left: "86%", top: "60%", delay: "320ms", size: 12 },
                      { left: "50%", top: "10%", delay: "260ms", size: 20 },
                      { left: "58%", top: "78%", delay: "420ms", size: 14 },
                      { left: "32%", top: "28%", delay: "520ms", size: 12 },
                      { left: "70%", top: "48%", delay: "640ms", size: 16 },
                    ].map((b, i) => (
                      <Image
                        key={i}
                        src="/bubble.svg"
                        alt="Bubble"
                        width={b.size}
                        height={b.size}
                        className="absolute animate-bubble-pop pointer-events-none select-none"
                        style={{
                          left: b.left,
                          top: b.top,
                          animationDelay: b.delay,
                        }}
                        priority
                      />
                    ))}
                  </>
                )}

                <Image
                  src={showPet ? "/LPet.svg" : "/egg1.svg"}
                  alt={showPet ? "Your Axolotl" : "Axolotl egg"}
                  width={showPet || revealActive ? 450 : 256}
                  height={showPet || revealActive ? 450 : 256}
                  className={[
                    "rounded-3xl",
                    // Egg idle float; pet idle float only after reveal finishes
                    !showPet ? "animate-egg-float" : !revealActive ? "animate-egg-float" : "",
                    // Pending hatch keeps egg flashing/stretching
                    isHatching ? "animate-egg-hatch" : "",
                    // Pet reveal: fast -> slow settle + flashing/stretching, then stops
                    revealActive ? "animate-pet-reveal" : "",
                  ].join(" ")}
                  priority
                />
              </div>
            </div>
            {showPet && <p className="text-lg text-center">Click the Axo LP tab to see your position details</p>}

            {/* Hatch card (only before hatch; single-position test flow) */}
            {!showPet && (
              <div className="card bg-base-100 w-full">
                <div className="card-body text-center">
                  <p className="text-sm text-base-content/70">Auto swap ETH into USDC/USDT + mint LP.</p>

                  <div className="mt-4 grid grid-cols-1 gap-3 text-center mx-auto">
                    <div className="mx-auto font-della">
                      <EtherInput
                        defaultValue={ethAmountInput}
                        onValueChange={({ valueInEth }) => setEthAmountInput(valueInEth)}
                        defaultUsdMode={false}
                        placeholder="ETH amount"
                      />
                    </div>

                    <button
                      className="btn btn-neutral hover:btn-accent mx-auto"
                      disabled={!connectedAddress || !autoLpHelper?.address || !ethAmountInput || isPending}
                      onClick={handleAutoLp}
                    >
                      {isPending ? "Submitting..." : "Hatch Auto LP Egg"}
                    </button>

                    <p className="text-xs text-base-content/60">
                      Uses fixed tick offsets (-6 / +6) and a default slippage buffer.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
