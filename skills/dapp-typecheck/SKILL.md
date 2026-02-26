# dapp-typecheck — Contract Type Verification

## Purpose

You are a Web3 type verification agent. Your job is to ensure that the TypeScript types used in the frontend EXACTLY match the deployed smart contract ABIs. Type drift — where the frontend types no longer match what's actually deployed — is one of the most insidious Web3 bugs because it compiles fine but fails at runtime with cryptic revert errors.

## Execution Protocol

### Phase 1: Discover Codegen Configuration

You MUST find the project's contract type generation setup.

1. Search for wagmi codegen config:
   ```
   Glob: **/wagmi.config.{ts,js,mjs}
   ```

2. Search for alternative codegen configs:
   ```
   Glob: **/foundry.toml
   Glob: **/hardhat.config.{ts,js}
   Glob: **/.graphql-codegen.{ts,yml,yaml}
   ```

3. Search for manual ABI imports:
   ```
   Grep: import.*(?:abi|ABI).*from
   ```

4. Read `package.json` to check for codegen scripts:
   ```
   Grep: "generate|codegen|typechain|wagmi" in package.json scripts
   ```

5. Classify the project's type generation strategy:
   - **wagmi CLI**: Uses `@wagmi/cli` with plugins (etherscan, foundry, react, actions)
   - **TypeChain**: Uses typechain for ethers-based projects
   - **Manual ABIs**: ABIs copied as JSON files or TypeScript constants
   - **Foundry output**: Types generated from forge build artifacts
   - **None detected**: No codegen — this is itself a finding

### Phase 2: Inventory Contract Interactions

Scan the codebase to build a complete inventory of every contract interaction.

1. Find all wagmi hook usage:
   ```
   Grep: use(?:Read|Write|Simulate|Watch)Contract
   ```
   For each match, extract:
   - The contract ABI reference
   - The function name being called
   - The arguments being passed

2. Find all viem client calls:
   ```
   Grep: (?:readContract|writeContract|simulateContract|multicall)\(
   ```

3. Find all ethers contract instances (if ethers is used):
   ```
   Grep: new\s+(?:ethers\.)?Contract\(
   ```
   ```
   Grep: \.connect\(.*(?:signer|provider)\)
   ```

4. Find all ABI definitions in the project:
   ```
   Glob: **/*abi*.{ts,js,json}
   Glob: **/abis/**
   Glob: **/contracts/**/*.{ts,js,json}
   ```

5. Build an inventory table:
   | File:Line | Contract | Function | ABI Source | Args |
   |-----------|----------|----------|------------|------|

### Phase 3: Type Generation Freshness Check

Determine if the generated types are current.

1. If wagmi CLI is configured, check the generated output:
   ```
   Glob: **/generated.ts
   Glob: **/wagmi.generated.ts
   Glob: **/__generated__/**
   ```

2. Compare timestamps:
   - When was the generated file last modified?
   - When was the wagmi config last modified?
   - When was any ABI file last modified?
   - If ABI files are newer than generated types, types are STALE.

3. Check git status for uncommitted type changes:
   ```bash
   git status --porcelain -- '**/generated*' '**/typechain*' '**/__generated__*' 2>/dev/null
   ```

4. If types appear stale, flag this as a HIGH finding.

### Phase 4: Regenerate Types

If a codegen tool is configured and types appear stale, run regeneration.

**For wagmi CLI:**
```bash
npx wagmi generate 2>&1
```

**For TypeChain:**
```bash
npx typechain --target ethers-v6 --out-dir src/typechain 'abi/*.json' 2>&1
```

**For foundry:**
```bash
forge build 2>&1
```

Capture the output. If generation fails, this is a CRITICAL finding — it means the codegen config itself is broken.

After regeneration, check if any files changed:
```bash
git diff --stat -- '**/generated*' '**/typechain*' '**/__generated__*' 2>/dev/null
```

If files changed, types were stale. Record every changed file.

### Phase 5: TypeScript Verification

Run the TypeScript compiler in check mode to find type errors.

```bash
npx tsc --noEmit 2>&1
```

Parse the output for errors. Focus especially on errors in files that import contract ABIs or use contract interaction hooks/functions.

Categorize errors:

| Error Pattern | Likely Cause | Severity |
|---------------|-------------|----------|
| `Property 'X' does not exist on type` | ABI changed, function renamed or removed | CRITICAL |
| `Argument of type 'X' is not assignable to parameter of type 'Y'` | Parameter type mismatch (e.g., string where bigint expected) | CRITICAL |
| `Type 'X' is not assignable to type 'Y'` in return values | Return type changed in contract | HIGH |
| `Expected N arguments, but got M` | Function signature changed | CRITICAL |
| `Cannot find module` for ABI imports | Missing or moved ABI files | HIGH |
| Generic TS errors in non-contract code | Unrelated type issues | LOW |

### Phase 6: Cross-Reference ABI vs Usage

This is the deepest check. For each contract interaction found in Phase 2:

1. Read the ABI definition for that contract
2. Find the function in the ABI
3. Verify:
   - **Function exists**: Does the function name in the frontend call match an ABI entry?
   - **Parameter count**: Does the number of arguments match?
   - **Parameter types**: Do the TypeScript types align with Solidity types?
     - `uint256` → `bigint` (NOT `number`)
     - `address` → `` `0x${string}` `` or `Address`
     - `bytes` → `` `0x${string}` `` or `Hex`
     - `bytes32` → `` `0x${string}` `` or `Hash`
     - `bool` → `boolean`
     - `string` → `string`
     - `tuple` → object with named fields
     - `uint8/uint16/.../uint128` → `number` is OK for small uints, `bigint` for uint256
   - **Return type handling**: Is the return type correctly destructured?
   - **Overloaded functions**: If the contract has overloads, is the correct one being called?

4. For each mismatch, record:
   - The file and line of the frontend call
   - The expected type from the ABI
   - The actual type being passed
   - The risk: what happens at runtime if this mismatch hits

### Phase 7: Check for Phantom References

Search for contract functions that are called in the frontend but DON'T exist in any ABI:

1. Extract all function names from `useReadContract`, `useWriteContract`, etc.
2. Extract all function names from all ABIs
3. Find the set difference: functions called but not in any ABI

These are phantom references — they will fail at runtime. Mark as CRITICAL.

Also check the reverse: ABI functions that are never called. This is INFO-level — it may indicate unused contract functionality or missing frontend features.

### Phase 8: Generate Report

Write the report to `grimoires/protocol/typecheck-report.md`:

```markdown
# dApp Type Verification Report

**Date**: [timestamp]
**Project**: [name]
**Codegen**: [wagmi CLI / TypeChain / manual / none]
**Types Fresh**: [yes/no — were types stale before regeneration?]

## Summary

| Category | Count |
|----------|-------|
| Type Mismatches | N |
| Stale Types | N |
| Phantom References | N |
| Missing ABIs | N |
| TSC Errors (contract-related) | N |

## CRITICAL: Type Mismatches

### [Contract].[function]
**Frontend**: `file.ts:42` — passes `number` for amount
**ABI expects**: `uint256` (bigint)
**Runtime risk**: Transaction will revert or silently truncate value
**Fix**: Change `amount` to `BigInt(amount)` or use `parseUnits()`

...

## Drift Analysis

| Contract | ABI Last Modified | Generated Types | Status |
|----------|------------------|-----------------|--------|
| Token | 2026-02-20 | 2026-02-15 | STALE |
| Governor | 2026-02-20 | 2026-02-20 | FRESH |

## Phantom References
Functions called in frontend with no matching ABI entry:
- `contract.claimRewards()` at `src/hooks/useRewards.ts:28` — not in TokenABI

## Unused ABI Functions
Functions in ABIs never called from frontend:
- `TokenABI.pause()` — may be admin-only
- `TokenABI.unpause()` — may be admin-only
```

### Phase 9: Summary Output

Present to the user:
- Whether types were fresh or stale
- Number of type mismatches found (with top 3 most critical)
- Whether `tsc --noEmit` passes
- Any phantom references (functions called but not in ABI)
- Path to the full report

## Solidity-to-TypeScript Type Mapping Reference

| Solidity Type | TypeScript Type (viem) | TypeScript Type (ethers v6) | Common Mistake |
|---------------|----------------------|---------------------------|----------------|
| `uint256` | `bigint` | `bigint` | Using `number` |
| `int256` | `bigint` | `bigint` | Using `number` |
| `uint8`-`uint128` | `number` or `bigint` | `number` or `bigint` | Usually fine |
| `address` | `` `0x${string}` `` | `string` | No checksum validation |
| `bool` | `boolean` | `boolean` | — |
| `string` | `string` | `string` | — |
| `bytes` | `` `0x${string}` `` | `string` | Not hex-encoding |
| `bytes32` | `` `0x${string}` `` | `string` | Not hex-encoding |
| `uint256[]` | `readonly bigint[]` | `bigint[]` | Mutable array type |
| `tuple(...)` | Named object | Named object | Missing field names |
| `enum` | `number` | `number` | Using string values |

## Edge Cases

- **Proxy contracts**: The ABI might be for the proxy, not the implementation. Check for proxy patterns (`delegatecall`, `ERC1967Proxy`) and verify the implementation ABI is used.
- **Diamond pattern (EIP-2535)**: Multiple facets share an address. Verify the correct facet ABI is used for each function.
- **Upgradeable contracts**: After an upgrade, the ABI changes but the address stays the same. This is the primary source of type drift.
- **Multi-chain deployments**: Same contract may have different ABIs on different chains if deployed at different times. Check per-chain ABI configurations.
- **ABI encoding edge cases**: `tuple[]` types need special attention — viem and ethers handle nested array encoding differently.
