# contract-verify

> Ground dApp frontend assumptions in on-chain reality.

You are executing the **contract-verify** skill. Your job is to read deployed smart contract state and compare it against hardcoded values in the frontend codebase. This catches the #1 class of dApp bugs: the frontend displaying one thing while the chain enforces another.

## Prerequisites

Before starting, verify that `cast` (from Foundry) is available:

```bash
cast --version
```

If `cast` is not installed, inform the user and suggest:
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

Do NOT proceed without `cast`. This skill is useless without it.

## Phase 1: Identify Target Contract

You MUST determine three things before any on-chain reads:

1. **Contract address** — from user input, `.env`, config files, or deployment artifacts
2. **Chain / RPC URL** — from user input, `.env`, or hardhat/foundry config
3. **Contract type** — what does this contract do? (auction, token, marketplace, vault, etc.)

### Finding the contract address

Search the project in this order:

1. Check user input first — they may have provided the address directly
2. Search environment files:
   ```
   Grep for the contract name or "CONTRACT" or "ADDRESS" in .env, .env.local, .env.production
   ```
3. Search config files:
   ```
   Grep for "0x" followed by 40 hex chars in src/, lib/, config/, constants/
   Pattern: "0x[a-fA-F0-9]{40}"
   ```
4. Search deployment artifacts:
   ```
   Glob for deployments/**/*.json, broadcast/**/*.json, addresses.json
   ```

### Finding the RPC URL

Search in this order:

1. User input
2. `.env` files — look for `RPC_URL`, `NEXT_PUBLIC_RPC`, `ALCHEMY_URL`, `INFURA_URL`
3. `foundry.toml` — check `[rpc_endpoints]` section
4. `hardhat.config.ts` — check `networks` config
5. Frontend config — wagmi chains config, constants files

If no RPC URL is found, use public RPCs as fallback:
- Ethereum mainnet: `https://eth.llamarpc.com`
- Base: `https://mainnet.base.org`
- Arbitrum: `https://arb1.arbitrum.io/rpc`
- Optimism: `https://mainnet.optimism.io`
- Polygon: `https://polygon-rpc.com`

**IMPORTANT**: Always prefer the project's configured RPC. Public RPCs have rate limits and may fail on complex calls.

## Phase 2: Detect Proxy Pattern

Before reading contract state, you MUST check if the contract is a proxy. Reading state from a proxy without knowing the implementation gives wrong results for some patterns.

Run the EIP-1967 implementation slot read:

```bash
cast storage <address> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <rpc>
```

**Interpret the result:**
- If the result is `0x000...000` (all zeros) → NOT a proxy (or not EIP-1967)
- If the result is a non-zero value → It IS a proxy. The value (last 20 bytes) is the implementation address.

If it's a proxy:
1. Extract the implementation address: take the last 40 hex characters of the storage value
2. Log both the proxy address and implementation address
3. For ABI/function calls, you'll call the PROXY address but the IMPLEMENTATION's functions

Also check the admin slot (useful context):
```bash
cast storage <address> 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 --rpc-url <rpc>
```

## Phase 3: Read On-Chain State

### Strategy: Enumerate Public View Functions

You need to discover what state the contract exposes. Use these approaches in order:

#### Approach A: Known contract type patterns

If you can identify the contract type, read these common parameters:

**Auction contracts:**
```bash
cast call <addr> "reservePrice()(uint256)" --rpc-url <rpc>
cast call <addr> "minBidIncrementPercentage()(uint8)" --rpc-url <rpc>
cast call <addr> "duration()(uint256)" --rpc-url <rpc>
cast call <addr> "timeBuffer()(uint256)" --rpc-url <rpc>
cast call <addr> "owner()(address)" --rpc-url <rpc>
cast call <addr> "paused()(bool)" --rpc-url <rpc>
```

**Token/ERC20 contracts:**
```bash
cast call <addr> "name()(string)" --rpc-url <rpc>
cast call <addr> "symbol()(string)" --rpc-url <rpc>
cast call <addr> "decimals()(uint8)" --rpc-url <rpc>
cast call <addr> "totalSupply()(uint256)" --rpc-url <rpc>
```

**ERC721/NFT contracts:**
```bash
cast call <addr> "name()(string)" --rpc-url <rpc>
cast call <addr> "symbol()(string)" --rpc-url <rpc>
cast call <addr> "totalSupply()(uint256)" --rpc-url <rpc>
cast call <addr> "baseURI()(string)" --rpc-url <rpc>
cast call <addr> "maxSupply()(uint256)" --rpc-url <rpc>
cast call <addr> "mintPrice()(uint256)" --rpc-url <rpc>
```

**Marketplace contracts:**
```bash
cast call <addr> "feeBps()(uint256)" --rpc-url <rpc>
cast call <addr> "feeRecipient()(address)" --rpc-url <rpc>
cast call <addr> "protocolFee()(uint256)" --rpc-url <rpc>
cast call <addr> "owner()(address)" --rpc-url <rpc>
```

**Vault/DeFi contracts:**
```bash
cast call <addr> "asset()(address)" --rpc-url <rpc>
cast call <addr> "totalAssets()(uint256)" --rpc-url <rpc>
cast call <addr> "depositFee()(uint256)" --rpc-url <rpc>
cast call <addr> "withdrawalFee()(uint256)" --rpc-url <rpc>
cast call <addr> "maxDeposit(address)(uint256)" "0x0000000000000000000000000000000000000000" --rpc-url <rpc>
```

**Universal parameters (try on any contract):**
```bash
cast call <addr> "owner()(address)" --rpc-url <rpc>
cast call <addr> "paused()(bool)" --rpc-url <rpc>
cast call <addr> "version()(string)" --rpc-url <rpc>
```

#### Approach B: Get the full ABI from explorer

If the contract is verified on a block explorer:

```bash
cast etherscan-source <address> --chain <chain-name>
```

Or use the Etherscan API directly:
```bash
cast abi-encode --help  # for reference
```

If you can get the ABI, extract all view/pure functions and call each one that takes zero arguments.

#### Approach C: Scan the frontend for function names

If you can't get the ABI from an explorer, search the frontend for function names being called:

```
Grep for patterns like:
- functionName: "
- "functionName"
- abi: [
- useReadContract
- useContractRead
- readContract
```

Then try calling each discovered function name.

### Handling Return Values

**CRITICAL**: `cast call` returns raw hex by default when a signature is provided with return types. Parse appropriately:

- `uint256` values: Convert from wei if they represent ETH amounts. Use `cast from-wei <value>` or `cast --to-unit <value> ether`.
- `uint8` / `uint16` values: These are small numbers, usually percentages or basis points.
- `address` values: 20-byte addresses, already human-readable from cast.
- `bool` values: `0x01` = true, `0x00` = false.
- `string` values: Cast decodes these automatically with the right signature.
- Basis points: If a value is labeled "bps" or "BasisPoints", divide by 100 to get percentage.

**Record every value you read.** You'll need them all for the comparison phase.

## Phase 4: Scan Frontend for Hardcoded Values

Now search the frontend codebase for values that SHOULD match what you read on-chain. This is where mismatches hide.

### What to search for

For EACH on-chain value you read, search the codebase:

**Numeric values (fees, percentages, durations):**
```
Grep for the exact number in src/, app/, lib/, constants/, config/
Example: if on-chain minBidIncrementPercentage is 5, grep for "5" in context of bid/increment
```

**IMPORTANT**: Don't just grep for bare numbers like "5" — that matches everything. Search with context:
```
Grep for "minBidIncrement" or "MIN_BID" or "bidIncrement"
Grep for "reservePrice" or "RESERVE_PRICE" or "reserve"
Grep for "feeBps" or "FEE" or "protocolFee" or "fee"
```

**Address values:**
```
Grep for the full address (case-insensitive): "0xABc...123"
Also grep for the address without "0x" prefix
Also grep for the checksummed AND lowercased versions
```

**Boolean/state values:**
```
Grep for the parameter name: "paused", "isActive", etc.
Check if the frontend hardcodes these instead of reading from chain
```

### Where to search

Search these directories with priority:

1. `src/constants/` or `constants/` — most likely location for hardcoded values
2. `src/config/` or `config/` — configuration files
3. `src/hooks/` or `hooks/` — custom React hooks that read contract state
4. `src/lib/` or `lib/` — utility libraries
5. `src/abis/` or `abis/` — ABI definitions (check for inline constants)
6. `src/components/` — UI components that display values
7. `.env` files — environment-level constants

### Patterns that indicate hardcoded values (BAD)

These patterns mean the frontend is NOT reading from chain:

```typescript
// HARDCODED — will desync from chain
const MIN_BID_INCREMENT = 5;
const RESERVE_PRICE = ethers.utils.parseEther("1");
const FEE_PERCENTAGE = 2.5;
const AUCTION_DURATION = 86400; // 24 hours
```

### Patterns that indicate dynamic reads (GOOD)

These patterns mean the frontend IS reading from chain:

```typescript
// DYNAMIC — stays in sync
const { data: minBid } = useReadContract({
  address: AUCTION_ADDRESS,
  abi: auctionAbi,
  functionName: 'minBidIncrementPercentage',
});
```

### Record every finding

For each value, record:
- The on-chain value (what the contract says)
- The frontend value (what the code says), with `file:line` reference
- Whether the frontend value is hardcoded or dynamically read
- Whether they match

## Phase 5: Generate Report

Write the verification report to `grimoires/protocol/verify-report.md`.

Use this format:

```markdown
# Contract Verification Report

**Generated**: <timestamp>
**Contract**: <address>
**Chain**: <chain name>
**Proxy**: <yes/no — if yes, implementation: <impl address>>

## Summary

| Status | Count |
|--------|-------|
| Matches | <n> |
| Mismatches | <n> |
| Hardcoded (no chain read) | <n> |
| Not found in frontend | <n> |

## Discrepancies

### CRITICAL: <parameter name>
- **On-chain value**: <value>
- **Frontend value**: <value> (`<file>:<line>`)
- **Impact**: <what goes wrong for users>
- **Fix**: <exact code change needed>

### WARNING: <parameter name>
- **On-chain value**: <value>
- **Frontend**: Hardcoded as <value> (`<file>:<line>`)
- **Risk**: Value matches NOW but will desync if contract is updated
- **Fix**: Replace hardcoded value with on-chain read

## Verified Parameters

| Parameter | On-Chain | Frontend | Source | Status |
|-----------|----------|----------|--------|--------|
| <name> | <value> | <value> | `<file>:<line>` | MATCH / MISMATCH / HARDCODED |

## Recommendations

<numbered list of actions, ordered by severity>
```

### Severity classification

- **CRITICAL**: On-chain value differs from frontend value. Users see wrong information or transactions fail.
- **WARNING**: Values match but frontend is hardcoded. Will desync on contract update.
- **INFO**: Value exists on-chain but is not referenced in frontend. May or may not be needed.

## Error Handling

### `cast call` fails with "execution reverted"
The function may not exist on this contract. Skip it and try the next one. Do NOT treat this as a fatal error.

### `cast call` returns empty or zero
The function exists but returns zero/empty. This is a valid value — record it and compare against frontend.

### RPC rate limiting
If you get rate-limited, wait 2 seconds and retry once. If it fails again, inform the user they need a better RPC endpoint.

### Contract not verified on explorer
You can still call known function signatures. You just can't enumerate all functions. Focus on what the frontend uses.

## Edge Cases

### Multiple contracts
If the dApp interacts with multiple contracts (e.g., auction house + token + treasury), verify EACH contract. Create a section per contract in the report.

### Contracts on different chains
If the dApp is multichain, verify each chain separately. Note which chain each finding applies to.

### Values that require computation
Some frontend values are derived (e.g., "minimum bid = current bid + increment percentage"). In this case, verify both the raw parameters AND the computation logic.

### Upgradeable contracts
If you detect a proxy, note this prominently. The implementation can change, making ALL hardcoded values dangerous. Strongly recommend dynamic reads for any proxy contract.

## Completion Criteria

You are done when:
1. You have identified the contract address and chain
2. You have checked for proxy pattern
3. You have read all discoverable on-chain state
4. You have searched the frontend for every on-chain value
5. You have written the report to `grimoires/protocol/verify-report.md`
6. You have presented the key findings (especially any CRITICAL mismatches) to the user

If there are CRITICAL mismatches, make them impossible to miss. The whole point of this skill is catching these before users do.
