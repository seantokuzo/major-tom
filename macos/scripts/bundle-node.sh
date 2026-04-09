#!/usr/bin/env bash
#
# bundle-node.sh — Downloads Node.js v22 LTS binary for macOS arm64
# and stages just the `node` executable for app bundle embedding.
#
# Usage: ./bundle-node.sh [output-dir]
#   output-dir: where to place the node binary (default: ./build/node)
#
# Idempotent: skips download if the cached tarball already exists.

set -euo pipefail

NODE_VERSION="22.16.0"
ARCH="arm64"
PLATFORM="darwin"
TARBALL="node-v${NODE_VERSION}-${PLATFORM}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/../.cache"
OUTPUT_DIR="${1:-${SCRIPT_DIR}/../build/node}"

mkdir -p "${CACHE_DIR}" "${OUTPUT_DIR}"

CACHED_TARBALL="${CACHE_DIR}/${TARBALL}"
EXTRACTED_DIR="${CACHE_DIR}/node-v${NODE_VERSION}-${PLATFORM}-${ARCH}"

echo "=== Ground Control: Bundle Node.js v${NODE_VERSION} (${ARCH}) ==="

# Download if not cached
if [[ -f "${CACHED_TARBALL}" ]]; then
    echo "Using cached tarball: ${CACHED_TARBALL}"
else
    echo "Downloading Node.js v${NODE_VERSION}..."
    curl -fSL --progress-bar -o "${CACHED_TARBALL}" "${DOWNLOAD_URL}"
    echo "Downloaded to ${CACHED_TARBALL}"
fi

# Extract if not already extracted
if [[ ! -f "${EXTRACTED_DIR}/bin/node" ]]; then
    echo "Extracting..."
    tar -xzf "${CACHED_TARBALL}" -C "${CACHE_DIR}"
fi

# Copy just the node binary
cp "${EXTRACTED_DIR}/bin/node" "${OUTPUT_DIR}/node"
chmod +x "${OUTPUT_DIR}/node"

# Verify
NODE_BUNDLED_VERSION=$("${OUTPUT_DIR}/node" --version)
echo "Bundled node binary: ${OUTPUT_DIR}/node (${NODE_BUNDLED_VERSION})"
echo "=== Done ==="
