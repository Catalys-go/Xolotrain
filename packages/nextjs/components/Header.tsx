"use client";

import React, { useRef } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { formatUnits, zeroAddress } from "viem";
import { hardhat } from "viem/chains";
import { useAccount, useBalance } from "wagmi";
import { Bars3Icon, BugAntIcon } from "@heroicons/react/24/outline";
import { FaucetButton, RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";
import { useOutsideClick, useTargetNetwork } from "~~/hooks/scaffold-eth";

type HeaderMenuLink = {
  label: string;
  href: string;
  icon?: React.ReactNode;
};

export const menuLinks: HeaderMenuLink[] = [
  {
    label: "Home",
    href: "/",
  },
  {
    label: "Debug Contracts",
    href: "/debug",
    icon: <BugAntIcon className="h-4 w-4" />,
  },
  {
    label: "View LP",
    href: "/liquidity",
  },
];

export const HeaderMenuLinks = () => {
  const pathname = usePathname();

  return (
    <>
      {menuLinks.map(({ label, href, icon }) => {
        const isActive = pathname === href;
        return (
          <li key={href}>
            <Link
              href={href}
              passHref
              className={`${
                isActive ? "bg-primary shadow-md text-white" : ""
              } hover:bg-primary hover:text-white hover:shadow-md focus:!bg-secondary active:!text-neutral py-1.5 px-3 text-sm rounded-full gap-2 grid grid-flow-col text-primary items-center transition-colors`}
            >
              {icon}
              <span>{label}</span>
            </Link>
          </li>
        );
      })}
    </>
  );
};

/**
 * Site header
 */
export const Header = () => {
  const { address, isConnected } = useAccount();

  const { targetNetwork } = useTargetNetwork();
  const isLocalNetwork = targetNetwork.id === hardhat.id;

  const usdcAddress = process.env.NEXT_PUBLIC_USDC_ADDRESS as `0x${string}` | undefined;
  const usdtAddress = process.env.NEXT_PUBLIC_USDT_ADDRESS as `0x${string}` | undefined;

  const safeAddress = (address ?? zeroAddress) as `0x${string}`;

  const { data: ethBal } = useBalance({
    address: safeAddress,
    query: { enabled: Boolean(isConnected && address) },
  });

  const { data: usdcBal } = useBalance({
    address: safeAddress,
    token: usdcAddress,
    query: { enabled: Boolean(isConnected && address && usdcAddress) },
  });

  const { data: usdtBal } = useBalance({
    address: safeAddress,
    token: usdtAddress,
    query: { enabled: Boolean(isConnected && address && usdtAddress) },
  });

  const fmt = (val?: bigint, decimals?: number) => {
    if (val === undefined || decimals === undefined) return "—";
    const n = Number(formatUnits(val, decimals));
    if (!Number.isFinite(n)) return "—";
    // compact: 6 decimals max, trim visually
    return n >= 1000 ? n.toFixed(0) : n >= 10 ? n.toFixed(2) : n.toFixed(3);
  };

  const burgerMenuRef = useRef<HTMLDetailsElement>(null);
  useOutsideClick(burgerMenuRef, () => {
    burgerMenuRef?.current?.removeAttribute("open");
  });

  if (!isConnected) return null;

  return (
    <div className="sticky lg:static top-0 navbar bg-accent min-h-0 shrink-0 justify-between z-20 px-0 sm:px-2">
      <div className="navbar-start w-auto lg:w-1/2">
        <details className="dropdown" ref={burgerMenuRef}>
          <summary className="ml-1 btn btn-ghost lg:hidden hover:bg-transparent">
            <Bars3Icon className="h-1/2" />
          </summary>
          <ul
            className="menu menu-compact dropdown-content mt-3 p-2 shadow-sm bg-primary rounded-box w-52 text-primary"
            onClick={() => {
              burgerMenuRef?.current?.removeAttribute("open");
            }}
          >
            <HeaderMenuLinks />
          </ul>
        </details>
        <Link href="/" passHref className="hidden lg:flex items-center gap-2 ml-4 mr-6 shrink-0">
          <div className="flex relative w-12 h-12">
            <Image alt="Xolotrain logo" className="cursor-pointer" fill src="/logo.svg" />
          </div>
          <div className="flex flex-col text-primary text-xl">
            <span className="font-bold leading-tight">XOLOTRAIN</span>
          </div>
        </Link>
        <ul className="hidden lg:flex lg:flex-nowrap menu menu-horizontal px-1 gap-2">
          <HeaderMenuLinks />
        </ul>
      </div>
      <div className="navbar-end grow mr-4 flex items-center justify-end gap-3">
        {/* Wallet HUD (balances). Token balances require NEXT_PUBLIC_USDC_ADDRESS / NEXT_PUBLIC_USDT_ADDRESS */}
        <div className="hidden md:flex items-center gap-2 bg-base-200 rounded-full px-3 py-2">
          <div className="text-xs font-medium text-base-content/70">USDT</div>
          <div className="text-xs text-base-content">{fmt(usdtBal?.value, usdtBal?.decimals)}</div>
          <div className="mx-1 h-4 w-px bg-base-300" />
          <div className="text-xs font-medium text-base-content/70">ETH</div>
          <div className="text-xs text-base-content">{fmt(ethBal?.value, ethBal?.decimals)}</div>
          <div className="mx-1 h-4 w-px bg-base-300" />
          <div className="text-xs font-medium text-base-content/70">USDC</div>
          <div className="text-xs text-base-content">{fmt(usdcBal?.value, usdcBal?.decimals)}</div>
        </div>

        <RainbowKitCustomConnectButton />
        {isLocalNetwork && <FaucetButton />}
      </div>
    </div>
  );
};
