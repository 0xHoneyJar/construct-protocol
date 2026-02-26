# abi-audit

> Compare frontend ABI definitions against deployed contract reality.

You are executing the **abi-audit** skill. Your job is to find every ABI definition and contract interface reference in the frontend codebase, compare each against the actually deployed contract, and report mismatches that cause silent failures, wrong data, or reverts.

## Prerequisites

Verify `cast` is available:
```bash
cast --version
```

## Phase 1: Discover Frontend ABI Usage

You MUST find ALL places the frontend defines or references contract ABIs. There are multiple patterns to check.

### 1A: Standalone ABI files

Search for ABI JSON files:
```
Glob for **/*.abi.json, **/abi/*.json, **/abis/*.json, **/artifacts/**/*.json, **/generated/**/*.ts
```

Read each file. ABI files are JSON arrays of objects with `type`, `name`, `inputs`, `outputs` fields.

### 1B: Inline ABI definitions

Search for inline ABI arrays in TypeScript/JavaScript:

```
Grep for "abi:" or "abi =" in **/*.ts, **/*.tsx, **/*.js, **/*.jsx
```

```
Grep for "parseAbi" or "parseAbiItem" (viem pattern)
```

```
Grep for "ethers.utils.Interface" or "new Interface" (ethers pattern)
```

### 1C: Wagmi/viem contract hooks

These are the most common frontend contract interaction patterns:

```
Grep for "useReadContract" or "useWriteContract" or "useContractRead" or "useContractWrite"
```

```
Grep for "useContractEvent" or "useWatchContractEvent"
```

```
Grep for "readContract" or "writeContract" or "simulateContract" (viem actions)
```

```
Grep for "getContract" or "createPublicClient" (direct viem usage)
```

For each hook/call found, identify:
- The ABI being used (inline or imported)
- The contract address
- The function name being called
- The chain ID

### 1D: Contract config objects

Many projects centralize contract definitions:

```
Grep for "wagmiConfig" or "contractConfig" or "contracts =" or "const contracts"
```

```
Grep for patterns like "address:" near "abi:" (co-located definitions)
```

### 1E: Code generation artifacts

Check for generated contract types:

```
Glob for **/generated/*.ts, **/__generated__/*.ts, **/typechain/**/*.ts
```

These may contain ABI definitions baked in during build time.

### Record every ABI source

For each ABI found, record:
- **File path and line number**
- **Contract address it's associated with** (may need to trace imports)
- **Full list of function/event/error signatures**
- **Whether it's a full ABI or partial** (some projects only include functions they use)

## Phase 2: Get Deployed Contract ABI

For each unique contract address found, fetch the on-chain ABI.

### Method A: Block explorer (preferred)

```bash
cast etherscan-source <address> --chain <chain>
```

This downloads verified source code. Extract the ABI from the compiled output. If the command succeeds, you have the ground truth ABI.

### Method B: Direct ABI fetch via API

If you have an Etherscan API key (check `.env` for `ETHERSCAN_API_KEY`):

```bash
cast abi <address> --chain <chain>
```

### Method C: Reconstruct from bytecode

If the contract is not verified, you can still check individual function signatures:

```bash
cast 4byte <selector>
```

For each function the frontend calls, compute the selector and verify it matches what the contract exposes. Compute a selector:

```bash
cast sig "functionName(uint256,address)"
```

### Proxy contracts

If the contract is a proxy (check with the EIP-1967 storage slot read):
```bash
cast storage <address> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <rpc>
```

If it's a proxy, get the ABI from the IMPLEMENTATION contract, not the proxy itself. The proxy typically only has fallback/receive functions in its own ABI.

## Phase 3: Diff ABIs

Compare every function, event, and error in the frontend ABI against the deployed ABI.

### Function comparison

For each function in the frontend ABI:

1. **Check existence**: Does the function exist in the deployed ABI?
   - If NO → **CRITICAL**: Frontend calls a function that doesn't exist. Will revert.

2. **Check input types**: Do the parameter types match exactly?
   - If NO → **CRITICAL**: Wrong encoding will cause revert or wrong behavior.
   - Common mismatch: `uint256` vs `uint128`, `address` vs `bytes20`

3. **Check output types**: Do the return types match?
   - If NO → **HIGH**: Wrong decoding will show wrong values to users.
   - The function will succeed but the frontend will misinterpret the return data.

4. **Check state mutability**: Is it `view`/`pure` vs state-changing?
   - If mismatch → **MEDIUM**: Wrong mutability means the frontend may not prompt for a transaction when it should.

Compute function selectors to verify:
```bash
cast sig "functionName(paramType1,paramType2)"
```

The selector must match between frontend and deployed contract. If selectors differ, the function signatures differ.

### Event comparison

For each event the frontend listens for:

1. **Check existence**: Does the event exist in the deployed ABI?
   - If NO → **HIGH**: Frontend listens for an event that's never emitted. Silent failure.

2. **Check indexed parameters**: Do the indexed parameter positions match?
   - If NO → **HIGH**: Topic filtering will not work correctly.

3. **Check parameter types**: Do types match?
   - If NO → **MEDIUM**: Event data will be decoded incorrectly.

### Error comparison

For each custom error the frontend handles:

1. **Check existence**: Does the error exist in the deployed ABI?
2. **Check for MISSING errors**: Does the deployed contract define errors the frontend doesn't handle?
   - If YES → **MEDIUM**: Frontend can't decode these revert reasons. Users see "unknown error."

### New functions in deployed contract

Check the reverse: functions in the deployed ABI that are NOT in the frontend ABI.
- If these are user-facing functions → **INFO**: The frontend may be missing features.
- If these are admin functions → expected, no action needed.

## Phase 4: Check Usage Patterns

Beyond ABI correctness, check for common integration bugs:

### 4A: Wrong address per chain

```
Grep for the contract address across all files
```

Verify that the address is only used for the correct chain. A common bug: mainnet address used for testnet calls (or vice versa).

### 4B: Missing error handling

For each `useWriteContract` / `writeContract` call, check if there's error handling:

```
Grep for "onError" or "catch" or "try" near each write call
```

If write calls have no error handling → **MEDIUM**: Users see no feedback on failure.

### 4C: Stale generated types

If the project uses code generation (wagmi CLI, typechain):

```
Grep for "@generated" or "DO NOT EDIT" in generated files
```

Check when these were last modified vs when the contract was last deployed/upgraded. If generated files are older than the last deployment, they may be stale.

### 4D: Hardcoded chain IDs

```
Grep for "chainId:" or "chain:" near contract definitions
```

Verify these match the actual deployment chain.

## Phase 5: Generate Report

Write the audit report to `grimoires/protocol/abi-audit-report.md`.

```markdown
# ABI Audit Report

**Generated**: <timestamp>
**Contracts audited**: <count>

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | <n> |
| HIGH | <n> |
| MEDIUM | <n> |
| INFO | <n> |

## Findings

### CRITICAL-1: <title>
- **Contract**: <address> on <chain>
- **Frontend ABI**: `<file>:<line>`
- **Issue**: <description>
- **Impact**: <what breaks for users>
- **Fix**: <exact change needed>

### HIGH-1: <title>
...

## Contract-by-Contract Audit

### <contract name> (<address>)

| Function | Frontend | Deployed | Status |
|----------|----------|----------|--------|
| `functionA(uint256)` | Present | Present | MATCH |
| `functionB(address)` | Present | MISSING | CRITICAL |
| `functionC(uint256)` | `uint256` | `uint128` | CRITICAL (type mismatch) |
| `functionD()` | Missing | Present | INFO (not used by frontend) |

| Event | Frontend | Deployed | Status |
|-------|----------|----------|--------|
| `Transfer(...)` | Present | Present | MATCH |
| `OldEvent(...)` | Present | MISSING | HIGH (never emitted) |

| Error | Frontend | Deployed | Status |
|-------|----------|----------|--------|
| `InsufficientBalance()` | Handled | Present | MATCH |
| `NewCustomError()` | Missing | Present | MEDIUM (unhandled) |

## Recommendations

<ordered list>
```

### Severity definitions

| Severity | Meaning |
|----------|---------|
| **CRITICAL** | Function signature mismatch, missing function, wrong parameter types. Calls WILL fail or return wrong data. |
| **HIGH** | Missing event handlers, wrong event parameters, missing error handlers. Silent failures. |
| **MEDIUM** | Stale types, missing error messages, wrong mutability. Degraded UX. |
| **INFO** | Unused deployed functions, extra ABI entries. No immediate impact. |

## Edge Cases

### Partial ABIs
Many projects only include the functions they use, not the full ABI. This is fine — only flag functions that ARE included but are wrong.

### Multiple ABI versions
If you find multiple ABI files for the same contract (e.g., v1 and v2), check which one is actually imported and used. The unused one should be deleted to avoid confusion.

### Generated vs manual ABIs
If the project has BOTH generated types AND manual ABI files, check if they're consistent with each other. Inconsistency between these is a separate bug class.

### Diamond/multi-facet proxies (EIP-2535)
Diamond proxies have multiple implementation contracts (facets). Each facet has its own ABI. The combined ABI is the union of all facet ABIs. You need to check all facets.

## Completion Criteria

You are done when:
1. You have found ALL ABI definitions in the frontend
2. You have fetched the deployed ABI for each contract
3. You have compared every function, event, and error
4. You have checked for common integration bugs
5. You have written the report to `grimoires/protocol/abi-audit-report.md`
6. You have presented all CRITICAL and HIGH findings prominently

A single CRITICAL finding (function signature mismatch) is a ship-blocker. Make it unmissable.
