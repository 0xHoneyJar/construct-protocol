#!/usr/bin/env bash
# Post-install hook — runs after Protocol construct installation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../../../.."

# Create grimoire directory for Protocol reports
mkdir -p "${PROJECT_ROOT}/grimoires/protocol"

# Check for Foundry (cast)
if ! command -v cast &>/dev/null; then
  echo ""
  echo "  WARNING: Foundry (cast) not found."
  echo "  Protocol requires cast for on-chain verification."
  echo ""
  echo "  Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
  echo ""
else
  CAST_VERSION=$(cast --version 2>/dev/null | head -1)
  echo "  Foundry detected: ${CAST_VERSION}"
fi

# Check for RPC_URL
if [[ -z "${RPC_URL:-}" ]]; then
  echo ""
  echo "  NOTE: RPC_URL not set."
  echo "  Set it in .env or export RPC_URL=https://your-rpc-endpoint"
  echo "  Protocol needs this for all on-chain reads."
  echo ""
fi

echo ""
echo "  Protocol installed. 10 skills ready."
echo ""
echo "  Verify Path (live debugging):"
echo "    /verify → /proxy-inspect → /debug-tx → /abi-audit → /simulate"
echo ""
echo "  QA Path (development pipeline):"
echo "    /lint-dapp → /typecheck-dapp → /test-dapp → /e2e-dapp → /review-contract"
echo ""
echo "  Start here: /verify"
echo "    Ground your dApp's frontend in on-chain reality."
echo ""
