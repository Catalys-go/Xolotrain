"use client";

import React, { useMemo, useState } from "react";
import { hardhat } from "viem/chains";
import { useAccount } from "wagmi";
import { ChevronUpIcon } from "@heroicons/react/24/outline";
import { SwitchTheme } from "~~/components/SwitchTheme";
import { Faucet } from "~~/components/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";

/**
 * Footer: LP bottom sheet.
 * - Hidden on LOCKED screen.
 * - On UNLOCKED screen, shows a collapsed "Axo LP" tab.
 * - Expands upward to reveal LP details (wire to on-chain reads next).
 */
export const Footer = () => {
  const { isConnected } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const isLocalNetwork = targetNetwork.id === hardhat.id;

  // Per docs: LP details depend on PetRegistry + PoolManager position reads.
  // For now, we display a coherent placeholder panel.
  const [open, setOpen] = useState(false);

  const sheetClass = useMemo(() => {
    // leave a tab visible when closed
    return open ? "translate-y-0" : "translate-y-[calc(100%-64px)]";
  }, [open]);

  if (!isConnected) return null;

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
            <div className="flex items-center justify-between gap-4 pb-4">
              <div className="text-sm ">
                LP position details (Uniswap v4 USDC/USDT) — expands from bottom per main-screen spec.
              </div>
              <div className="flex items-center gap-2">
                {isLocalNetwork && <Faucet />}
                <SwitchTheme className="" />
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div className="bg-base-200 rounded-2xl p-4">
                <div className="text-xs text-base-content/60">Status</div>
                <div className="mt-1 text-sm text-base-content">—</div>
                <div className="mt-3 text-xs text-base-content/60">In range</div>
                <div className="mt-1 text-sm text-base-content">—</div>
              </div>
              <div className="bg-base-200 rounded-2xl p-4">
                <div className="text-xs text-base-content/60">Liquidity</div>
                <div className="mt-1 text-sm text-base-content">—</div>
                <div className="mt-3 text-xs text-base-content/60">Fees earned</div>
                <div className="mt-1 text-sm text-base-content">—</div>
              </div>
              <div className="bg-base-200 rounded-2xl p-4">
                <div className="text-xs text-base-content/60">Range</div>
                <div className="mt-1 text-sm text-base-content">—</div>
                <div className="mt-3 text-xs text-base-content/60">Pet health</div>
                <div className="mt-1 text-sm text-base-content">—</div>
              </div>
            </div>

            <div className="mt-5 text-xs text-base-content/60">
              Next wiring step: read PetRegistry.getPetsByOwner(address) → positionId → PoolManager position state;
              compute health deterministically as described in INTERACTIONS.md / SYSTEM_ARCHITECTURE.md.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
