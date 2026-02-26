# dapp-e2e — Agent-Browser Web3 E2E Testing

## Purpose

You are an end-to-end Web3 testing agent. Your job is to test the actual user experience of a dApp in a real browser: connect a wallet, navigate through flows, submit transactions, and verify that the frontend correctly reflects blockchain state changes. You work with or without the `agent-browser` MCP tool — if it's available, you execute flows directly; if not, you generate Playwright scripts the developer can run.

**IMPORTANT**: This skill has `danger_level: high` because it interacts with browsers and potentially submits transactions. You MUST verify you are working against a test environment (localhost, testnet, or anvil fork) before executing any transaction flows. NEVER execute transactions against mainnet.

## Execution Protocol

### Phase 1: Environment Assessment

You MUST determine what tools and environments are available before proceeding.

1. Check for agent-browser MCP availability:
   - If the `agent-browser` tool is available in your tool list, you can execute browser flows directly
   - If not, you will generate Playwright scripts for manual execution

2. Check for Playwright installation:
   ```bash
   npx playwright --version 2>/dev/null || echo "Playwright not installed"
   ```

3. Check for existing E2E test infrastructure:
   ```
   Glob: **/playwright.config.{ts,js}
   Glob: **/e2e/**/*.{ts,js}
   Glob: **/tests/e2e/**/*.{ts,js}
   Glob: **/*.e2e.{ts,js}
   ```

4. Check for a running dev server:
   ```bash
   lsof -i :3000 2>/dev/null | head -3 || echo "No process on port 3000"
   ```
   ```bash
   lsof -i :5173 2>/dev/null | head -3 || echo "No process on port 5173"
   ```

5. Check for a running local chain:
   ```bash
   lsof -i :8545 2>/dev/null | head -3 || echo "No process on port 8545"
   ```

6. Determine the target URL:
   - If dev server running: use `http://localhost:3000` or `:5173`
   - If not running: note that dev server must be started first

7. Verify testnet/local environment:
   ```
   Grep: chainId|chain.*id|NEXT_PUBLIC_CHAIN in .env* files
   ```
   You MUST confirm the target chain is NOT mainnet (chainId 1) before proceeding with transaction tests.

### Phase 2: User Flow Discovery

Analyze the frontend code to identify testable user flows.

1. Find all page routes:
   ```
   Glob: **/app/**/page.{tsx,jsx,ts,js}
   Glob: **/pages/**/*.{tsx,jsx,ts,js}
   ```

2. Find wallet connection points:
   ```
   Grep: ConnectButton|ConnectWallet|useConnect|connectAsync|Web3Modal|RainbowKit
   ```

3. Find transaction submission forms:
   ```
   Grep: useWriteContract|useSendTransaction|writeContract|sendTransaction
   ```
   For each match, trace back to the UI component to find the form/button that triggers it.

4. Find approval flows:
   ```
   Grep: useApprove|approve|allowance|useAllowance
   ```

5. Find state-reading displays:
   ```
   Grep: useReadContract|useBalance|useToken|useContractRead
   ```
   These show blockchain state — E2E tests should verify they update after transactions.

6. Build a flow inventory:

   | Flow | Entry Point | Actions | Expected Result |
   |------|------------|---------|-----------------|
   | Connect Wallet | /app | Click Connect → Select Mock | Address shown in header |
   | Submit Transaction | /swap | Fill amount → Click Swap → Confirm | TX hash shown, balance updated |
   | Approve Token | /pool | Click Approve → Confirm | Allowance updated, next step enabled |

### Phase 3: Wallet Mock Strategy

Web3 E2E tests need a mock wallet. There are several approaches:

#### Option A: Wagmi Mock Connector (Preferred for Playwright)

If the app uses wagmi, inject a mock connector via window or environment:

```typescript
// e2e/fixtures/wallet.ts
import { chromium, type BrowserContext } from '@playwright/test';

export async function setupMockWallet(context: BrowserContext) {
  // Inject mock ethereum provider before page loads
  await context.addInitScript(() => {
    const accounts = ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'];
    const chainId = '0x7a69'; // 31337 (hardhat/anvil)

    window.ethereum = {
      isMetaMask: true,
      selectedAddress: accounts[0],
      chainId,
      networkVersion: '31337',
      request: async ({ method, params }: { method: string; params?: unknown[] }) => {
        switch (method) {
          case 'eth_requestAccounts':
          case 'eth_accounts':
            return accounts;
          case 'eth_chainId':
            return chainId;
          case 'net_version':
            return '31337';
          case 'wallet_switchEthereumChain':
            return null;
          case 'eth_sendTransaction': {
            // Forward to local anvil
            const response = await fetch('http://127.0.0.1:8545', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: Date.now(),
                method: 'eth_sendTransaction',
                params,
              }),
            });
            const data = await response.json();
            return data.result;
          }
          case 'personal_sign':
          case 'eth_signTypedData_v4':
            // Return a mock signature
            return '0x' + '00'.repeat(65);
          default:
            // Proxy other calls to anvil
            const rpcResponse = await fetch('http://127.0.0.1:8545', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: Date.now(),
                method,
                params: params || [],
              }),
            });
            const rpcData = await rpcResponse.json();
            return rpcData.result;
        }
      },
      on: () => {},
      removeListener: () => {},
      removeAllListeners: () => {},
    };
  });
}
```

#### Option B: Agent-Browser Direct Interaction

If `agent-browser` MCP is available, you can interact with the real page:
- Navigate to the URL
- Click the wallet connect button
- If a modal appears, interact with it
- For transaction confirmations, look for wallet popup patterns

### Phase 4: Test Generation

Generate Playwright test files for each discovered flow.

#### Base Test Template

```typescript
// e2e/dapp.spec.ts
import { test, expect } from '@playwright/test';
import { setupMockWallet } from './fixtures/wallet';

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';

test.describe('dApp E2E Tests', () => {
  test.beforeEach(async ({ context, page }) => {
    await setupMockWallet(context);
    await page.goto(BASE_URL);
    // Wait for app hydration
    await page.waitForLoadState('networkidle');
  });

  test('wallet connection flow', async ({ page }) => {
    // 1. Find and click the connect button
    const connectButton = page.getByRole('button', { name: /connect/i });
    await expect(connectButton).toBeVisible();
    await connectButton.click();

    // 2. Wait for connection to establish
    await page.waitForTimeout(2000);

    // 3. Verify address is displayed
    // Look for truncated address pattern: 0xf39F...2266
    await expect(page.getByText(/0xf39F/i)).toBeVisible({ timeout: 10000 });
  });

  test('page loads without errors', async ({ page }) => {
    // Check no console errors
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') errors.push(msg.text());
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');

    // Filter out known benign errors (like missing favicon)
    const realErrors = errors.filter(e =>
      !e.includes('favicon') && !e.includes('manifest')
    );
    expect(realErrors).toHaveLength(0);
  });
});
```

#### Transaction Flow Template

```typescript
test('submit transaction flow', async ({ page }) => {
  // 1. Navigate to the transaction page
  await page.goto(`${BASE_URL}/swap`);
  await page.waitForLoadState('networkidle');

  // 2. Fill in transaction parameters
  const amountInput = page.getByPlaceholder(/amount|enter/i);
  await amountInput.fill('1.0');

  // 3. Check for approval step (if needed)
  const approveButton = page.getByRole('button', { name: /approve/i });
  if (await approveButton.isVisible({ timeout: 2000 }).catch(() => false)) {
    await approveButton.click();
    // Wait for approval transaction
    await expect(page.getByText(/approved|success/i)).toBeVisible({ timeout: 30000 });
  }

  // 4. Submit the transaction
  const submitButton = page.getByRole('button', { name: /swap|submit|confirm/i });
  await expect(submitButton).toBeEnabled({ timeout: 10000 });
  await submitButton.click();

  // 5. Verify loading state appears
  await expect(page.getByText(/pending|confirming|loading/i)).toBeVisible({ timeout: 5000 });

  // 6. Verify success state
  await expect(page.getByText(/success|confirmed|complete/i)).toBeVisible({ timeout: 30000 });

  // 7. Verify state update (balance changed, etc.)
  // This is app-specific — adapt to the actual UI
});
```

#### Error Handling Template

```typescript
test('handles transaction rejection gracefully', async ({ context, page }) => {
  // Override mock to reject transactions
  await context.addInitScript(() => {
    const original = window.ethereum.request;
    window.ethereum.request = async (args: { method: string; params?: unknown[] }) => {
      if (args.method === 'eth_sendTransaction') {
        throw new Error('User rejected the request');
      }
      return original(args);
    };
  });

  await page.goto(`${BASE_URL}/swap`);
  // ... fill in form ...

  const submitButton = page.getByRole('button', { name: /swap|submit/i });
  await submitButton.click();

  // Should show error, not crash
  await expect(page.getByText(/rejected|cancelled|denied/i)).toBeVisible({ timeout: 5000 });

  // App should still be functional
  await expect(submitButton).toBeVisible();
});

test('handles network switch gracefully', async ({ context, page }) => {
  await page.goto(BASE_URL);
  await page.waitForLoadState('networkidle');

  // Simulate chain change event
  await page.evaluate(() => {
    if (window.ethereum && window.ethereum.on) {
      // Trigger chainChanged event
      const handlers = (window.ethereum as any)._handlers?.chainChanged || [];
      handlers.forEach((h: Function) => h('0x1')); // Switch to mainnet
    }
  });

  // App should handle network change (show wrong network banner, or switch)
  // Look for network-related UI elements
  await page.waitForTimeout(2000);
});
```

### Phase 5: Execute Tests

#### Path A: Agent-Browser Execution

If `agent-browser` is available, execute the key flows directly:

1. Navigate to the app URL
2. Take a screenshot of the initial state
3. Look for the connect wallet button and click it
4. Take a screenshot after connection
5. Navigate to transaction pages
6. Fill in forms and submit
7. Take screenshots at each step
8. Verify success/error states visually

For each step, report:
- What was visible on the page
- Whether the expected elements were found
- Any console errors
- Any unexpected behavior

#### Path B: Playwright Script Execution

If Playwright is installed:

```bash
npx playwright test e2e/dapp.spec.ts --reporter=list 2>&1
```

If Playwright is NOT installed, output the generated test files and provide setup instructions:

```bash
npm install -D @playwright/test
npx playwright install chromium
```

### Phase 6: Visual Verification Checklist

For each tested flow, verify these UX patterns:

| Check | What to Look For | Severity if Missing |
|-------|-----------------|-------------------|
| Loading states | Spinner/skeleton during transaction | HIGH |
| Error messages | User-readable error on revert | HIGH |
| Success confirmation | Clear success indicator + TX hash | MEDIUM |
| Balance updates | Numbers change after transaction | HIGH |
| Button disabled states | Submit disabled during pending TX | MEDIUM |
| Network mismatch warning | Banner when wrong chain | HIGH |
| Wallet disconnection handling | Graceful fallback UI | MEDIUM |
| Mobile responsiveness | Layout doesn't break on small screens | MEDIUM |
| Transaction hash link | Links to block explorer | LOW |
| Gas estimation display | Shows estimated gas before confirm | LOW |

### Phase 7: Generate Report

Write the report to `grimoires/protocol/e2e-report.md`:

```markdown
# dApp E2E Test Report

**Date**: [timestamp]
**Method**: [agent-browser / playwright / scripts-only]
**Target**: [URL]
**Chain**: [local anvil / testnet name]

## Flows Tested

### 1. Wallet Connection
**Status**: PASS/FAIL
**Steps**:
1. Navigated to home page — [screenshot if available]
2. Clicked Connect Wallet — [result]
3. Verified address displayed — [result]

**Issues Found**:
- [issue description with severity]

### 2. Transaction Submission
...

## UX Checklist

| Check | Status | Notes |
|-------|--------|-------|
| Loading states | PASS/FAIL | ... |
| Error messages | PASS/FAIL | ... |
...

## Generated Test Files

| File | Covers |
|------|--------|
| e2e/dapp.spec.ts | Wallet connection, page load |
| e2e/transactions.spec.ts | Swap flow, approval flow |
| e2e/fixtures/wallet.ts | Mock wallet provider |

## Setup Instructions (if scripts-only)

1. Install Playwright: `npm install -D @playwright/test`
2. Install browsers: `npx playwright install chromium`
3. Start anvil: `anvil --fork-url <RPC_URL>`
4. Start dev server: `npm run dev`
5. Run tests: `npx playwright test`
```

### Phase 8: Summary Output

Present to the user:
- Which flows were tested (and how: live browser or generated scripts)
- Pass/fail results for each flow
- Critical UX issues found
- Generated test file locations
- Path to the full report

## Safety Constraints

1. **NEVER execute against mainnet**. Before any transaction flow:
   - Verify chain ID is NOT 1 (Ethereum mainnet)
   - Verify chain ID is NOT 56 (BSC), 137 (Polygon), etc. for production networks
   - Acceptable: 31337 (hardhat/anvil), 1337 (local), 11155111 (Sepolia), 5 (Goerli)

2. **NEVER use real private keys**. The mock wallet uses Anvil's default test account only.

3. **NEVER submit transactions to real contracts** unless explicitly targeting testnet-deployed contracts.

4. If uncertain about the target environment, ASK the user before proceeding with transaction tests.

## Playwright Configuration Reference

If generating a new `playwright.config.ts`:

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 60000, // Web3 tests need longer timeouts
  retries: 1,
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'npm run dev',
    port: 3000,
    reuseExistingServer: true,
    timeout: 120000,
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
});
```
