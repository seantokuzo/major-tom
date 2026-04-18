#!/usr/bin/env bash
# genpin.sh — mint a fresh iOS pairing PIN from the local relay.
#
# Usage: ./genpin.sh [PORT]
#   Defaults to $WS_PORT from relay/.env, then 9090 if unset.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/relay/.env"

port=${1:-}
if [[ -z "$port" && -f "$env_file" ]]; then
  port=$(grep -E '^WS_PORT=' "$env_file" | tail -n1 | cut -d= -f2 | tr -d '"' || true)
fi
port=${port:-9090}

base="http://127.0.0.1:${port}"

if ! curl -fsS --max-time 2 "$base/auth/methods" >/dev/null 2>&1; then
  echo "❌ relay not reachable at $base" >&2
  echo "   start it with:  cd relay && npm run dev" >&2
  exit 1
fi

response=$(curl -sS -X POST "$base/auth/pin/generate")

pin=$(printf '%s' "$response" | sed -n 's/.*"pin":"\([0-9]*\)".*/\1/p')
expires=$(printf '%s' "$response" | sed -n 's/.*"expiresAt":"\([^"]*\)".*/\1/p')

if [[ -z "$pin" ]]; then
  echo "❌ unexpected response from $base/auth/pin/generate:" >&2
  echo "$response" >&2
  exit 1
fi

printf '\n  🔑 PIN: \033[1;36m%s\033[0m\n' "$pin"
if [[ -n "$expires" ]]; then
  printf '  ⏱  expires: %s\n\n' "$expires"
else
  printf '\n'
fi
