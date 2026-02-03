# Hook Address Issue & Solutions

## Problem

In Uniswap v4, the **hook address is part of the PoolKey**:

```solidity
struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;  // ← Hook address is in the PoolKey!
}
```

When you deploy `EggHatchHook`, it gets a new address each time. This means:

- The PoolKey in your contracts won't match the actual pool
- AutoLpHelper will reference the wrong pool
- LP operations will fail

## Current Situation

```
Deployment 1:
EggHatchHook deployed to: 0xABCD...
PoolKey.hooks = 0xABCD...  ✅ Matches

Deployment 2:
EggHatchHook deployed to: 0x1234...  ← NEW ADDRESS!
PoolKey.hooks = 0xABCD...  ❌ Doesn't match anymore
```

## Solution Options

### ✅ Option 1: CREATE2 Deterministic Deployment (RECOMMENDED)

Deploy the hook to the **same address every time** using CREATE2 with a consistent salt.

**Pros:**

- Hook address never changes
- Pool keys remain valid
- Clean, professional solution
- No contract modifications needed

**Cons:**

- Must use same deployer address
- Can't deploy twice with same parameters

**Implementation:**

```solidity
// Use the new script
EggHatchHook hook = new EggHatchHook{salt: DEPLOYMENT_SALT}(
    poolManager,
    petRegistryAddr,
    poolId
);
```

File created: `script/DeployEggHatchHookDeterministic.s.sol`

### Option 2: Update Hook After Deployment

Modify AutoLpHelper to have updatable pool keys.

**Pros:**

- Flexible for testing

**Cons:**

- Gas cost to update
- Centralization risk
- Less professional
- Need admin access

**Implementation:**

```solidity
// In AutoLpHelper.sol
function updatePoolKeys(
    PoolKey memory _ethUsdcPoolKey,
    PoolKey memory _ethUsdtPoolKey,
    PoolKey memory _usdcUsdtPoolKey
) external onlyOwner {
    ethUsdcPoolKey = _ethUsdcPoolKey;
    ethUsdtPoolKey = _ethUsdtPoolKey;
    usdcUsdtPoolKey = _usdcUsdtPoolKey;
}
```

### Option 3: No Hook in Pool Keys

Don't use hooks for the swap pools (ETH/USDC, ETH/USDT).
Only use hooks for the USDC/USDT pool where you want to trigger pet hatching.

**Pros:**

- Simpler
- Less gas

**Cons:**

- Can't trigger hooks on ETH swaps
- Loses some functionality

## Recommended Approach

**Use Option 1 (CREATE2)** because:

1. ✅ Professional and clean
2. ✅ No contract modifications needed
3. ✅ Works across all deployments
4. ✅ Standard practice in DeFi
5. ✅ **CRITICAL FOR CROSS-CHAIN: Same hook address on ALL chains!**

### Why CREATE2 is Perfect for Cross-Chain Travel

When users travel their LP positions between chains (Sepolia ↔ Base Sepolia):

**With CREATE2:**

- ✅ EggHatchHook deploys to **same address** on all chains
- ✅ Pool keys remain consistent across chains
- ✅ No need to reconfigure when moving chains
- ✅ Simpler PetRegistry tracking (same hook address everywhere)
- ✅ Frontend only needs one hook address in config

**Without CREATE2:**

- ❌ Different hook addresses per chain (0xABCD on Sepolia, 0x1234 on Base)
- ❌ Must track which hook address goes with which chain
- ❌ More complex pool key management
- ❌ Risk of using wrong hook address when traveling

### Cross-Chain Deployment Strategy

```solidity
// Same deployer account + Same salt + Same constructor args
// = Same address on all chains!

// Sepolia:     EggHatchHook @ 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2
// Base Sepolia: EggHatchHook @ 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2
//               ↑ SAME ADDRESS!
```

## Implementation Steps

1. **Use the deterministic deployment script:**

   ```bash
   forge script script/DeployEggHatchHookDeterministic.s.sol:DeployEggHatchHookDeterministic --rpc-url $RPC_URL --broadcast
   ```

2. **The hook will deploy to the same address every time**

3. **Use that address in your PoolKeys when deploying AutoLpHelper**

## Notes for Testing

In tests, you can either:

- Use CREATE2 in setUp() for consistency
- Mock the pool manager to accept any hook address
- Deploy hook first, then create pool keys with the actual address

## Current Test Status

✅ All unit tests passing (31/31)

- Tests now properly encode hookData with tick values
- Events match actual contract events
- Error selectors properly encoded
