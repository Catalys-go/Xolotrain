import { useMemo, useState } from "react";
import poolKeysData from "~~/../../packages/foundry/addresses/poolKeys.json";
import { useTargetNetwork } from "~~/hooks/scaffold-eth";

// Simple truncate helper
const truncateString = (str: string, startChars = 10, endChars = 8) => {
  if (str.length <= startChars + endChars) return str;
  return `${str.slice(0, startChars)}...${str.slice(-endChars)}`;
};

// Copy button component
const CopyButton = ({ text }: { text: string }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button onClick={handleCopy} className="btn btn-ghost btn-xs" title="Copy to clipboard">
      {copied ? (
        <svg className="h-4 w-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
        </svg>
      ) : (
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
      )}
    </button>
  );
};

type LpPositionTrackerProps = {
  hasLpPositions: boolean;
  userPetIds: readonly bigint[] | undefined;
  firstPetHealth: bigint | undefined;
  firstPetPositionId: bigint | undefined;
  firstPetPoolId: string | undefined;
  firstPetChainId: bigint | undefined;
  hasFirstPet: boolean;
  firstPetId: bigint | undefined;
};

export const LpPositionTracker = ({
  hasLpPositions,
  userPetIds,
  firstPetHealth,
  firstPetPositionId,
  firstPetPoolId,
  firstPetChainId,
  hasFirstPet,
  firstPetId,
}: LpPositionTrackerProps) => {
  const { targetNetwork } = useTargetNetwork();

  // Match poolId with poolKeys.json to get pool name
  const poolInfo = useMemo(() => {
    if (!firstPetPoolId || !firstPetChainId) return null;

    const chainId = firstPetChainId.toString();
    const chainPools = (poolKeysData as any)[chainId];

    if (!chainPools) return null;

    // Search through all pools to find matching poolId
    for (const [poolName, poolData] of Object.entries(chainPools)) {
      if (poolName === "chainName" || poolName === "poolManager" || poolName === "positionManager") continue;

      const pool = poolData as any;
      if (pool.poolId?.toLowerCase() === firstPetPoolId.toLowerCase()) {
        return {
          name: poolName,
          fee: pool.fee,
          tickSpacing: pool.tickSpacing,
        };
      }
    }

    return null;
  }, [firstPetPoolId, firstPetChainId]);

  // Render chain icon based on network
  const renderChainIcon = () => {
    if (targetNetwork.id === 1 || targetNetwork.id === 31337) {
      // Ethereum icon
      return (
        <svg className="w-10 h-10" viewBox="0 0 256 417" xmlns="http://www.w3.org/2000/svg">
          <path fill="#343434" d="M127.961 0l-2.795 9.5v275.668l2.795 2.79 127.962-75.638z" />
          <path fill="#8C8C8C" d="M127.962 0L0 212.32l127.962 75.639V154.158z" />
          <path fill="#3C3C3B" d="M127.961 312.187l-1.575 1.92v98.199l1.575 4.6L256 236.587z" />
          <path fill="#8C8C8C" d="M127.962 416.905v-104.72L0 236.585z" />
          <path fill="#141414" d="M127.961 287.958l127.96-75.637-127.96-58.162z" />
          <path fill="#393939" d="M0 212.32l127.96 75.638v-133.8z" />
        </svg>
      );
    } else if (targetNetwork.id === 8453) {
      // Base icon (blue circle)
      return <div className="w-10 h-10 rounded-full bg-[#0052FF]" />;
    } else if (targetNetwork.id === 11155111) {
      // Sepolia (Ethereum testnet icon)
      return (
        <svg className="w-10 h-10 opacity-60" viewBox="0 0 256 417" xmlns="http://www.w3.org/2000/svg">
          <path fill="#343434" d="M127.961 0l-2.795 9.5v275.668l2.795 2.79 127.962-75.638z" />
          <path fill="#8C8C8C" d="M127.962 0L0 212.32l127.962 75.639V154.158z" />
          <path fill="#3C3C3B" d="M127.961 312.187l-1.575 1.92v98.199l1.575 4.6L256 236.587z" />
          <path fill="#8C8C8C" d="M127.962 416.905v-104.72L0 236.585z" />
          <path fill="#141414" d="M127.961 287.958l127.96-75.637-127.96-58.162z" />
          <path fill="#393939" d="M0 212.32l127.96 75.638v-133.8z" />
        </svg>
      );
    }
    // Generic chain icon
    return <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center text-2xl">⛓️</div>;
  };

  // Determine position status based on health
  const getPositionStatus = () => {
    if (!firstPetHealth) return { text: "Unknown", badge: "badge-ghost", icon: "?" };

    const health = Number(firstPetHealth);
    if (health >= 70) return { text: "In Range", badge: "badge-success", icon: "✓" };
    if (health >= 40) return { text: "Near Range", badge: "badge-warning", icon: "!" };
    return { text: "Out of Range", badge: "badge-error", icon: "!" };
  };

  const status = getPositionStatus();

  if (!hasLpPositions && !hasFirstPet) {
    return (
      <div className="card shadow-xl">
        <div className="card-body">
          <h2 className="card-title">LP Position Tracker</h2>
          <p className="text-sm  mb-4">Track your USDC/USDT liquidity positions and their performance</p>
          <div className="alert alert-warning">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="stroke-current shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
            <div>
              <div className="font-semibold">No LP Positions Yet</div>
              <div className="text-sm">Use &ldquo;Auto LP + Hatch&rdquo; above to create your first position</div>
            </div>
          </div>
          <div className="mt-4 text-sm ">
            <div className="font-semibold mb-2">What you&apos;ll get:</div>
            <ul className="list-disc list-inside space-y-1">
              <li>Liquidity position in USDC/USDT Uniswap v4 pool</li>
              <li>Automatic fee earning from swaps</li>
              <li>A hatched Xolotl pet (NFT) tracking your position</li>
              <li>Real-time health monitoring</li>
            </ul>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="card">
      <div className="card-body">
        <h2 className="card-title">LP Position Tracker</h2>

        {hasLpPositions ? (
          <div className="space-y-4">
            <div className="mx-auto">
              <div className=" text-sm mb-1">Status</div>
              <div className="flex items-center gap-2 mx-auto">
                <div className="text-3xl font-bold">{status.text}</div>
                <div className={`badge ${status.badge}`}>{status.icon}</div>
              </div>
              <div className="text-sm  mt-1">
                Health-based estimate • Accurate tick data requires PoolManager integration
              </div>
            </div>
            {/* Chain Icon & Position Header */}
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 rounded-full bg-base-200 flex items-center justify-center">
                {renderChainIcon()}
              </div>
              <div className="flex-1">
                <div className="text-2xl font-bold">LP POSITION</div>
                <div className="text-sm">{targetNetwork.id === 31337 ? "Localhost (Fork)" : targetNetwork.name}</div>
              </div>
            </div>

            <div className="divider my-2" />

            {/* Pool & Position Data */}
            <div className="space-y-3">
              <div>
                <div className="text-sm mb-1">Pool</div>
                <div className="text-3xl font-bold">{poolInfo?.name?.replace("_", "/") || "USDC/USDT"}</div>
                {poolInfo && (
                  <div className="text-xs mt-1">
                    Fee: {(poolInfo.fee / 10000).toFixed(3)}% • Tick Spacing: {poolInfo.tickSpacing}
                  </div>
                )}
              </div>

              <div>
                <div className="text-sm mb-1">Position ID</div>
                <div className="flex items-center gap-2 text-primary">
                  <div className="text-2xl font-mono font-bold">
                    {firstPetPositionId ? truncateString(firstPetPositionId.toString(), 12, 10) : "—"}
                  </div>
                  {firstPetPositionId && <CopyButton text={firstPetPositionId.toString()} />}
                </div>
              </div>

              <div>
                <div className="text-sm mb-1">Pool ID</div>
                <div className="flex items-center gap-2">
                  <div className="text-sm font-mono break-all">
                    {firstPetPoolId ? truncateString(firstPetPoolId, 16, 12) : "—"}
                  </div>
                  {firstPetPoolId && <CopyButton text={firstPetPoolId} />}
                </div>
              </div>

              <div>
                <div className=" text-sm mb-1">Position NFT</div>
                <div className="flex items-center gap-2">
                  <div className="text-2xl font-mono font-bold">
                    {firstPetPositionId ? `#${truncateString(firstPetPositionId.toString(), 12, 10)}` : "—"}
                  </div>
                  {firstPetPositionId && <CopyButton text={firstPetPositionId.toString()} />}
                </div>
                <div className="text-xs mt-1">Uniswap v4 PositionManager NFT</div>
              </div>
            </div>

            <div className="divider" />

            <div className="space-y-2">
              <div className="text-sm font-semibold">Your Pets & LP Positions:</div>
              <div className="flex flex-wrap gap-2">
                {userPetIds?.map(petId => (
                  <div key={petId.toString()} className="badge badge-primary badge-lg">
                    Pet #{petId.toString()}
                  </div>
                ))}
              </div>
            </div>

            <div className="alert alert-info text-sm">
              ℹ️ Each pet represents one LP position. Position tracking moved to PetRegistry for consistency.
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="stat bg-base-200 rounded-xl">
                <div className="stat-title">Position ID</div>
                <div className="stat-value text-lg font-mono">{firstPetPositionId?.toString()}</div>
                <div className="stat-desc">From Pet #{firstPetId?.toString()}</div>
              </div>
              <div className="stat bg-base-200 rounded-xl">
                <div className="stat-title">Health Score</div>
                <div className="stat-value text-lg">
                  {firstPetHealth?.toString() ?? "0"}
                  <span className="text-base">/100</span>
                </div>
                <div className="stat-desc">
                  <progress
                    className="progress progress-success w-full"
                    value={firstPetHealth?.toString() ?? "0"}
                    max="100"
                  />
                </div>
              </div>
            </div>

            <div className="divider">Position Details</div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <div className="text-sm font-semibold">Pool Information</div>
                <div className="p-3 bg-base-200 rounded-xl space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span className="">Pool:</span>
                    <span className="font-semibold">USDC/USDT</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="">Fee Tier:</span>
                    <span className="font-mono">0.001%</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="">Tick Spacing:</span>
                    <span className="font-mono">1</span>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
                <div className="text-sm font-semibold">Range Strategy</div>
                <div className="p-3 bg-base-200 rounded-xl space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span className="">Lower Offset:</span>
                    <span className="font-mono">-6 ticks</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="">Upper Offset:</span>
                    <span className="font-mono">+6 ticks</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="">Status:</span>
                    <span className="badge badge-success badge-sm">In Range</span>
                  </div>
                </div>
              </div>
            </div>

            <div className="alert alert-info">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                className="stroke-current shrink-0 w-6 h-6"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span className="text-xs">
                Position health is monitored by an off-chain agent. When health drops below 50, your Xolotl becomes
                unhappy! Keep your position in-range and earning fees.
              </span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
