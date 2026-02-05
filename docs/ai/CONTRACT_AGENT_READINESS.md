# Contract Readiness for Agent System

## 📋 Executive Summary

This document assesses whether our smart contracts are ready to support the unified agent system (health monitoring + intent fulfillment).

**Status**: ⚠️ **Partially Ready** - Health monitoring is ready, but intent fulfillment requires significant additions.

---

## ✅ What's Ready (Health Monitoring)

### PetRegistry.sol - READY ✅

**Agent Requirements**:

- ✅ `updateHealth(petId, health, chainId)` - Agent can update health
- ✅ `HealthUpdated` event - Frontend can listen for updates
- ✅ `setAgent(address)` - Owner can authorize agent address
- ✅ `getActivePetId(owner)` - Agent can query active pets
- ✅ `getPet(petId)` - Agent can read pet state
- ✅ Agent authorization check (currently commented for testing)

**Current Implementation**:

```solidity
function updateHealth(uint256 petId, uint256 health, uint256 chainId) external {
    // TODO: Re-enable when agent system is implemented
    // if (msg.sender != agent) revert NotAgent(msg.sender);
    if (health > 100) revert InvalidHealth(health);

    Pet storage p = pets[petId];
    if (p.owner == address(0)) revert PetNotFound(petId);

    p.health = health;
    p.lastUpdate = block.timestamp;
    p.chainId = chainId;

    emit HealthUpdated(petId, health, chainId);
}
```

**Action Required**:

- Uncomment `onlyAgent` check once agent is deployed
- Deploy and call `setAgent(agentAddress)`

---

### EggHatchHook.sol - READY ✅

**Agent Requirements**:

- ✅ `afterAddLiquidity()` hook triggers `PetRegistry.hatchFromHook()`
- ✅ Decodes hookData: `(address owner, uint256 positionId, int24 tickLower, int24 tickUpper)`
- ✅ Validates owner and positionId
- ✅ Works with AutoLpHelper's current implementation

**Current Implementation**:

```solidity
function afterAddLiquidity(
    address,
    PoolKey calldata key,
    ModifyLiquidityParams calldata,
    BalanceDelta,
    BalanceDelta,
    bytes calldata hookData
) external returns (bytes4, BalanceDelta) {
    if (msg.sender != POOL_MANAGER) revert OnlyPoolManager(msg.sender);

    bytes32 poolId = PoolId.unwrap(key.toId());
    (address owner, uint256 positionId,,) = abi.decode(hookData, (address, uint256, int24, int24));

    if (owner == address(0)) revert InvalidOwner();
    if (positionId == 0) revert InvalidPositionId();

    REGISTRY.hatchFromHook(owner, block.chainid, poolId, positionId);

    return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
}
```

**No Action Required** - Ready for agent monitoring.

---

### AutoLpHelper.sol - PARTIALLY READY ⚠️

**What's Ready**:

- ✅ `swapEthToUsdcUsdtAndMint()` - Users can hatch axolotls
- ✅ `LiquidityAdded` event - Agent can monitor new positions
- ✅ Atomic ETH → USDC/USDT → LP flow works correctly
- ✅ hookData encoding includes owner and positionId

**Current Implementation**:

```solidity
function swapEthToUsdcUsdtAndMint(uint128 minUsdcOut, uint128 minUsdtOut)
    external
    payable
    returns (uint128 liquidity)
{
    // Creates LP position, emits LiquidityAdded event
    // hookData contains: (owner, positionId, tickLower, tickUpper)
}
```

**Agent Can**:

- Monitor `LiquidityAdded` events to track new pets
- Read LP position details from event data

---

## ❌ What's Missing (Intent Fulfillment)

### AutoLpHelper.sol - NEEDS ADDITIONS ❌

**Missing Functions**:

#### 1. `mintLpFromTokens()` - CRITICAL ❌

**Purpose**: Solver creates LP from pre-bridged USDC/USDT (no ETH swap needed)

**Required Signature**:

```solidity
function mintLpFromTokens(
    uint128 usdcAmount,
    uint128 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    address recipient
) external returns (uint256 positionId);
```

**Why Needed**:

- After Li.FI bridges USDC/USDT to destination, solver needs to create LP
- Current `swapEthToUsdcUsdtAndMint()` only works with ETH input
- Solver has tokens, not ETH

**Implementation Strategy**:

```solidity
function mintLpFromTokens(
    uint128 usdcAmount,
    uint128 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    address recipient
) external returns (uint256 positionId) {
    // 1. Transfer USDC/USDT from solver to this contract
    IERC20(Currency.unwrap(usdcUsdtPoolKey.currency0)).transferFrom(msg.sender, address(this), usdcAmount);
    IERC20(Currency.unwrap(usdcUsdtPoolKey.currency1)).transferFrom(msg.sender, address(this), usdtAmount);

    // 2. Create position via unlock callback (no swaps, just LP mint)
    // 3. Encode hookData with recipient address
    // 4. Emit LiquidityAdded event
    // 5. Return positionId for arbiter verification
}
```

---

#### 2. `travelToChain()` - CRITICAL for Intent Creation ❌

**Purpose**: User initiates cross-chain travel intent

**Required Signature**:

```solidity
function travelToChain(
    uint256 petId,
    uint256 destinationChainId,
    int24 tickLower,
    int24 tickUpper
) external returns (bytes32 compactId);
```

**Why Needed**:

- User needs to close LP on source chain
- Deposit assets into The Compact
- Emit `IntentCreated` event for solver to detect

**Implementation Strategy**:

```solidity
function travelToChain(
    uint256 petId,
    uint256 destinationChainId,
    int24 tickLower,
    int24 tickUpper
) external returns (bytes32 compactId) {
    // 1. Verify msg.sender owns the pet (read from PetRegistry)
    // 2. Close existing LP position → get USDC/USDT amounts
    // 3. Approve The Compact to spend USDC/USDT
    // 4. Call TheCompact.registerMultichainIntent(...)
    // 5. Emit IntentCreated event
    // 6. Return compactId for tracking
}
```

**Alternative**: Could split into two separate contracts:

- `AutoLpHelper` - Just LP creation
- `TravelManager` - Intent creation + The Compact integration

---

#### 3. Missing Events ❌

**Required Events**:

```solidity
event IntentCreated(
    bytes32 indexed compactId,
    uint256 indexed petId,
    address indexed user,
    uint256 sourceChainId,
    uint256 destinationChainId,
    uint128 usdcAmount,
    uint128 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    uint256 timestamp
);

event LPCreatedFromIntent(
    bytes32 indexed compactId,
    uint256 indexed positionId,
    address indexed solver,
    uint256 chainId,
    uint128 liquidity,
    uint256 timestamp
);
```

---

### The Compact Integration - NOT STARTED ❌

**Missing Contracts**:

#### 1. XolotrainAllocator.sol ❌

**Purpose**: Prevents double-spending of locked assets

**Interface**:

```solidity
interface IAllocator {
    function attest(
        address allocator,
        bytes32 claimHash,
        address claimant,
        bytes calldata data
    ) external returns (bytes4);
}
```

#### 2. LPMigrationArbiter.sol ❌

**Purpose**: Verifies LP creation before releasing payment to solver

**Required Functions**:

```solidity
function verifyAndClaim(
    uint256 positionId,
    bytes32 compactId,
    address solver
) external;
```

**Verification Steps**:

1. Read LP position from IPoolManager on destination chain
2. Verify position exists and matches intent specs (liquidity, tick range)
3. Verify position was created by `mintLpFromTokens()` call
4. Call `TheCompact.processClaim()` to release assets to solver

---

### IPoolManager / IPositionManager Interfaces - READY ✅

**Good News**: These are external Uniswap v4 contracts, already deployed on testnet.

**Agent Can Use**:

```solidity
// Read pool state
IPoolManager.getSlot0(poolId) returns (
    uint160 sqrtPriceX96,
    int24 tick,
    uint24 protocolFee,
    uint24 lpFee
);

// Read position details (via StateLibrary)
StateLibrary.getPosition(poolManager, poolId, positionKey) returns (
    uint128 liquidity,
    // ... other fields
);
```

**Action Required**:

- Add interface files to `packages/agent/src/contracts/`
- Use Viem/Ethers to query these contracts

---

## 📊 Implementation Priority

### Phase 1: Health Monitoring (READY NOW)

✅ Can start building agent immediately:

- Read from PetRegistry
- Calculate health off-chain
- Call `updateHealth()` (with agent auth disabled for testing)

**Estimated Time**: 1-2 days

---

### Phase 2: Intent Fulfillment (NEEDS CONTRACT WORK)

#### High Priority (Blockers)

1. ❌ Add `mintLpFromTokens()` to AutoLpHelper - **CRITICAL**
2. ❌ Add `travelToChain()` to AutoLpHelper or new contract **New travel manager is Recommended** - **CRITICAL**
3. ❌ Add `IntentCreated` event - **CRITICAL**

**Estimated Time**: 1-2 days

#### Medium Priority (Nice to Have)

4. ⚠️ Build XolotrainAllocator.sol - **NEEDED FOR TRUSTLESS**
5. ⚠️ Build LPMigrationArbiter.sol - **NEEDED FOR TRUSTLESS**
6. ⚠️ Integrate The Compact SDK - **NEEDED FOR TRUSTLESS**

**Estimated Time**: 2-3 days

#### Low Priority (Can Mock)

7. 🔵 Add detailed LP position tracking
8. 🔵 Add position transfer/ownership management
9. 🔵 Add emergency pause mechanisms

**Estimated Time**: 1-2 days

---

## 🎯 Recommended Approach

### Chosen Option A: Blend of Build Contracts + Build Health Monitoring First (RECOMMENDED)

**Rationale**: Can start immediately, demonstrates agent capability for bounty

**Steps**:

1. Add `mintLpFromTokens()` to AutoLpHelper
2. new `TravelManager` contract
    - Create new tests for both to ensure Agent will work with new contracts
3. ✅ Build agent service with health monitoring loop
4. ✅ Deploy to testnet, monitor real LP positions
5. ✅ Show working demo: "Agent autonomously updates pet health"
6. ⏳ Add intent fulfillment later (parallel track)

**Timeline**:

- Day 1-2: Agent health monitoring working
- Day 3-4: Add contract functions for intents
- Day 5-6: Connect agent to intent fulfillment

---

## 🚧 Contract Modifications Needed

### AutoLpHelper.sol and Travel Manager Changes

```solidity
// ADD: New function for solver
function mintLpFromTokens(
    uint128 usdcAmount,
    uint128 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    address recipient
) external returns (uint256 positionId) {
    // Implementation here
}

// ADD: New function for intent creation
function travelToChain(
    uint256 petId,
    uint256 destinationChainId,
    int24 tickLower,
    int24 tickUpper
) external returns (bytes32 compactId) {
    // Implementation here
}

// ADD: New event
event IntentCreated(
    bytes32 indexed compactId,
    uint256 indexed petId,
    address indexed user,
    uint256 sourceChainId,
    uint256 destinationChainId,
    uint128 usdcAmount,
    uint128 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    uint256 timestamp
);
```

---

### PetRegistry.sol Changes

```solidity
// MODIFY: Uncomment agent check when ready
function updateHealth(uint256 petId, uint256 health, uint256 chainId) external {
    if (msg.sender != agent) revert NotAgent(msg.sender); // UNCOMMENT THIS
    // ... rest of function
}
```

---

## 📝 Integration Checklist

### For Health Monitoring Agent

- [x] `PetRegistry.updateHealth()` exists
- [x] `PetRegistry.setAgent()` exists
- [x] `HealthUpdated` event exists
- [x] `getActivePetId()` view function exists
- [x] `getPet()` view function exists
- [ ] Deploy agent service
- [ ] Set agent address in PetRegistry
- [ ] Uncomment agent authorization check

### For Intent Fulfillment Agent (Solver)

- [x] `AutoLpHelper.mintLpFromTokens()` exists
- [ ] `AutoLpHelper.travelToChain()` exists (or equivalent)
- [ ] `IntentCreated` event exists
- [ ] XolotrainAllocator.sol deployed
- [ ] LPMigrationArbiter.sol deployed
- [ ] The Compact integration complete
- [ ] Li.FI SDK integrated in agent
- [ ] Agent has capital float on both chains

---

## 🎬 Next Steps

### Immediate (Do First)

1. **Decide**: Option A (agent first) or Option B (contracts first)?
2. **If Option A**: Start building agent health monitoring now
3. **If Option B**: Implement `mintLpFromTokens()` first

### This Week

- Complete missing contract functions
- Test contract flows with scripts
- Deploy updated contracts to testnet

### Next Week

- Build complete agent service
- Integrate Li.FI SDK
- Deploy agent monitoring service
- Connect agent to contracts

---

## 💡 Key Insights

1. **Health Monitoring is Ready** - Can build agent immediately with existing contracts
2. **Intent Fulfillment Needs Work** - Missing critical functions in AutoLpHelper
3. **The Compact Integration is Optional** - Can demo without it, use centralized solver initially
4. **Agent-First Approach Works** - Can show "agent-driven systems" for bounty with just health monitoring

---

## 🔗 Related Documents

- [AGENT_DESIGN.md](./design/AGENT_DESIGN.md) - Detailed agent architecture
- [SYSTEM_ARCHITECTURE.md](./design/SYSTEM_ARCHITECTURE.md) - Complete system flows
- [INTERACTIONS.md](./design/INTERACTIONS.md) - User/agent interaction catalog
- [6_DAY_TIMELINE.md](./6_DAY_TIMELINE.md) - Implementation schedule

---

**Last Updated**: February 5, 2026  
**Status**: ⚠️ Contracts partially ready, health monitoring can start now, intent fulfillment needs contract additions
