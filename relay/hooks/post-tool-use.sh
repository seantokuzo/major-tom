#!/usr/bin/env bash
# Major Tom — Post-Tool-Use Hook
# Claude Code calls this after a tool completes.
# Reads result JSON from stdin, POSTs to relay (fire and forget).

set -euo pipefail

RELAY_HOOK_URL="${MAJOR_TOM_HOOK_URL:-http://localhost:9091}"

# Read hook data from stdin
HOOK_DATA=$(cat)

# POST to relay server (non-blocking — don't care about response)
curl -s -X POST \
  "${RELAY_HOOK_URL}/hooks/post-tool-use" \
  -H "Content-Type: application/json" \
  -d "${HOOK_DATA}" \
  --max-time 5 > /dev/null 2>&1 || true
