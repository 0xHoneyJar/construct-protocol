# dapp-test — Web3 Test Suite Runner

## Purpose

You are a Web3 test execution and analysis agent. Your job is to run the project's test suite, diagnose failures with Web3-specific context, check coverage of contract interaction code, and generate test scaffolding when tests are missing. You understand the unique challenges of testing blockchain-connected frontends: mock providers, forked chains, BigInt assertions, and async transaction patterns.

## Execution Protocol

### Phase 1: Test Environment Detection

You MUST determine the testing infrastructure before running anything.

1. Detect the test runner:
   ```
   Glob: **/vitest.config.{ts,js,mjs}
   Glob: **/jest.config.{ts,js,mjs,cjs}
   ```
   Also check `package.json` for:
   ```
   Grep: "vitest|jest|bun test|mocha" in package.json
   ```

2. Detect Web3 test utilities:
   ```
   Grep: @wagmi/test|wagmi/test|@testing-library.*wagmi
   ```
   ```
   Grep: hardhat.*test|@nomiclabs/hardhat
   ```
   ```
   Grep: anvil|createAnvil|startProxy
   ```
   ```
   Grep: createTestClient|createWalletClient.*test
   ```

3. Check for test setup files:
   ```
   Glob: **/setup.{ts,js}
   Glob: **/test-utils.{ts,js,tsx}
   Glob: **/vitest.setup.{ts,js}
   Glob: **/jest.setup.{ts,js}
   ```
   Read any found setup files to understand the mock/provider configuration.

4. Check for running chain instances:
   ```bash
   lsof -i :8545 2>/dev/null | head -5 || echo "No process on port 8545"
   ```
   Port 8545 is the default for Hardhat node and Anvil.

5. Detect test file patterns:
   ```
   Glob: **/*.test.{ts,tsx,js,jsx}
   Glob: **/*.spec.{ts,tsx,js,jsx}
   Glob: **/__tests__/**/*.{ts,tsx,js,jsx}
   ```
   Count the total number of test files and categorize:
   - Unit tests (no chain interaction)
   - Integration tests (mock providers)
   - Fork tests (require anvil/hardhat node)

### Phase 2: Pre-Run Checks

Before running tests, verify the environment is ready.

1. Check if dependencies are installed:
   ```bash
   ls node_modules/.package-lock.json 2>/dev/null || echo "node_modules may be missing"
   ```

2. If fork tests exist, check for RPC URL configuration:
   ```
   Grep: FORK_URL|RPC_URL|ALCHEMY_KEY|INFURA_KEY|ANVIL
   ```
   in `.env`, `.env.test`, `.env.local` files.

3. Check if anvil needs to be started:
   ```
   Grep: globalSetup.*anvil|beforeAll.*anvil|createAnvil
   ```
   If tests expect anvil but no global setup starts it, flag this.

4. Verify test timeouts are appropriate:
   ```
   Grep: timeout.*(?:5000|10000|30000)|testTimeout
   ```
   Web3 tests often need longer timeouts (15-30s) for forked chain interactions.

### Phase 3: Run Test Suite

Execute the tests with appropriate flags.

**For vitest:**
```bash
npx vitest run --reporter=verbose 2>&1
```

**For jest:**
```bash
npx jest --verbose --no-cache 2>&1
```

**For bun:**
```bash
bun test --verbose 2>&1
```

Capture the full output. If the command fails immediately (not test failures, but runner failures), diagnose:

| Error | Cause | Fix |
|-------|-------|-----|
| `Cannot find module` | Missing dependency | Run `npm install` or `pnpm install` |
| `Connection refused :8545` | No local chain running | Start anvil: `anvil --fork-url <RPC_URL>` |
| `Invalid RPC URL` | Missing env var | Check `.env.test` configuration |
| `ENOMEM` or `heap out of memory` | Node memory limit | Add `--max-old-space-size=4096` |
| `SyntaxError: Unexpected token` | Missing transformer | Check vitest/jest config for TypeScript support |

### Phase 4: Analyze Test Results

Parse the test output and categorize results.

1. **Passing tests**: Count and note what they cover.

2. **Failing tests**: For each failure, analyze with Web3 context:

   **RPC/Connection failures:**
   ```
   Grep in output: ECONNREFUSED|fetch failed|network error|timeout|RPC
   ```
   - Cause: No local chain or RPC endpoint unavailable
   - Fix: Start anvil with `anvil --fork-url <RPC_URL>` or configure a test RPC

   **BigInt assertion failures:**
   ```
   Grep in output: BigInt|cannot mix BigInt|Cannot convert a BigInt
   ```
   - Cause: Using `===` or `toEqual` with BigInt values (Jest/vitest may not handle BigInt equality)
   - Fix: Use `toBigInt` custom matcher or compare with `.toString()`

   **Gas estimation failures:**
   ```
   Grep in output: gas required exceeds|out of gas|intrinsic gas
   ```
   - Cause: Transaction parameters incorrect in test environment
   - Fix: Add gas overrides or check contract state setup

   **Revert errors:**
   ```
   Grep in output: reverted|revert|execution reverted|CALL_EXCEPTION
   ```
   - Cause: Contract preconditions not met in test setup
   - Fix: Check test setup — is the contract state correct? Are approvals set?

   **Nonce errors:**
   ```
   Grep in output: nonce|replacement transaction
   ```
   - Cause: Test isolation issue — previous test modified chain state
   - Fix: Use `snapshot/revert` pattern or reset anvil between tests

   **Timeout errors:**
   ```
   Grep in output: timeout|exceeded.*ms|Exceeded timeout
   ```
   - Cause: Default timeout too short for chain interaction
   - Fix: Increase timeout to 30000ms for integration tests

3. **Skipped tests**: Note and check why — often indicates broken setup.

### Phase 5: Coverage Analysis

If the test runner supports coverage:

**For vitest:**
```bash
npx vitest run --coverage --reporter=verbose 2>&1
```

**For jest:**
```bash
npx jest --coverage --verbose 2>&1
```

Focus coverage analysis on contract interaction code specifically:

1. Find all files that import from wagmi/viem/ethers:
   ```
   Grep: import.*(?:wagmi|viem|ethers|@web3)
   ```

2. Cross-reference these files with coverage data:
   - Are contract interaction files covered?
   - What percentage of contract-calling functions have tests?
   - Are error paths tested (revert handling, gas failures)?

3. Identify untested contract interactions:
   - List every `useReadContract`, `useWriteContract`, `readContract`, `writeContract` call
   - Check which ones appear in test files
   - Flag untested contract interactions as HIGH priority

### Phase 6: Generate Missing Tests (if needed)

If no tests exist or contract interaction coverage is below 50%, generate starter tests.

#### Vitest + Wagmi Test Pattern

```typescript
import { describe, it, expect, beforeAll } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { createConfig, http } from 'wagmi';
import { mainnet, hardhat } from 'wagmi/chains';
import { mock } from 'wagmi/connectors';
import { WagmiProvider, QueryClientProvider, QueryClient } from 'wagmi';
import React from 'react';

// Create test config with mock connector
const config = createConfig({
  chains: [hardhat],
  connectors: [
    mock({
      accounts: ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'],
    }),
  ],
  transports: {
    [hardhat.id]: http('http://127.0.0.1:8545'),
  },
});

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false },
  },
});

// Wrapper for wagmi hooks
function wrapper({ children }: { children: React.ReactNode }) {
  return React.createElement(
    WagmiProvider,
    { config },
    React.createElement(QueryClientProvider, { client: queryClient }, children)
  );
}

describe('Contract Interactions', () => {
  it('should read contract state', async () => {
    // Example: test a read hook
    const { result } = renderHook(
      () => useReadContract({
        address: '0x...',
        abi: tokenABI,
        functionName: 'balanceOf',
        args: ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'],
      }),
      { wrapper }
    );

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(typeof result.current.data).toBe('bigint');
  });
});
```

#### Anvil Fork Setup Pattern

```typescript
// vitest.setup.ts
import { createAnvil } from '@viem/anvil';

let anvil: ReturnType<typeof createAnvil>;

beforeAll(async () => {
  anvil = createAnvil({
    forkUrl: process.env.FORK_URL,
    forkBlockNumber: 19000000n, // Pin block for deterministic tests
  });
  await anvil.start();
}, 30000);

afterAll(async () => {
  await anvil.stop();
});
```

#### BigInt Assertion Helpers

```typescript
// test-utils.ts
import { expect } from 'vitest';

expect.extend({
  toBeBigInt(received: unknown) {
    const pass = typeof received === 'bigint';
    return {
      pass,
      message: () => `expected ${received} ${pass ? 'not ' : ''}to be a BigInt`,
    };
  },
  toEqualBigInt(received: bigint, expected: bigint) {
    const pass = received === expected;
    return {
      pass,
      message: () =>
        `expected ${received.toString()} ${pass ? 'not ' : ''}to equal ${expected.toString()}`,
    };
  },
});
```

#### Address Assertion Helpers

```typescript
import { getAddress } from 'viem';

expect.extend({
  toBeAddress(received: string) {
    try {
      getAddress(received);
      return { pass: true, message: () => '' };
    } catch {
      return {
        pass: false,
        message: () => `expected ${received} to be a valid checksummed address`,
      };
    }
  },
  toEqualAddress(received: string, expected: string) {
    const pass = getAddress(received) === getAddress(expected);
    return {
      pass,
      message: () =>
        `expected ${received} ${pass ? 'not ' : ''}to equal ${expected} (case-insensitive)`,
    };
  },
});
```

### Phase 7: Generate Report

Write the report to `grimoires/protocol/test-report.md`:

```markdown
# dApp Test Report

**Date**: [timestamp]
**Runner**: [vitest/jest/bun]
**Chain**: [anvil fork / hardhat / mock only]

## Results

| Metric | Value |
|--------|-------|
| Total Tests | N |
| Passing | N |
| Failing | N |
| Skipped | N |
| Duration | Xs |

## Contract Interaction Coverage

| File | Contract Calls | Tested | Coverage |
|------|---------------|--------|----------|
| src/hooks/useToken.ts | 3 | 2 | 67% |
| ... | ... | ... | ... |

## Failures Analysis

### [Test Name]
**Error**: [error message]
**Web3 Context**: [what this means in blockchain context]
**Fix**: [specific suggestion]

## Missing Tests

Contract interactions with no test coverage:
- `useWriteContract({ functionName: 'approve' })` in `src/hooks/useApprove.ts:15`
- ...

## Recommendations
1. ...
```

### Phase 8: Summary Output

Present to the user:
- Pass/fail counts
- Key failures with Web3-specific diagnosis
- Contract interaction coverage percentage
- Whether any test files were generated
- Path to the full report

## Common Web3 Test Anti-Patterns

### Anti-Pattern: Testing Against Live RPC
Tests that hit mainnet RPC are slow, flaky, and can break when chain state changes.
**Fix**: Use anvil fork pinned to a specific block number.

### Anti-Pattern: No Transaction Confirmation Wait
```typescript
// BAD: No wait for transaction
await writeContract(config);
expect(balance).toBe(newBalance); // Fails — transaction not mined yet

// GOOD: Wait for confirmation
const hash = await writeContract(config);
await waitForTransactionReceipt(config, { hash });
expect(await readBalance()).toBe(newBalance);
```

### Anti-Pattern: Shared Chain State Between Tests
Tests that modify chain state (send transactions, change balances) without resetting between tests.
**Fix**: Use `snapshot` and `revert` to isolate test state.

### Anti-Pattern: Hardcoded Block Numbers in Assertions
Block numbers change on every test run unless using a pinned fork.
**Fix**: Use relative assertions or pin fork block number.
