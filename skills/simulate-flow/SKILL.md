# simulate-flow

> Dry-run user flows to catch reverts before users hit them.

You are executing the **simulate-flow** skill. Your job is to simulate contract interactions using `cast call` and `cast estimate` to verify that user flows will succeed, estimate gas costs, and compare simulated outcomes against what the frontend would display. This is proactive QA — catching failures before deployment or before users encounter them.

## Prerequisites

Verify `cast` is available:
```bash
cast --version
```

## Phase 1: Identify the Flow to Simulate

Determine what user action to simulate. Common flows:

| Flow Type | Key Functions | Common Failure Points |
|-----------|--------------|----------------------|
| **Bid/Auction** | `createBid(uint256)` | Reserve not met, auction ended, outbid threshold |
| **Swap/Trade** | `swap(...)`, `exactInputSingle(...)` | Slippage, deadline, insufficient liquidity |
| **Deposit/Stake** | `deposit(uint256)`, `stake(uint256)` | Missing approval, cap reached, paused |
| **Withdraw** | `withdraw(uint256)`, `unstake(...)` | Insufficient balance, timelock, cooldown |
| **Mint/NFT** | `mint(uint256)`, `claim(...)` | Max supply, wrong price, not whitelisted |
| **Approve** | `approve(address,uint256)` | Usually succeeds (but check for approval caps) |
| **Transfer** | `transfer(address,uint256)` | Insufficient balance, blacklisted |
| **Governance** | `propose(...)`, `castVote(...)` | Insufficient voting power, proposal expired |

If the user specifies a flow (e.g., "simulate a bid"), use that. If they say "simulate everything" or "test the main flows", identify the primary user flows from the frontend code.

### Discover flows from frontend

Search for transaction-sending patterns:
```
Grep for "useWriteContract" or "writeContract" or "sendTransaction" in src/, app/
```

```
Grep for "functionName:" near these calls to identify the contract functions
```

For each write function found, that's a flow to simulate.

## Phase 2: Gather Parameters

For each flow, you need:

1. **Contract address** — from config, .env, or constants
2. **Function signature** — exact Solidity signature with types
3. **Parameters** — realistic values for simulation
4. **Sender address** — who is calling (affects balance/permission checks)
5. **Value** — ETH to send (for payable functions)

### Determine realistic parameters

**DO NOT use zero or dummy values.** The point of simulation is to test realistic conditions.

Read the frontend to find what parameters it would send:

```
Grep for the function name to find where the frontend constructs the call
```

Look for:
- Form input validation (min/max values)
- Computed parameters (e.g., slippage calculations)
- Constants used as defaults

If the frontend constructs parameters dynamically, read the relevant on-chain state to compute realistic values:

```bash
# For an auction bid, get the current highest bid first
cast call <auction> "auction()(uint256,uint256,address,uint256,uint256,bool)" --rpc-url <rpc>

# Then compute a valid bid (current + minIncrement)
cast call <auction> "minBidIncrementPercentage()(uint8)" --rpc-url <rpc>
```

### Sender address

Use a realistic sender. Options:
1. An address from the user (if they specify)
2. An address that has the right token balances (find one from recent events)
3. The zero address (for basic call simulation — but won't catch balance/permission issues)

To find a realistic sender, check recent events:
```bash
# Find recent bidders/depositors/etc.
cast logs --from-block -1000 --address <contract> --rpc-url <rpc>
```

Or use the `--from` flag with impersonation in `cast call` (this works because `cast call` is a simulation, not a real transaction):
```bash
cast call <contract> "function(args)" <params> --from <any-address> --rpc-url <rpc>
```

## Phase 3: Pre-flight Checks

Before simulating the main flow, check prerequisites that commonly cause failures:

### 3A: Check if contract is paused
```bash
cast call <contract> "paused()(bool)" --rpc-url <rpc>
```
If paused, report immediately — all user flows will fail.

### 3B: Check token approvals (for flows that transfer tokens)

If the flow involves depositing/spending tokens:
```bash
# Check current allowance
cast call <token> "allowance(address,address)(uint256)" <sender> <spender-contract> --rpc-url <rpc>

# Check sender balance
cast call <token> "balanceOf(address)(uint256)" <sender> --rpc-url <rpc>
```

If allowance is insufficient, note that an `approve` transaction is needed first. Simulate the approve too:
```bash
cast call <token> "approve(address,uint256)(bool)" <spender-contract> <amount> --from <sender> --rpc-url <rpc>
```

### 3C: Check ETH balance (for payable flows)
```bash
cast balance <sender> --rpc-url <rpc>
```

### 3D: Check time-dependent conditions
```bash
# Get current block timestamp
cast block latest --rpc-url <rpc> --json 2>/dev/null | jq -r '.timestamp'
```

Compare against deadlines, auction end times, cooldown periods, etc.

## Phase 4: Simulate the Transaction

### Basic simulation with `cast call`

`cast call` simulates a transaction without broadcasting it. It runs against the current state and returns the result (or reverts).

```bash
cast call <contract> "functionName(type1,type2)(returnType)" <arg1> <arg2> \
  --from <sender> \
  --value <wei-amount> \
  --rpc-url <rpc>
```

**IMPORTANT**: `cast call` returns the return value of the function. For state-changing functions, this may not be meaningful (often returns nothing or a bool). The key information is whether it REVERTS or not.

### Gas estimation with `cast estimate`

```bash
cast estimate <contract> "functionName(type1,type2)" <arg1> <arg2> \
  --from <sender> \
  --value <wei-amount> \
  --rpc-url <rpc>
```

This returns the estimated gas in units. Convert to cost:
```bash
# Get current gas price
cast gas-price --rpc-url <rpc>

# Calculate cost: gas_units * gas_price = cost in wei
# Use cast to convert: cast --to-unit <wei-cost> ether
```

### Handling simulation results

**If simulation succeeds:**
- Record the return value
- Record the gas estimate
- Calculate the gas cost in ETH and USD (if possible)
- Compare return value against what the frontend would show

**If simulation reverts:**
- Decode the revert reason (same as tx-forensics Phase 3)
- Determine the root cause
- Suggest how to fix the parameters or prerequisites

## Phase 5: Multi-Step Flow Simulation

Many user flows require multiple transactions. Simulate the full sequence:

### Common multi-step flows

**Approve + Deposit:**
```bash
# Step 1: Approve
cast call <token> "approve(address,uint256)(bool)" <vault> <amount> --from <sender> --rpc-url <rpc>

# Step 2: Deposit (depends on approval)
cast call <vault> "deposit(uint256)(uint256)" <amount> --from <sender> --rpc-url <rpc>
```

**NOTE**: `cast call` doesn't persist state between calls. The approve simulation won't affect the deposit simulation. You need to check if the allowance is ALREADY sufficient, or note that the approve is needed.

**Swap with permit:**
```bash
# Permit is off-chain signing — skip to the swap
# But check that the router has the right allowance or that the contract supports permit
```

**Mint + List (NFT flow):**
```bash
# Step 1: Mint
cast call <nft> "mint(uint256)" --value <price> --from <sender> --rpc-url <rpc>

# Step 2: Approve marketplace
# Step 3: Create listing
```

For each step:
1. Simulate the call
2. Estimate gas
3. Note dependencies (Step 2 requires Step 1 to succeed first)
4. Calculate total gas cost across all steps

## Phase 6: Compare Against Frontend Display

This is where simulation becomes truly valuable. Check whether what the frontend SHOWS matches what the simulation PRODUCES.

### Find frontend display values

```
Grep for components that display transaction previews, estimates, or confirmations
```

Look for:
- Gas estimate displays
- Output amount displays (for swaps)
- Price impact calculations
- Fee displays
- Expected return calculations

### Common mismatches

| Frontend Shows | Simulation Shows | Cause |
|---------------|-----------------|-------|
| Lower gas estimate | Higher actual gas | Frontend uses hardcoded gas limit |
| Different swap output | Actual output amount | Frontend quote is stale (price moved) |
| "Transaction will succeed" | Simulation reverts | Frontend doesn't check all preconditions |
| Lower fee | Higher fee | Fee parameter changed on-chain |

### Specific checks

**For swaps/trades:**
```bash
# Get the actual output amount
cast call <router> "getAmountsOut(uint256,address[])(uint256[])" <amountIn> "[<tokenIn>,<tokenOut>]" --rpc-url <rpc>
```

Compare against the frontend's displayed quote.

**For deposits/yields:**
```bash
# Get the actual shares received for deposit
cast call <vault> "previewDeposit(uint256)(uint256)" <amount> --rpc-url <rpc>
```

Compare against the frontend's displayed expected shares.

## Phase 7: Edge Case Simulations

Test boundary conditions that normal usage wouldn't hit but attackers might:

### Zero amount
```bash
cast call <contract> "deposit(uint256)" 0 --from <sender> --rpc-url <rpc>
```
Should revert. If it doesn't, that's a potential bug.

### Max uint256 amount
```bash
cast call <contract> "deposit(uint256)" 115792089237316195423570985008687907853269984665640564039457584007913129639935 --from <sender> --rpc-url <rpc>
```
Should revert cleanly. If it overflows, that's critical.

### Already-used parameters
For operations that should be one-time (claim, initialize):
```bash
# Try to claim again with an address that already claimed
cast call <contract> "claim()" --from <already-claimed-address> --rpc-url <rpc>
```
Should revert. If it doesn't, double-claim is possible.

### Expired deadlines
```bash
# Use a past deadline
cast call <router> "swap(...,uint256 deadline)" ... 1 --from <sender> --rpc-url <rpc>
```
Should revert with "expired" or similar.

## Phase 8: Generate Report

Write the simulation report to `grimoires/protocol/simulate-report.md`:

```markdown
# Flow Simulation Report

**Generated**: <timestamp>
**Contract**: <address>
**Chain**: <chain>
**RPC**: <rpc url (redact API keys)>

## Summary

| Flow | Status | Gas (units) | Gas (ETH) | Notes |
|------|--------|-------------|-----------|-------|
| <flow name> | PASS / FAIL | <gas> | <cost> | <note> |

## Detailed Results

### Flow 1: <name>

**Steps**:
1. <step description>
   - Command: `cast call ...`
   - Result: <success/revert>
   - Gas: <estimate>
2. <step description>
   ...

**Pre-flight checks**:
- Contract paused: <No>
- Token approval sufficient: <Yes/No>
- Sender balance sufficient: <Yes/No>

**Simulation result**: <PASS/FAIL>
**Return value**: <decoded>
**Gas estimate**: <units> (<ETH cost>)
**Frontend comparison**: <match/mismatch details>

### Flow 2: <name>
...

## Edge Case Results

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| Zero amount | Revert | <result> | PASS/FAIL |
| Max amount | Revert | <result> | PASS/FAIL |
| Duplicate action | Revert | <result> | PASS/FAIL |
| Expired deadline | Revert | <result> | PASS/FAIL |

## Frontend Discrepancies

| What Frontend Shows | What Simulation Shows | Impact |
|--------------------|----------------------|--------|
| <value> | <value> | <user-facing impact> |

## Recommendations

1. <recommendation>
2. <recommendation>
```

## Error Handling

### "execution reverted" with no data
The function may require specific conditions. Check:
- Is the sender whitelisted/authorized?
- Is the contract in the right state (not paused, auction active, etc.)?
- Are all prerequisite steps completed?

### Gas estimation fails
If `cast estimate` fails, the transaction WOULD revert. This is equivalent to a simulation failure. Decode the revert reason.

### RPC timeout on simulation
Complex simulations (especially with many internal calls) can timeout on public RPCs. Suggest the user use a dedicated RPC with higher compute limits.

### Fork simulation (advanced)
If available, suggest using `anvil` for more complex simulations:
```bash
# Fork mainnet state locally
anvil --fork-url <rpc> --fork-block-number <block>

# Then simulate against the fork with full state modification
cast send <contract> "function()" --from <sender> --rpc-url http://localhost:8545 --private-key <anvil-test-key>
```

This allows multi-step simulations with state persistence between calls. Only suggest this for complex flows that can't be adequately tested with `cast call`.

## Completion Criteria

You are done when:
1. You have identified all flows to simulate
2. You have gathered realistic parameters for each flow
3. You have run pre-flight checks
4. You have simulated each flow and recorded results
5. You have estimated gas for successful flows
6. You have compared results against frontend display
7. You have tested edge cases
8. You have written the report
9. You have highlighted any FAIL results or frontend discrepancies to the user

The single most important output is: **which flows will revert and why.** Lead with failures.
