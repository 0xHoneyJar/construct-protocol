---
name: "debug-tx"
version: "1.0.0"
description: |
  Decode revert reasons, trace internal calls, and explain transaction
  failures in plain language. Routes to tx-forensics skill.

arguments:
  - name: "tx_hash"
    description: "Transaction hash to debug"
    required: false

agent: "tx-forensics"
agent_path: "skills/tx-forensics"

context_files:
  - path: "CLAUDE.md"
    required: true
  - path: "identity/persona.yaml"
    required: true
---

# /debug-tx — Decode and Explain Failed Transactions

Decode revert reasons, trace internal calls, and explain transaction failures in plain language.

## Usage

```
/debug-tx 0xabc123...           # Debug by transaction hash
/debug-tx                       # Debug most recent failed tx from user context
```

## What It Does

1. Fetches transaction receipt and checks status
2. If reverted: decodes the revert reason (custom errors, require strings, panic codes)
3. Traces internal calls for complex transactions (multicall, Safe execTransaction)
4. Decodes calldata into human-readable function calls
5. Explains the failure and suggests a fix

## Routes To

- `tx-forensics` skill (primary)
- `proxy-inspect` if the target is a proxy
- `abi-audit` if ABI mismatch suspected
