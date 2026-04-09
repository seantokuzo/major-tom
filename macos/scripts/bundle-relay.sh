#!/usr/bin/env bash
#
# bundle-relay.sh — Builds the relay server and stages its dist output
# plus the node-pty native addon for app bundle embedding.
#
# Usage: ./bundle-relay.sh [output-dir]
#   output-dir: where to place relay dist files (default: ./build/relay-dist)
#
# Requires: npm, node

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
RELAY_DIR="${PROJECT_ROOT}/relay"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/../build/relay-dist}"

echo "=== Ground Control: Bundle Relay Server ==="

# Verify relay source exists
if [[ ! -f "${RELAY_DIR}/package.json" ]]; then
    echo "ERROR: relay/package.json not found at ${RELAY_DIR}"
    exit 1
fi

# Install dependencies if needed
if [[ ! -d "${RELAY_DIR}/node_modules" ]]; then
    echo "Installing relay dependencies..."
    (cd "${RELAY_DIR}" && npm ci)
fi

# Build the relay (tsc + esbuild)
echo "Building relay..."
(cd "${RELAY_DIR}" && npm run build)

# Verify build output
if [[ ! -f "${RELAY_DIR}/dist/server.js" ]]; then
    echo "ERROR: Build failed — relay/dist/server.js not found"
    exit 1
fi

# Stage the dist output
mkdir -p "${OUTPUT_DIR}"
echo "Copying relay dist..."
cp -R "${RELAY_DIR}/dist/"* "${OUTPUT_DIR}/"

# Copy node-pty native addon
# node-pty compiles a .node file that lives in node_modules
echo "Locating node-pty native addon..."

NODE_PTY_BINDING=""
# Check common locations for the native addon
for candidate in \
    "${RELAY_DIR}/node_modules/node-pty/build/Release/pty.node" \
    "${RELAY_DIR}/node_modules/node-pty/build/Debug/pty.node" \
    ; do
    if [[ -f "${candidate}" ]]; then
        NODE_PTY_BINDING="${candidate}"
        break
    fi
done

if [[ -n "${NODE_PTY_BINDING}" ]]; then
    echo "Found node-pty binding: ${NODE_PTY_BINDING}"
    mkdir -p "${OUTPUT_DIR}/node-pty"
    cp "${NODE_PTY_BINDING}" "${OUTPUT_DIR}/node-pty/pty.node"

    # Also copy the JS shims node-pty needs
    if [[ -d "${RELAY_DIR}/node_modules/node-pty/lib" ]]; then
        cp -R "${RELAY_DIR}/node_modules/node-pty/lib" "${OUTPUT_DIR}/node-pty/"
    fi
    echo "node-pty addon staged"
else
    echo "WARNING: node-pty native addon not found — relay will not be able to spawn PTY sessions"
    echo "         This is expected if node-pty is not yet installed. Run 'cd relay && npm install' first."
fi

# Copy package.json for Node module resolution (node needs it for ESM)
cp "${RELAY_DIR}/package.json" "${OUTPUT_DIR}/package.json"

# Also need the node_modules for external dependencies that esbuild didn't bundle
# (esbuild uses --packages=external, so runtime deps must be present)
echo "Copying node_modules (external dependencies)..."
if [[ -d "${RELAY_DIR}/node_modules" ]]; then
    cp -R "${RELAY_DIR}/node_modules" "${OUTPUT_DIR}/node_modules"
fi

echo ""
echo "Relay dist staged at: ${OUTPUT_DIR}"
ls -la "${OUTPUT_DIR}/server.js"
echo "=== Done ==="
