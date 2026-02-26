# Deep Research Prompts for Protocol Construct

> For Gemini Deep Research — feed these individually for maximum depth.

---

## Prompt 1: Modern dApp UX — The 0.00001% Standard

```
Research the current state of the art in Web3 dApp user experience as of Q1 2026.
Focus exclusively on the top-tier consumer crypto products that set the standard:

**Primary references:**
- Uniswap (v4, Universal Router, frontend patterns)
- Aave (v3, GHO integration, governance UX)
- Family (wallet UX, transaction flow, social recovery)
- Mango/Drift (Solana DeFi, speed-optimized UX)
- Zora (NFT marketplace, mint UX, gas abstraction)
- Rainbow (mobile wallet, swap UX)
- Blur/OpenSea (marketplace UX evolution)

**Research questions:**
1. What frontend-to-contract consistency patterns do these apps use? How do they prevent the "UI says X, chain does Y" class of bugs?
2. How do they handle transaction lifecycle UX — pending, confirmed, reverted, replaced? What's the gold standard for error messages when transactions fail?
3. What BigInt/wei handling patterns are standard? Do they use custom formatters, or have viem/wagmi patterns settled?
4. How do they handle chain-switching, multi-chain states, and L2 bridging UX?
5. What wallet connection patterns are standard — RainbowKit, ConnectKit, AppKit? Which provides the best developer experience?
6. How do they handle gas estimation and gas-free/sponsored transactions?
7. What role does EIP-712 typed data signing play in modern dApp UX?
8. How do they handle contract upgrades from the frontend perspective — do they use proxy-aware patterns?

**Output format:**
For each app, provide:
- The specific pattern/technique used
- Code-level implementation detail where available (React hooks, viem patterns)
- Why this pattern is superior to alternatives
- Links to relevant source code or documentation

The goal is to extract the frontier patterns that should be codified into an AI agent construct for dApp development assistance.
```

---

## Prompt 2: Web3 Frontend Verification — Testing at the Chain Boundary

```
Research comprehensive testing and verification patterns for Web3 frontend applications as of 2026.

**Focus areas:**

1. **Foundry `cast` as a verification oracle:**
   - What are the standard `cast` commands for reading contract state from a frontend debugging perspective?
   - How do teams use `cast` for pre-deployment verification (staging vs mainnet)?
   - What's the state of `cast` integration with CI/CD pipelines?

2. **wagmi/viem testing infrastructure:**
   - Current best practices for testing wagmi hooks (useReadContract, useWriteContract, useSimulateContract)
   - Mock provider patterns — how do Uniswap, Aave, and others mock chain state in tests?
   - The vitest + wagmi test utils ecosystem — what's mature vs experimental?
   - How do teams test against forked mainnet state (anvil --fork-url)?

3. **ABI consistency tooling:**
   - How do teams prevent ABI drift between contract deploys and frontend?
   - What's the state of automatic ABI generation from verified contracts?
   - How do wagmi CLI generate types and how do teams validate them?
   - Contract address management across chains and environments

4. **E2E testing with wallets:**
   - Playwright + Synpress for wallet automation — current state?
   - How do teams test MetaMask/Rainbow/Rabby interactions in CI?
   - Mock wallet approaches vs fork-backed real wallets
   - Tenderly virtual testnets for E2E

5. **Cross-model/adversarial review for contract code:**
   - Do any teams use multi-LLM review for contract interaction code?
   - What patterns exist for automated security scanning of frontend-to-contract calls?
   - How does Trail of Bits testing handbook apply to frontend verification?

**Specific products to analyze:**
- Tenderly (simulation, virtual testnets)
- Foundry (cast, forge, anvil)
- Hardhat (testing patterns)
- Synpress (E2E wallet testing)
- oxlint (fast linting with Web3 rules — if any exist)

Output as a structured landscape with maturity ratings (experimental / growing / mature / standard).
```

---

## Prompt 3: Game Design Principles Applied to Transaction UX

```
Research the intersection of game design principles and Web3 transaction UX.
The thesis: the best dApp experiences feel like games — snappy, responsive, zero-friction, and deeply satisfying when an action completes.

**Core references:**
- Raph Koster's "A Theory of Fun for Game Design" — fun as learning
- Emil Kowalski's interaction design principles — animation, motion, feedback
- Juice It or Lose It (GDC talk) — game feel through visual/audio/haptic feedback
- "Game Feel" by Steve Swink — the experience of interacting with virtual objects

**Research questions:**

1. **Transaction as game action:**
   - How should a transaction feel? Compare: submitting a bid, executing a swap, minting an NFT
   - What's the equivalent of "game juice" for a blockchain transaction? (visual feedback, animation, sound, haptics)
   - How do the best apps (Family, Rainbow, Uniswap) make waiting for confirmations feel satisfying instead of anxious?

2. **Error states as game design:**
   - In games, failure is a learning opportunity. How should a reverted transaction feel?
   - What's the equivalent of "try again" vs "game over" for different transaction failure types?
   - How do you turn "insufficient gas" or "slippage too high" into actionable, non-scary guidance?

3. **Progressive disclosure in Web3:**
   - How do games introduce complex systems gradually? Apply to: gas settings, slippage, MEV protection, advanced order types
   - What should a first-time user see vs an expert user for the same swap interface?
   - How do you reveal chain complexity without overwhelming — similar to how games reveal crafting systems, skill trees

4. **Flow state and dApps:**
   - Gloria Mark's research (UC Irvine): 23 minutes to refocus after interruption
   - How do wallet popups, gas approval steps, chain-switching break flow?
   - What patterns minimize interruptions while maintaining security? (session keys, gas abstraction, batch transactions)

5. **Snappiness and perceived performance:**
   - Optimistic updates for pending transactions — what's the standard pattern?
   - How do apps like Family achieve "feels instant" UX on a 12-second block time chain?
   - Skeleton states, progressive loading, and transaction streaming

Output as a design principles document with concrete before/after examples suitable for encoding into an AI construct that assists with dApp development.
```

---

## Prompt 4: The dApp Development Landscape — Standards, Frameworks, and Emerging Patterns

```
Map the complete dApp frontend development landscape as of Q1 2026.
Focus on what a senior developer would need to know to build a production dApp today.

**Stack layers to cover:**

1. **Frameworks**: Next.js 15 (App Router, RSC for Web3), Remix, Vite + React
   - Which framework is winning for dApps? Why?
   - How do RSC and server actions interact with wallet state?

2. **Chain interaction libraries**: viem, wagmi, ethers.js v6
   - Current market share and trajectory
   - viem vs ethers: has the migration settled?
   - wagmi v2 patterns — what's standard now?

3. **Wallet connection**: RainbowKit, ConnectKit, AppKit (WalletConnect), Privy
   - Which abstractions are winning?
   - Social login + embedded wallets — Privy, Dynamic, Magic
   - Account abstraction (ERC-4337, ERC-7702) impact on connection UX

4. **Indexing/data**: The Graph, Envio, Goldsky, Ponder
   - Real-time indexing patterns for responsive UX
   - How do modern dApps handle historical data queries?

5. **Transaction management**: Transaction lifecycle, batching, session keys
   - EIP-5792 (wallet capabilities) — adoption status
   - Smart accounts (Safe, Kernel, Biconomy) — frontend patterns
   - Gas sponsorship/paymaster integration

6. **Security tooling**: Slither, Mythril for contracts → what about frontend?
   - Frontend security scanning specific to Web3
   - Supply chain attacks on Web3 frontends (Ledger Connect Kit incident)
   - Content Security Policy patterns for dApps

7. **Emerging standards:**
   - ERC-7702 (account abstraction upgrade)
   - EIP-6963 (multi-wallet discovery)
   - x402 (HTTP payment protocol)
   - CAIP-25 (multi-chain session management)

For each layer, rate:
- Maturity: Experimental → Growing → Mature → Standard
- Recommendation: "Use this now" vs "Watch this space"
- Key decision: What's the fork-in-the-road choice?

The output should be a landscape map that an AI construct can reference when advising developers building new dApps.
```

---

*These prompts are designed for Gemini Deep Research sessions. Each should take 15-30 minutes of deep research. The outputs will be ingested into the Protocol construct as domain context files under `contexts/base/`.*
