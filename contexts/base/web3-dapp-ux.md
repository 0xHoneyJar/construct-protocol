# Modern dApp UX Patterns — Gemini Deep Research (2026-02-26)

> Source: Gemini Deep Research, Prompt 1 — "Modern dApp UX — The 0.00001% Standard"

## Key Patterns Extracted

### 1. Simulate-Then-Execute (Uniswap v4)
- `useSimulateContract` before every `useWriteContract` — preemptively catch reverts
- v4Planner + Universal Router: all routing through singleton PoolManager
- StateView contract for gas-free frontend reads
- Pattern: if `simulateError` populated → disable submit, show human-readable error

### 2. Execution Plans (Aave v3)
- `@aave/react` SDK: `prepare()` returns TransactionRequest | ApprovalRequired | InsufficientBalanceError
- ResultAsync model (Ok/Err) — type-safe chaining without try/catch race conditions
- Multi-step flows (approve → permit → execute) collapsed into single hook execution
- ~40% frontend complexity reduction vs v2

### 3. Transaction Lifecycle (Rainbow)
- Cancel = send 0 ETH to self with same nonce + 10% gas bump
- Speed-up = resubmit with same nonce + higher maxFeePerGas
- Raw hex calldata → human-readable activity feeds (ERC-20 approvals, multisend)
- UI abstracts nonces entirely — "lightning bolt" to speed up, "X" to cancel

### 4. Human-Readable Reverts (viem)
- `decodeErrorResult` + typed ABI → custom Solidity errors → user messages
- Aave: numbered error registry (error 14 = "Reserve already added", etc.)
- Uniswap: "Increase slippage tolerance", "Insufficient liquidity"
- Bridge the semantic gap between EVM and end-user

### 5. BigInt/Wei Handling
- Native JS BigInt everywhere — no ethers.BigNumber or web3.js wrappers
- `parseUnits`/`formatUnits` from viem — never custom math
- `defineChain` formatters: hex → BigInt at RPC boundary
- Bundle size: viem ~120KB vs ethers.js ~320KB

### 6. Cross-Chain Abstraction (Zora)
- Single-click cross-chain minting: L1 funds → L2 NFT
- `@zoralabs/protocol-sdk` collectorClient handles bridge + mint atomically
- Bridging = invisible backend routing, not user-facing action
- Uniswap: permissionless bridging across 9 networks in-interface

### 7. Wallet Connection Stack
| Library | Focus | Best For |
|---------|-------|----------|
| RainbowKit | React-first, Wagmi-native | Consumer dApps, US/UK retail |
| AppKit (Web3Modal v3) | Framework-agnostic, Web Components | Enterprise, multi-framework |
| ConnectKit (Family) | React, WCAG 2.2 AA accessible | Regulated markets, accessibility |

- Next-gen: Privy, Dynamic — email/social login → auto-provisioned smart wallet
- Progressive onboarding: Web2 signup → optional key export later

### 8. Gas Abstraction (ERC-4337)
- Paymaster sponsors gas in native ETH, optionally charges user in USDC
- UserOperation struct → alternative mempool → Bundler → EntryPoint contract
- Social Recovery: N-of-M guardian threshold to recover lost access
- "One-click" experiences: blockchain infrastructure functionally invisible

### 9. EIP-712 + Permit2 (Uniswap)
- Off-chain typed data signing → bundled with execution payload
- Collapse approve + execute into single user interaction
- Unordered, non-monotonic nonces: failure of one doesn't block others
- Strict expiration deadlines → no infinite allowance risk

### 10. Solana DeFi (Drift/Mango)
- Address Lookup Tables: 32-byte keys → 1-byte indices
- Account ceiling: 35 → 256 per transaction
- `skipPreflight: true` for HFT latency optimization
- Versioned Transactions (v0 format)

### 11. Proxy-Aware Frontends (EIP-1967)
- 54.2% of active Ethereum contracts use proxy patterns
- Implementation slot: `0x360894...bbc` — read with `getStorageAt`
- Frontend auto-detects proxy → fetches implementation ABI dynamically
- DAO upgrades: frontend adapts without redeployment

### 12. Marketplace Bifurcation (Blur vs OpenSea)
- Blur: Bloomberg-terminal density, WebSockets, sweep transactions, off-chain order books
- Blur avg tx: 1.88 ETH vs OpenSea: 0.434 ETH
- OpenSea: creator community tools, diverse media, retail onboarding
- UX is context-dependent upon target audience's intent
