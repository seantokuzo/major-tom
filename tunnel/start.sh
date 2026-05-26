#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Major Tom — Start Cloudflare Tunnel
#
# Runs the named tunnel using the local config.
# Run setup.sh first if you haven't already.
# ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Error: ${CONFIG_FILE} not found."
  echo "Run 'npm run tunnel:setup' first to configure the tunnel."
  exit 1
fi

# Derive tunnel ID from config.yml to stay in sync with setup.sh
TUNNEL_ID="$(grep -E '^[[:space:]]*tunnel:' "${CONFIG_FILE}" | head -n1 | sed 's/^[[:space:]]*tunnel:[[:space:]]*//' | sed 's/[[:space:]]*$//')"

if [ -z "${TUNNEL_ID}" ]; then
  echo "Error: Could not determine tunnel ID from ${CONFIG_FILE}"
  exit 1
fi

# Force the HTTP/2 edge transport. The QUIC default flaps on some networks
# ("failed to accept QUIC stream: timeout: no recent network activity"),
# repeatedly dropping the WebSocket before the PTY can spawn.
exec cloudflared tunnel --config "${CONFIG_FILE}" --protocol http2 run "${TUNNEL_ID}"
