import { useState } from "react";
import { Address } from "@scaffold-ui/components";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

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

type YourPetsProps = {
  totalSupply: bigint | undefined;
  userPetIds: readonly bigint[] | undefined;
  connectedAddress: string | undefined;
  petRegistryAddress: string | undefined;
  autoLpHelperAddress: string | undefined;
  eggHatchHookAddress: string | undefined;
};

export const YourPets = ({
  totalSupply,
  userPetIds,
  connectedAddress,
  petRegistryAddress,
  autoLpHelperAddress,
  eggHatchHookAddress,
}: YourPetsProps) => {
  const [petIdInput, setPetIdInput] = useState("1");

  const userPetCount = (userPetIds as bigint[])?.length ?? 0;
  const petId = Number(petIdInput);
  const isPetIdValid = Number.isInteger(petId) && petId > 0;

  // Fetch pet data using hook at component level
  const { data: petData } = useScaffoldReadContract({
    contractName: "PetRegistry",
    functionName: "getPet",
    args: [isPetIdValid ? BigInt(petId) : undefined],
    query: { enabled: Boolean(petRegistryAddress && isPetIdValid) },
  });

  const hasPet = Boolean(petData?.owner && petData.owner !== "0x0000000000000000000000000000000000000000");
  const petOwner = petData?.owner;
  const petHealth = petData?.health;
  const petPoolId = petData?.poolId;
  const petPositionId = petData?.positionId;
  const petChainId = petData?.chainId;
  const petLastUpdate = petData?.lastUpdate;
  const matchesConnected = Boolean(connectedAddress && petOwner?.toLowerCase() === connectedAddress.toLowerCase());
  const hasLpPosition = Boolean(petPositionId && petPositionId !== 0n);
  const isEggHatched = hasPet && hasLpPosition;

  return (
    <div className="card bg-base-100 shadow-xl">
      <div className="card-body">
        <h2 className="card-title">Your Pets</h2>

        {userPetCount > 0 ? (
          <div>
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
          </div>
        ) : (
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
            <div>
              <div className="font-semibold">No Pets Yet</div>
              <div className="text-sm">Create your first LP position above to hatch a Xolotl pet!</div>
            </div>
          </div>
        )}

        {userPetCount > 0 && (
          <>
            <div className="divider">Selected Pet Details</div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Look Up Pets by ID</label>
                <input
                  className="input input-bordered w-full my-2"
                  value={petIdInput}
                  onChange={event => setPetIdInput(event.target.value)}
                  placeholder="Enter pet ID"
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm text-base-content/70">Status</label>
                <div className="p-3 rounded-xl bg-base-200 space-y-1 text-sm">
                  <div>Exists: {hasPet ? "✓ Yes" : "✗ No"}</div>
                  <div>Hatched: {isEggHatched ? "✓ Yes" : "✗ No"}</div>
                  <div>Has LP: {hasLpPosition ? "✓ Yes" : "✗ No"}</div>
                  <div>Yours: {matchesConnected ? "✓ Yes" : "✗ No"}</div>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm mb-4">
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
                  <div className="flex items-center gap-2 mt-1">
                    <div className="text-xs font-mono break-all">
                      {petPoolId ? truncateString(petPoolId, 16, 12) : "—"}
                    </div>
                    {petPoolId && <CopyButton text={petPoolId} />}
                  </div>
                </div>
                <div>
                  <span className="font-semibold">Position ID:</span>
                  <div className="flex items-center gap-2 mt-1">
                    <div className="text-xs font-mono">
                      {petPositionId ? truncateString(petPositionId.toString(), 12, 10) : "—"}
                    </div>
                    {petPositionId && petPositionId !== 0n && <CopyButton text={petPositionId.toString()} />}
                  </div>
                </div>
              </div>
            </div>

            <div className="divider">Contract Addresses</div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-xs">
              <div>
                <div className="font-semibold mb-1">PetRegistry</div>
                {petRegistryAddress ? (
                  <Address address={petRegistryAddress as `0x${string}`} />
                ) : (
                  <span className="text-base-content/60">Not deployed</span>
                )}
              </div>
              <div>
                <div className="font-semibold mb-1">AutoLpHelper</div>
                {autoLpHelperAddress ? (
                  <Address address={autoLpHelperAddress as `0x${string}`} />
                ) : (
                  <span className="text-base-content/60">Not deployed</span>
                )}
              </div>
              <div>
                <div className="font-semibold mb-1">EggHatchHook</div>
                {eggHatchHookAddress ? (
                  <Address address={eggHatchHookAddress as `0x${string}`} />
                ) : (
                  <span className="text-base-content/60">Not deployed</span>
                )}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
