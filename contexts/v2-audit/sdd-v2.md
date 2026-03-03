# SDD: construct-protocol v2.0 — Wallet Boundary Verification

> **Status**: DRAFT
> **Upstream PRD**: `grimoires/protocol/prd-v2.md`
> **Target**: `.claude/constructs/packs/protocol/` (installed construct)

## 1. Architecture Overview

construct-protocol is a **prompt-based skill pack** — the "code" is markdown protocols that guide AI agents through verification workflows. Each skill is a `SKILL.md` file containing phased execution instructions with grep patterns, cast commands, and report templates.

**v2.0 changes are purely additive** — new scans append after existing scans, new phases insert between existing phases. No existing behavior is modified.

### Change Map

```
construct.yaml                    → version bump 1.0.0 → 2.0.0
                                    + agent-browser optional dependency

skills/dapp-lint/SKILL.md         → +4 scans (8-11) in Phase 2
                                    +2 scans (12-13) in Phase 2
                                    (6 total new scans)

skills/contract-verify/SKILL.md   → +Phase 3.5 (Semantic Activation)
                                    between existing Phase 3 and Phase 4

skills/dapp-e2e/SKILL.md          → Phase 3 alternative (RPC interception)
                                    +Phase 5.5 (Wallet Edge Case Matrix)

skills/simulate-flow/SKILL.md     → +Phase 2.5 (Frontend Simulation Check)
                                    between existing Phase 2 and Phase 3

CLAUDE.md                         → Update skill descriptions
README.md                         → Version + capability docs
scripts/detect-state.sh           → agent-browser detection
```

## 2. Detailed Design

### 2.1 dapp-lint: 6 New Scans (FR-1, FR-4, FR-5)

All new scans are added to **Phase 2: Web3 Anti-Pattern Scanning**, after existing Scan 7.

#### Scan 8: `require-network-guard`

**Intent**: Every `writeContract` / `writeContractAsync` call must be preceded by a chain verification guard in the same hook scope.

**Detection Pattern**:
1. Grep for all files containing `writeContract` or `writeContractAsync`
2. For each file: grep for guard patterns: `ensureNetwork`, `chainId ===`, `switchChain`, `useSwitchChain`
3. If a file has write calls but no guard pattern → flag

**Grep Patterns**:
```
# Find write calls
pattern: "writeContract|writeContractAsync"
glob: "**/*.{ts,tsx}"

# Find guards (same files)
pattern: "ensureNetwork|chainId\\s*===|switchChain|useSwitchChain"
```

**Report Format**:
```
SCAN 8: require-network-guard
Severity: HIGH (CRITICAL if in approval/transfer flow)

[FILE]: hooks/use-moneycomb-close.ts
  writeContract found at line 45
  No chain verification guard found in hook scope
  → Transaction may fire on wrong chain
```

#### Scan 9: `require-simulation-dependency`

**Intent**: When `useSimulate*` and `useWrite*` / `writeContract` co-exist in the same hook, the write MUST reference the simulation result (`simData.request`) — not construct args inline.

**Detection Pattern**:
1. Grep for files containing both `useSimulate` AND (`useWrite` OR `writeContract`)
2. In matching files: check if `request` from simulation is passed to write
3. Flag if write args are constructed inline (not from simulation result)

**Grep Patterns**:
```
# Find co-occurrence files
pattern: "useSimulate"
glob: "**/*.{ts,tsx}"

# Then in matching files, check for:
pattern: "writeContract|writeContractAsync"
# And verify presence of:
pattern: "\\.request|simData|simulat.*\\.data"
```

**Report Format**:
```
SCAN 9: require-simulation-dependency
Severity: CRITICAL

[FILE]: hooks/use-moneycomb-close.ts
  useSimulateMoneycombVaultCloseAccount at line 12
  writeContract at line 30
  Write args constructed inline — simulation result not referenced
  → User may sign transaction guaranteed to revert
```

#### Scan 10: `require-decoded-error-handling`

**Intent**: Catch blocks around write calls must decode errors, not swallow them.

**Detection Pattern**:
1. Grep for `catch` blocks in files containing `writeContract` / `writeContractAsync`
2. Flag: empty catch `catch {}`
3. Flag: catch body is only `console.error` / `console.log`
4. Flag: no check for `error.code === 4001` or `UserRejectedRequestError`
5. Flag: no call to error decoding utility

**Grep Patterns**:
```
# Find catch blocks in write-containing files
pattern: "catch\\s*\\{|catch\\s*\\(\\w+\\)\\s*\\{"
glob: "**/*.{ts,tsx}"

# Check for proper error handling
pattern: "4001|UserRejectedRequestError|decodeErrorResult|parseViemError"
```

**Report Format**:
```
SCAN 10: require-decoded-error-handling
Severity: MEDIUM (HIGH if in financial flow)

[FILE]: hooks/use-moneycomb-account.ts
  catch block at line 92 — body is empty (only re-throws)
  No error code discrimination (4001 vs revert vs network)
  → Generic "transaction failed" for solvable issues
```

#### Scan 11: `env-var-alignment`

**Intent**: Cross-reference `process.env.*` references against `.env*` file definitions.

**Detection Pattern**:
1. Grep all source files for `process.env.` — extract var names
2. Read all `.env*` files — extract defined var names
3. Cross-reference: flag vars referenced but not defined
4. Flag: non-`NEXT_PUBLIC_` var in `'use client'` file
5. Flag: naming mismatch (e.g., `ALCHEMY_API_KEY` vs `NEXT_PUBLIC_ALCHEMY_API_KEY`)

**Grep Patterns**:
```
# Find all env var references
pattern: "process\\.env\\.(\\w+)"
glob: "**/*.{ts,tsx,js,jsx}"

# Find all env definitions
pattern: "^[A-Z_]+=.+"
glob: ".env*"

# Find client directive files
pattern: "use client"
glob: "**/*.{ts,tsx}"
```

**Report Format**:
```
SCAN 11: env-var-alignment
Severity: HIGH

ALCHEMY_API_KEY referenced in lib/alchemy.ts (server)
NEXT_PUBLIC_ALCHEMY_API_KEY referenced in hooks/use-nfts.ts (client)
  → Same logical variable with different prefix — likely mismatch
  → Server-side may get undefined if only NEXT_PUBLIC_ version defined
```

#### Scan 12: `require-receipt-timeout` (FR-4)

**Intent**: `useWaitForTransactionReceipt` must have a `timeout` property.

**Detection Pattern**:
1. Grep for `useWaitForTransactionReceipt`
2. In each call: check if config object includes `timeout`
3. Also find manual polling patterns (`setInterval` / recursive `setTimeout` on receipt)
4. Flag: no `clearInterval` / max iteration count

**Grep Patterns**:
```
# Find receipt waiting
pattern: "useWaitForTransactionReceipt"
glob: "**/*.{ts,tsx}"

# Check for timeout in same context
pattern: "timeout"

# Find manual polling
pattern: "setInterval|setTimeout.*receipt|setTimeout.*getTransaction"
glob: "**/*.{ts,tsx}"
```

#### Scan 13: `dead-web3-integration` (FR-5)

**Intent**: Find orphaned hooks, ABIs, and contract addresses.

**Detection Pattern**:
1. Grep for `export function use*` in hooks directories
2. For each: check if imported in any component/page
3. Grep for `export const *Abi` — check if imported
4. Grep for contract address config entries — check if used

**Grep Patterns**:
```
# Find exported hooks
pattern: "export\\s+function\\s+use\\w+"
glob: "**/hooks/**/*.{ts,tsx}"

# Find ABI exports
pattern: "export\\s+const\\s+\\w+Abi"
glob: "**/*.{ts,tsx}"

# Cross-reference: search for import of each name
pattern: "import.*{hookName}" (dynamic per finding)
```

### 2.2 contract-verify: Phase 3.5 Semantic Activation (FR-2)

Inserted between existing Phase 3 (Read On-Chain State) and Phase 4 (Scan Frontend).

#### Phase 3.5: Activation State Analysis

After Phase 3 reads all view function return values, apply semantic interpretation rules:

**Semantic Rules Table** (embedded in SKILL.md):

| Return Value | Semantic Meaning | Frontend Cross-Reference |
|---|---|---|
| `address(0)` from token/reward/fee getter | Feature disabled / not initialized | Grep for related UI (buttons, forms, claim handlers) |
| `paused() == true` | Contract paused | All write buttons should be disabled |
| `totalSupply == maxSupply` or `== cap` | Sold out | Mint/deposit UI should show "sold out" |
| `owner() == address(0)` | Ownership renounced | Admin features should be hidden |
| Timestamp getter < `block.timestamp` | Expired deadline/auction | UI should show "ended" |

**Execution**:
1. Review Phase 3 results for any values matching semantic rules
2. For each match: grep frontend for related hooks/components
3. Flag if an interactive element (button, form, submit handler) would trigger a write to the disabled/paused/expired feature
4. Severity: CRITICAL if user can trigger a guaranteed-revert transaction

**Example Finding**:
```
PHASE 3.5: Semantic Activation Analysis

rewardToken() = 0x0000000000000000000000000000000000000000
  Semantic: FEATURE_DISABLED (rewards not initialized)
  Frontend: components/rewards-panel.tsx has "Claim Rewards" button
  Hook: hooks/use-moneycomb-rewards.ts calls claimRewards()
  → CRITICAL: User can click "Claim Rewards" but transaction WILL revert
  → Fix: Hide rewards UI or disable button when rewardToken == address(0)
```

### 2.3 dapp-e2e: agent-browser Integration (FR-3)

#### Phase 3 Alternative: RPC Interception (when agent-browser available)

The existing Phase 3 mock wallet approach is preserved as fallback. When agent-browser MCP is detected in Phase 1, an alternative Phase 3 activates:

**Detection** (added to Phase 1):
```
Check if agent-browser MCP is available:
- Look for agent-browser in MCP server configuration
- Try invoking agent-browser's `navigate` command
- If available: set AGENT_BROWSER=true, use Phase 3-AB
- If not: set AGENT_BROWSER=false, use Phase 3-PW (existing)
```

**Phase 3-AB: RPC Interception via agent-browser**:
```
Instead of injecting mock window.ethereum, use agent-browser's `route` command
to intercept JSON-RPC calls at the browser network level:

1. Navigate to the dApp URL
2. Set up RPC route interception:
   - route intercept for eth_chainId → return correct chain
   - route intercept for eth_accounts → return test address
   - route intercept for eth_sendTransaction → capture, return mock hash
   - route intercept for eth_getTransactionReceipt → return success receipt
3. This tests the actual wallet → connector → wagmi → viem → RPC pipeline
   unmodified — no mock injection means real code paths execute
```

#### Phase 5.5: Wallet Edge Case Matrix (NEW)

Added after Phase 5. Only runs when `AGENT_BROWSER=true`.

**Test Matrix** (7 edge cases):

| # | Test Case | RPC Interception | Expected UI |
|---|-----------|-----------------|-------------|
| 1 | Wrong chain → write | `eth_chainId` returns `0x1` | Network guard fires, toast |
| 2 | User rejects tx | `eth_sendTransaction` returns `{error:{code:4001}}` | UI resets, no error toast |
| 3 | Receipt timeout | `eth_getTransactionReceipt` returns `null` indefinitely | Timeout toast, explorer link |
| 4 | On-chain revert | Receipt with `status: 0` + revert data | Decoded error message |
| 5 | Chain switch mid-batch | Change `eth_chainId` between iterations | Graceful partial-success |
| 6 | Disconnect mid-flow | Remove `eth_accounts` response | UI returns to connect state |
| 7 | Hardware wallet hang | `wallet_switchEthereumChain` never responds | Post-switch verification catches |

**Dogfood Integration**:
- Each test case produces a structured finding with severity + repro steps + screenshot
- Results formatted as dogfood-compatible QA output
- `agent-browser screenshot --annotate` at each step

**Graceful Degradation**: When `AGENT_BROWSER=false`, Phase 5.5 is skipped with an INFO note in the report.

### 2.4 simulate-flow: Phase 2.5 Frontend Simulation Check (FR-6)

Inserted between existing Phase 2 (Gather Parameters) and Phase 3 (Pre-flight Checks).

#### Phase 2.5: Client-Side Simulation Verification

For each write flow discovered in Phase 1:

1. Check if a `useSimulate*` hook exists for the same contract function
2. Check if the simulation result gates the write invocation (the write references `request` from simulation)
3. Classify:
   - **GATED**: Simulation exists and gates write → no agent action needed
   - **PARALLEL**: Simulation exists but doesn't gate write → CRITICAL flag
   - **AGENT_ONLY**: No client-side simulation → recommendation to add

**Grep Patterns**:
```
# For each write function found in Phase 1:
# e.g., closeAccount → search for useSimulateMoneycombVaultCloseAccount
pattern: "useSimulate.*{FunctionName}"
glob: "**/*.{ts,tsx}"
```

**Report Format**:
```
PHASE 2.5: Frontend Simulation Check

Flow: closeAccount (MoneycombVault)
  Client simulation: useSimulateMoneycombVaultCloseAccount ✓
  Simulation gates write: YES (pendingIndex dependency) ✓
  Status: GATED

Flow: openAccount (MoneycombVault)
  Client simulation: NONE
  Status: AGENT_ONLY
  → Recommendation: Add useSimulateMoneycombVaultOpenAccount
```

## 3. construct.yaml Changes

```yaml
# Version bump
version: 2.0.0

# Add optional dependency
runtime_requirements:
  external_tools:
    - foundry (cast): required
    - node: required
    - agent-browser: optional — enables RPC interception in dapp-e2e
```

## 4. CLAUDE.md and README.md Updates

**CLAUDE.md**: Update dapp-lint description to mention wallet boundary scans. Add note about agent-browser optional integration for dapp-e2e.

**README.md**: Update version to 2.0.0. Add "What's New in v2.0" section listing the 6 new scans, semantic activation rules, agent-browser integration, and frontend simulation check.

## 5. Backward Compatibility

- All v1.0 invocations produce identical results (existing scans/phases unchanged)
- New scans produce additional findings (never suppress existing ones)
- `dapp-e2e` mock wallet approach preserved as fallback
- Phase numbering: 3.5, 5.5, 2.5 — never renumber existing phases
- Report format unchanged (additional sections append)
- No changes to golden path routing or state detection

## 6. Risk Mitigations

| Risk | Mitigation |
|------|------------|
| Grep false positives on Scan 8 | Guard detection checks for any of 4 patterns, not exact code structure |
| Scan 9 false positives (legitimate parallel usage) | Flag as INFO if simulation is used for display only, CRITICAL only if write doesn't reference sim result |
| Scan 13 over-flagging generated code | Exclude `generated.ts` / `generated/` from dead code detection |
| Phase 3.5 rigid `address(0)` interpretation | Note in report that address(0) MAY be intentional — recommend verification |
| agent-browser not available | Explicit graceful degradation — Phase 5.5 skipped, Phase 3-PW used |

---

*SDD generated for construct-protocol v2.0 upgrade*
*Target: `.claude/constructs/packs/protocol/` skill files*
