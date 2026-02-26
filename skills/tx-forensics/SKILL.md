# tx-forensics

> Decode, trace, and explain failed or complex transactions.

You are executing the **tx-forensics** skill. Your job is to take a transaction hash, fetch its data, decode what happened (or why it failed), and explain it in plain language. You handle reverts, custom errors, Safe multisig payloads, multicalls, and nested calldata.

## Prerequisites

Verify `cast` is available:

```bash
cast --version
```

If unavailable, inform the user:
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

## Phase 1: Gather Transaction Data

You MUST obtain two things from the user:
1. **Transaction hash** — a 66-character hex string starting with `0x`
2. **Chain / RPC URL** — determine from context or ask

### Validate the hash

A valid tx hash is exactly 66 characters: `0x` + 64 hex digits. If the user provides something else, ask for clarification.

### Determine the RPC

Use the same RPC resolution order as contract-verify:
1. User input
2. `.env` files
3. `foundry.toml` / `hardhat.config.ts`
4. Public fallbacks (rate-limited)

## Phase 2: Fetch Transaction and Receipt

Run these commands to gather the full picture:

### Get the transaction object
```bash
cast tx <hash> --rpc-url <rpc> --json
```

This gives you:
- `from` — sender address
- `to` — target contract
- `input` — raw calldata
- `value` — ETH sent
- `gasPrice` / `maxFeePerGas` — gas pricing
- `blockNumber` — when it was mined

### Get the receipt
```bash
cast receipt <hash> --rpc-url <rpc> --json
```

This gives you:
- `status` — `1` (success) or `0` (reverted)
- `gasUsed` — actual gas consumed
- `logs` — emitted events
- `effectiveGasPrice` — actual gas price paid

### Check status immediately

If `status` is `0`: The transaction REVERTED. Proceed to Phase 3 (Decode Revert).
If `status` is `1`: The transaction SUCCEEDED. Skip to Phase 4 (Decode Calldata) to explain what it did.

## Phase 3: Decode Revert Reason

This is the most critical phase. There are several types of revert reasons:

### 3A: Get the revert reason directly

Try `cast run` which replays the transaction and shows the revert:

```bash
cast run <hash> --rpc-url <rpc>
```

**NOTE**: `cast run` requires an archive node. If it fails with a "missing trie node" error, the RPC doesn't support historical state. Inform the user they need an archive RPC (Alchemy, QuickNode, etc.).

### 3B: Decode custom errors

If `cast run` shows a revert with data starting with a 4-byte selector, decode it:

```bash
cast 4byte <selector>
```

This looks up the selector in the 4byte.directory. Common custom error patterns:

| Selector | Error | Meaning |
|----------|-------|---------|
| `0x08c379a0` | `Error(string)` | Standard require/revert message |
| `0x4e487b71` | `Panic(uint256)` | Solidity panic code |
| Custom | Custom error | Contract-defined error |

### Decoding `Error(string)` — standard require message
```bash
cast abi-decode "Error(string)" <revert-data-after-selector>
```

Or more directly, the revert data after `0x08c379a0` contains an ABI-encoded string.

### Decoding `Panic(uint256)` — Solidity panic codes

| Code | Meaning |
|------|---------|
| 0x00 | Generic compiler panic |
| 0x01 | Assert failure |
| 0x11 | Arithmetic overflow/underflow |
| 0x12 | Division by zero |
| 0x21 | Enum conversion out of range |
| 0x22 | Incorrectly encoded storage byte array |
| 0x31 | `.pop()` on empty array |
| 0x32 | Array index out of bounds |
| 0x41 | Too much memory allocated |
| 0x51 | Internal function call error |

### Decoding custom errors

If the selector doesn't match `Error(string)` or `Panic(uint256)`, it's a custom error. Try:

1. Look up the selector: `cast 4byte <selector>`
2. If found, decode the parameters: `cast abi-decode "<error-signature>" <data>`
3. If not found in 4byte directory, search the project's Solidity source for the selector or error name

### 3C: Out of gas

If `gasUsed` equals the gas limit (`gas` field in the tx object), the transaction ran out of gas. Report:
- The gas limit set by the sender
- That it was exhausted
- Suggest increasing gas limit or optimizing the transaction

### 3D: No revert data

Sometimes transactions revert with no data (empty revert). This usually means:
- A low-level `.call()` or `.delegatecall()` failed and the parent didn't propagate the error
- The contract used `revert()` with no message
- An ETH transfer to a contract without a `receive()` function

Report this and suggest the user check with a trace.

## Phase 4: Decode Calldata

Whether the tx succeeded or failed, decode the calldata to explain what was attempted.

### Simple function calls
```bash
cast 4byte-decode <calldata>
```

This decodes the function selector and parameters. If it can't find the selector, try:

```bash
cast 4byte <first-4-bytes-of-calldata>
```

### Multicall decoding

If the function is `multicall(bytes[])` or similar batch call:

1. Decode the outer multicall: `cast 4byte-decode <calldata>`
2. For each inner call in the bytes array, decode it separately
3. Present each inner call as a numbered step

### Safe execTransaction decoding

Gnosis Safe transactions have this signature:
```
execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes signatures)
```

Decode it:
```bash
cast abi-decode "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" <calldata-after-selector>
```

Then decode the inner `data` parameter to see what the Safe is actually executing:
```bash
cast 4byte-decode <inner-data>
```

If `operation` is `1`, it's a `delegatecall` — note this as it has different security implications.

### Nested contract calls

For complex transactions (e.g., a Safe calling a multicall calling individual functions):
1. Decode each layer
2. Present as a nested tree structure
3. Indicate which layer failed (if reverted)

## Phase 5: Analyze Events (Successful Transactions)

For successful transactions, decode the emitted events to explain what state changes occurred:

```bash
cast receipt <hash> --rpc-url <rpc> --json | jq '.logs'
```

For each log:
1. Look up `topics[0]` (the event selector): `cast 4byte-event <topics[0]>`
2. Decode the full event data if you know the signature
3. Explain what each event means in context

Common event patterns:
- `Transfer(address,address,uint256)` — token transfer
- `Approval(address,address,uint256)` — token approval
- `Swap(...)` — DEX swap
- `Deposit(...)` / `Withdraw(...)` — vault operations

## Phase 6: Produce Explanation

Present your findings in this structure:

### For reverted transactions:

```markdown
## Transaction Forensics: <short hash>

**Status**: REVERTED
**From**: <address>
**To**: <contract address>
**Block**: <number>
**Gas Used**: <used> / <limit>

### What was attempted
<human-readable description of what the transaction tried to do>

### Why it failed
**Revert reason**: <decoded error>
**Plain language**: <explanation a non-technical person could understand>

### Root cause
<technical explanation of why the condition was not met>

### How to fix
<specific steps to make the transaction succeed>
1. <step 1>
2. <step 2>
```

### For successful transactions:

```markdown
## Transaction Forensics: <short hash>

**Status**: SUCCESS
**From**: <address>
**To**: <contract address>
**Block**: <number>
**Gas Used**: <amount> (<cost in ETH at effective gas price>)

### What happened
<step-by-step breakdown of what the transaction did>

### State changes
<list of state changes inferred from events>

### Key values
| Parameter | Value |
|-----------|-------|
| <name> | <decoded value> |
```

## Phase 7: Write Report (if requested)

If the user wants a persistent report, write to `grimoires/protocol/tx-forensics/<hash-short>.md` where `<hash-short>` is the first 10 characters of the hash.

## Common Patterns and Gotchas

### ERC20 approve before transfer
Many reverts happen because the user didn't approve the contract to spend their tokens. Check:
```bash
cast call <token> "allowance(address,address)(uint256)" <sender> <contract> --rpc-url <rpc>
```

### Deadline expired
DEX swaps and permit signatures have deadlines. If the revert mentions "expired" or "deadline", check the deadline parameter against the block timestamp:
```bash
cast block <blockNumber> --rpc-url <rpc> --json | jq '.timestamp'
```

### Slippage protection
Swaps revert if the output amount is below the minimum. Decode the swap parameters to find `amountOutMin` and explain that market moved against the user.

### Insufficient balance
Check the sender's balance at the block before the transaction:
```bash
cast balance <address> --rpc-url <rpc> --block <blockNumber-1>
```

### Reentrancy guard
If you see a revert with "ReentrancyGuard" or a custom reentrancy error, the contract is protecting against reentrancy. The user may be calling from another contract.

### Nonce issues
If the transaction was never mined, check:
```bash
cast nonce <address> --rpc-url <rpc>
```
Compare against the tx nonce. If the tx nonce is below the current nonce, it was already replaced.

## Error Handling

### `cast run` fails with "missing trie node"
The RPC doesn't support archive state. Inform the user:
> "This RPC doesn't support historical state replay. To trace this transaction, you need an archive node (Alchemy, QuickNode, or a local archive node)."

### `cast 4byte` returns no results
The function/error selector isn't in the public database. Try:
1. Search the project source for custom errors/functions
2. Check if the contract is verified on the block explorer
3. Use `cast etherscan-source` to get the source code

### Transaction not found
The hash may be on a different chain, or the transaction may be pending. Check:
```bash
cast tx <hash> --rpc-url <other-chain-rpc>
```

## Completion Criteria

You are done when:
1. You have fetched the transaction and receipt
2. You have determined success/failure status
3. If reverted: you have decoded the revert reason and explained it
4. You have decoded the calldata into human-readable form
5. You have provided a clear explanation and fix suggestions
6. You have written a report if requested

Always present the most important finding first — if the tx reverted, lead with WHY.
