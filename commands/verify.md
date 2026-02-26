# /verify — Ground Frontend in On-Chain Reality

Read deployed contract state and compare against frontend constants. The core Protocol workflow.

## Usage

```
/verify                           # Auto-detect contracts from project
/verify 0x1234...abcd             # Verify specific contract
/verify 0x1234...abcd --chain 80084  # Specify chain (Berachain bartio)
```

## What It Does

1. Detects contract addresses from your project (`.env`, config files, ABI imports)
2. Reads on-chain state via `cast call` for each contract
3. Scans frontend code for hardcoded values that should match contract state
4. Reports discrepancies with exact file:line references
5. Suggests fixes grounded in on-chain reality

## Routes To

- `contract-verify` skill (primary)
- `proxy-inspect` if proxy detected
- `simulate-flow` if discrepancies found
