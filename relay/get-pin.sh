#!/bin/bash
# Generate a fresh 6-digit login PIN from the relay server.
# PIN expires after 5 minutes.

PORT="${WS_PORT:-9090}"
RESPONSE=$(curl -sfS -X POST "http://localhost:${PORT}/auth/pin/generate" 2>&1)

if [ $? -ne 0 ]; then
  echo "Failed — is the relay running on port ${PORT}?" >&2
  echo "curl error: ${RESPONSE}" >&2
  exit 1
fi

PIN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['pin'])" 2>/dev/null)

if [ -z "$PIN" ] || [ ${#PIN} -ne 6 ]; then
  echo "Bad response from relay: ${RESPONSE}" >&2
  exit 1
fi

echo "$PIN"
