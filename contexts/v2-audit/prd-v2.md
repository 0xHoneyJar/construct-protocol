# PRD: construct-protocol v2.0 — Wallet Boundary Verification

> **Status**: DRAFT
> **Author**: Protocol (plan-and-analyze)
> **Grounding**: MCV vault audit (2026-03-02), Gemini Deep Research (Uniswap/Relay/LayerZero/Zora)
> **Upstream**: https://github.com/0xHoneyJar/construct-protocol

## 1. Problem Statement

The construct-protocol v1.0 verifies two things: (1) on-chain state vs frontend constants, and (2) code-level Web3 anti-patterns (BigInt safety, address checksums). A real production audit of a Berachain vault dApp revealed a third domain that v1.0 completely ignores: **the wallet boundary** — the browser-level layer where chain switching, transaction signing, error propagation, and receipt polling actually happen.

### Bugs v1.0 Missed (Grounded in Real Audit)

| Bug | Category | Impact | v1.0 Coverage |
|-----|----------|--------|---------------|
| `approveHc` / `approveAllHc` without try/catch | Error handling | Unhandled promise rejection on wallet reject | `abi-audit` Phase 4B does shallow grep — didn't catch |
| `useSimulateContract` fires in parallel with `writeContract` | Simulation gating | Zero protection from simulation | `simulate-flow` runs agent-side only — never checks frontend code |
| `ensureNetwork()` failure returns silently | Network guard | Button does nothing, no toast | Not covered at all |
| `rewardToken()` = `address(0)` but full rewards UI exists | Activation state | `claimRewards()` guaranteed revert | `contract-verify` reports raw values, no semantic interpretation |
| `ALCHEMY_API_KEY` vs `NEXT_PUBLIC_ALCHEMY_API_KEY` | Env alignment | NFT API route 500 | Not covered at all |
| `useMoneycombRewards` never imported, `Nft.ts` ABI unused | Dead integration | Code bloat, confusion | Delegates to oxlint — no Web3-specific detection |
| `useWaitForTransactionReceipt` without timeout | Receipt lifecycle | Infinite loading on congestion | Not covered at all |

> Sources: MCV audit session (2026-03-02), hooks/use-moneycomb-account.ts, hooks/use-moneycomb-close.ts, hooks/use-moneycomb-burn.ts, lib/alchemy.ts

### Research Validation

Gemini Deep Research across Uniswap, Relay, LayerZero, and Zora confirms these are not edge cases — they're architectural patterns that top-tier protocols enforce at the infrastructure level:

- **Uniswap**: Simulation gates write (request object dependency injection). Error taxonomy distinguishes 4001 (user reject) from custom revert. TransactionReducer persists tx state globally.
- **Relay**: Cross-chain intent status polling with bounded timeouts. Step-indexed state machine for multi-leg transactions.
- **LayerZero**: Middleware wrapper pattern — `useWriteContract` never imported directly in components. Post-switch chain verification.
- **Zora**: `address(0)` = feature disabled. Hook Registry for dynamic capability discovery. Rendering suppression on inactive features.

> Sources: Gemini Deep Research output (dapp-landscape-2026), contexts/base/web3-dapp-ux.md

## 2. Vision

construct-protocol v2.0 doesn't just compare the frontend to the chain — it verifies the entire path from the user's click to the chain's receipt. It catches the bugs that live in the wallet boundary: wrong chain, swallowed errors, parallel simulation, stale feature flags, env var mismatches, and dead integrations. When combined with `agent-browser`, it can _execute_ wallet edge cases in a real browser, not just grep for them.

## 3. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Catch network guard gaps | `dapp-lint` Scan 8 finds unguarded write paths | Would have flagged 3/5 MCV write hooks |
| Catch simulation gating | `dapp-lint` Scan 9 detects parallel sim+write | Would have flagged `useMoneycombClose` |
| Catch swallowed errors | `dapp-lint` Scan 10 finds empty/shallow catch blocks | Would have flagged `approveHc`/`approveAllHc` |
| Catch env var drift | `dapp-lint` Scan 11 cross-references env files | Would have flagged ALCHEMY_API_KEY mismatch |
| Interpret on-chain state | `contract-verify` Phase 3.5 flags `address(0)` features | Would have flagged stale `CONTRACTS.RewardToken` |
| Find dead integrations | New detection scan across hooks/ABIs/addresses | Would have flagged `useMoneycombRewards`, `Nft.ts` |
| Test wallet boundary | `dapp-e2e` + `agent-browser` RPC interception | Can simulate wrong-chain, rejection, timeout, disconnect |
| Receipt lifecycle | Scan for unbounded polling/missing timeout | Would have flagged `useOnSuccess` |

## 4. Functional Requirements

### FR-1: `dapp-lint` — 4 New Scans (P0)

**Scan 8: `require-network-guard`**
- Detect all `writeContract` / `writeContractAsync` invocations
- For each: verify a chain verification guard exists in the same hook scope
- Guard patterns: `ensureNetwork`, `chainId === `, `switchChain`, `useSwitchChain`
- Severity: HIGH (CRITICAL if in a token transfer/approval flow)
- Failure mode prevented: Transaction fires on wrong chain

**Scan 9: `require-simulation-dependency`**
- Detect co-occurrence of `useSimulate*` and `useWrite*` / `writeContract` in same hook
- Verify: write function's args reference `simData.request` (not inline construction)
- Flag: `writeContract` called in same synchronous function as `setAccountIndex` or equivalent simulation trigger
- Severity: CRITICAL
- Failure mode prevented: User signs tx guaranteed to revert

**Scan 10: `require-decoded-error-handling`**
- Detect all `catch` blocks associated with `writeContract` / `writeContractAsync` calls
- Flag: empty catch `catch {}`
- Flag: catch body is only `console.error` / `console.log`
- Flag: no check for `error.code === 4001` or `UserRejectedRequestError`
- Flag: no call to error decoding utility (`decodeErrorResult`, `parseViemError`, etc.)
- Severity: MEDIUM (HIGH if in a financial flow)
- Failure mode prevented: Generic "transaction failed" for solvable issues

**Scan 11: `env-var-alignment`**
- Extract all `process.env.*` references from source files
- Extract all variable definitions from `.env*` files
- Cross-reference: flag vars referenced but not defined
- Flag: non-`NEXT_PUBLIC_` var referenced in `'use client'` file (secret leak risk)
- Flag: `NEXT_PUBLIC_` vs non-`NEXT_PUBLIC_` naming mismatch for same logical var
- Severity: HIGH
- Failure mode prevented: Server routes crash, client gets `undefined`

### FR-2: `contract-verify` — Semantic Activation Rules (P0)

**New Phase 3.5: Activation State Analysis**

After reading all view functions in Phase 3, apply semantic interpretation:

| Return Value | Semantic Meaning | Frontend Cross-Reference |
|---|---|---|
| `address(0)` from token/reward/fee getter | Feature disabled / not initialized | Grep for related UI components — flag if interactive |
| `paused() == true` | Contract paused | All write buttons should be disabled |
| `totalSupply == maxSupply` or `totalSupply == cap` | Sold out | Mint/deposit UI should reflect "sold out" |
| `owner() == address(0)` | Ownership renounced | Admin features should be hidden |
| Timestamp getter < `block.timestamp` | Expired deadline/auction | UI should show "ended" |

For each semantic hit: search frontend for related hooks/components and flag if an interactive element (button, form, submit handler) would trigger a write to the disabled feature.

### FR-3: `dapp-e2e` — agent-browser Native Integration (P1)

**Replace Phase 3 (Wallet Mock) with RPC Interception:**

When `agent-browser` is available, use its `route` command to intercept JSON-RPC calls at the browser network level instead of injecting a mock `window.ethereum`. This tests the actual wallet → connector → wagmi → viem → RPC pipeline unmodified.

**New Phase 5.5: Wallet Edge Case Matrix:**

| Test Case | agent-browser Method | Expected UI Behavior |
|---|---|---|
| Wrong chain → write | Mock `eth_chainId` to return `0x1` | Network guard fires, toast shown |
| User rejects tx | Mock `eth_sendTransaction` with `{error:{code:4001}}` | UI resets, no error toast, retry possible |
| Receipt timeout | Mock `eth_getTransactionReceipt` to return `null` indefinitely | Timeout toast, block explorer link |
| On-chain revert | Return receipt with `status: 0` + revert data | Decoded error message shown |
| Chain switch mid-batch | Change `eth_chainId` between loop iterations | Graceful partial-success handling |
| Disconnect mid-flow | Remove `eth_accounts` response | UI returns to connect state |
| Hardware wallet hang | `wallet_switchEthereumChain` never responds (timeout) | Post-switch verification catches it |

**Dogfood Integration:**
- `dapp-e2e` discovers flows and generates test matrix
- `agent-browser` executes each test with `screenshot --annotate` at each step
- Report structured as `dogfood`-compatible QA output with severity + repro + screenshots

**Graceful Degradation:** When `agent-browser` is NOT available, fall back to existing Playwright mock wallet approach (v1.0 behavior preserved).

### FR-4: Receipt Lifecycle Checks (P1)

Add to `dapp-lint` Phase 2 or as a new scan:

**Scan 12: `require-receipt-timeout`**
- Find all `useWaitForTransactionReceipt` calls
- Flag: no `timeout` property in config object
- Flag: no `confirmations` property (INFO severity — suggest for high-value flows)
- Find manual polling patterns (`setInterval` / recursive `setTimeout` on receipt)
- Flag: no `clearInterval` / max iteration count / time-bound cancellation
- Severity: MEDIUM
- Failure mode prevented: Infinite loading on congested chain

### FR-5: Dead Integration Detection (P2)

New scan in `dapp-lint` or standalone:

**Scan 13: `dead-web3-integration`**
- Find all exported custom hooks that wrap contract interactions (`export function use*`)
- Cross-reference: check if imported in any component/page file
- Find all exported ABI constants (`export const *Abi`)
- Cross-reference: check if imported in wagmi config or any hook
- Find all entries in contract address config (`CONTRACTS.*` or similar)
- Cross-reference: check if used in any hook, component, or API route
- Severity: INFO (MEDIUM if the dead hook wraps a write operation)
- Failure mode prevented: Code bloat, confusion, stale integrations

### FR-6: `simulate-flow` — Frontend Simulation Verification (P2)

**New Phase 2.5: Client-Side Simulation Check**

For each write flow discovered in Phase 1:
- Check if a `useSimulate*` hook exists for the same contract function
- Check if the simulation result gates the write invocation
- Report: "Flow X has client-side simulation" vs "Flow X relies on agent-side simulation only"
- Recommendation: flows without client-side simulation should add it

## 5. Technical Requirements

### 5.1 File Changes

| File | Change Type | Description |
|------|------------|-------------|
| `construct.yaml` | Modify | Version bump 1.0.0 → 2.0.0, add `agent-browser` optional dependency |
| `skills/dapp-lint/SKILL.md` | Modify | Add Scans 8-13 (6 new scans) |
| `skills/contract-verify/SKILL.md` | Modify | Add Phase 3.5 (Semantic Activation) |
| `skills/dapp-e2e/SKILL.md` | Modify | Add RPC interception Phase 3 alternative + Phase 5.5 wallet matrix |
| `skills/simulate-flow/SKILL.md` | Modify | Add Phase 2.5 (Frontend Simulation Check) |
| `CLAUDE.md` | Modify | Update skill descriptions |
| `README.md` | Modify | Update version, document new capabilities |
| `scripts/detect-state.sh` | Modify | Detect `agent-browser` availability |

### 5.2 Constraints

- All skill changes are additive — existing scan patterns/phases unchanged
- New scans append after existing scans (Scan 8+ after Scan 7)
- New phases insert between existing phases (Phase 3.5 between 3 and 4)
- `agent-browser` is optional — skills degrade gracefully without it
- Grep patterns must work with ripgrep syntax
- Report format unchanged (grimoires/protocol/*.md)

### 5.3 Backward Compatibility

- All v1.0 invocations produce identical results
- New scans produce additional findings (never suppress existing ones)
- `dapp-e2e` mock wallet approach preserved as fallback when agent-browser unavailable
- No changes to golden path routing or state detection logic

## 6. Scope

### In Scope (v2.0)
- 6 new lint scans in `dapp-lint`
- Semantic activation rules in `contract-verify`
- agent-browser RPC interception in `dapp-e2e`
- Frontend simulation check in `simulate-flow`
- Version bump, docs update

### Out of Scope (Future)
- Custom ESLint plugin generation (v3.0 — compile lint scans into installable rules)
- Foundry fork testing integration (use `anvil --fork-url` for live simulation)
- Cross-chain intent lifecycle tracking (Relay/LayerZero specific)
- Formal verification integration (Certora, Halmos)
- WebSocket receipt subscription (alternative to polling)
- Multi-wallet connection state machine verification

## 7. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Grep patterns produce false positives | Noisy reports, developer fatigue | Tune patterns against MCV codebase; document known false positive patterns |
| agent-browser not installed in most environments | E2E skill falls back to Playwright scripts | Explicit graceful degradation; v1.0 mock wallet preserved |
| Semantic rules too rigid (address(0) may be valid in some contexts) | False CRITICAL findings | Allow INFO-level override for documented exceptions |
| Phase 3.5 increases contract-verify execution time | Slower /verify runs | Phase 3.5 only runs when view function returns are available |

---

*PRD generated by `/plan-and-analyze` — construct-protocol v2.0*
*Grounded in: MCV vault audit, Gemini Deep Research, construct-protocol v1.0 source analysis*
