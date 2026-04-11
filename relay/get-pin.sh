#!/bin/bash
# Generate a fresh 6-digit login PIN from the relay server.
# PIN expires after 5 minutes.

PORT="${WS_PORT:-9090}"
RESPONSE=$(curl -s -X POST "http://localhost:${PORT}/auth/pin/generate")

if [ $? -ne 0 ] || echo "$RESPONSE" | grep -q '"error"'; then
  echo "Failed — is the relay running on port ${PORT}?" >&2
  exit 1
fi

PIN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['pin'])" 2>/dev/null)
echo "$PIN"
