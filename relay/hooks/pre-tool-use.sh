#!/usr/bin/env bash
# Major Tom — Pre-Tool-Use Hook
# Claude Code calls this before executing a tool.
# Reads tool call JSON from stdin, POSTs to relay, blocks until decision.

set -euo pipefail

RELAY_HOOK_URL="${MAJOR_TOM_HOOK_URL:-http://localhost:9091}"

# Read hook data from stdin
HOOK_DATA=$(cat)

# POST to relay server and wait for approval decision
RESPONSE=$(curl -s -X POST \
  "${RELAY_HOOK_URL}/hooks/pre-tool-use" \
  -H "Content-Type: application/json" \
  -d "${HOOK_DATA}" \
  --max-time 300)

# Output the decision JSON for Claude Code
echo "${RESPONSE}"
