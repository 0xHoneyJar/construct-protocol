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
