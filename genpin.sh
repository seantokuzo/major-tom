#!/usr/bin/env bash
# genpin.sh — mint a fresh iOS pairing PIN from the Major Tom relay.
#
# Usage: ./genpin.sh [--tunnel | --lan | --ts]
#   --tunnel    (default)  hit via the Cloudflare Tunnel hostname from tunnel/config.yml
#   --lan                  hit via 127.0.0.1:$WS_PORT (same machine only)
#   --ts                   hit via the Tailscale IP of this machine (tailscale ip -4)
#
# NOTE: the relay's /auth/pin/generate endpoint is localhost-only (127.0.0.1).
#   tunnel → cloudflared proxies from loopback → 127.0.0.1 → ALLOWED
#   lan    → it *is* 127.0.0.1                                → ALLOWED
#   ts     → request arrives as 100.x.x.x                      → 403 (unless endpoint relaxed)

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/relay/.env"
tunnel_config="$script_dir/tunnel/config.yml"

port=$(grep -E '^WS_PORT=' "$env_file" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d '"' || true)
port=${port:-9090}

target=tunnel
while (($#)); do
  case "$1" in
    --tunnel) target=tunnel; shift ;;
    --lan) target=lan; shift ;;
    --ts|--tailscale) target=ts; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
  esac
done

discover_tunnel_url() {
  [[ -f "$tunnel_config" ]] || return 1
  local host
  host=$(awk '/^[[:space:]]*-[[:space:]]*hostname:/ {print $3; exit}' "$tunnel_config")
  [[ -n "$host" ]] || return 1
  printf 'https://%s' "$host"
}

discover_ts_base() {
  command -v tailscale >/dev/null || return 1
  local ip
  ip=$(tailscale ip -4 2>/dev/null | head -1)
  [[ -n "$ip" ]] || return 1
  printf 'http://%s:%s' "$ip" "$port"
}

case "$target" in
  lan)
    base="http://127.0.0.1:${port}"
    ;;
  tunnel)
    if ! base=$(discover_tunnel_url); then
      echo "❌ couldn't read tunnel hostname from $tunnel_config" >&2
      echo "   fall back to --lan or --ts" >&2
      exit 1
    fi
    ;;
  ts)
    if ! base=$(discover_ts_base); then
      echo "❌ couldn't discover Tailscale IP (is tailscale installed + running?)" >&2
      exit 1
    fi
    ;;
esac

echo "→ ${target}: ${base}"

if ! curl -fsS --max-time 3 "$base/auth/methods" >/dev/null 2>&1; then
  echo "❌ relay not reachable at $base" >&2
  if [[ "$target" == tunnel ]]; then
    echo "   is cloudflared running?  cd tunnel && ./start.sh" >&2
  elif [[ "$target" == lan ]]; then
    echo "   start the relay:  cd relay && npm run dev" >&2
  fi
  exit 1
fi

tmp=$(mktemp -t genpin.XXXXXX)
trap 'rm -f "$tmp"' EXIT

http_code=$(curl -sS -o "$tmp" -w '%{http_code}' -X POST "$base/auth/pin/generate")
response=$(cat "$tmp")

if [[ "$http_code" != 200 ]]; then
  echo "❌ relay returned HTTP $http_code:" >&2
  echo "   $response" >&2
  if [[ "$target" == ts ]]; then
    echo "   (the /auth/pin/generate endpoint is localhost-only; Tailscale" >&2
    echo "    requests arrive as 100.x.x.x and get rejected. Mint via --lan or --tunnel.)" >&2
  fi
  exit 1
fi

pin=$(printf '%s' "$response" | sed -n 's/.*"pin":"\([0-9]*\)".*/\1/p')
expires=$(printf '%s' "$response" | sed -n 's/.*"expiresAt":"\([^"]*\)".*/\1/p')

if [[ -z "$pin" ]]; then
  echo "❌ unexpected response:" >&2
  echo "$response" >&2
  exit 1
fi

printf '\n  🔑 PIN: \033[1;36m%s\033[0m\n' "$pin"
[[ -n "$expires" ]] && printf '  ⏱  expires: %s\n' "$expires"
printf '  🌐 host:    %s\n\n' "$base"
