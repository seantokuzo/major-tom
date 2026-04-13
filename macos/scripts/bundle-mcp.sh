#!/usr/bin/env bash
#
# bundle-mcp.sh — Builds the MCP server and stages its dist output
# plus production deps for app bundle embedding.
#
# Usage: ./bundle-mcp.sh [output-dir]
#   output-dir: where to place MCP dist files (default: ./build/mcp)
#
# Requires: npm, node
#
# Output includes:
#   index.js         — MCP server entry point
#   node_modules/    — Production dependencies only
#   package.json     — For Node.js module resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
MCP_DIR="${PROJECT_ROOT}/mcp/ground-control-mcp"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/../build/staged-mcp}"

echo "=== Ground Control: Bundle MCP Server ==="

# Verify MCP source exists
if [[ ! -f "${MCP_DIR}/package.json" ]]; then
    echo "ERROR: mcp/ground-control-mcp/package.json not found at ${MCP_DIR}"
    exit 1
fi

# Install dependencies if needed
if [[ ! -d "${MCP_DIR}/node_modules" ]]; then
    echo "Installing MCP dependencies..."
    (cd "${MCP_DIR}" && npm ci)
fi

# Build the MCP server (tsc)
echo "Building MCP server..."
(cd "${MCP_DIR}" && npm run build)

# Verify build output
if [[ ! -f "${MCP_DIR}/dist/index.js" ]]; then
    echo "ERROR: Build failed — dist/index.js not found"
    exit 1
fi

# Stage the dist output
mkdir -p "${OUTPUT_DIR}"
echo "Copying MCP dist..."
cp -R "${MCP_DIR}/dist/"* "${OUTPUT_DIR}/"

# Install production-only dependencies into staged output
echo "Installing production node_modules (--omit=dev)..."
cp "${MCP_DIR}/package.json" "${OUTPUT_DIR}/package.json"
cp "${MCP_DIR}/package-lock.json" "${OUTPUT_DIR}/package-lock.json" 2>/dev/null || true
(cd "${OUTPUT_DIR}" && npm ci --omit=dev --ignore-scripts 2>/dev/null || npm install --omit=dev --ignore-scripts)

echo ""
echo "MCP server staged at: ${OUTPUT_DIR}"
ls -la "${OUTPUT_DIR}/index.js"
echo "=== Done ==="
