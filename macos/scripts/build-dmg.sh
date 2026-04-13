#!/usr/bin/env bash
#
# build-dmg.sh — Creates GroundControl.dmg from the built .app
#
# Usage:
#   ./scripts/build-dmg.sh                   # uses build/GroundControl.app
#   ./scripts/build-dmg.sh path/to/App.app   # uses custom .app path
#
# Output: build/GroundControl.dmg (compressed, read-only)
# Requires: hdiutil (built into macOS, no deps)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
APP_PATH="${1:-${BUILD_DIR}/GroundControl.app}"
DMG_PATH="${BUILD_DIR}/GroundControl.dmg"
TMP_DMG="${BUILD_DIR}/tmp-gc.dmg"
VOLUME_NAME="Ground Control"

# ── Preflight ─────────────────────────────────────────────────────────────
if [[ ! -d "${APP_PATH}" ]]; then
    echo "ERROR: .app not found at ${APP_PATH}" >&2
    echo "Run scripts/build-app.sh first." >&2
    exit 1
fi

echo "=== Ground Control: Create DMG ==="
echo "Source: ${APP_PATH}"

# Clean previous artifacts
rm -f "${DMG_PATH}" "${TMP_DMG}"

# ── Create temporary writable DMG ─────────────────────────────────────────
# Size the DMG to ~1.5x the .app to leave room for the symlink and filesystem
# overhead. hdiutil will compress it down in the convert step.
APP_SIZE_KB=$(du -sk "${APP_PATH}" | awk '{print $1}')
DMG_SIZE_KB=$(( APP_SIZE_KB * 3 / 2 ))
DMG_SIZE_MB=$(( DMG_SIZE_KB / 1024 + 10 ))

echo "Creating temporary DMG (${DMG_SIZE_MB}MB)..."
hdiutil create \
    -size "${DMG_SIZE_MB}m" \
    -fs HFS+ \
    -volname "${VOLUME_NAME}" \
    "${TMP_DMG}" \
    -quiet

# ── Populate ──────────────────────────────────────────────────────────────
echo "Mounting and populating..."
hdiutil attach "${TMP_DMG}" -mountpoint "/Volumes/${VOLUME_NAME}" -quiet

cp -R "${APP_PATH}" "/Volumes/${VOLUME_NAME}/"
ln -s /Applications "/Volumes/${VOLUME_NAME}/Applications"

# ── Detach + convert ──────────────────────────────────────────────────────
echo "Detaching..."
hdiutil detach "/Volumes/${VOLUME_NAME}" -quiet

echo "Compressing to read-only DMG..."
hdiutil convert "${TMP_DMG}" -format UDZO -o "${DMG_PATH}" -quiet

rm -f "${TMP_DMG}"

# ── Summary ───────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')
echo ""
echo "Created: ${DMG_PATH} (${DMG_SIZE})"
echo "=== Done ==="
