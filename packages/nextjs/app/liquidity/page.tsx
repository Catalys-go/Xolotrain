"use client";

import { useMemo, useState } from "react";
import { Address, EtherInput } from "@scaffold-ui/components";
import { useWatchBalance } from "@scaffold-ui/hooks";
import type { NextPage } from "next";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTargetNetwork,
} from "~~/hooks/scaffold-eth";
import { Tokens } from "~~/utils/contractAddresses";

const LiquidityPage: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { targetNetwork } = useTargetNetwork();

  const [petIdInput, setPetIdInput] = useState("1");
  const [ethAmountInput, setEthAmountInput] = useState("");

  // Automatically get token addresses based on network
  const usdcAddress = useMemo(() => {
    const networkName = targetNetwork.name?.toLowerCase();
    if (networkName === "mainnet" || networkName === "ethereum" || networkName === "foundry") {
      return Tokens.mainnet.USDC.address as `0x${string}`;
    } else if (networkName === "sepolia") {
      return Tokens.sepolia.USDC.address as `0x${string}`;
    } else if (networkName === "base") {
      return Tokens.base.USDC.address as `0x${string}`;
    }
    // Default to mainnet for local/fork
    return Tokens.mainnet.USDC.address as `0x${string}`;
  }, [targetNetwork]);

  const usdtAddress = useMemo(() => {
    const networkName = targetNetwork.name?.toLowerCase();
    if (networkName === "mainnet" || networkName === "ethereum" || networkName === "foundry") {
      return Tokens.mainnet.USDT.address as `0x${string}`;
    } else if (networkName === "sepolia") {
      return Tokens.sepolia.USDT.address as `0x${string}`;
    } else if (networkName === "base") {
      return Tokens.base.USDT.address as `0x${string}`;
    }
    // Default to mainnet for local/fork
    return Tokens.mainnet.USDT.address as `0x${string}`;
  }, [targetNetwork]);

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

  const petId = Number(petIdInput);
  const isPetIdValid = Number.isInteger(petId) && petId > 0;

  const { data: petData } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "pets",
    args: [isPetIdValid ? BigInt(petId) : undefined],
    query: { enabled: Boolean(petRegistry?.address && isPetIdValid) },
  });

  const hasPet = Boolean(
    petData && (petData as any).owner && (petData as any).owner !== "0x0000000000000000000000000000000000000000",
  );
  const petOwner = (petData as any)?.owner as string | undefined;
  const petHealth = (petData as any)?.health as bigint | undefined;
  const petPoolId = (petData as any)?.poolId as string | undefined;
  const petPositionId = (petData as any)?.positionId as bigint | undefined;

  const matchesConnected = Boolean(connectedAddress && petOwner?.toLowerCase() === connectedAddress.toLowerCase());
  const hasLpPosition = Boolean(petPositionId && petPositionId !== 0n);
  const isEggHatched = hasPet && hasLpPosition;

  const { writeContractAsync, isPending } = useScaffoldWriteContract({
    contractName: "AutoLpHelper",
  });

  const handleAutoLp = async () => {
    if (!writeContractAsync) return;
    const value = parseEther(ethAmountInput || "0");
    await writeContractAsync({
      functionName: "swapEthToUsdcUsdtAndMint",
      value,
    });
  };

  return (
    <div className="flex flex-col items-center gap-8 pt-10 px-6">
      <div className="max-w-5xl w-full">
        <h1 className="text-3xl font-bold mb-2">Swap + LP (Uniswap v4)</h1>
        <p className="text-base-content/70">
          Connect a wallet, swap ETH to USDC/USDT, and create an LP position that hatches your egg.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 w-full max-w-5xl">
        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Wallet</h2>
            <div className="mt-2">
              <Address address={connectedAddress} chain={targetNetwork} />
              <div className="mt-2 text-sm text-base-content/70">Network: {targetNetwork.name}</div>
            </div>
          </div>
        </div>

        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Token Balances</h2>
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
            <div className="divider" />
            <div>
              <div className="text-sm font-semibold mb-2">Token Addresses (auto-detected)</div>
              <div className="space-y-2 text-xs text-base-content/70">
                <div>
                  <span className="font-semibold">USDC:</span> {usdcAddress}
                </div>
                <div>
                  <span className="font-semibold">USDT:</span> {usdtAddress}
                </div>
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

        <div className="card bg-base-100 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Create LP (Hatch Egg)</h2>
            <p className="text-sm text-base-content/70">
              Creating liquidity triggers the hook and hatches the egg on-chain.
            </p>
            <div className="mt-4 grid grid-cols-1 gap-3">
              <button className="btn btn-accent" disabled>
                Create LP Position
              </button>
              <p className="text-xs text-base-content/60">LP creation is handled by the Auto LP action.</p>
            </div>
          </div>
        </div>

        <div className="card bg-base-100 shadow-xl lg:col-span-2">
          <div className="card-body">
            <h2 className="card-title">LP + Egg Status</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Pet ID</label>
                <input
                  className="input input-bordered"
                  value={petIdInput}
                  onChange={event => setPetIdInput(event.target.value)}
                  placeholder="Enter pet ID"
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Status</label>
                <div className="p-3 rounded-xl bg-base-200">
                  <div className="text-sm">Has Egg: {hasPet ? "Yes" : "No"}</div>
                  <div className="text-sm">Egg Hatched: {isEggHatched ? "Yes" : "No"}</div>
                  <div className="text-sm">LP Position: {hasLpPosition ? "Yes" : "No"}</div>
                  <div className="text-sm">Owned by Wallet: {matchesConnected ? "Yes" : "No"}</div>
                </div>
              </div>
            </div>
            <div className="divider" />
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="text-sm">Pool ID: {petPoolId ?? "—"}</div>
              <div className="text-sm">Position ID: {petPositionId?.toString() ?? "—"}</div>
              <div className="text-sm">Health: {petHealth?.toString() ?? "—"}</div>
              <div className="text-sm">Registry: {petRegistry?.address ?? "Not deployed"}</div>
              <div className="text-sm">Auto LP Helper: {autoLpHelper?.address ?? "Not deployed"}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default LiquidityPage;
