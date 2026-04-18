#!/usr/bin/env bash
# genpin.sh — mint a fresh iOS pairing PIN from the Major Tom relay.
#
# Usage: ./genpin.sh [--tunnel | --lan | --ts]
#   --tunnel    (default)  print the Cloudflare Tunnel hostname as the
#                          sharable host (phone/friend uses this). The
#                          PIN itself is always minted against
#                          127.0.0.1 because /auth/pin/generate is
#                          localhost-only and tunnel traffic can appear
#                          as an external IP via cloudflared forwarded
#                          headers.
#   --lan                  mint + print 127.0.0.1:$WS_PORT (same Mac)
#   --ts                   print the Tailscale IP of this machine, mint
#                          against 127.0.0.1

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

# `mint_base` is always the local loopback — /auth/pin/generate is
# localhost-only. `share_base` is what we print for the phone/friend.
mint_base="http://127.0.0.1:${port}"

case "$target" in
  lan)
    share_base="$mint_base"
    ;;
  tunnel)
    if ! share_base=$(discover_tunnel_url); then
      echo "❌ couldn't read tunnel hostname from $tunnel_config" >&2
      echo "   is the tunnel set up?  ./setup.sh" >&2
      exit 1
    fi
    # Verify the tunnel is actually live so the printed URL works.
    if ! curl -fsS --max-time 3 "$share_base/auth/methods" >/dev/null 2>&1; then
      echo "⚠️  tunnel hostname resolved ($share_base) but the relay didn't"
      echo "    answer through it — is cloudflared running?"
      echo "    cd tunnel && ./start.sh"
      echo "    (continuing anyway — PIN minted against localhost)"
    fi
    ;;
  ts)
    if ! share_base=$(discover_ts_base); then
      echo "❌ couldn't discover Tailscale IP (is tailscale installed + running?)" >&2
      exit 1
    fi
    ;;
esac

echo "→ ${target}: ${share_base}"

if ! curl -fsS --max-time 3 "$mint_base/auth/methods" >/dev/null 2>&1; then
  echo "❌ relay not reachable at $mint_base" >&2
  echo "   start the relay:  cd relay && npm run dev" >&2
  exit 1
fi

tmp=$(mktemp -t genpin.XXXXXX)
trap 'rm -f "$tmp"' EXIT

http_code=$(curl -sS -o "$tmp" -w '%{http_code}' -X POST "$mint_base/auth/pin/generate")
response=$(cat "$tmp")

if [[ "$http_code" != 200 ]]; then
  echo "❌ relay returned HTTP $http_code:" >&2
  echo "   $response" >&2
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
printf '  🌐 host:    %s\n\n' "$share_base"
