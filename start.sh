#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Major Tom — One-command startup
#
# Starts relay server, PWA dev server, and Cloudflare tunnel.
# Run from repo root: ./start.sh
#
# Options:
#   --local    Skip the Cloudflare tunnel (local dev only)
#   --prod     Use production relay (node dist/) instead of tsx watch
# ──────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELAY_DIR="${ROOT_DIR}/relay"
WEB_DIR="${ROOT_DIR}/web"
TUNNEL_DIR="${ROOT_DIR}/tunnel"

LOCAL_ONLY=false
PROD_MODE=false

for arg in "$@"; do
  case "$arg" in
    --local) LOCAL_ONLY=true ;;
    --prod)  PROD_MODE=true ;;
  esac
done

# Prevent macOS from sleeping / dimming display while relay is running
caffeinate -dims -w $$ &
CAFFEINE_PID=$!

# Track child PIDs for cleanup
PIDS=()

cleanup() {
  echo ""
  echo "Shutting down..."
  kill "$CAFFEINE_PID" 2>/dev/null || true
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null
  echo "Done."
}
trap cleanup EXIT INT TERM

# ── 1. Relay server ──────────────────────────────────────────

echo "Starting relay server..."
if [ "$PROD_MODE" = true ]; then
  (cd "$RELAY_DIR" && npm run start) &
else
  (cd "$RELAY_DIR" && npm run dev) &
fi
PIDS+=($!)

# Give relay a moment to start
sleep 1

# ── 2. PWA dev server ───────────────────────────────────────

echo "Starting PWA dev server..."
(cd "$WEB_DIR" && npm run dev) &
PIDS+=($!)

# ── 3. Cloudflare tunnel ────────────────────────────────────

if [ "$LOCAL_ONLY" = false ]; then
  if [ -f "${TUNNEL_DIR}/config.yml" ]; then
    echo "Starting Cloudflare tunnel..."
    (cd "$RELAY_DIR" && npm run tunnel) &
    PIDS+=($!)
  else
    echo ""
    echo "⚠ Tunnel not configured — skipping. Run: npm run tunnel:setup (in relay/)"
    echo "  Once set up, the tunnel will start automatically with this script."
    echo ""
  fi
fi

# ── Ready ────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Major Tom is running"
echo ""
echo " PWA:   http://localhost:5173"
echo " Relay: http://localhost:9090"
if [ "$LOCAL_ONLY" = false ] && [ -f "${TUNNEL_DIR}/config.yml" ]; then
  HOSTNAME="$(grep -E 'hostname:' "${TUNNEL_DIR}/config.yml" | head -n1 | sed 's/^.*hostname:[[:space:]]*//' | sed 's/[[:space:]]*$//')" || true
  if [ -n "$HOSTNAME" ]; then
    echo " Tunnel: https://${HOSTNAME}"
  fi
fi
echo ""
echo " Ctrl+C to stop everything"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait for any child to exit
wait
