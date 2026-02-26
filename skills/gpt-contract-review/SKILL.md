# gpt-contract-review — Cross-Model Adversarial Contract Review

## Purpose

You are an adversarial contract interaction reviewer. Your job is to perform a deep, systematic review of every place the frontend touches smart contracts, then prepare findings for cross-model validation. You look for the bugs that slip through normal code review: parameter mismatches, incomplete error handling, gas estimation gaps, optimistic update races, and BigInt safety violations throughout the entire call chain.

This skill follows the Bridgebuilder review format for structured, severity-tagged findings with file:line references.

## Execution Protocol

### Phase 1: Contract Interaction Inventory

Build a complete map of every contract touchpoint in the codebase.

#### Step 1: Find all Web3 library imports

Scan for all files that import from Web3 libraries:

```
Grep: import.*from\s+['"](?:wagmi|viem|ethers|@wagmi|@rainbow-me|@web3modal|web3)
```

Read each file that matches. Build a list of files, organized by what they import.

#### Step 2: Find all ABI references

```
Grep: (?:abi|ABI)\s*[:=]
```

```
Glob: **/*abi*.{ts,js,json}
Glob: **/abis/**
Glob: **/contracts/**/*.json
```

For each ABI found:
- Read it and extract function signatures
- Note which functions are `view`/`pure` (reads) vs state-changing (writes)
- Note which functions are `payable`
- Note custom error definitions
- Note event definitions

#### Step 3: Find all address constants

```
Grep: (?:address|ADDRESS|contractAddress|CONTRACT_ADDRESS)\s*[:=]\s*['"`]0x
```

```
Grep: 0x[a-fA-F0-9]{40}
```

For each address:
- Is it checksummed?
- Is it in a config file (good) or hardcoded inline (bad)?
- Is it per-chain or shared across chains?

#### Step 4: Find all contract read calls

```
Grep: useReadContract|useContractRead|readContract|publicClient\.read
```

For each read call, extract:
- Contract address source
- ABI reference
- Function name
- Arguments
- How the return value is used

#### Step 5: Find all contract write calls

```
Grep: useWriteContract|useContractWrite|writeContract|walletClient\.write|useSendTransaction|sendTransaction
```

For each write call, extract:
- Contract address source
- ABI reference
- Function name
- Arguments (especially value/msg.value for payable functions)
- Gas settings (if any)
- How the transaction hash is handled
- Success/error callbacks

#### Step 6: Find all transaction building code

```
Grep: encodeFunctionData|encodeAbiParameters|parseAbiParameters
```

```
Grep: prepareTransactionRequest|prepareFunctionCall
```

Manual encoding is higher risk than using typed hooks.

### Phase 2: Deep Analysis

For each contract interaction found, perform these analyses:

#### Analysis A: Parameter Consistency

For every write call, trace each argument back to its source:

1. Where does the value come from? (user input, state, computed)
2. What type transformations happen along the way?
3. Does the final type match what the contract expects?

**Common parameter bugs to flag:**

| Pattern | Risk | Severity |
|---------|------|----------|
| User input string passed directly as uint256 | Type mismatch at runtime | CRITICAL |
| Amount without decimals adjustment | Wrong magnitude (1 token vs 1 wei) | CRITICAL |
| Address from user input without validation | Invalid address causes revert | HIGH |
| Deadline computed from `Date.now()` without `/1000` | Deadline 1000x too far | HIGH |
| Slippage as percentage not converted to basis points | 1% becomes 100% | CRITICAL |
| Token amount without parseUnits | Sends dust instead of tokens | CRITICAL |
| msg.value mismatch with function expectation | ETH lost or tx reverts | CRITICAL |

For each finding, record:
- The file and line where the parameter is set
- The file and line where it's consumed by the contract call
- The expected type/format from the ABI
- The actual type/format being passed
- The runtime consequence

#### Analysis B: Error Handling Completeness

For every write call, check:

1. **Is the transaction error caught?**
   ```
   Grep: onError|\.catch|try.*catch.*(?:write|send|transaction)
   ```
   If not, an uncaught revert will crash the UI.

2. **Are specific revert reasons handled?**
   Read the ABI for custom errors. Then check if the frontend handles them:
   ```
   Grep: (?:error|revert|reason).*(?:InsufficientBalance|NotAuthorized|Paused|custom_error_name)
   ```
   Missing revert reason handling means users see generic "transaction failed" instead of actionable messages.

3. **Is the user notified of the error?**
   Check for toast/notification/alert patterns near error handlers:
   ```
   Grep: toast|notification|alert|setError|showError
   ```

4. **Revert reason decoding**: Does the app decode custom errors from the ABI or just show raw hex?
   ```
   Grep: decodeErrorResult|parseError|errorName
   ```

**Error handling checklist for each write call:**

| Check | Status |
|-------|--------|
| Try/catch or onError present | |
| Specific revert reasons decoded | |
| User-facing error message shown | |
| UI state reset after error | |
| Retry mechanism available | |
| Gas estimation error handled | |

#### Analysis C: Gas Estimation

For write calls, check gas handling:

1. **Is gas explicitly set?**
   ```
   Grep: gas\s*:|gasLimit|maxFeePerGas|maxPriorityFeePerGas
   ```

2. **Is gas estimation called before submission?**
   ```
   Grep: estimateGas|estimateContractGas|prepareWrite
   ```

3. **Is the gas estimation error handled?**
   Gas estimation failure usually means the transaction would revert. This is a useful pre-check.

4. **Is there a gas buffer?**
   Best practice is to add 10-20% buffer to estimated gas:
   ```typescript
   // Good pattern
   const estimated = await publicClient.estimateContractGas(args);
   const gasLimit = estimated * 120n / 100n; // 20% buffer
   ```

#### Analysis D: Optimistic Update Safety

Check for patterns where the UI updates before the transaction confirms:

```
Grep: optimistic|setBalance|setState.*before.*(?:write|send|confirm)
```

Optimistic updates are common for UX but dangerous if:
- The transaction reverts (UI shows wrong state)
- There's no rollback mechanism
- The optimistic value is used for subsequent calculations

For each optimistic update, check:
1. Is there a rollback on transaction failure?
2. Does the UI re-sync with chain state after confirmation?
3. Can the user take actions based on the optimistic (potentially wrong) state?

#### Analysis E: BigInt Safety Chain

Trace BigInt values through the entire call chain, from user input to contract submission:

1. **Input**: How does the value enter the system? (form input, API response, computed)
2. **Conversion**: Is `parseUnits`/`parseEther` used correctly?
3. **Arithmetic**: Are all operations BigInt-safe? (`+`, `-`, `*`, `/` on BigInt, not Number)
4. **Comparison**: Are comparisons BigInt-safe? (`<`, `>`, `===` on BigInt)
5. **Display**: Is `formatUnits`/`formatEther` used for display?
6. **Submission**: Is the final value BigInt when passed to the contract?

Flag any point where a BigInt value is implicitly or explicitly converted to Number.

#### Analysis F: Reentrancy-Adjacent Frontend Patterns

While reentrancy is a contract-level vulnerability, frontends can create reentrancy-like conditions:

1. **Double-submit**: Can the user click the submit button twice?
   ```
   Grep: disabled.*(?:pending|loading|submitting)|isPending|isLoading
   ```
   If the button isn't disabled during pending transaction, flag HIGH.

2. **Stale reads after writes**: Does the app re-read contract state after a write?
   ```
   Grep: refetch|invalidate|revalidate.*after.*(?:write|send)
   ```

3. **Race conditions**: Multiple concurrent transactions to the same contract?
   Check for nonce management or transaction queuing.

### Phase 3: Prepare Cross-Model Review Prompt

If GPT integration is available (check for GPT review toggle or MCP tool), prepare a structured review prompt.

Compile the collected code into a review package:

```markdown
# Cross-Model Contract Interaction Review

## Context
[Project name, Web3 stack, number of contracts, number of interaction points]

## Contract ABIs
[Include relevant ABI excerpts — function signatures, custom errors, events]

## Contract Interaction Code
[Include all files that interact with contracts, with file paths and line numbers]

## Specific Review Focus Areas
1. Parameter type consistency between frontend and ABI
2. Error handling completeness for all custom revert reasons
3. BigInt safety throughout the value chain
4. Gas estimation and buffer patterns
5. Optimistic update safety
6. Double-submit prevention

## Questions for Reviewer
- Are there any parameter mismatches I missed?
- Is the error handling sufficient for mainnet deployment?
- Are there race conditions in the transaction flow?
- Is the gas handling appropriate?
```

If GPT is available, send this prompt. If not, write it as a review document that can be manually sent to another model.

### Phase 4: Synthesize Findings

Whether or not GPT review was available, compile ALL findings into Bridgebuilder format.

#### Finding Format

Each finding MUST follow this structure:

```markdown
### [SEVERITY] [Finding Title]

**ID**: PROTOCOL-CR-NNN
**File**: `path/to/file.ts:42`
**Category**: [Parameter Safety | Error Handling | Gas Estimation | BigInt Safety | Optimistic Updates | Reentrancy-Adjacent | Configuration]

**Observation**:
[What was found, with exact code reference]

**Risk**:
[What could go wrong in production — be specific about the failure mode]

**Recommendation**:
[Specific fix, with code example if applicable]

**Cross-Model Agreement**: [Claude-only | GPT-confirmed | GPT-disputed]
```

#### Severity Classification

| Severity | Criteria |
|----------|----------|
| CRITICAL | Could cause fund loss, transaction failure on mainnet, or security vulnerability |
| HIGH | Causes bad UX, incorrect state display, or reliability issues |
| MEDIUM | Code quality issue that could become HIGH under certain conditions |
| LOW | Best practice violation, minor improvement |
| INFO | Observation, not a problem |
| PRAISE | Genuinely good pattern worth highlighting |

### Phase 5: Generate Report

Write the report to `grimoires/protocol/contract-review.md`:

```markdown
# Contract Interaction Review

**Date**: [timestamp]
**Reviewer**: Protocol Construct (dapp-qa / gpt-contract-review)
**Cross-Model**: [GPT-validated / Claude-only]
**Project**: [name]

## Executive Summary

[2-3 sentence overview of the review findings]

| Severity | Count |
|----------|-------|
| CRITICAL | N |
| HIGH | N |
| MEDIUM | N |
| LOW | N |
| PRAISE | N |

## Contract Interaction Map

| Contract | Address Source | Functions Used | Files |
|----------|--------------|----------------|-------|
| Token | config.ts:5 | balanceOf, transfer, approve | 4 files |
| ... | ... | ... | ... |

## Findings

### CRITICAL Findings
[Finding blocks in Bridgebuilder format]

### HIGH Findings
...

### MEDIUM Findings
...

### LOW Findings
...

### PRAISE
[Highlight good patterns found in the codebase]

## Error Handling Coverage

| Contract.Function | Error Caught | Revert Decoded | User Notified | UI Reset |
|-------------------|-------------|----------------|---------------|----------|
| Token.transfer | YES | NO | YES | YES |
| ... | ... | ... | ... | ... |

## BigInt Safety Trace

| Value | Source | Conversions | Final Type | Safe? |
|-------|--------|-------------|------------|-------|
| amount | form input | parseUnits → BigInt | bigint | YES |
| ... | ... | ... | ... | ... |

## Recommendations (Priority Order)

1. [Most critical fix first]
2. ...
```

### Phase 6: Summary Output

Present to the user:
- Total findings by severity
- Top 3 most critical issues with file:line
- Whether cross-model review was performed
- Key patterns: what's good about the codebase (PRAISE findings)
- What needs immediate attention before deployment
- Path to the full report

## Review Heuristics

These are the patterns that separate "works in development" from "safe on mainnet":

### The Decimal Trap
```typescript
// DANGER: parseUnits with wrong decimals
const amount = parseUnits(userInput, 18); // What if token has 6 decimals (USDC)?
// SAFE: Read decimals from contract
const decimals = await readContract({ functionName: 'decimals' });
const amount = parseUnits(userInput, decimals);
```

### The Approval Footgun
```typescript
// DANGER: Approve exact amount (requires re-approval for every transaction)
await writeContract({ functionName: 'approve', args: [spender, amount] });
// BETTER: Approve max (common UX pattern, but inform user)
await writeContract({ functionName: 'approve', args: [spender, maxUint256] });
// BEST: Let user choose between exact and unlimited approval
```

### The Silent Revert
```typescript
// DANGER: Generic error catch hides revert reason
try { await writeContract(args); }
catch (e) { toast.error('Transaction failed'); } // User has no idea why

// SAFE: Decode the revert reason
catch (e) {
  const decoded = decodeErrorResult({ abi, data: e.data });
  toast.error(`Transaction failed: ${decoded.errorName}`);
}
```

### The Stale State Read
```typescript
// DANGER: Display uses cached data after state change
await writeContract({ functionName: 'transfer', args: [to, amount] });
// Balance display still shows old value!

// SAFE: Invalidate and refetch after write
await writeContract({ functionName: 'transfer', args: [to, amount] });
await queryClient.invalidateQueries({ queryKey: ['balance'] });
```

### The Gas Cliff
```typescript
// DANGER: No gas estimation, uses default
await writeContract({ functionName: 'complexMulticall', args: [data] });
// If gas exceeds block limit, silent failure

// SAFE: Estimate first, apply buffer
const gas = await publicClient.estimateContractGas({
  functionName: 'complexMulticall', args: [data],
});
await writeContract({
  functionName: 'complexMulticall',
  args: [data],
  gas: gas * 120n / 100n,
});
```

### The Nonce Race
```typescript
// DANGER: Two writes without waiting for confirmation
await writeContract({ functionName: 'approve', args: [spender, amount] });
await writeContract({ functionName: 'swap', args: [params] }); // Nonce conflict!

// SAFE: Wait for first transaction to confirm
const hash = await writeContract({ functionName: 'approve', args: [spender, amount] });
await waitForTransactionReceipt(config, { hash });
await writeContract({ functionName: 'swap', args: [params] });
```

## Cross-Model Review Integration

When GPT review is available:

1. Prepare the review package (Phase 3)
2. Send via the GPT integration tool with the structured prompt
3. Parse GPT's response — look for findings that:
   - **Confirm** your findings (increases confidence)
   - **Add new findings** you missed (cross-model value)
   - **Dispute** your findings (requires deeper analysis — who's right?)
4. Tag each finding with cross-model agreement status

When GPT is NOT available:
- Complete the review with Claude-only analysis
- Note in the report that cross-model validation was not performed
- Recommend the user send the review package to another model for validation

The value of cross-model review is catching blindspots — each model has different failure modes and different strengths in code analysis. Claude excels at systematic enumeration; GPT often catches subtle semantic issues. The combination is stronger than either alone.
