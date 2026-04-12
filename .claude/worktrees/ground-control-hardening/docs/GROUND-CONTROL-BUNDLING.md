# Ground Control Bundling + Login Items — Spec

> Hand this doc to a fresh Claude session on a worktree branch.
> Branch name: `ground-control/full-bundle`

---

## Goal

Make `build-app.sh` produce a fully self-contained GroundControl.app that
includes Node.js and the relay dist — no external dependencies needed. Also
wire up Login Items so Ground Control can auto-start on login.

---

## Task 1: Wire bundle-node.sh + bundle-relay.sh into build-app.sh

**Current state:**
- `scripts/bundle-node.sh` downloads Node v22 LTS binary for macOS arm64,
  stages it to a configurable output dir. Idempotent (skips if cached).
- `scripts/bundle-relay.sh` runs `npm run build` on the relay and stages
  the dist output.
- `scripts/build-app.sh` assembles the .app but does NOT invoke either
  bundler — the app currently expects Node + relay at development paths.

**Desired state:**
After `build-app.sh --release`, the .app bundle looks like:

```
GroundControl.app/
  Contents/
    Info.plist
    PkgInfo
    MacOS/
      GroundControl           # Swift binary
    Resources/
      AppIcon.icns
      node/
        node                  # Stripped Node.js binary (~28-32MB)
      relay/
        server.js             # Relay entry point
        node_modules/         # Production deps only
        package.json
    _CodeSignature/
```

**Changes to build-app.sh:**
1. After `swift build`, invoke `bundle-node.sh "${RESOURCES_DIR}/node"`
2. Invoke `bundle-relay.sh "${RESOURCES_DIR}/relay"`
3. Strip the Node binary: `strip "${RESOURCES_DIR}/node/node"`
4. Prune dev dependencies: only production `node_modules`

**Changes to bundle-node.sh:**
- Add `strip` step (or make it opt-in via `--strip` flag)
- Verify the downloaded binary's SHA256 against a pinned hash

**Changes to bundle-relay.sh:**
- Accept an output directory argument
- Run `npm ci --production` (or `npm prune --production`) for the staged copy
  so devDependencies don't bloat the bundle

**Changes to NodeBundleManager.swift:**
- Currently resolves node/relay paths for development mode. Needs a
  "bundled mode" path that looks inside the app's `Bundle.main.resourceURL`.
- Detection: if `Bundle.main.resourceURL?.appendingPathComponent("node/node")`
  exists and is executable, use bundled paths. Otherwise fall back to
  development paths (current behavior).

**Changes to RelayProcess.swift:**
- `launchProcess` already uses `NodeBundleManager.resolve()` — no changes
  needed here if NodeBundleManager handles the bundled-vs-dev detection.

---

## Task 2: Login Items (SMAppService)

**Current state:**
- `RelayConfig.autoStart: Bool` exists (default true)
- `ConfigView` has an "Auto-start relay on app launch" toggle
- But there's no macOS Login Items registration — the app doesn't start on
  login, only the relay auto-starts when the app is manually launched.

**Desired state:**
- When `autoStart` is true AND the user has toggled "Launch at Login" in
  config, register the app as a Login Item via `SMAppService`.
- The toggle should be separate from "auto-start relay" — you might want
  the app to launch at login but not auto-start the relay (e.g., for
  config-only access).

**Implementation:**

New config field: `launchAtLogin: Bool` (default false).

In `GroundControlApp.init()` or `onAppear`:
```swift
import ServiceManagement

if configManager.config.launchAtLogin {
    try? SMAppService.mainApp.register()
} else {
    try? SMAppService.mainApp.unregister()
}
```

In `ConfigView`, new toggle in the Startup section:
```swift
Toggle("Launch at Login", isOn: $configManager.config.launchAtLogin)
    .help("Start Ground Control automatically when you log in")
    .onChange(of: configManager.config.launchAtLogin) { _, newValue in
        if newValue {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
```

**Entitlements:** No additional entitlements needed — SMAppService.mainApp
works without special capabilities for .app bundles.

**Note:** SMAppService requires macOS 13+ (Ventura). Our minimum is macOS 14,
so we're fine.

---

## Task 3: Strip + verify in bundle-node.sh

- `strip "${OUTPUT_DIR}/node"` — removes debug symbols, saves ~8-10MB
- Pin the expected SHA256 of the download and verify after extraction:
  ```bash
  echo "${EXPECTED_SHA}  ${OUTPUT_DIR}/node" | shasum -a 256 -c -
  ```
- This prevents supply-chain attacks on the Node binary download.

---

## Size Budget

| Component | Raw | Stripped/Pruned |
|-----------|-----|-----------------|
| Node binary | ~38MB | ~28-32MB |
| Relay dist + prod deps | ~5MB | ~3-4MB |
| GroundControl Swift | ~8MB | ~5-6MB (release) |
| Icon + plists | ~0.3MB | ~0.3MB |
| **Total** | **~51MB** | **~37-43MB** |

Nothing committed to the repo — all build artifacts are generated during
`build-app.sh` and land in the gitignored `macos/build/` directory.

---

## Key Files to Modify

| File | Change |
|------|--------|
| `macos/scripts/build-app.sh` | Invoke bundle-node.sh + bundle-relay.sh, strip |
| `macos/scripts/bundle-node.sh` | Add --strip flag, SHA256 verification |
| `macos/scripts/bundle-relay.sh` | Accept output dir, prune devDeps |
| `macos/GroundControl/Services/NodeBundleManager.swift` | Bundled-mode path detection |
| `macos/GroundControl/Models/RelayConfig.swift` | Add launchAtLogin field |
| `macos/GroundControl/Views/ConfigView.swift` | Add Login Items toggle |
| `macos/GroundControl/App/GroundControlApp.swift` | Register/unregister on launch |

## Implementation Order

1. NodeBundleManager: add bundled-mode detection (look in Bundle.main)
2. bundle-node.sh: add --strip + SHA256 verification
3. bundle-relay.sh: accept output dir, prune devDeps
4. build-app.sh: wire in both bundlers after swift build
5. Login Items: config field + toggle + SMAppService calls
6. Test: build-app.sh --release --install, verify self-contained launch
