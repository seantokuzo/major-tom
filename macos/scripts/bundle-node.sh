#!/usr/bin/env bash
#
# bundle-node.sh — Downloads Node.js v22 LTS binary for macOS arm64
# and stages just the `node` executable for app bundle embedding.
#
# Usage: ./bundle-node.sh [--strip] [output-dir]
#   --strip     Strip debug symbols from the node binary (~8-10MB savings)
#   output-dir: where to place the node binary (default: ./build/node)
#
# Idempotent: skips download if the cached tarball already exists.
# Verifies SHA256 hash after download to prevent supply-chain attacks.

set -euo pipefail

NODE_VERSION="22.16.0"
ARCH="arm64"
PLATFORM="darwin"
TARBALL="node-v${NODE_VERSION}-${PLATFORM}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"

# SHA256 hash of the official tarball (from https://nodejs.org/dist/v22.16.0/SHASUMS256.txt)
# Updated when NODE_VERSION changes.
EXPECTED_SHA256="1d7f34ec4c03e12d8b33481e5c4560432d7dc31a0ef3ff5a4d9a8ada7cf6ecc9"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/../.cache"

# Arg parsing
STRIP_BINARY=0
OUTPUT_DIR=""
for arg in "$@"; do
    case "$arg" in
        --strip) STRIP_BINARY=1 ;;
        *)
            if [[ -z "${OUTPUT_DIR}" ]]; then
                OUTPUT_DIR="$arg"
            else
                echo "error: unexpected arg '$arg'" >&2
                exit 1
            fi
            ;;
    esac
done
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../build/node}"

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

# Verify SHA256 hash
echo "Verifying SHA256 hash..."
ACTUAL_SHA256=$(shasum -a 256 "${CACHED_TARBALL}" | awk '{print $1}')
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    echo "ERROR: SHA256 mismatch!"
    echo "  Expected: ${EXPECTED_SHA256}"
    echo "  Actual:   ${ACTUAL_SHA256}"
    echo "Removing corrupted download."
    rm -f "${CACHED_TARBALL}"
    exit 1
fi
echo "SHA256 verified: ${ACTUAL_SHA256}"

# Extract if not already extracted
if [[ ! -f "${EXTRACTED_DIR}/bin/node" ]]; then
    echo "Extracting..."
    tar -xzf "${CACHED_TARBALL}" -C "${CACHE_DIR}"
fi

# Copy just the node binary
cp "${EXTRACTED_DIR}/bin/node" "${OUTPUT_DIR}/node"
chmod +x "${OUTPUT_DIR}/node"

# Strip debug symbols if requested (saves ~8-10MB)
if [[ "${STRIP_BINARY}" -eq 1 ]]; then
    BEFORE_SIZE=$(stat -f%z "${OUTPUT_DIR}/node" 2>/dev/null || stat --printf="%s" "${OUTPUT_DIR}/node" 2>/dev/null)
    echo "Stripping debug symbols..."
    strip "${OUTPUT_DIR}/node" 2>/dev/null || echo "  (strip had warnings — binary is still functional)"
    AFTER_SIZE=$(stat -f%z "${OUTPUT_DIR}/node" 2>/dev/null || stat --printf="%s" "${OUTPUT_DIR}/node" 2>/dev/null)
    SAVED=$(( (BEFORE_SIZE - AFTER_SIZE) / 1024 / 1024 ))
    echo "Stripped: ${BEFORE_SIZE} -> ${AFTER_SIZE} bytes (saved ~${SAVED}MB)"
fi

# Verify — the binary might be a different architecture than the build host
# (e.g., arm64 binary built on x86_64 CI), so don't fail if we can't run it.
NODE_BUNDLED_VERSION=$("${OUTPUT_DIR}/node" --version 2>/dev/null) || NODE_BUNDLED_VERSION="(cross-arch — cannot verify)"
FINAL_SIZE=$(stat -f%z "${OUTPUT_DIR}/node" 2>/dev/null || stat --printf="%s" "${OUTPUT_DIR}/node" 2>/dev/null)
FINAL_MB=$(( FINAL_SIZE / 1024 / 1024 ))
echo "Bundled node binary: ${OUTPUT_DIR}/node (${NODE_BUNDLED_VERSION}, ${FINAL_MB}MB)"
echo "=== Done ==="
