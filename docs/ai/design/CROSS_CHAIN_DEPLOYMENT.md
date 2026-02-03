# Cross-Chain Deployment Strategy

## Overview

Xolotrain allows users to travel their LP positions between chains:

- **Origin**: Sepolia (11155111)
- **Destination**: Base Sepolia (84532)
- **Mechanism**: Li.FI + The Compact (intent-based settlement)

## Critical Requirement: Deterministic Addresses

Since LP positions move between chains, contracts MUST deploy to the same address on all chains.

## CREATE2 Deployment Benefits

### Same Address Across Chains

Using CREATE2 with identical parameters:

- ✅ Same deployer account
- ✅ Same salt value
- ✅ Same constructor arguments

Results in **identical addresses** on all chains!

```
EggHatchHook:
- Sepolia:      0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2
- Base Sepolia: 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2
                ↑ SAME ADDRESS!
```

### Contracts That MUST Be Deterministic

1. **EggHatchHook** ⚡ CRITICAL

   - Part of Uniswap v4 PoolKey
   - Must be identical for pool key consistency
   - Use: `DeployEggHatchHookDeterministic.s.sol`

2. **PetRegistry** ⚡ CRITICAL

   - Tracks pets and their health across chains
   - Must be same address for cross-chain pet lookup
   - Use CREATE2 deployment

3. **XolotrainAllocator** (The Compact) ⚡ CRITICAL

   - Handles LP migration intents
   - Must be same address for intent validation
   - Use CREATE2 deployment

4. **LPMigrationArbiter** (Optional deterministic)
   - Could differ per chain, but simpler if same

### Contracts That CAN Differ

1. **AutoLpHelper**

   - Chain-specific pool configurations
   - Different mock tokens per chain
   - Can have different addresses

2. **Mock ERC20s** (Test tokens)
   - USDC/USDT addresses differ per chain anyway
   - These are just for testing

## Deployment Sequence

### Step 1: Deploy Core Contracts (Deterministic)

```bash
# On Sepolia
forge script script/DeployPetRegistryDeterministic.s.sol --rpc-url sepolia --broadcast

# On Base Sepolia
forge script script/DeployPetRegistryDeterministic.s.sol --rpc-url base-sepolia --broadcast

# Verify same address!
```

### Step 2: Deploy Hook (Deterministic)

```bash
# On Sepolia
forge script script/DeployEggHatchHookDeterministic.s.sol --rpc-url sepolia --broadcast

# On Base Sepolia
forge script script/DeployEggHatchHookDeterministic.s.sol --rpc-url base-sepolia --broadcast

# Verify same address!
```

### Step 3: Deploy Chain-Specific Contracts

```bash
# AutoLpHelper can differ per chain
# Different pool keys, different token addresses
forge script script/DeployAutoLpHelper.s.sol --rpc-url sepolia --broadcast
forge script script/DeployAutoLpHelper.s.sol --rpc-url base-sepolia --broadcast
```

## Configuration Management

### Per-Chain Pool Keys

Even with deterministic hook addresses, pool IDs differ per chain:

```json
{
  "11155111": {
    "poolManager": "0x...",
    "USDC_USDT": {
      "poolId": "0xabc...",
      "currency0": "0x...",
      "currency1": "0x...",
      "hooks": "0x742d35Cc..." // ← Same hook address
    }
  },
  "84532": {
    "poolManager": "0x...",
    "USDC_USDT": {
      "poolId": "0xdef...", // ← Different pool ID
      "currency0": "0x...", // ← Different token addresses
      "currency1": "0x...",
      "hooks": "0x742d35Cc..." // ← Same hook address!
    }
  }
}
```

## Testing Strategy

### Local Testing with Deterministic Addresses

```solidity
contract CrossChainTest is Test {
    // Simulate two chains
    uint256 sepoliaFork;
    uint256 baseFork;

    function setUp() public {
        sepoliaFork = vm.createFork("sepolia");
        baseFork = vm.createFork("base");

        // Deploy on Sepolia
        vm.selectFork(sepoliaFork);
        address hookSepolia = deployHookDeterministic();

        // Deploy on Base
        vm.selectFork(baseFork);
        address hookBase = deployHookDeterministic();

        // Verify same address!
        assertEq(hookSepolia, hookBase);
    }
}
```

## Salt Management

### Recommended Salts

```solidity
// PetRegistry
bytes32 public constant PET_REGISTRY_SALT = keccak256("PetRegistry.v1");

// EggHatchHook
bytes32 public constant EGG_HATCH_HOOK_SALT = keccak256("EggHatchHook.v1");

// XolotrainAllocator
bytes32 public constant ALLOCATOR_SALT = keccak256("XolotrainAllocator.v1");
```

### Version Upgrades

If you need to deploy a new version:

```solidity
// Change the salt to get a new address
bytes32 public constant EGG_HATCH_HOOK_SALT = keccak256("EggHatchHook.v2");
```

## Security Considerations

1. **Deployer Key Security**

   - Must use same deployer on all chains
   - Secure the deployer private key
   - Consider using a hardware wallet

2. **Salt Collision**

   - Different salts per contract type
   - Version salts if redeploying

3. **Constructor Args**
   - Pool IDs will differ per chain
   - Must pass correct chain-specific args
   - Verify addresses after deployment

## Frontend Configuration

With deterministic addresses, frontend config is simpler:

```typescript
// scaffold.config.ts
export const contracts = {
  PetRegistry: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2", // Same on all chains
  EggHatchHook: "0x123...", // Same on all chains

  // Chain-specific
  AutoLpHelper: {
    11155111: "0xABC...", // Sepolia
    84532: "0xDEF...", // Base Sepolia
  },
};
```

## Checklist Before Cross-Chain Deployment

- [ ] Same deployer account funded on all chains
- [ ] Consistent salts in deployment scripts
- [ ] Constructor args prepared per chain
- [ ] PetRegistry deployed deterministically
- [ ] EggHatchHook deployed deterministically
- [ ] Verify addresses match across chains
- [ ] Update frontend config
- [ ] Test cross-chain travel on testnet
