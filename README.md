# Protocol

> *The verifier — grounds dApp behavior in on-chain reality. Never trust the frontend, verify the chain.*

**Protocol** is a [Loa construct](https://constructs.network) that catches the bugs users hit but developers never see. The ones where the frontend says "submit" and the chain says "revert." Where the UI shows 2% but the contract enforces 5%.

Born from a live debugging session where regular users couldn't bid on an auction while a bot succeeded — because the frontend hardcoded a 2% bid increment while the on-chain `minBidIncrementPercentage` was 5%.

## Install

```bash
# Inside Claude Code with Loa installed
/constructs install protocol
```

**Prerequisites:**
- [Foundry](https://book.getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- `RPC_URL` environment variable — any EVM RPC endpoint
- Optional: `ETHERSCAN_API_KEY` for ABI fetching
- Optional: `agent-browser` MCP — enables RPC interception for wallet edge case testing in `/dapp-e2e`

## Skills

### Verify Path — Live Debugging

| Skill | Command | What It Does |
|-------|---------|-------------|
| `contract-verify` | `/verify` | Read deployed contract state via `cast`, compare against frontend constants, semantic activation analysis |
| `tx-forensics` | `/debug-tx` | Decode revert reasons, trace internal calls, decode Safe/multicall payloads |
| `abi-audit` | `/audit-abi` | Compare frontend ABI against deployed contract — find stale ABIs |
| `proxy-inspect` | `/inspect-proxy` | Read EIP-1967 slots, identify implementation, check upgrade patterns |
| `simulate-flow` | `/simulate` | Simulate user flows via `cast call`, verify frontend simulation gating |

### QA Path — Development Pipeline

| Skill | Command | What It Does |
|-------|---------|-------------|
| `dapp-lint` | `/lint-dapp` | Web3 linting — BigInt safety, network guards, simulation gating, error handling, env alignment, receipt lifecycle, dead integrations |
| `dapp-typecheck` | `/typecheck-dapp` | Verify wagmi/viem type generation matches deployed ABIs |
| `dapp-test` | `/test-dapp` | Execute test suites with contract mock patterns and forked chain testing |
| `dapp-e2e` | `/e2e-dapp` | Agent-browser QA — wallet flows, RPC interception, wallet edge case matrix |
| `gpt-contract-review` | `/review-contract` | Cross-model review of frontend-to-contract consistency |

## How It Works

**Verify finds the bug. QA prevents it from recurring.**

```
Frontend shows 2% bid increment
        │
        ▼
/verify ──→ cast call minBidIncrementPercentage()
        │         returns 5
        ▼
  DISCREPANCY FOUND
  File: services/auctions.ts:42
  Hardcoded: MIN_BID_INCREMENT = 2
  On-chain:  minBidIncrementPercentage = 5
        │
        ▼
/simulate ──→ cast call with user's bid amount
        │         REVERT: "Must send more than last bid by minBidIncrementPercentage"
        ▼
  FIX: Read from chain, not constants
        │
        ▼
/test-dapp ──→ Add regression test
              assert(bidIncrement === onChainValue)
```

## Key Patterns Codified

| Pattern | What It Prevents |
|---------|-----------------|
| Ground in on-chain reality | Frontend hardcoded values diverging from contract state |
| Simulate before submit | Users hitting reverts that `cast call` would have caught |
| Decode the revert | "Transaction failed" UX with no explanation |
| Check the proxy | Interacting with a proxy's fallback instead of the implementation |
| BigInt is not a number | Wei arithmetic overflow, timestamp s/ms confusion, percentage rounding |
| Cross-model review | Single-model blind spots in contract interaction code |

## Composability

Protocol works with other constructs:

- **Observer** captures user friction reports about failed transactions → Protocol verifies the on-chain reality
- **Artisan** designs the transaction UX → Protocol ensures it matches contract behavior
- **Crucible** validates user journeys → Protocol grounds those journeys in chain state

## What's New in v2.0

v2.0 adds **wallet boundary verification** — the browser-level layer where chain switching, transaction signing, error propagation, and receipt polling actually happen. Grounded in a real production audit of a Berachain vault dApp and deep research across Uniswap, Relay, LayerZero, and Zora frontend infrastructure.

### New Scans in `/dapp-lint` (6 new)

| Scan | What It Catches |
|------|----------------|
| `require-network-guard` | Write calls without chain verification — tx fires on wrong chain |
| `require-simulation-dependency` | Simulation and write firing in parallel — zero revert protection |
| `require-decoded-error-handling` | Empty/shallow catch blocks — "transaction failed" with no explanation |
| `env-var-alignment` | `process.env` refs vs `.env` definitions — server 500s, client undefined |
| `require-receipt-timeout` | `useWaitForTransactionReceipt` without timeout — infinite loading |
| `dead-web3-integration` | Orphaned hooks, unused ABIs, unreferenced contract addresses |

### Semantic Activation in `/contract-verify`

New Phase 3.5 interprets on-chain state semantically: `address(0)` = feature disabled, `paused()` = contract paused, expired timestamps = ended. Cross-references against frontend UI to flag buttons that trigger guaranteed-revert transactions.

### Agent-Browser RPC Interception in `/dapp-e2e`

When `agent-browser` MCP is available, Phase 3-AB replaces mock wallet injection with browser-level RPC interception — testing the actual wagmi/viem pipeline unmodified. Phase 5.5 adds a 7-case wallet edge case matrix: wrong chain, user rejection, receipt timeout, on-chain revert, chain switch mid-batch, disconnect mid-flow, hardware wallet hang.

### Frontend Simulation Verification in `/simulate-flow`

New Phase 2.5 checks if the frontend has client-side simulation (`useSimulate*`) for each write flow, and whether the simulation actually gates the write invocation. Classifies flows as GATED (self-protecting), PARALLEL (dangerous), or AGENT_ONLY (recommendation to add).

## Origin

Filed from an apDAO Auction House debugging session on Berachain. Every finding that took 1-5 minutes manually is now an automated check:

| Finding | How Protocol Catches It |
|---------|------------------------|
| Timestamp bug (20k+ days ago) | `/verify` reads `block.timestamp` format, compares with frontend Date handling |
| 2% vs 5% bid increment | `/verify` reads `minBidIncrementPercentage()`, greps frontend for hardcoded values |
| Reserve price not enforced | `/verify` reads `reservePrice()`, finds frontend "0" fallback |
| Bot is a Gnosis Safe | `/inspect-proxy` reads bytecode, identifies Safe pattern |
| Promise.all resilience | `/review-contract` cross-model review catches error handling gaps |

## Development

```bash
# Clone
git clone https://github.com/0xHoneyJar/construct-protocol.git
cd construct-protocol

# Validate structure
yq eval '.' construct.yaml
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
