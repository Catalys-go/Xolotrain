"use client";

import { useState } from "react";
import { Address, EtherInput } from "@scaffold-ui/components";
import { useWatchBalance } from "@scaffold-ui/hooks";
import type { NextPage } from "next";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { LpPositionTracker } from "~~/components/LpPositionTracker";
import { YourPets } from "~~/components/YourPets";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTargetNetwork,
} from "~~/hooks/scaffold-eth";
import { getTokenAddress } from "~~/utils/tokenHelpers";

const LiquidityPage: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { targetNetwork } = useTargetNetwork();

  const [ethAmountInput, setEthAmountInput] = useState("");

  const usdcAddress = getTokenAddress("USDC", targetNetwork);
  const usdtAddress = getTokenAddress("USDT", targetNetwork);

  const { data: ethBalance } = useWatchBalance({ address: connectedAddress, chain: targetNetwork });
  const { data: usdcBalance } = useWatchBalance({
    address: connectedAddress,
    chain: targetNetwork,
    token: usdcAddress,
  });
  const { data: usdtBalance } = useWatchBalance({
    address: connectedAddress,
    chain: targetNetwork,
    token: usdtAddress,
  });

  const { data: petRegistry } = useDeployedContractInfo({ contractName: "PetRegistry" });
  const { data: autoLpHelper } = useDeployedContractInfo({ contractName: "AutoLpHelper" });
  const { data: eggHatchHook } = useDeployedContractInfo({ contractName: "EggHatchHook" });

  const { data: totalSupply } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "totalSupply",
    query: { enabled: Boolean(petRegistry?.address) },
  });

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

  const firstPetHealth = firstPetData?.health;
  const firstPetPositionId = firstPetData?.positionId;
  const firstPetPoolId = firstPetData?.poolId;
  const firstPetChainId = firstPetData?.chainId;
  const hasFirstPet = Boolean(firstPetData && firstPetPositionId && firstPetPositionId !== 0n);
  const hasLpPositions = userPetCount > 0;

  const { writeContractAsync, isPending } = useScaffoldWriteContract({
    contractName: "AutoLpHelper",
  });

  // Read contract to quote swap outputs
  const { data: quoteData } = useScaffoldReadContract({
    contractName: "AutoLpHelper",
    functionName: "quoteSwapOutputs",
    args: [parseEther(ethAmountInput || "0")],
  });

  const handleAutoLp = async () => {
    if (!writeContractAsync) return;
    try {
      const value = parseEther(ethAmountInput || "0");

      // Get quote from contract for accurate pricing
      let minUsdcOut: bigint;
      let minUsdtOut: bigint;

      if (quoteData) {
        const [quotedUsdc, quotedUsdt] = quoteData;

        // Apply 10% slippage tolerance to quoted amounts
        const slippageTolerance = 0.9; // 10% slippage
        minUsdcOut = BigInt(Math.floor(Number(quotedUsdc) * slippageTolerance));
        minUsdtOut = BigInt(Math.floor(Number(quotedUsdt) * slippageTolerance));
      } else {
        // Fallback: use very conservative minimums
        minUsdcOut = BigInt(100_000); // 0.1 USDC minimum
        minUsdtOut = BigInt(100_000); // 0.1 USDT minimum
      }

      await writeContractAsync({
        functionName: "swapEthToUsdcUsdtAndMint",
        args: [minUsdcOut, minUsdtOut],
        value,
      });
    } catch (error: any) {
      console.error("Transaction error:", error);

      if (error?.message?.includes("User rejected") || error?.message?.includes("User denied")) {
        return;
      }

      if (error?.message?.includes("replacement transaction underpriced")) {
        console.error("⚠️ NONCE ERROR - Check console for details");
        console.error("To fix: MetaMask → Settings → Advanced → Clear activity tab data");
        return;
      }

      console.error("❌ TRANSACTION FAILED - Full error details:");
      console.error("Error message:", error?.message);
      console.error("Error details:", error);
    }
  };

  return (
    <div className="flex flex-col items-center gap-8 pt-10 px-6">
      <div className="max-w-5xl w-full">
        <h1 className="text-3xl font-bold mb-2">Swap + LP (Uniswap v4)</h1>
        <p className="text-base-content/70">
          Connect a wallet, add funds from faucet, swap ETH to USDC/USDT, and create an LP position that hatches your
          egg.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 w-full max-w-5xl">
        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Wallet & Balances</h2>
            <div className="mb-3">
              <div className="text-sm text-base-content/70 mb-1">Connected Address</div>
              <Address address={connectedAddress} chain={targetNetwork} />
              <div className="mt-1 text-xs text-base-content/60">Network: {targetNetwork.name}</div>
            </div>
            <div className="divider my-2" />
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span>ETH</span>
                <span className="font-semibold">{ethBalance?.formatted ?? "0"}</span>
              </div>
              <div className="flex items-center justify-between">
                <span>USDC</span>
                <span className="font-semibold">{usdcBalance?.formatted ?? "—"}</span>
              </div>
              <div className="flex items-center justify-between">
                <span>USDT</span>
                <span className="font-semibold">{usdtBalance?.formatted ?? "—"}</span>
              </div>
            </div>
          </div>
        </div>

        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Auto LP (ETH → USDC/USDT)</h2>
            <p className="text-sm text-base-content/70">
              Auto swap + mint LP using the helper contract and fixed tick range.
            </p>
            <div className="mt-4 grid grid-cols-1 gap-3">
              <EtherInput
                defaultValue={ethAmountInput}
                onValueChange={({ valueInEth }) => setEthAmountInput(valueInEth)}
                defaultUsdMode={false}
                placeholder="ETH amount"
              />
              <button
                className="btn btn-primary"
                disabled={!connectedAddress || !autoLpHelper?.address || !ethAmountInput || isPending}
                onClick={handleAutoLp}
              >
                {isPending ? "Submitting..." : "Auto LP + Hatch"}
              </button>
              <p className="text-xs text-base-content/60">
                Uses fixed tick offsets (-6 / +6) and a default slippage buffer.
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="w-full max-w-5xl">
        <LpPositionTracker
          hasLpPositions={hasLpPositions}
          userPetIds={userPetIds as bigint[]}
          firstPetHealth={firstPetHealth}
          firstPetPositionId={firstPetPositionId}
          firstPetPoolId={firstPetPoolId}
          firstPetChainId={firstPetChainId}
          hasFirstPet={hasFirstPet}
          firstPetId={firstPetId}
        />
      </div>

      <div className="w-full max-w-5xl">
        <YourPets
          totalSupply={totalSupply}
          userPetIds={userPetIds}
          connectedAddress={connectedAddress}
          petRegistryAddress={petRegistry?.address}
          autoLpHelperAddress={autoLpHelper?.address}
          eggHatchHookAddress={eggHatchHook?.address}
        />
      </div>
    </div>
  );
};

export default LiquidityPage;
