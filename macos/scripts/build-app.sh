#!/usr/bin/env bash
#
# build-app.sh — Wrap the `swift build` output into a macOS .app bundle.
#
# SwiftPM's executableTarget produces a bare Unix binary. This script takes
# that binary and assembles the directory tree macOS expects from a
# double-clickable app, so Ground Control can live in /Applications, be
# dragged into the Dock, and launch like any other native app.
#
# Usage:
#   ./scripts/build-app.sh                    # debug build to macos/build/
#   ./scripts/build-app.sh --release          # release build
#   ./scripts/build-app.sh --release --install
#                                             # release + copy to /Applications
#
# Idempotent: rebuilding overwrites macos/build/GroundControl.app in place.
# The --install step replaces /Applications/GroundControl.app if present.
#
# Requires: Xcode command line tools (swift, codesign, iconutil).

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Arg parsing ───────────────────────────────────────────────────────────
CONFIG="debug"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --debug)   CONFIG="debug" ;;
        --install) INSTALL=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown arg '$arg'" >&2
            echo "usage: $0 [--release|--debug] [--install]" >&2
            exit 1
            ;;
    esac
done

# ── Constants ─────────────────────────────────────────────────────────────
APP_NAME="GroundControl"                   # Filesystem-safe name (no space)
EXEC_NAME="GroundControl"
BUILD_DIR="${MACOS_DIR}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_BUNDLE_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST_SRC="${MACOS_DIR}/GroundControl/Info.plist"
ENTITLEMENTS="${MACOS_DIR}/GroundControl/GroundControl.entitlements"
ICON_SRC="${MACOS_DIR}/GroundControl/Assets/AppIcon.icns"

# ── Preflight ─────────────────────────────────────────────────────────────
if [ ! -f "${INFO_PLIST_SRC}" ]; then
    echo "error: Info.plist not found at ${INFO_PLIST_SRC}" >&2
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────
cd "${MACOS_DIR}"
echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

# Derive the binary path directly — avoids a second `swift build` invocation
# just for `--show-bin-path` (which is mostly a no-op but still slow).
SOURCE_BINARY="${MACOS_DIR}/.build/${CONFIG}/${EXEC_NAME}"
if [ ! -f "${SOURCE_BINARY}" ]; then
    echo "error: built binary not found at ${SOURCE_BINARY}" >&2
    exit 1
fi

# ── Assemble bundle ───────────────────────────────────────────────────────
echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_BUNDLE_DIR}" "${RESOURCES_DIR}"

cp "${SOURCE_BINARY}" "${MACOS_BUNDLE_DIR}/${EXEC_NAME}"
chmod +x "${MACOS_BUNDLE_DIR}/${EXEC_NAME}"

cp "${INFO_PLIST_SRC}" "${CONTENTS_DIR}/Info.plist"

# Classic PkgInfo — `APPL` for app, `????` for unspecified creator. macOS
# still checks this file for some Launch Services edge cases.
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

# ── Icon ──────────────────────────────────────────────────────────────────
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${RESOURCES_DIR}/AppIcon.icns"
    # Embed the icon name in Info.plist if not already set. The key must
    # match the filename (minus extension) for Launch Services to pick it up.
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "${CONTENTS_DIR}/Info.plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS_DIR}/Info.plist"
    fi
    echo "==> icon: ${ICON_SRC}"
else
    echo "==> no AppIcon.icns at ${ICON_SRC} — run scripts/generate-icon.sh or drop one in"
fi

# ── Code sign (ad-hoc) ────────────────────────────────────────────────────
# Identity "-" means ad-hoc: signs with no cert. Good enough for personal /
# sideloaded use; macOS will still let you run it after the first-launch
# Gatekeeper prompt (right-click → Open).
echo "==> codesign --sign - --entitlements"
if [ -f "${ENTITLEMENTS}" ]; then
    codesign --force --deep \
        --sign - \
        --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        "${APP_DIR}"
else
    codesign --force --deep --sign - --options runtime "${APP_DIR}"
fi
codesign --verify --deep --strict "${APP_DIR}"
echo "==> verified"

echo ""
echo "Built: ${APP_DIR}"

# ── Install ──────────────────────────────────────────────────────────────
if [ "${INSTALL}" -eq 1 ]; then
    TARGET="/Applications/${APP_NAME}.app"
    echo ""
    echo "==> installing to ${TARGET}"
    if [ -d "${TARGET}" ]; then
        # Don't blindly nuke — quit any running instance first so we don't
        # overwrite a live process's files.
        osascript -e 'tell application "GroundControl" to quit' 2>/dev/null || true
        sleep 0.5
        rm -rf "${TARGET}"
    fi
    cp -R "${APP_DIR}" "${TARGET}"
    echo "installed: ${TARGET}"
    echo ""
    echo "Open with:  open '${TARGET}'"
    echo "Or drag it to the Dock from /Applications."
fi
