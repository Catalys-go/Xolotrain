# Xolotrain Deployment Guide

## Why Special Deployment?

Xolotrain uses **Uniswap v4 hooks** where:

- Hook address encodes permission bits (which functions are called)
- Hook address is part of the pool's unique identifier (PoolKey)
- **Any change to EggHatchHook.sol requires complete redeployment**

## Quick Start (Automated)

Use the unified deployment script that handles everything:

```bash
cd packages/foundry

# Deploy everything (mines hook address automatically)
yarn deploy --rpc-url http://127.0.0.1:8545 # --keystore my-account  Optional flag to add your account as the deployer address

# Update poolKeys.json with the hook address from output
# Edit: addresses/poolKeys.json -> USDC_USDT.hooks = <mined_address>

# Set agent address (get from output or use your agent wallet once agent is created)
cast send <PET_REGISTRY_ADDRESS> "setAgent(address)" <YOUR_AGENT_ADDRESS> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <YOUR_KEY>

# Generate frontend ABIs
node scripts-js/generateTsAbis.js

# Test on Forks
cast send <AUTO_LP_HELPER_ADDRESS> "swapEthToUsdcUsdtAndMint(uint128,uint128)" \
  1000000 1000000 \
  --value 0.001ether \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <YOUR_KEY> 
  # or 
  # --keystore <PATH>
  # Use the keystore in the given folder or file
  # [env: ETH_KEYSTORE=]

  # --account <ACCOUNT_NAME>
  # Use a keystore from the default keystores folder (~/.foundry/keystores) by its filename  
  # [env: ETH_KEYSTORE_ACCOUNT=]
```

**That's it!** The script handles:

- ✅ PetRegistry deployment
- ✅ Hook address mining
- ✅ EggHatchHook deployment with correct salt
- ✅ AutoLpHelper deployment
- ✅ Contract connections (setHook, setPetRegistry)
- ✅ Pool initialization

---

## Manual Deployment (Step-by-Step)

If you need more control or want to understand each step:

### Prerequisites

Ensure `addresses/poolKeys.json` has correct addresses for your chain:

```json
{
  "31337": {
    "poolManager": "0x000000000004444c5dc75cB358380D2e3dE08A90",
    "positionManager": "0x...",
    "ETH_USDC": { "token0": "0x...", ... },
    "ETH_USDT": { "token0": "0x...", ... },
    "USDC_USDT": { "token0": "0x...", "hooks": "0x0000..." }
  }
}
```

### Step 1: Mine Hook Address Manually (Optional)

If you want to mine the hook address separately (need an existing contract address for PetRegistry):

```bash
# Parameters: <poolManager> <petRegistry> <chainId>
# Note: You should have an existing PetRegistry cotract address to use as the second parameter and paste in for script usage
forge script script/MineHookAddress.s.sol \
  --sig "run(address,address,uint256)" \
  0x000000000004444c5dc75cB358380D2e3dE08A90 \
  0x0000000000000000000000000000000000000001 \
  31337 \
  --rpc-url http://127.0.0.1:8545

# Save the salt and hook address from output
```

### Step 2: Deploy Contracts

```bash
# Uses DeployAll.s.sol (recommended) or Deploy.s.sol
forge script script/DeployAll.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key <YOUR_KEY>
```

### Step 3: Post-Deployment Configuration

```bash
# Set agent (for health monitoring)
cast send <PET_REGISTRY> "setAgent(address)" <AGENT_ADDRESS> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <YOUR_KEY>

# Add liquidity to swap pools
forge script script/AddInitialLiquidity.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

# Generate frontend ABIs
node scripts-js/generateTsAbis.js
```

---

## Deployment Checklist

**Automated (DeployAll.s.sol):**

- [ ] Ensure poolKeys.json has correct poolManager, positionManager, token addresses
- [ ] Run `yarn deploy`
- [ ] Update poolKeys.json USDC_USDT.hooks with mined address from output
- [ ] Set agent address with `cast send`
- [ ] Add initial liquidity
- [ ] Generate frontend ABIs with `node scripts-js/generateTsAbis.js`
- [ ] Test with 0.001 ETH

**Manual:**

- [ ] (Optional) Mine hook address separately with MineHookAddress.s.sol
- [ ] Deploy PetRegistry first (or use DeployAll)
- [ ] Deploy EggHatchHook with mined salt
- [ ] Verify hook address matches mined output
- [ ] Initialize pools (USDC/USDT)
- [ ] Deploy AutoLpHelper
- [ ] Connect contracts (setHook, setPetRegistry, setAgent)
- [ ] Add liquidity to swap pools
- [ ] Generate frontend ABIs
- [ ] Test with 0.001 ETH

---

## Understanding the Files

**CREATE2_DEPLOYER**

The CREATE2_DEPLOYER is the address that will deploy the hook contract:

- **In forge test**: Uses test contract address (`this`) or the pranking address `vm.prank(myAddress)`
- **In forge script**: Use `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy - standard across most chains)
- **Alternative**: Could use scaffold-eth deployer account (the broadcasting account (`--account` or `--keystore`), `msg.sender`)

Our deployment scripts use the CREATE2 Deployer Proxy for deterministic addresses across chains. If you want to use your scaffold-eth deployer as the CREATE2_DEPLOYER instead, you would need to modify the `CREATE2_DEPLOYER` constant in the scripts, but note that this would make hook addresses different on each chain unless you use the same deployer account everywhere.

---

**poolKeys.json**: Pool configuration for each chain

- `poolManager`: Uniswap v4 PoolManager address
- `positionManager`: Uniswap v4 PositionManager address
- `ETH_USDC`, `ETH_USDT`: Existing pools (no hooks)
- `USDC_USDT`: Our LP pool (uses EggHatchHook)

**Deploy Scripts**:

- `DeployAll.s.sol`: ⭐ **Recommended** - Automated deployment with hook mining
- `Deploy.s.sol`: Manual deployment (requires pre-mined salt)
- `MineHookAddress.s.sol`: Standalone hook address mining
- `AddInitialLiquidity.s.sol`: Add liquidity to ETH/USDC and ETH/USDT pools

**Deployment Output**:

- `deployments/<chainId>.json`: Contract addresses and ABIs
- Console output shows: PetRegistry address, mined hook address + salt, AutoLpHelper address

---

## Common Issues

**`InvalidHookResponse()`**

- Cause: Hook implementation doesn't match permission bits
- Fix: Remove unused hook functions, re-mine address, redeploy

**`PoolNotInitialized()`**

- Cause: Pool doesn't exist
- Fix: Run `forge script script/Deploy.s.sol --broadcast`

**Hook address mismatch**

- Cause: poolKeys.json has wrong hook address
- Fix: Update poolKeys.json, redeploy AutoLpHelper, run `yarn generate`

**Swap reverts**

- Cause: No liquidity in ETH/USDC or ETH/USDT pools
- Fix: Run AddInitialLiquidity script
