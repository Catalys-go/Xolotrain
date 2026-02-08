"use client";

import React, { useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { ChevronUpIcon } from "@heroicons/react/24/outline";
import { LpPositionTracker } from "~~/components/LpPositionTracker";
//import { SwitchTheme } from "~~/components/SwitchTheme";
//import { Faucet } from "~~/components/scaffold-eth";
import { useDeployedContractInfo, useScaffoldReadContract } from "~~/hooks/scaffold-eth";

/**
 * Footer: LP bottom sheet.
 * - Hidden on LOCKED screen.
 * - On UNLOCKED screen, shows a collapsed "Axo LP" tab.
 * - Expands upward to reveal LP details (wire to on-chain reads next).
 */
export const Footer = () => {
  const { isConnected, address: connectedAddress } = useAccount();

  // PetRegistry contract info and reads (mirror Liquidity page)
  const { data: petRegistry } = useDeployedContractInfo({ contractName: "PetRegistry" });

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

  // Sheet open state: user-controlled (collapsed by default)
  const [open, setOpen] = useState(false);

  const sheetClass = useMemo(() => {
    // leave a tab visible when closed
    return open ? "translate-y-0" : "translate-y-[calc(100%-64px)]";
  }, [open]);

  if (!isConnected) return null;
  if (!hasFirstPet && !hasLpPositions) return null;

  return (
    <div className="fixed bottom-0 left-0 right-0 z-30 pointer-events-none">
      <div
        className={
          "pointer-events-auto mx-auto max-w-3xl px-4 transition-transform duration-300 ease-out " + sheetClass
        }
      >
        <div className="bg-accent text-primary rounded-t-3xl shadow-2xl shadow-secondary/30 border border-base-200">
          {/* Tab */}
          <button
            type="button"
            onClick={() => setOpen(v => !v)}
            className="w-full flex items-center justify-center gap-2 py-4"
            aria-expanded={open}
            aria-controls="lp-bottom-sheet"
          >
            <span className="font-della">Axo LP</span>
            <ChevronUpIcon className={"h-5 w-5 transition-transform " + (open ? "rotate-180" : "rotate-0")} />
          </button>

          {/* Content */}
          <div id="lp-bottom-sheet" className="px-5 pb-6">
            <div className="mt-2">
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
          </div>
        </div>
      </div>
    </div>
  );
};
