"use client";

import Image from "next/image";
import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";

const Home: NextPage = () => {
  const { isConnected } = useAccount();

  // 1) LOCKED: title screen (no wallet connected)
  if (!isConnected) {
    return (
      <div className="min-h-screen flex items-center justify-center px-5">
        <div className="bg-base-100 rounded-3xl shadow-lg shadow-secondary/20 max-w-xl w-full text-center p-8">
          <div className="flex flex-col items-center justify-center gap-6">
            <Image src="/logo.png" alt="Xolotrain logo" width={800} height={100} priority />
            <p className="text-base-content/80 font-della text-lg">
              An onchain virtual axolotl pet that lives, evolves, and travels across networks
            </p>
            <div className="pt-2">
              {/* Connect entrypoint (per INTERACTIONS.md) */}
              <RainbowKitCustomConnectButton />
            </div>
            <p className="text-sm text-base-content/60">
              Connect to hatch your first Axolotl by creating a USDC/USDT LP position.
            </p>
          </div>
        </div>
      </div>
    );
  }

  // 2) UNLOCKED: default screen (wallet connected)
  // Header shows wallet + balances; Footer shows LP bottom sheet.
  return (
    <div className="min-h-screen flex items-center justify-center px-5 pt-16 pb-28">
      <div className="w-full max-w-xl">
        <div className="bg-base-100 rounded-3xl shadow-lg shadow-secondary/20 p-6">
          <div className="flex flex-col items-center justify-center gap-6">
            {/* Placeholder main visual (swap with Axolotl component once wired) */}
            <div className="w-full flex items-center justify-center">
              <div className="w-64 h-64 rounded-3xl bg-base-200 flex items-center justify-center">
                <span className="text-base-content/60 font-della">Axolotl</span>
              </div>
            </div>

            <button className="btn btn-secondary rounded-full px-10">Get water</button>

            <p className="text-sm text-base-content/70 text-center">
              Next: Hatch your Axolotl by creating an LP position (AutoLpHelper → EggHatchHook → PetRegistry).
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
