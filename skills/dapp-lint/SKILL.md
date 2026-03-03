# dapp-lint — Web3 Frontend Linter

## Purpose

You are a Web3 frontend code quality scanner. Your job is to find the most common and dangerous categories of dApp frontend bugs: BigInt safety violations, wei handling errors, address checksum failures, timestamp confusion, and unsafe number coercions. These are the bugs that cause real money loss in production.

## Execution Protocol

### Phase 1: Environment Detection

You MUST first determine what tools are available and what the project structure looks like.

1. Check if oxlint is installed:
   ```bash
   npx oxlint --version 2>/dev/null || echo "oxlint not available"
   ```

2. Check if eslint is installed with any web3 plugins:
   ```bash
   npx eslint --version 2>/dev/null || echo "eslint not available"
   ```

3. Detect the project's Web3 stack by scanning for imports:
   - Use Glob to find `package.json` files
   - Use Grep to identify which libraries are in use: `wagmi`, `viem`, `ethers`, `web3.js`, `@rainbow-me/rainbowkit`, `@web3modal`
   - Note the versions — ethers v5 vs v6 have different BigInt semantics

4. Identify the source directories to scan:
   - Use Glob for `src/**/*.{ts,tsx,js,jsx}`, `app/**/*.{ts,tsx,js,jsx}`, `pages/**/*.{ts,tsx,js,jsx}`
   - Exclude `node_modules`, `.next`, `dist`, `build`

### Phase 2: Web3 Anti-Pattern Scanning

Run ALL of the following scans. Each scan targets a specific category of Web3 frontend bug. Use Grep for all pattern matching.

#### Scan 1: Unsafe BigInt Coercions (CRITICAL)

These patterns cause silent precision loss. A `Number()` call on a wei value truncates it, potentially losing user funds.

**Patterns to search for:**

```
Number\(.*(?:balance|amount|value|price|wei|gwei|supply|allowance|total|reserve)
```

```
parseInt\(.*(?:balance|amount|value|price|wei|gwei|supply|allowance|total|reserve)
```

```
parseFloat\(.*(?:balance|amount|value|price|wei|gwei|supply|allowance|total|reserve)
```

```
\+\s*(?:balance|amount|value|price|wei|gwei)
```

This last pattern catches unary `+` coercion like `+balance` which silently converts BigInt to Number.

**Severity**: CRITICAL — Can cause fund loss
**Fix suggestion**: Use `formatUnits()` from viem or ethers for display, keep as BigInt for all calculations.

#### Scan 2: Hardcoded Chain IDs and Addresses (HIGH)

Hardcoded values break multi-chain support and make contract upgrades dangerous.

**Patterns to search for:**

```
chainId\s*[:=]\s*\d+
```

```
0x[a-fA-F0-9]{40}(?!.*(?:const|ABI|abi|type|interface))
```

Look for raw hex addresses that aren't in ABI/type definition contexts.

```
chain:\s*(?:mainnet|goerli|sepolia|arbitrum|optimism|polygon|base)
```

**Severity**: HIGH — Breaks multi-chain, blocks upgrades
**Fix suggestion**: Use environment variables or config objects for chain IDs and addresses. Reference a single `contracts.ts` config file.

**Exceptions to note**: Test files may legitimately hardcode addresses. Config files that serve as the single source of truth are fine. Flag but don't auto-fix these.

#### Scan 3: Timestamp Confusion (HIGH)

Solidity `block.timestamp` is in seconds. JavaScript `Date.now()` is in milliseconds. Mixing them causes transactions to fail or set deadlines 1000x too far in the future.

**Patterns to search for:**

```
Date\.now\(\).*(?:deadline|expir|timestamp|block)
```

```
(?:deadline|expir|timestamp).*Date\.now\(\)
```

```
Math\.floor\(Date\.now\(\)\s*/\s*1000\)
```

The third pattern is actually correct usage — flag it as INFO to confirm intentional conversion.

**Severity**: HIGH — Causes transaction failures or security vulnerabilities
**Fix suggestion**: Always use `Math.floor(Date.now() / 1000)` when comparing with or setting Solidity timestamps. Add a utility function `nowInSeconds()`.

#### Scan 4: Address Comparison Without Checksum (MEDIUM)

Ethereum addresses are case-insensitive but `===` comparison is case-sensitive. This causes false negatives when comparing user-entered addresses with on-chain data.

**Patterns to search for:**

```
===.*(?:address|addr|owner|sender|recipient|spender)
```

```
(?:address|addr|owner|sender|recipient|spender).*===
```

Then inspect each match to see if the comparison normalizes case first (`.toLowerCase()` or `getAddress()`).

```
\.toLowerCase\(\).*(?:address|addr)
```

Using `.toLowerCase()` works but `getAddress()` from viem/ethers is preferred because it validates the address format too.

**Severity**: MEDIUM — Causes false negative comparisons
**Fix suggestion**: Use `getAddress()` from viem for normalization, or at minimum `.toLowerCase()` on both sides.

#### Scan 5: BigInt.toString() Without Radix (LOW)

`BigInt.toString()` without a radix argument defaults to base 10, which is usually fine. But when used in contexts expecting hex (like constructing calldata), it produces wrong results.

**Patterns to search for:**

```
\.toString\(\).*(?:hex|data|calldata|bytes|encode)
```

```
(?:hex|data|calldata|bytes|encode).*\.toString\(\)
```

**Severity**: LOW — Mostly harmless but can cause encoding bugs
**Fix suggestion**: Use explicit `toString(16)` for hex contexts or `toHex()` from viem.

#### Scan 6: Loose Equality on Addresses (MEDIUM)

Using `==` instead of `===` for address comparison can cause type coercion issues.

**Patterns to search for:**

```
[^=!]==[^=].*(?:address|addr|0x)
```

```
(?:address|addr|0x).*[^=!]==[^=]
```

**Severity**: MEDIUM — Type coercion can cause false positives
**Fix suggestion**: Always use `===` (and normalize with `getAddress()` first).

#### Scan 7: Missing Wallet Connection Guards (MEDIUM)

Accessing wallet properties (address, chainId, connector) without null checks causes runtime crashes when the wallet disconnects mid-session.

**Patterns to search for:**

```
(?:address|account|chainId)(?:\!|\?)?\.\w+
```

Also check for patterns where `useAccount()` destructured values are used without conditional checks:

```
const\s*\{.*address.*\}\s*=\s*useAccount\(\)
```

Then verify that code using `address` has guard clauses like `if (!address)` or `address &&` or `address?.`.

**Severity**: MEDIUM — Causes runtime crashes
**Fix suggestion**: Always check `isConnected` before accessing wallet state. Use optional chaining on address-derived values.

#### Scan 8: Unguarded Write Calls — `require-network-guard` (HIGH)

Every `writeContract` / `writeContractAsync` call must be preceded by a chain verification guard in the same hook scope. Without this, users on the wrong chain will sign transactions that silently fail or execute against the wrong contract.

**Patterns to search for:**

Find all files containing write calls:
```
writeContract|writeContractAsync
```

Then for each file, check for the presence of a FUNCTIONAL guard pattern. The guard must be invoked (not just imported) and must precede the write call:
```
ensureNetwork\(|chainId\s*===|switchChainAsync\(|await\s+switchChain
```

If a file has write calls but NO invoked guard pattern → flag it.

**False positive reduction**: A file that merely imports `useSwitchChain` but never calls `switchChainAsync()` is NOT guarded. Check for the function CALL (with parentheses), not just the import.

**Severity**: HIGH — CRITICAL if the write is in an approval or token transfer flow
**Fix suggestion**: Add a network guard before every write call. Pattern: `if (!(await ensureNetwork())) { toast.error("Please switch to [chain name]"); return; }`

**Grounding**: MCV audit found `useMoneycombBurn` and `useMoneycombRewards` had write calls with `ensureNetwork()` that returned silently on failure — the button did nothing, no toast, no feedback.

#### Scan 9: Parallel Simulation — `require-simulation-dependency` (CRITICAL)

When `useSimulate*` and `useWrite*` / `writeContract` co-exist in the same hook, the write MUST depend on the simulation result. If simulation fires in parallel with the write call (or the write constructs args inline instead of using `simData.request`), users sign transactions guaranteed to revert.

**Detection pattern:**

Step 1 — Find files with both simulation and write:
```
useSimulate
```
Cross-reference with files also containing:
```
writeContract|writeContractAsync|useWrite
```

Step 2 — In matching files, check if the write references the simulation result:
```
simData\.request|simulation\.data\.request|simulat\w+\.data\.request
```

If the write constructs args inline (e.g., `writeContract({ args: [index] })` instead of `writeContract(simData.request)`), flag it.

**Note**: The pattern `\.request` alone is too broad (matches unrelated property access like `fetch.request`). Always anchor to simulation-related variable names.

Step 3 — Check for simulation error gating:
```
simError|simulat.*error|simData.*error
```

If no error check exists before the write call, flag it.

**Severity**: CRITICAL — User signs tx guaranteed to revert
**Fix suggestion**: Simulation should run reactively (e.g., via a `pendingIndex` prop set when modal opens). Write call should check `simError` before executing. Ideal pattern: `if (simError) { toast.error("Transaction would revert"); return; }`

**Grounding**: MCV audit found `useMoneycombClose` had `useSimulateMoneycombVaultCloseAccount` and `closeAccountWrite` firing in parallel — the simulation provided zero protection.

#### Scan 10: Swallowed Errors — `require-decoded-error-handling` (MEDIUM)

Catch blocks around `writeContract` / `writeContractAsync` calls must provide useful error feedback. Empty catches, console-only catches, and catches without error code discrimination all degrade UX.

**Detection pattern:**

Step 1 — Find catch blocks in files containing write calls:
```
catch\s*\{|catch\s*\(\w+\)\s*\{
```

Step 2 — Flag if catch body is empty (handles both `catch {}` and `catch (e) {}`):
```
catch\s*(?:\(\w+\))?\s*\{\s*\}
```

Step 2b — Flag console-only catches. **Note**: This pattern spans lines in real code (the `{` and `console.error` are typically on separate lines, which single-line grep cannot match). Use a two-step approach:

1. Use Step 1 results to identify catch block locations (file:line)
2. For each catch location, use the Read tool to read the next 3-5 lines after the opening `{`
3. Classify the catch body:
   - **Empty**: Only whitespace/closing `}` → flag
   - **Console-only**: Only `console.log` / `console.error` / `console.warn` calls → flag
   - **Silent return**: Only `return` / `return undefined` → flag
   - **Has user feedback**: Contains `toast`, `throw`, `handleError`, error dispatch → pass

Step 3 — Check for error code discrimination:
```
4001|UserRejectedRequestError|user.*reject|rejected
```

If no check for user rejection (error code 4001) exists, flag it — user rejection is the most common wallet error and should be handled silently (no error toast), not treated as a failure.

Step 4 — Check for error decoding:
```
decodeErrorResult|parseViemError|ContractFunctionRevertedError|BaseError
```

**Severity**: MEDIUM — HIGH if in a financial flow (approval, transfer, deposit)
**Fix suggestion**: At minimum, discriminate user rejection (4001) from on-chain revert. Ideal: decode revert reason and show it to the user. Pattern:
```typescript
catch (error) {
  if ((error as any).code === 4001) return; // User rejected — silent
  toast.error("Transaction failed", { description: decodeError(error) });
}
```

**Grounding**: MCV audit found `approveHc` and `approveAllHc` had catch blocks that were either empty or only logged to console — unhandled promise rejections on wallet reject.

#### Scan 11: Environment Variable Alignment — `env-var-alignment` (HIGH)

Cross-reference `process.env.*` references in source files against actual definitions in `.env*` files. Catches: referenced but undefined vars, secret leak risk (non-`NEXT_PUBLIC_` in client code), and naming mismatches.

**Detection pattern:**

Step 1 — Extract all env var references from source:
```
process\.env\.(\w+)
```
Also scan for Vite-style env access:
```
import\.meta\.env\.(\w+)
```
Scan in `**/*.{ts,tsx,js,jsx}` — build a list of referenced var names with file locations. Use the framework prefix to determine which pattern applies:
- **Next.js** (`NEXT_PUBLIC_`): Uses `process.env`
- **Vite** (`VITE_`): Uses `import.meta.env`
- **Both may coexist** in monorepos

Step 2 — Extract all env var definitions from `.env*` files:
```
^[A-Z_]+=
```
Scan in `.env`, `.env.local`, `.env.production`, `.env.example`, `.env.development` — build a list of defined var names.

Step 3 — Cross-reference:
- **Referenced but not defined**: Flag as HIGH — will be `undefined` at runtime
- **Defined but not referenced**: Flag as INFO — may be dead config

Step 4 — Client/server boundary check:
For each env var referenced in a file containing `"use client"`:
- **Next.js**: If the var does NOT start with `NEXT_PUBLIC_`: Flag as HIGH — secret leak risk (var will be undefined in browser, but the pattern suggests the developer intended it to be available client-side)
- **Vite**: If the var does NOT start with `VITE_`: Flag as HIGH — same issue, different prefix convention

Step 5 — Naming mismatch detection:
Look for vars that share the same suffix but differ in prefix:
```
ALCHEMY_API_KEY vs NEXT_PUBLIC_ALCHEMY_API_KEY
RPC_URL vs NEXT_PUBLIC_RPC_URL
```
If both exist, flag as WARNING — likely one should reference the other, or the developer is confused about which is needed where.

**Severity**: HIGH — server routes crash with undefined, client gets undefined silently
**Fix suggestion**: Ensure every referenced env var is defined in `.env.example`. For client-side usage, always use `NEXT_PUBLIC_` prefix. For server-side env vars needed in API routes, use server-only imports.

**Grounding**: MCV audit found `lib/alchemy.ts` referenced `process.env.ALCHEMY_API_KEY` (server-side) but the `.env.local` only defined `NEXT_PUBLIC_ALCHEMY_API_KEY` — the NFT API route returned 500.

#### Scan 12: Unbounded Receipt Polling — `require-receipt-timeout` (MEDIUM)

`useWaitForTransactionReceipt` calls without a `timeout` property cause infinite loading states on congested chains. Manual polling patterns without bounds are equally dangerous.

**Detection pattern:**

Step 1 — Find receipt waiting hooks:
```
useWaitForTransactionReceipt
```

Step 2 — For each `useWaitForTransactionReceipt` call, use the Read tool to inspect the config object passed to it. Check for a `timeout` property in the configuration.

**Note**: A simple grep for `timeout` in the same file is insufficient — the file may contain `timeout` in unrelated contexts. Instead, read the 5-10 lines surrounding the `useWaitForTransactionReceipt` call and verify that `timeout` appears within the hook's config parameter object.

If `useWaitForTransactionReceipt` is called without `timeout` in its config object → flag.

Step 3 — Check for confirmation count (INFO severity):
```
confirmations
```
For high-value flows (deposit, transfer, swap), suggest `confirmations: 2` or higher.

Step 4 — Find manual polling patterns:
```
setInterval|setTimeout.*receipt|setTimeout.*getTransaction
```
If found, check for `clearInterval`, max iteration count, or time-bound cancellation. Flag if unbounded.

**Severity**: MEDIUM — Causes infinite loading spinner on congested chain
**Fix suggestion**: Always pass `timeout` to `useWaitForTransactionReceipt`. Recommended: `timeout: 60_000` (60 seconds). For manual polling, always include a max iteration count or time-bound cancellation.

**Grounding**: MCV audit found `useOnSuccess` wrapper called `useWaitForTransactionReceipt` without timeout — fixed to use `timeout: 60_000`.

#### Scan 13: Dead Web3 Integrations — `dead-web3-integration` (INFO)

Orphaned hooks, unused ABI exports, and unreferenced contract addresses create confusion and bloat. Web3-specific dead code is particularly dangerous because it can mislead developers into thinking features are active.

**Detection pattern:**

Step 1 — Find all exported custom hooks:
```
export\s+function\s+use\w+
```
Scan in `**/hooks/**/*.{ts,tsx}`. For each exported hook, check if it's imported in any component or page file:
```
import.*{hookName}
```
Flag if never imported.

Step 2 — Find all exported ABI constants:
```
export\s+const\s+\w+Abi
```
For each, check if imported in any wagmi config, hook, or component file. Flag if never imported.

Step 3 — Find contract address config entries:
```
CONTRACTS\.\w+|CONTRACT_ADDRESS|contractAddress
```
For each address entry, check if it's used in any hook, component, or API route. Flag if never referenced.

**Exclusions**: Skip `generated.ts` / `generated/` directories — these are auto-generated and may have unused exports by design.

**Severity**: INFO — MEDIUM if the dead hook wraps a write operation (misleading, potential security risk)
**Fix suggestion**: Remove unused hooks, ABIs, and contract address entries. If intentionally kept for future use, add a comment explaining why.

**Grounding**: MCV audit found `useMoneycombRewards` was never imported in any component, `Nft.ts` ABI was unused, and `getHJBurnStatuses`'s `totalBurned` was dead code.

### Phase 3: Run Oxlint (if available)

If oxlint was detected in Phase 1:

```bash
npx oxlint --deny suspicious --deny correctness --deny perf -f json src/ 2>/dev/null
```

Parse the JSON output and merge findings with the grep-based scan results. Oxlint catches general JS/TS issues that complement the Web3-specific scans.

If oxlint is not available but eslint is:

```bash
npx eslint --format json src/ 2>/dev/null
```

If neither is available, note this in the report and proceed with grep-based results only.

### Phase 4: Generate Report

Write the report to `grimoires/protocol/lint-report.md` with this structure:

```markdown
# dApp Lint Report

**Date**: [timestamp]
**Project**: [project name from package.json]
**Web3 Stack**: [detected libraries and versions]
**Linter**: [oxlint/eslint/grep-only]

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | N |
| HIGH | N |
| MEDIUM | N |
| LOW | N |
| INFO | N |

## CRITICAL Findings

### [Finding Title]
**File**: `path/to/file.ts:42`
**Pattern**: [what was detected]
**Risk**: [what could go wrong]
**Fix**: [specific fix suggestion]

...

## HIGH Findings
...

## Recommendations

1. [Top priority actions]
2. [Quick wins]
3. [Long-term improvements]
```

### Phase 5: Summary Output

After writing the report, output a concise summary to the user:
- Total findings by severity
- Top 3 most critical issues with file:line references
- Whether oxlint/eslint was used or only grep-based scanning
- Path to the full report

## Classification Rules

| Category | Default Severity | Upgrade Condition |
|----------|-----------------|-------------------|
| BigInt coercion | CRITICAL | — |
| Hardcoded addresses | HIGH | CRITICAL if in transaction-building code |
| Timestamp confusion | HIGH | CRITICAL if used in deadline calculations |
| Address comparison | MEDIUM | HIGH if in access control logic |
| toString without radix | LOW | MEDIUM if in encoding context |
| Loose equality | MEDIUM | — |
| Missing wallet guards | MEDIUM | HIGH if in transaction submission flow |

## Edge Cases

- **Monorepo projects**: Scan all packages, not just root `src/`. Use Glob to find all source directories.
- **ethers v5 vs v6**: ethers v6 uses native BigInt, v5 uses ethers.BigNumber. Scan for both patterns.
- **Test files**: Flag findings in test files at INFO severity — they may be intentional mocks.
- **Type-only files**: Skip `.d.ts` files — they contain type definitions, not runtime code.
- **Generated code**: Skip files in `generated/`, `typechain/`, `typechain-types/` — these are auto-generated.

## Anti-Patterns Reference

### The "Number Sandwich"
```typescript
// BAD: Precision loss
const displayBalance = Number(balance) / 1e18;

// GOOD: Use formatUnits
const displayBalance = formatUnits(balance, 18);
```

### The "Timestamp Trap"
```typescript
// BAD: Milliseconds where seconds expected
const deadline = Date.now() + 3600;

// GOOD: Explicit seconds conversion
const deadline = Math.floor(Date.now() / 1000) + 3600;
```

### The "Case-Sensitive Address"
```typescript
// BAD: Case-sensitive comparison
if (userAddress === contractOwner) { ... }

// GOOD: Normalized comparison
if (getAddress(userAddress) === getAddress(contractOwner)) { ... }
```

### The "Phantom Wallet"
```typescript
// BAD: No connection check
const { address } = useAccount();
submitTransaction(address); // crashes if disconnected

// GOOD: Guard clause
const { address, isConnected } = useAccount();
if (!isConnected || !address) return <ConnectButton />;
submitTransaction(address);
```
