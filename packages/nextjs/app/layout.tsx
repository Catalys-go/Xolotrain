import { Della_Respira, Federo } from "next/font/google";
import "@rainbow-me/rainbowkit/styles.css";
import "@scaffold-ui/components/styles.css";
import { ScaffoldEthAppWithProviders } from "~~/components/ScaffoldEthAppWithProviders";
import { ThemeProvider } from "~~/components/ThemeProvider";
import "~~/styles/globals.css";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

const fede = Federo({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-fede",
  display: "swap",
});

const della = Della_Respira({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-della",
  display: "swap",
});

export const metadata = getMetadata({
  title: "Scaffold-ETH 2 App",
  description: "Built with 🏗 Scaffold-ETH 2",
});

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return (
    <html suppressHydrationWarning className={`${fede.variable} ${della.variable}`}>
      <body className="relative overflow-x-hidden">
        <ThemeProvider enableSystem>
          <div
            className="parallax-bg animate-parallax-scroll pointer-events-none fixed inset-0 z-[-5]"
            aria-hidden="true"
          />
          <div className="train-bg animate-train-bump pointer-events-none fixed inset-0 -z-10" aria-hidden="true" />
          <ScaffoldEthAppWithProviders>{children}</ScaffoldEthAppWithProviders>
        </ThemeProvider>
      </body>
    </html>
  );
};

export default ScaffoldEthApp;
