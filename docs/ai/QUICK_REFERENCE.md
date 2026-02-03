# Xolotrain Quick Reference Card

## 🎯 Elevator Pitch (30 seconds)

"**Xolotrain** is a DeFi Tamagotchi where your pet's health reflects your Uniswap v4 LP performance. Travel cross-chain in one click using Li.FI Composer. An agent monitors your LP 24/7 and updates health deterministically. Learn DeFi by keeping your axolotl alive!"

---

## 🏆 Bounties We're Targeting

| Bounty         | What We Built              | Key Feature                                     |
| -------------- | -------------------------- | ----------------------------------------------- |
| **Li.FI**      | Cross-chain LP migration   | Solver uses Li.FI Composer for optimal bridging |
| **Uniswap v4** | Agent-driven health system | Deterministic monitoring + custom hooks         |

---

## 📦 Architecture in 3 Lines

1. **User**: Signs travel intent → LP closed, assets locked in The Compact
2. **Solver**: Uses Li.FI to bridge → Creates LP on destination → Claims locked assets
3. **Agent**: Monitors LP position → Calculates health → Updates pet state

---

## 🔑 Key Contracts

| Contract             | Purpose                                   | Key Function                                    |
| -------------------- | ----------------------------------------- | ----------------------------------------------- |
| `AutoLpHelper`       | Atomic ETH → LP creation + travel intents | `swapEthToUsdcUsdtAndMint()`, `travelToChain()` |
| `EggHatchHook`       | Uniswap v4 hook for pet minting           | `afterAddLiquidity()`                           |
| `PetRegistry`        | Pet NFT storage + metadata                | `hatchFromHook()`, `updateHealth()`             |
| `XolotrainAllocator` | The Compact allocator                     | `attest()`, `authorizeClaim()`                  |
| `LPMigrationArbiter` | Verifies LP on destination                | `verifyAndClaim()`                              |

---

## 🤖 Agent Components

| Service      | Purpose                 | Key Tech                                 |
| ------------ | ----------------------- | ---------------------------------------- |
| `lifi.ts`    | Li.FI SDK wrapper       | `@lifi/sdk` for optimal routing          |
| `solver.ts`  | Fulfills travel intents | The Compact + Li.FI integration          |
| `health.ts`  | Monitors LP health      | `StateLibrary.getSlot0()` for pool state |
| `monitor.ts` | Event listening         | Ethers.js event filters                  |

---

## 🎬 Demo Flow (3 minutes)

```
1. HATCH (45s)
   → Input 0.1 ETH
   → AutoLpHelper creates LP
   → EggHatchHook mints pet NFT
   → Axolotl appears healthy

2. MONITOR (30s)
   → Show health bar
   → Explain agent logic
   → Highlight deterministic formula

3. TRAVEL (60s)
   → Click "Travel to Base"
   → Sign intent (1 signature)
   → Show solver using Li.FI (logs)
   → LP appears on Base
   → Axolotl arrives!

4. TECH (40s)
   → Uniswap v4: Hooks + IPoolManager
   → Li.FI: Composer for bridging
   → The Compact: Intent settlement
   → Agent: Deterministic monitoring

5. CLOSE (15s)
   → Educational + fun
   → Built for agents
   → Thank you!
```

---

## ✅ Pre-Demo Checklist

**Contracts**:

- [ ] Deployed on Sepolia + Base Sepolia
- [ ] All addresses in config files
- [ ] Verified on Etherscan

**Agent**:

- [ ] Solver bot running
- [ ] Health monitor running
- [ ] Li.FI API key configured
- [ ] Sufficient testnet funds

**Frontend**:

- [ ] Deployed on Vercel
- [ ] Connected to testnets
- [ ] RainbowKit working
- [ ] Animations smooth

**Demo Materials**:

- [ ] Video recorded (max 3 min)
- [ ] GitHub repo public
- [ ] README complete
- [ ] TxIDs documented

---

## 🚨 Troubleshooting

### Issue: Li.FI route not found

**Fix**: Check chain support with `lifi.getConnections()`, ensure sufficient liquidity

### Issue: Solver not fulfilling intent

**Fix**: Check profitability calculation, verify solver has testnet funds

### Issue: Health not updating

**Fix**: Verify agent is running, check RPC connection, confirm gas funds

### Issue: Hook not firing

**Fix**: Confirm hook address in pool initialization, check hook flags

---

## 📊 Key Numbers to Memorize

- **Traditional bridging**: 6 transactions, 30 minutes
- **With Xolotrain**: 1 signature, 2-5 minutes
- **Health formula**: `100 - (tickDistance × 2)`
- **Chains supported**: 2 (Sepolia ↔ Base Sepolia)
- **LP pools**: USDC/USDT on Uniswap v4

---

## 💬 Talking Points

**For judges unfamiliar with intents**:

> "Instead of manually bridging, the user just says 'I want my LP on Base.' A solver bot fulfills that intent using Li.FI to find the best route. The user signs once and is done."

**For judges questioning agent reliability**:

> "Our health formula is 100% deterministic: `health = f(currentTick, tickLower, tickUpper)`. Anyone can verify the agent's calculations off-chain. It's transparent and trustless."

**For judges asking 'why gamification?'**:

> "DeFi is intimidating. By turning LP management into a pet care game, we make it approachable. Users learn by doing, and the axolotl provides instant visual feedback on their position health."

---

## 🎯 Bounty Qualification Proofs

### Li.FI Bounty

**Requirement**: Use Li.FI SDK for cross-chain action  
**Proof**: `agent/solver.ts` lines 45-60, `lifi.getRoutes()` call

**Requirement**: Support 2+ chains  
**Proof**: Sepolia (11155111) ↔ Base Sepolia (84532) in config

**Requirement**: Working frontend  
**Proof**: Live demo at [vercel-url], video walkthrough

### Uniswap Bounty

**Requirement**: Build on v4  
**Proof**: `AutoLpHelper.sol` uses `IPoolManager`, `EggHatchHook.sol` implements hooks

**Requirement**: Agent-driven  
**Proof**: `agent/health.ts` monitors pools, calculates health, updates on-chain

**Requirement**: Hooks used meaningfully  
**Proof**: `EggHatchHook` triggers pet minting on LP creation

**Requirement**: TxIDs  
**Proof**: [sepolia-tx], [base-tx] in README

---

## 📚 Documentation Quick Links

- **GAME_DESIGN.md** - User experience and game mechanics
- **SYSTEM_ARCHITECTURE.md** - Technical architecture and flows
- **LIFI_INTEGRATION_GUIDE.md** - How to integrate Li.FI SDK
- **6_DAY_TIMELINE.md** - Day-by-day development plan
- **BOUNTY_STRATEGY.md** - Dual bounty approach details

---

## 🔗 Important Addresses

### Mainnet/Testnet Deployments

```
Uniswap v4 PoolManager:   0x000000000004444c5dc75cB358380D2e3dE08A90
Uniswap v4 PositionMgr:   0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e
The Compact:               0x00000000000000171ede64904551eeDF3C6C9788
```

### Your Contracts (Fill in after deploy)

```
AutoLpHelper (Sepolia):    [YOUR_ADDRESS]
AutoLpHelper (Base):       [YOUR_ADDRESS]
EggHatchHook (Sepolia):    [YOUR_ADDRESS]
PetRegistry (Sepolia):     [YOUR_ADDRESS]
XolotrainAllocator:        [YOUR_ADDRESS]
LPMigrationArbiter:        [YOUR_ADDRESS]
```

---

## 🎤 One-Liner Responses

**"What makes this different from other DeFi games?"**

> "We're not play-to-earn. We're learn-by-doing. Your pet's health directly reflects real LP performance on Uniswap v4."

**"Why use intents instead of direct bridging?"**

> "Better UX. One signature vs six transactions. The solver handles complexity using Li.FI for optimal routing."

**"How do you ensure agent reliability?"**

> "Deterministic formula. Same inputs always produce same outputs. Users can verify calculations independently."

**"What's the educational value?"**

> "Users learn: LP range management, impermanent loss, fee generation, cross-chain bridging - all through keeping their pet healthy."

---

## 🎊 Good Luck!

**Remember**: You're solving a real problem (complex cross-chain LP management) with innovative tech (intents + Li.FI + v4 hooks) in an approachable way (gamification).

**Your story**: "Making DeFi educational, one axolotl at a time! 🐸"
