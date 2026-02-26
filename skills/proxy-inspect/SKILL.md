# proxy-inspect

> Identify proxy architecture, implementation, and upgrade authority.

You are executing the **proxy-inspect** skill. Your job is to determine whether a contract is a proxy, identify its type and implementation, discover who controls upgrades, and report the architecture with security implications.

## Prerequisites

Verify `cast` is available:
```bash
cast --version
```

## Phase 1: Gather Target Information

Obtain from the user:
1. **Contract address** — the address to inspect
2. **Chain / RPC URL** — resolve using standard order (.env, foundry.toml, public fallback)

If the user says "check our contract" without an address, search the project:
```
Grep for "0x[a-fA-F0-9]{40}" in .env, .env.local, .env.production, constants/, config/
```

## Phase 2: Read EIP-1967 Storage Slots

EIP-1967 defines standardized storage slots for proxy metadata. Read ALL three slots:

### Implementation slot
```bash
cast storage <address> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <rpc>
```

**Derivation**: `bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)`

**Interpret**:
- All zeros → Not an EIP-1967 proxy (but may be another type — see Phase 3)
- Non-zero → The last 20 bytes (40 hex chars) are the implementation address

Extract the implementation address:
```bash
# If the result is 0x000000000000000000000000abcdef1234567890abcdef1234567890abcdef12
# The implementation is 0xabcdef1234567890abcdef1234567890abcdef12
```

### Admin slot
```bash
cast storage <address> 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 --rpc-url <rpc>
```

**Derivation**: `bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1)`

**Interpret**:
- All zeros → No admin (or admin managed differently — common with UUPS)
- Non-zero → The last 20 bytes are the admin/upgrade authority

### Beacon slot
```bash
cast storage <address> 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50 --rpc-url <rpc>
```

**Derivation**: `bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)`

**Interpret**:
- All zeros → Not a Beacon proxy
- Non-zero → The last 20 bytes are the beacon contract address

## Phase 3: Determine Proxy Type

Based on the slot readings, classify the proxy:

### Decision tree

```
Implementation slot non-zero?
├── YES
│   ├── Admin slot non-zero? → TRANSPARENT PROXY (TransparentUpgradeableProxy)
│   ├── Admin slot zero?
│   │   ├── Implementation has upgradeToAndCall? → UUPS PROXY
│   │   └── Implementation lacks upgradeToAndCall? → MINIMAL PROXY or custom
│   └── Beacon slot non-zero? → BEACON PROXY (unusual to have both)
├── NO
│   ├── Beacon slot non-zero? → BEACON PROXY
│   └── All slots zero?
│       ├── Check for EIP-1167 clone pattern → MINIMAL PROXY (clone)
│       ├── Check for Diamond storage → DIAMOND PROXY (EIP-2535)
│       └── None of the above → NOT A PROXY (or non-standard)
```

### Transparent Proxy (OpenZeppelin TransparentUpgradeableProxy)

**Characteristics**:
- Implementation slot: populated
- Admin slot: populated (usually a ProxyAdmin contract)
- The admin can call `upgradeToAndCall` on the proxy
- Non-admin calls are delegated to implementation
- The admin CANNOT call implementation functions (admin/user collision protection)

Verify by checking the admin address:
```bash
# Is the admin a ProxyAdmin contract?
cast call <admin-address> "owner()(address)" --rpc-url <rpc>
```

### UUPS Proxy (ERC1822)

**Characteristics**:
- Implementation slot: populated
- Admin slot: usually zero (no separate admin)
- Upgrade logic lives in the IMPLEMENTATION, not the proxy
- The implementation has `upgradeToAndCall(address,bytes)` function

Verify by checking the implementation:
```bash
# Check if implementation has upgradeToAndCall
cast call <impl-address> "proxiableUUID()(bytes32)" --rpc-url <rpc>
```

If this returns `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`, it confirms UUPS.

### Beacon Proxy

**Characteristics**:
- Beacon slot: populated
- Implementation slot: usually zero
- The beacon contract holds the implementation address
- Multiple proxies can share one beacon

Read the implementation from the beacon:
```bash
cast call <beacon-address> "implementation()(address)" --rpc-url <rpc>
```

### Minimal Proxy (EIP-1167 Clone)

**Characteristics**:
- All EIP-1967 slots are zero
- Bytecode follows the pattern: `363d3d373d3d3d363d73<address>5af43d82803e903d91602b57fd5bf3`

Check bytecode:
```bash
cast code <address> --rpc-url <rpc>
```

If the bytecode matches the EIP-1167 pattern, extract the implementation address from bytes 10-29.

**IMPORTANT**: Minimal proxies are NOT upgradeable. The implementation is baked into the bytecode.

### Diamond Proxy (EIP-2535)

**Characteristics**:
- All EIP-1967 slots may be zero
- Contract has `facets()`, `facetFunctionSelectors(address)`, `facetAddresses()` functions

Check:
```bash
cast call <address> "facetAddresses()(address[])" --rpc-url <rpc>
```

If this succeeds, it's a Diamond. List all facets and their selectors.

### Not a Proxy

If none of the above patterns match, the contract is likely NOT a proxy. Confirm by checking if the bytecode contains a `delegatecall` opcode. If the bytecode is straightforward, report "Not a proxy — this is a direct implementation."

## Phase 4: Investigate Upgrade Authority

Once you've identified the proxy type, trace the upgrade authority chain:

### Who can upgrade?

**Transparent Proxy**: The ProxyAdmin contract is the upgrade authority.
```bash
# Get ProxyAdmin owner
cast call <admin-address> "owner()(address)" --rpc-url <rpc>
```

**UUPS Proxy**: The implementation contract controls upgrades.
```bash
# Check owner/admin of the implementation through the proxy
cast call <proxy-address> "owner()(address)" --rpc-url <rpc>
```

**Beacon Proxy**: The beacon owner controls upgrades.
```bash
cast call <beacon-address> "owner()(address)" --rpc-url <rpc>
```

### Resolve the authority

The owner may be:
- **EOA (externally owned account)**: A single private key controls upgrades. **HIGH RISK**.
- **Multisig (Safe)**: Check if it's a Safe contract.
- **Timelock**: Check if it's a timelock controller.
- **Governor**: Check if it's a governance contract.

Check if the owner is a contract:
```bash
cast code <owner-address> --rpc-url <rpc>
```

If the code is non-empty, it's a contract. Try to identify it:

```bash
# Check for Safe
cast call <owner> "getThreshold()(uint256)" --rpc-url <rpc>
cast call <owner> "getOwners()(address[])" --rpc-url <rpc>

# Check for Timelock
cast call <owner> "getMinDelay()(uint256)" --rpc-url <rpc>

# Check for Governor
cast call <owner> "votingDelay()(uint256)" --rpc-url <rpc>
```

### Upgrade authority chain

Trace the full chain. Example:
```
Proxy → ProxyAdmin → Timelock (48h delay) → Governor (token voting)
```

or

```
Proxy → ProxyAdmin → Safe (3/5 multisig)
```

Report the FULL chain, not just the immediate owner.

## Phase 5: Verify Implementation

Read the implementation contract to confirm it has the expected interface:

```bash
# Get basic info about the implementation
cast call <impl-address-via-proxy> "name()(string)" --rpc-url <rpc>
cast call <impl-address-via-proxy> "version()(string)" --rpc-url <rpc>
```

If the implementation source is available:
```bash
cast etherscan-source <impl-address> --chain <chain>
```

Check for:
- Expected view functions are present
- Initializer was called (check initialized state)
- Storage layout compatibility (if you have both old and new impl)

## Phase 6: Security Assessment

Evaluate the security posture based on findings:

### Risk factors

| Factor | Risk Level | Description |
|--------|-----------|-------------|
| EOA as upgrade authority | **CRITICAL** | Single key compromise = full contract takeover |
| No timelock on upgrades | **HIGH** | Upgrades are instant, no time for community review |
| Unverified implementation | **HIGH** | Cannot audit the code being executed |
| UUPS without upgrade check | **MEDIUM** | Risk of bricking (upgrading to non-UUPS impl) |
| Beacon with many proxies | **MEDIUM** | Single beacon upgrade affects all proxies |
| Transparent proxy (standard) | **LOW** | Well-tested, OZ-audited pattern |
| Minimal proxy (non-upgradeable) | **INFO** | Cannot be upgraded (good or bad) |

### Checks to run

1. **Initializer**: Was the proxy properly initialized?
```bash
# Try calling initialize — if it succeeds, the proxy was NOT initialized (BAD)
# Most will revert with "Initializable: contract is already initialized"
```

2. **Storage collision**: Are the proxy and implementation storage layouts compatible? (Only checkable with source code)

3. **Self-destruct risk**: Does the implementation contain `selfdestruct`? (Only with source)

## Phase 7: Generate Report

Write the report to `grimoires/protocol/proxy-inspect-report.md`:

```markdown
# Proxy Inspection Report

**Generated**: <timestamp>
**Address**: <proxy address>
**Chain**: <chain>

## Architecture

| Property | Value |
|----------|-------|
| Proxy Type | <Transparent / UUPS / Beacon / Diamond / Minimal / None> |
| Implementation | <address> |
| Admin | <address or N/A> |
| Beacon | <address or N/A> |

## Upgrade Authority Chain

```
<visual chain, e.g.: Proxy → ProxyAdmin (0x...) → Safe 3/5 (0x...) >
```

### Authority Details

| Level | Address | Type | Details |
|-------|---------|------|---------|
| ProxyAdmin | <address> | Contract | Owner: <address> |
| Owner | <address> | Safe | Threshold: 3/5 |

## Security Assessment

| Check | Status | Notes |
|-------|--------|-------|
| Upgrade authority | <EOA/Safe/Timelock/Governor> | <risk note> |
| Timelock delay | <duration or "None"> | <recommendation> |
| Implementation verified | <Yes/No> | <explorer link if yes> |
| Initializer called | <Yes/No/Unknown> | |
| Storage layout risk | <Low/Medium/High/Unknown> | |

## Risk Level: <LOW / MEDIUM / HIGH / CRITICAL>

<paragraph explaining overall risk assessment>

## Recommendations

1. <recommendation>
2. <recommendation>
```

## Completion Criteria

You are done when:
1. You have read all three EIP-1967 storage slots
2. You have identified the proxy type (or confirmed it's not a proxy)
3. You have traced the full upgrade authority chain
4. You have assessed security posture
5. You have written the report
6. You have highlighted any CRITICAL or HIGH risk findings to the user

If the upgrade authority is an EOA, make this finding IMPOSSIBLE TO MISS. This is the highest-risk finding in proxy inspection.
