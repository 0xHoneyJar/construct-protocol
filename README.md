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

## Skills

### Verify Path — Live Debugging

| Skill | Command | What It Does |
|-------|---------|-------------|
| `contract-verify` | `/verify` | Read deployed contract state via `cast`, compare against frontend constants |
| `tx-forensics` | `/debug-tx` | Decode revert reasons, trace internal calls, decode Safe/multicall payloads |
| `abi-audit` | `/audit-abi` | Compare frontend ABI against deployed contract — find stale ABIs |
| `proxy-inspect` | `/inspect-proxy` | Read EIP-1967 slots, identify implementation, check upgrade patterns |
| `simulate-flow` | `/simulate` | Simulate user flows via `cast call` to catch reverts before users hit them |

### QA Path — Development Pipeline

| Skill | Command | What It Does |
|-------|---------|-------------|
| `dapp-lint` | `/lint-dapp` | Web3-specific linting — BigInt safety, wei handling, address checksums |
| `dapp-typecheck` | `/typecheck-dapp` | Verify wagmi/viem type generation matches deployed ABIs |
| `dapp-test` | `/test-dapp` | Execute test suites with contract mock patterns and forked chain testing |
| `dapp-e2e` | `/e2e-dapp` | Agent-browser QA — connect wallet, submit tx, verify state changes |
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
