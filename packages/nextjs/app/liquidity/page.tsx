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
  const { data: eggHatchHook } = useDeployedContractInfo({ contractName: "EggHatchHook" });

  // Get total pets minted
  const { data: totalSupply } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "totalSupply",
    query: { enabled: Boolean(petRegistry?.address) },
  });

  // Get user's pets
  const { data: userPetIds } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPetsByOwner",
    args: [connectedAddress],
    query: { enabled: Boolean(petRegistry?.address && connectedAddress) },
  });

  const petId = Number(petIdInput);
  const isPetIdValid = Number.isInteger(petId) && petId > 0;

  const { data: petData } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPet",
    args: [isPetIdValid ? BigInt(petId) : undefined],
    query: { enabled: Boolean(petRegistry?.address && isPetIdValid) },
  });

  const hasPet = Boolean(petData && petData.owner && petData.owner !== "0x0000000000000000000000000000000000000000");
  const petOwner = petData?.owner;
  const petHealth = petData?.health;
  const petPoolId = petData?.poolId;
  const petPositionId = petData?.positionId;
  const petChainId = petData?.chainId;
  const petLastUpdate = petData?.lastUpdate;

  const matchesConnected = Boolean(connectedAddress && petOwner?.toLowerCase() === connectedAddress.toLowerCase());
  const hasLpPosition = Boolean(petPositionId && petPositionId !== 0n);
  const isEggHatched = hasPet && hasLpPosition;

  const userPetCount = (userPetIds as bigint[])?.length ?? 0;

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
            <h2 className="card-title">Your Pets</h2>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
              <div className="stat bg-base-200 rounded-xl">
                <div className="stat-title">Total Pets Minted</div>
                <div className="stat-value text-2xl">{totalSupply?.toString() ?? "0"}</div>
              </div>
              <div className="stat bg-base-200 rounded-xl">
                <div className="stat-title">Your Pets</div>
                <div className="stat-value text-2xl">{userPetCount}</div>
              </div>
              <div className="stat bg-base-200 rounded-xl">
                <div className="stat-title">Hatched</div>
                <div className="stat-value text-2xl">{isEggHatched ? "✓" : "—"}</div>
              </div>
            </div>

            {userPetCount > 0 && (
              <div className="mb-4">
                <div className="text-sm font-semibold mb-2">Your Pet IDs:</div>
                <div className="flex flex-wrap gap-2">
                  {(userPetIds as bigint[])?.map(id => (
                    <button
                      key={id.toString()}
                      className={`btn btn-sm ${petIdInput === id.toString() ? "btn-primary" : "btn-outline"}`}
                      onClick={() => setPetIdInput(id.toString())}
                    >
                      Pet #{id.toString()}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <div className="divider">Selected Pet Details</div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Pet ID</label>
                <input
                  className="input input-bordered w-full"
                  value={petIdInput}
                  onChange={event => setPetIdInput(event.target.value)}
                  placeholder="Enter pet ID"
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Status</label>
                <div className="p-3 rounded-xl bg-base-200">
                  <div className="text-sm">Exists: {hasPet ? "✓ Yes" : "✗ No"}</div>
                  <div className="text-sm">Hatched: {isEggHatched ? "✓ Yes" : "✗ No"}</div>
                  <div className="text-sm">Has LP: {hasLpPosition ? "✓ Yes" : "✗ No"}</div>
                  <div className="text-sm">Yours: {matchesConnected ? "✓ Yes" : "✗ No"}</div>
                </div>
              </div>
            </div>

            <div className="divider" />

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div className="space-y-2">
                <div>
                  <span className="font-semibold">Owner:</span>{" "}
                  {petOwner ? <Address address={petOwner as `0x${string}`} /> : "—"}
                </div>
                <div>
                  <span className="font-semibold">Health:</span> {petHealth?.toString() ?? "—"} / 100
                </div>
                <div>
                  <span className="font-semibold">Chain ID:</span> {petChainId?.toString() ?? "—"}
                </div>
                <div>
                  <span className="font-semibold">Last Update:</span>{" "}
                  {petLastUpdate ? new Date(Number(petLastUpdate) * 1000).toLocaleString() : "—"}
                </div>
              </div>
              <div className="space-y-2">
                <div>
                  <span className="font-semibold">Pool ID:</span>
                  <div className="text-xs break-all">{petPoolId ?? "—"}</div>
                </div>
                <div>
                  <span className="font-semibold">Position ID:</span> {petPositionId?.toString() ?? "—"}
                </div>
              </div>
            </div>

            <div className="divider">Contract Addresses</div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
              <div>
                <span className="font-semibold">PetRegistry:</span>
                {petRegistry?.address ? (
                  <div className="break-all">
                    <Address address={petRegistry.address as `0x${string}`} />
                  </div>
                ) : (
                  " Not deployed"
                )}
              </div>
              <div>
                <span className="font-semibold">AutoLpHelper:</span>
                {autoLpHelper?.address ? (
                  <div className="break-all">
                    <Address address={autoLpHelper.address as `0x${string}`} />
                  </div>
                ) : (
                  " Not deployed"
                )}
              </div>
              <div>
                <span className="font-semibold">EggHatchHook:</span>
                {eggHatchHook?.address ? (
                  <div className="break-all">
                    <Address address={eggHatchHook.address as `0x${string}`} />
                  </div>
                ) : (
                  " Not deployed"
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default LiquidityPage;
