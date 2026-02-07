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
      <div className="min-h-screen flex items-center justify-center px-5 bg-primary">
        <div className="bg-primary rounded-3xl  max-w-xl w-full text-center p-8">
          <div className="flex flex-col items-center justify-center gap-6">
            <Image src="/logo.png" alt="Xolotrain logo" width={800} height={100} priority />
            <p className="text-base-content/80 font-della text-lg">
              An onchain virtual axolotl pet that lives, evolves, and travels across networks
            </p>
            <div className="pt-2">
              {/* Connect entrypoint (per INTERACTIONS.md) */}
              <RainbowKitCustomConnectButton />
            </div>
          </div>
        </div>
      </div>
    );
  }

  // 2) UNLOCKED: default screen (wallet connected)
  // Header shows wallet + balances; Footer shows LP bottom sheet.
  return (
    <div className="min-h-screen flex items-center justify-center px-5 pt-16 pb-28 bg-primary">
      <div className="w-full max-w-xl">
        <div className="bg-base-100 rounded-3xl p-6">
          <div className="flex flex-col items-center justify-center gap-6">
            {/* Placeholder main visual (swap with Axolotl component once wired) */}
            <div className="w-full flex items-center justify-center">
              <Image
                src="/egg2.svg"
                alt="Axolotl egg"
                width={256}
                height={256}
                className="rounded-3xl animate-egg-float"
                priority
              />
            </div>

            <button className="btn btn-neutral hover:btn-accent rounded-full px-10">Hatch your Pet</button>

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
