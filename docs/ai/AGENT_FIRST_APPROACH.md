# Agent-First Design Principles for Xolotrain

## Philosophy

**Xolotrain is designed for AI agents to operate autonomously.** Every smart contract, API, and system component should prioritize simplicity, atomicity, and predictability over human-readable complexity.

When a human uses a DeFi protocol, they can handle multi-step flows, read error messages, retry failed transactions, and manage intermediate states. **Agents cannot.** Agents need deterministic, atomic operations with minimal decision branches.

---

## Core Principles

### 1. Atomicity Over Composition

**Principle**: Combine related operations into single atomic transactions whenever possible.

**Why It Matters for Agents**:

- Agents treat each transaction as a discrete action with binary outcomes (success/fail)
- Multi-transaction flows create exponential state complexity (2^n possible states)
- Intermediate failures leave agents in undefined states requiring complex recovery logic

**Example from AutoLpHelper**:

```solidity
// ❌ BAD: Agent-hostile (2 transactions)
// Tx1: Swap ETH → USDC/USDT via Universal Router
// Tx2: Mint LP position via PositionManager
// Problem: Agent holds unwanted tokens if Tx2 fails

// ✅ GOOD: Agent-friendly (1 transaction)
function swapEthToUsdcUsdtAndMint() external payable returns (uint256 tokenId)
// Result: Agent gets NFT position OR nothing (clean revert)
```

**Decision Rule**:

- If operation A naturally leads to operation B, combine them
- If failure in B invalidates success of A, they must be atomic
- If agent would never want A without B, merge into single function

---

### 2. Minimize Decision Points

**Principle**: Reduce the number of choices an agent must make to accomplish a goal.

**Why It Matters for Agents**:

- Each decision point requires logic, testing, and potential for bugs
- Agents optimize for known-good paths, not flexibility
- Human-friendly options become agent complexity burden

**Example Decision Tree Comparison**:

**Multi-Transaction Flow** (10 decision points):

```
1. Calculate swap amounts for ETH→USDC
2. Calculate swap amounts for ETH→USDT
3. Choose slippage tolerance
4. Execute swap tx1
5. Wait N blocks for confirmation?
6. Query actual received amounts
7. Handle discrepancy from expected amounts
8. Choose approval amount (infinite vs exact?)
9. Calculate LP tick range
10. Execute mint tx2
11. Handle tx2 failure with tokens in hand
```

**Atomic Flow** (2 decision points):

```
1. Calculate ETH input amount
2. Call swapEthToUsdcUsdtAndMint{value: X}()
```

**Decision Rule**:

- Default to sensible parameters (slippage, gas, timeouts)
- Expose only parameters that significantly change behavior
- Batch approval handling internally

---

### 3. Zero Intermediate State

**Principle**: Agents should never hold intermediate tokens or positions they didn't explicitly request.

**Why It Matters for Agents**:

- Intermediate tokens create custody responsibility
- Agents need disposal strategies for unwanted assets
- Balance tracking across transactions increases complexity
- Creates attack surface (someone can manipulate agent's held tokens)

**Example**:

```solidity
// ❌ BAD: Agent temporarily holds USDC/USDT
1. Agent approves Universal Router for ETH
2. Universal Router swaps, agent receives USDC/USDT
3. Agent approves PositionManager for USDC/USDT
4. PositionManager mints LP, agent receives NFT

// ✅ GOOD: Agent never holds intermediate tokens
1. Agent sends ETH to AutoLpHelper
2. AutoLpHelper does swaps + LP mint internally
3. Agent receives NFT (and leftover dust swept back)
```

**Decision Rule**:

- If agent doesn't want an asset as a final outcome, it shouldn't touch their wallet
- Use internal accounting within contracts instead of external transfers
- Sweep any dust/leftovers back to caller atomically

---

### 4. No Token Approvals from Agents

**Principle**: Agents should never need to make approval transactions.

**Why It Matters for Agents**:

- Approvals are extra transactions (cost, latency, complexity)
- Infinite approvals create permanent attack surface
- Exact approvals require precise calculation (prone to rounding errors)
- Approval state management across operations is error-prone

**Example Patterns**:

```solidity
// ❌ BAD: Requires agent to approve tokens
contract BadHelper {
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        // ... add liquidity
    }
}

// ✅ GOOD: Agent sends ETH/native assets only
contract GoodHelper {
    function swapAndAddLiquidity() external payable {
        // Swap ETH internally to get tokens
        // Add liquidity with those tokens
        // No approvals needed from caller
    }
}
```

**Decision Rule**:

- Accept native assets (ETH) whenever possible
- If ERC20 required, have agent deposit once to your contract
- Use internal balance tracking instead of repeated transfers
- Batch operations so agent isn't approving multiple protocols

---

### 5. Predictable Outcomes

**Principle**: Given the same inputs, operations should produce similar outputs (accounting for market conditions).

**Why It Matters for Agents**:

- Agents build mental models: "X ETH → Y LP position"
- Unpredictable behavior breaks agent strategies
- Agents can't handle "it depends" scenarios well

**Example**:

```solidity
// ❌ BAD: Outcome depends on hidden state
function mintPosition() external payable {
    // Uses msg.sender's existing token balances (unknown to agent)
    uint256 usdc = IERC20(USDC).balanceOf(msg.sender);
    // Creates position with unknown size
}

// ✅ GOOD: Outcome depends only on inputs
function mintPosition(uint256 ethAmount) external payable {
    require(msg.value == ethAmount);
    // Swaps exact ethAmount to tokens
    // Creates position with predictable size
    // Returns tokenId and position details
}
```

**Decision Rule**:

- Outputs should be deterministic functions of inputs (plus current market state)
- Avoid dependencies on caller's hidden state (balances, approvals, etc.)
- Return comprehensive data about what was created/modified

---

### 6. Revert with Useful Errors

**Principle**: When operations fail, provide actionable error messages that agents can parse.

**Why It Matters for Agents**:

- Agents need to know WHY failure occurred to adjust strategy
- Generic reverts lead to blind retries (wasted gas)
- Structured errors enable programmatic handling

**Example**:

```solidity
// ❌ BAD: No context
require(amount > 0, "Invalid amount");

// ✅ GOOD: Actionable errors
error InsufficientLiquidity(uint256 requested, uint256 available);
error SlippageExceeded(uint256 minOutput, uint256 actualOutput);
error TickOutOfRange(int24 tick, int24 minTick, int24 maxTick);

function mintPosition() external payable {
    if (msg.value == 0) revert ZeroInput();

    uint256 output = _swap(msg.value);
    if (output < minOutput) {
        revert SlippageExceeded(minOutput, output);
    }
}
```

**Decision Rule**:

- Use custom errors with relevant parameters
- Include actual vs expected values
- Avoid string concatenation (gas + parsing complexity)
- Error names should suggest remediation

---

### 7. Gas Efficiency at Scale

**Principle**: Optimize for repeated agent operations, not one-time human usage.

**Why It Matters for Agents**:

- Agents may execute 1000s of operations per day
- Small inefficiencies compound at scale
- Gas costs directly impact agent profitability/viability

**Example Calculations**:

```
Human user: 10 transactions/month
- Inefficiency: +50k gas/tx
- Cost: 10 × 50k × 20 gwei × $3000/ETH = $3/month

Agent: 1000 transactions/day
- Inefficiency: +50k gas/tx
- Cost: 1000 × 50k × 20 gwei × $3000/ETH = $3000/day = $90k/month
```

**Optimization Patterns**:

- Batch operations to save base transaction cost (21k gas)
- Eliminate redundant approvals (46k gas each)
- Use immutable variables where possible
- Pack storage variables efficiently
- Use events for agent monitoring (cheaper than storage reads)

**Decision Rule**:

- If agent calls function repeatedly, optimize aggressively
- Trade code complexity for gas savings (agents don't read code)
- Profile gas usage under realistic agent workloads

---

### 8. Idempotency Where Possible

**Principle**: Operations should be safe to retry without unexpected side effects.

**Why It Matters for Agents**:

- Network issues cause transaction uncertainty
- Agents may retry on timeout without knowing if tx1 succeeded
- Double-execution should be safe or explicitly prevented

**Example**:

```solidity
// ❌ BAD: Double execution = double charge
function depositAndStake(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    _stake(msg.sender, amount);
    // If agent retries, stakes 2x
}

// ✅ GOOD: Track state to prevent double-execution
mapping(bytes32 => bool) public executed;

function depositAndStake(uint256 amount, bytes32 nonce) external {
    require(!executed[nonce], "Already executed");
    executed[nonce] = true;

    token.transferFrom(msg.sender, address(this), amount);
    _stake(msg.sender, amount);
}
```

**Decision Rule**:

- If operation is stateful, provide nonce/ID mechanism
- If operation is naturally idempotent, document it
- Consider EIP-712 signatures for agent-submitted transactions

---

### 9. MEV Awareness

**Principle**: Design operations to minimize MEV extraction opportunities.

**Why It Matters for Agents**:

- Agents have predictable behavior (easy to frontrun)
- Multi-step operations reveal strategy in mempool
- MEV losses reduce agent profitability

**Example**:

```
❌ BAD: 2 transactions visible in mempool
Tx1: Swap 10 ETH → USDC (agents always do this)
Tx2: Mint LP in USDC/USDT pool (predictable next step)

MEV Bot sees:
- Tx1 in mempool → "This address will have USDC next block"
- Frontrun Tx2 to manipulate tick
- Extract value from predictable agent behavior

✅ GOOD: 1 atomic transaction
Tx: swapEthToUsdcUsdtAndMint(10 ETH)

MEV Bot sees:
- Single opaque transaction
- Can't split operation to insert manipulation
- Smaller attack surface
```

**Decision Rule**:

- Atomic operations reduce MEV surface area
- Consider commit-reveal for high-value agent operations
- Use private mempools (Flashbots) for sensitive operations
- Implement slippage protection at contract level

---

### 10. Observable State Changes

**Principle**: Emit detailed events for every state change agents need to track.

**Why It Matters for Agents**:

- Agents monitor on-chain activity to update internal state
- Reading storage is expensive, events are cheap
- Events enable off-chain indexing for agent decision-making

**Example**:

```solidity
// ❌ BAD: Minimal events
event PositionCreated(uint256 tokenId);

// ✅ GOOD: Rich events for agent consumption
event PositionCreated(
    uint256 indexed tokenId,
    address indexed owner,
    uint256 ethInput,
    uint256 usdcAmount,
    uint256 usdtAmount,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity,
    uint256 timestamp
);

function swapEthToUsdcUsdtAndMint() external payable returns (uint256 tokenId) {
    // ... operation logic ...

    emit PositionCreated(
        tokenId,
        msg.sender,
        msg.value,
        usdcUsed,
        usdtUsed,
        tickLower,
        tickUpper,
        liquidity,
        block.timestamp
    );

    return tokenId;
}
```

**Decision Rule**:

- Emit events for all state changes
- Include indexed fields for efficient filtering
- Provide enough data that agents don't need to call view functions
- Use consistent event naming across contracts

---

## Anti-Patterns to Avoid

### 🚫 The "Human-Friendly" Trap

**Bad**: "Let's make this flexible so users can choose between multiple strategies"

- Creates decision paralysis for agents
- Increases testing surface area
- Most options never used in practice

**Good**: "Let's pick the optimal strategy and implement it well"

- Agents get known-good behavior
- Simpler testing and auditing
- Can always add options later if needed

---

### 🚫 The "Progressive Enhancement" Trap

**Bad**: "Let's build basic functionality first, then add agent support"

- Retrofit is harder than building correctly from start
- May require breaking changes to fix
- Technical debt compounds

**Good**: "Let's design for agents from day one"

- Atomic operations from the start
- Cleaner architecture
- Works well for humans too (simpler UX)

---

### 🚫 The "Separate Agent API" Trap

**Bad**: "Let's build a normal DeFi protocol, then add an agent-specific wrapper"

- Duplication of logic
- Wrapper becomes maintenance burden
- Splits testing and security review

**Good**: "Let's build ONE API that works great for agents"

- Single code path (easier to secure)
- Simpler = fewer bugs
- Humans benefit from simplicity too

---

## Design Checklist

When building any new feature, ask:

**Atomicity**:

- [ ] Can this operation complete in a single transaction?
- [ ] If it fails partway, will the agent be stuck with unwanted assets?
- [ ] Can I combine multiple steps into one atomic function?

**Simplicity**:

- [ ] How many decisions does the agent need to make?
- [ ] Can I reduce parameters by choosing sensible defaults?
- [ ] Is the happy path obvious and simple?

**State Management**:

- [ ] Does the agent need to hold intermediate tokens?
- [ ] Does the agent need to approve multiple contracts?
- [ ] Can I keep state internal to my contracts?

**Predictability**:

- [ ] Given same inputs, are outputs predictable?
- [ ] Do I depend on hidden state in the caller's wallet?
- [ ] Are failure modes clear and actionable?

**Gas Efficiency**:

- [ ] How often will agents call this function?
- [ ] Can I save gas by batching operations?
- [ ] Have I eliminated unnecessary approvals?

**MEV Resistance**:

- [ ] Does my multi-tx flow reveal agent strategy?
- [ ] Can MEV bots profit from frontrunning?
- [ ] Should this be atomic to reduce MEV surface?

**Observability**:

- [ ] Do I emit events with all relevant data?
- [ ] Can agents monitor state changes efficiently?
- [ ] Are my events consistently structured?

---

## Case Study: AutoLpHelper Evolution

### Initial Design (Agent-Hostile)

```solidity
// Required 4 agent decisions + 2 transactions
contract AutoLpHelperV1 {
    function swapETHToUSDC() external payable returns (uint256 usdcOut);
    function swapETHToUSDT() external payable returns (uint256 usdtOut);
    function addLiquidity(uint256 usdc, uint256 usdt) external returns (...);
}

// Agent logic required:
1. Calculate ETH split ratio
2. Call swapETHToUSDC with half
3. Call swapETHToUSDT with half
4. Approve USDC
5. Approve USDT
6. Calculate tick range
7. Call addLiquidity
8. Handle intermediate failures
```

### Evolution 1 (Better, but still issues)

```solidity
// Reduced to 1 transaction, but still has state issues
contract AutoLpHelperV2 {
    function swapAndMintLP() external payable returns (uint256 tokenId);
}

// Problems:
- Used WETH (extra wrap step)
- Called V4Router (hit ManagerLocked() error)
- Required complex callback handling
```

### Final Design (Agent-Optimal)

```solidity
// Single atomic operation, no intermediate state
contract AutoLpHelperV3 {
    // Agent just calls this with ETH
    function swapEthToUsdcUsdtAndMint()
        external
        payable
        returns (uint256 tokenId);

    // Contract handles:
    // - Native ETH (no WETH wrap)
    // - Atomic swaps via unlock callback
    // - LP mint in same transaction
    // - Leftover dust swept back to caller
    // - Returns NFT tokenId
}

// Agent logic required:
1. Call swapEthToUsdcUsdtAndMint{value: X}()
2. Receive tokenId
3. Done
```

**Key Improvements**:

- ✅ 10 decision points → 1 function call
- ✅ 2 transactions → 1 transaction
- ✅ 2 approvals → 0 approvals
- ✅ Complex failure modes → simple success/revert
- ✅ Price risk between txs → eliminated
- ✅ MEV attack surface → minimized
- ✅ Gas cost → reduced by ~30%

---

## Summary

**Building for agents means building for simplicity, atomicity, and predictability.**

Every decision point you add to a flow exponentially increases agent complexity. Every transaction you split increases failure modes. Every approval you require increases attack surface.

The best agent-friendly systems are so simple they feel "too basic" for humans. That's the goal.

**Default to atomic, single-transaction operations with zero intermediate state and comprehensive events.**

Your agents will thank you with reliable execution, lower costs, and fewer bugs.

---

## Resources

- [Uniswap v4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [IUnlockCallback Pattern](https://docs.uniswap.org/contracts/v4/concepts/unlocking)
- [AGENTS.md](../../AGENTS.md) - Implementation guidelines for this repository
- [UNISWAP_CANONICAL_CONTEXT.md](./UNISWAP_CANONICAL_CONTEXT.md) - Uniswap v4 protocol specifics

---

_Last Updated: February 3, 2026_
