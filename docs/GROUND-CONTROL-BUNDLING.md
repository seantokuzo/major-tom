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

**Desired .app layout:**

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

**Changes needed:**
- build-app.sh: invoke bundle-node.sh + bundle-relay.sh, strip node binary
- bundle-node.sh: add --strip flag, SHA256 verification
- bundle-relay.sh: accept output dir, prune devDeps
- NodeBundleManager.swift: detect bundled mode via Bundle.main.resourceURL

---

## Task 2: Login Items (SMAppService)

New config field: `launchAtLogin: Bool` (default false).

```swift
import ServiceManagement

if configManager.config.launchAtLogin {
    try? SMAppService.mainApp.register()
} else {
    try? SMAppService.mainApp.unregister()
}
```

New toggle in ConfigView Startup section. SMAppService requires macOS 13+;
our minimum is macOS 14, so no compatibility concern.

---

## Task 3: Node binary integrity

- `strip` the binary (saves ~8-10MB)
- Pin expected SHA256, verify after download extraction
- Prevents supply-chain attacks on the Node binary download

---

## Size Budget

| Component | Raw | Stripped/Pruned |
|-----------|-----|-----------------|
| Node binary | ~38MB | ~28-32MB |
| Relay dist + prod deps | ~5MB | ~3-4MB |
| GroundControl Swift | ~8MB | ~5-6MB (release) |
| Icon + plists | ~0.3MB | ~0.3MB |
| **Total** | **~51MB** | **~37-43MB** |

Nothing committed to the repo — all build artifacts land in gitignored
`macos/build/` directory.

---

## Key Files to Modify

| File | Change |
|------|--------|
| `macos/scripts/build-app.sh` | Invoke bundlers, strip |
| `macos/scripts/bundle-node.sh` | --strip flag, SHA256 |
| `macos/scripts/bundle-relay.sh` | Output dir arg, prune devDeps |
| `macos/GroundControl/Services/NodeBundleManager.swift` | Bundled-mode detection |
| `macos/GroundControl/Models/RelayConfig.swift` | Add launchAtLogin |
| `macos/GroundControl/Views/ConfigView.swift` | Login Items toggle |
| `macos/GroundControl/App/GroundControlApp.swift` | SMAppService register |

## Implementation Order

1. NodeBundleManager: bundled-mode detection (Bundle.main)
2. bundle-node.sh: --strip + SHA256
3. bundle-relay.sh: output dir, prune devDeps
4. build-app.sh: wire in both bundlers
5. Login Items: config field + toggle + SMAppService
6. Test: build-app.sh --release --install, verify self-contained launch
