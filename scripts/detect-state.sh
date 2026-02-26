#!/usr/bin/env bash
# detect-state.sh — Golden path state detection for Protocol construct
# Returns the current workflow state as a string for routing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../../../.."
PROTOCOL_DIR="${PROJECT_ROOT}/grimoires/protocol"

# Check if Protocol grimoire directory exists
if [[ ! -d "${PROTOCOL_DIR}" ]]; then
  echo "no_config"
  exit 0
fi

# Check for existing verification reports
if [[ -f "${PROTOCOL_DIR}/verify-report.md" ]]; then
  # Check if discrepancies were found
  if grep -q "DISCREPANCY" "${PROTOCOL_DIR}/verify-report.md" 2>/dev/null; then
    echo "discrepancies_found"
    exit 0
  fi
  echo "post_fix"
  exit 0
fi

# Check if RPC_URL is configured
if [[ -z "${RPC_URL:-}" ]]; then
  echo "no_config"
  exit 0
fi

echo "config_present"
