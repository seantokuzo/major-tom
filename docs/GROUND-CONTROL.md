# Ground Control: macOS Relay Manager

> **Status:** Spec v1 — 2026-04-09
> **Repo:** `major-tom` (new target in existing Xcode workspace, or separate SwiftPM project)
> **Predecessor:** Phase 13 "The Shell" (relay server is now the core product)
> **Parallel track:** Phase 14 "SwiftTerm" (iOS terminal)

---

## TL;DR

Ground Control is a **native macOS app** that wraps the Major Tom relay server in a proper Mac citizen experience. Today you start the relay with a bash script in a terminal window that you have to leave open. Ground Control replaces that with a **menu bar icon** (quick status + start/stop), a **full management window** (logs, connected clients, config, security), and **auto-start on login**. It bundles Node.js + the relay so there's nothing to install — drag to Applications, launch, done.

Think of it as the Mac half of the equation: Ground Control manages the relay, the iOS app (and PWA) consume it.

---

## Why

The relay server is the beating heart of Major Tom. Right now using it means:

1. Open Terminal.app
2. `cd ~/code/major-tom/relay`
3. `npm run dev`
4. Leave that terminal window open forever
5. Hope you remember to start it after a reboot
6. Check the terminal for errors
7. Ctrl+C to stop, remember to restart

This is fine for development. It's shit for daily use. A real product starts on login, lives in the menu bar, shows you what's happening, and gets out of your way.

### Who Is This For?

**Deployment Mode 1 — Personal Machine (primary target):**
You're running the relay on your own Mac. Single user. The relay controls Claude Code sessions on *this machine*. Ground Control is a native wrapper around `npm run dev` with a proper UI.

**Deployment Mode 2 — Team Server (future, Linux):**
A shared Linux server running the relay for multiple team members. Ground Control doesn't apply here — the relay runs as a systemd service. But the config file format and API endpoints we build for Ground Control will be reusable for a future web-based admin panel.

This spec focuses on Mode 1. Everything we build works for a single-user Mac setup.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Ground Control (macOS app, SwiftUI)                         │
│                                                              │
│  ┌────────────────────────┐  ┌─────────────────────────────┐ │
│  │  MenuBarExtra          │  │  Management Window          │ │
│  │  ┌──────────────────┐  │  │  ┌───────────────────────┐  │ │
│  │  │ ● Running        │  │  │  │ Dashboard             │  │ │
│  │  │ 2 clients        │  │  │  │ • Server status       │  │ │
│  │  │ Port 9090        │  │  │  │ • Connected clients   │  │ │
│  │  │ ──────────────── │  │  │  │ • Session activity    │  │ │
│  │  │ Start / Stop     │  │  │  │ • Resource usage      │  │ │
│  │  │ Open PWA...      │  │  │  ├───────────────────────┤  │ │
│  │  │ Management...    │  │  │  │ Logs (live stream)    │  │ │
│  │  │ Quit             │  │  │  │ • Structured pino     │  │ │
│  │  └──────────────────┘  │  │  │ • Level filters       │  │ │
│  └────────────────────────┘  │  │ • Search              │  │ │
│                              │  ├───────────────────────┤  │ │
│  ┌────────────────────────┐  │  │ Configuration         │  │ │
│  │  Process Manager       │  │  │ • Port, auth mode     │  │ │
│  │  ┌──────────────────┐  │  │  │ • Cloudflare Tunnel   │  │ │
│  │  │ Foundation.Process│  │  │  │ • Google OAuth creds  │  │ │
│  │  │ → node            │  │  │  │ • Multi-user toggle   │  │ │
│  │  │ → relay/dist/     │  │  │  ├───────────────────────┤  │ │
│  │  │   server.js       │  │  │  │ Security              │  │ │
│  │  │                   │  │  │  │ • Connected devices   │  │ │
│  │  │ stdout → LogStore │  │  │  │ • Revoke sessions     │  │ │
│  │  │ stderr → LogStore │  │  │  │ • Audit log viewer    │  │ │
│  │  └──────────────────┘  │  │  └───────────────────────┘  │ │
│  └────────────────────────┘  └─────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Bundled Runtime                                       │  │
│  │  • Node.js 22 binary (arm64 + x86_64 universal)       │  │
│  │  • esbuild-bundled relay (single server.js)            │  │
│  │  • node-pty native addon (.node, per-arch)             │  │
│  │  • tmux (Homebrew dependency, NOT bundled)             │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Decision: Bundled Node.js, NOT Node SEA

Node.js Single Executable Applications (SEA) compile your JS into the Node binary. Sounds perfect. **Does not work for us** because:

1. **node-pty** is a native addon (`.node` file compiled with node-gyp). SEA can't load native addons — they need `require()` against a real `.node` file on disk.
2. **tmux** is an external binary we exec — not a Node module. SEA wouldn't help here.

Instead, we bundle:
- **Node.js binary** — downloaded from nodejs.org at build time (`node-v22.x.x-darwin-arm64.tar.gz`). ~40MB.
- **Relay bundle** — our esbuild output (`server.js` + the few files that can't be bundled). ~2MB.
- **node-pty prebuilt** — the compiled `.node` addon for the target arch. ~200KB.

Total app size: ~50MB. Acceptable for a Mac app with an embedded runtime.

### tmux Dependency

tmux is NOT bundled. It's a Homebrew package that most Mac developers already have. Ground Control checks for tmux on launch and shows a friendly "Install tmux" prompt if it's missing:

```
Ground Control requires tmux for terminal session management.

Install with Homebrew:
  brew install tmux

[Copy Command]  [Open Terminal]
```

We could bundle tmux (it's a static binary, ~1MB), but:
- Homebrew keeps it updated
- Version conflicts with a user's existing tmux would be confusing
- The relay already handles tmux-missing gracefully

---

## UI Design

### Menu Bar

The menu bar icon is a small satellite dish (matching Major Tom's space theme). It shows:

```
┌──────────────────────────────┐
│  ● Relay Running              │
│  Port 9090 • 2 clients       │
│  ─────────────────────────── │
│  ■ Stop Relay                 │
│  🌐 Open PWA in Browser...   │
│  📡 Copy Tunnel URL...        │
│  ─────────────────────────── │
│  ⚙ Management Window...      │
│  ─────────────────────────── │
│  Quit Ground Control          │
└──────────────────────────────┘
```

When the relay is stopped:
```
┌──────────────────────────────┐
│  ○ Relay Stopped              │
│  ─────────────────────────── │
│  ▶ Start Relay                │
│  ⚙ Management Window...      │
│  ─────────────────────────── │
│  Quit Ground Control          │
└──────────────────────────────┘
```

### Management Window

A proper macOS window with a sidebar:

**Sidebar items:**
1. **Dashboard** — Overview cards: server status, uptime, connected clients, active sessions, CPU/memory of the node process
2. **Logs** — Live-streaming log viewer. Pino JSON logs parsed into structured rows with level badges (INFO blue, WARN yellow, ERROR red). Level filter toggles, text search, auto-scroll with pause-on-scroll.
3. **Configuration** — Form-based settings editor:
   - Port number
   - Auth mode (none / PIN / Google OAuth)
   - Google OAuth client ID / secret (stored in Keychain)
   - Multi-user mode toggle
   - Cloudflare Tunnel toggle + token
   - Claude work directory
   - Hook port
4. **Security** — Connected devices list (from relay's `/api/health` endpoint), session revocation, audit log viewer (if multi-user enabled)

---

## Wave Breakdown

### Wave 1: Scaffold & Process Management

**Goal:** Menu bar app that can start/stop the relay server. No management window yet. Bundled Node.js binary.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `macos/GroundControl/` | Create | New macOS app directory |
| `macos/GroundControl/App/GroundControlApp.swift` | Create | @main entry, MenuBarExtra + WindowGroup |
| `macos/GroundControl/Services/RelayProcess.swift` | Create | Foundation.Process wrapper — start/stop/restart Node |
| `macos/GroundControl/Services/NodeBundleManager.swift` | Create | Locates bundled Node.js binary + relay code |
| `macos/GroundControl/Views/MenuBarView.swift` | Create | Menu bar content — status, start/stop, quit |
| `macos/GroundControl/Models/RelayState.swift` | Create | Observable state: running/stopped/starting/error |
| `macos/Package.swift` | Create | SwiftPM manifest (macOS 14+, SwiftUI) |
| `macos/scripts/bundle-node.sh` | Create | Build script: downloads Node.js, copies to app bundle |
| `macos/scripts/bundle-relay.sh` | Create | Build script: runs esbuild, copies dist + node-pty |

**Acceptance:**
- [x] App appears in menu bar with satellite dish icon
- [x] Start button spawns `node server.js` using bundled Node binary
- [x] Stop button sends SIGTERM, waits for graceful shutdown
- [x] Status indicator shows running/stopped
- [x] App launches on login (LSUIElement + LaunchAtLogin)
- [x] Menu shows port number when running

**Architecture Notes:**
- Use `Foundation.Process` (not `posix_spawn` directly) — it handles stdout/stderr pipes, termination notifications, and environment setup.
- Set the working directory to the bundled relay's dist folder.
- Environment variables: `PORT`, `HOOK_PORT`, `LOG_LEVEL`, `NODE_ENV=production`, plus any config-derived vars.
- Pipe stdout to our LogStore for parsing.

---

### Wave 2: Log Viewer

**Goal:** Management window with a live log viewer. Pino JSON logs parsed into structured, filterable rows.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `macos/GroundControl/Views/ManagementWindow.swift` | Create | WindowGroup with sidebar navigation |
| `macos/GroundControl/Views/LogView.swift` | Create | Log viewer — virtual list, level badges, search |
| `macos/GroundControl/Models/LogEntry.swift` | Create | Parsed pino log entry model |
| `macos/GroundControl/Services/LogStore.swift` | Create | Ring buffer of parsed log entries, level filtering |
| `macos/GroundControl/Views/MenuBarView.swift` | Modify | Add "Management..." menu item |

**Acceptance:**
- [x] Management window opens from menu bar
- [x] Logs stream in real-time as relay runs
- [x] Each log line shows: timestamp, level badge, message, expandable JSON details
- [x] Level filter toggles (INFO, WARN, ERROR, DEBUG)
- [x] Text search filters visible logs
- [x] Auto-scroll with "pause on scroll up" behavior
- [x] Ring buffer caps at 10,000 entries (no unbounded memory growth)

**Pino Log Format:**
The relay uses pino structured logging. Each line is a JSON object:
```json
{"level":30,"time":1712678400000,"pid":1234,"hostname":"mac","name":"major-tom-relay","msg":"Server listening on port 9090"}
```

Pino levels: 10=trace, 20=debug, 30=info, 40=warn, 50=error, 60=fatal.

---

### Wave 3: Dashboard

**Goal:** Dashboard tab with server overview — status, uptime, connected clients, active sessions, resource usage.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `macos/GroundControl/Views/DashboardView.swift` | Create | Overview cards with live data |
| `macos/GroundControl/Services/RelayClient.swift` | Create | HTTP client hitting relay's `/api/health` endpoint |
| `macos/GroundControl/Models/HealthData.swift` | Create | Parsed health response model |
| `macos/GroundControl/Views/ClientListView.swift` | Create | Connected clients list with device info |

**Acceptance:**
- [x] Dashboard shows: server status, uptime, port, client count
- [x] Connected clients list with IP, user agent, connection duration
- [x] Active sessions list with session ID, working dir, status
- [x] Process resource usage (CPU%, memory) via `Process.processIdentifier` + sysctl
- [x] Auto-refresh every 5 seconds
- [x] Cards animate state transitions

**Data Source:**
The relay already has a `/api/health` endpoint that returns server status, session count, and fleet info. We extend it (or add a `/api/admin/status` endpoint) with:
- Connected WebSocket client count
- Per-client info (IP, user agent, connected-at)
- Node.js process memory usage
- tmux session count

---

### Wave 4: Configuration

**Goal:** GUI-based configuration editor. Settings stored in `~/.major-tom/config.json` and applied on next relay restart.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `macos/GroundControl/Views/ConfigView.swift` | Create | Form-based settings editor |
| `macos/GroundControl/Models/RelayConfig.swift` | Create | Typed config model, reads/writes config.json |
| `macos/GroundControl/Services/ConfigManager.swift` | Create | Config persistence, validation, migration |
| `macos/GroundControl/Views/CloudflareTunnelView.swift` | Create | Tunnel setup UI — token input, status check |
| `macos/GroundControl/Views/ManagementWindow.swift` | Modify | Add Config sidebar item |

**Config Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `port` | number | 9090 | Relay HTTP port |
| `hookPort` | number | 9091 | Hook server port |
| `authMode` | enum | `"pin"` | `"none"` / `"pin"` / `"google"` |
| `googleClientId` | string | — | OAuth client ID (stored in Keychain) |
| `googleClientSecret` | string | — | OAuth secret (stored in Keychain) |
| `multiUserEnabled` | boolean | false | Enable multi-user features |
| `claudeWorkDir` | string | `"~"` | Default working directory for Claude |
| `logLevel` | enum | `"info"` | Pino log level |
| `cloudflare.enabled` | boolean | false | Enable Cloudflare Tunnel |
| `cloudflare.token` | string | — | Tunnel token (stored in Keychain) |
| `autoStart` | boolean | true | Start relay on app launch |

**Acceptance:**
- [ ] All config fields editable in the UI
- [ ] Changes saved to `~/.major-tom/config.json`
- [ ] Secrets (OAuth credentials, tunnel token) stored in macOS Keychain, not the JSON file
- [ ] "Apply & Restart" button restarts the relay with new config
- [ ] Validation prevents invalid values (port range, required fields)
- [ ] Config file created with defaults on first launch

---

### Wave 5: Security & Polish

**Goal:** Security panel (connected devices, session revocation), auto-update check, first-run onboarding, Homebrew formula.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `macos/GroundControl/Views/SecurityView.swift` | Create | Connected devices, revoke sessions |
| `macos/GroundControl/Views/OnboardingView.swift` | Create | First-run wizard (check tmux, set port, choose auth) |
| `macos/GroundControl/Views/ManagementWindow.swift` | Modify | Add Security sidebar item |
| `macos/GroundControl/Services/UpdateChecker.swift` | Create | GitHub releases check for updates |

**Acceptance:**
- [ ] Security panel shows connected devices with "Revoke" button
- [ ] First-run onboarding checks prerequisites (tmux, port availability)
- [ ] First-run sets up initial config (port, auth mode)
- [ ] Menu bar icon changes color/shape based on status (green=running, red=error, gray=stopped)
- [ ] Dock icon hidden (LSUIElement) — app lives in menu bar only
- [ ] App notarization-ready (hardened runtime, proper entitlements)

---

## File Inventory

### New Files (22)

| File | Wave |
|------|------|
| `macos/GroundControl/App/GroundControlApp.swift` | 1 |
| `macos/GroundControl/Services/RelayProcess.swift` | 1 |
| `macos/GroundControl/Services/NodeBundleManager.swift` | 1 |
| `macos/GroundControl/Views/MenuBarView.swift` | 1 |
| `macos/GroundControl/Models/RelayState.swift` | 1 |
| `macos/Package.swift` | 1 |
| `macos/scripts/bundle-node.sh` | 1 |
| `macos/scripts/bundle-relay.sh` | 1 |
| `macos/GroundControl/Views/ManagementWindow.swift` | 2 |
| `macos/GroundControl/Views/LogView.swift` | 2 |
| `macos/GroundControl/Models/LogEntry.swift` | 2 |
| `macos/GroundControl/Services/LogStore.swift` | 2 |
| `macos/GroundControl/Views/DashboardView.swift` | 3 |
| `macos/GroundControl/Services/RelayClient.swift` | 3 |
| `macos/GroundControl/Models/HealthData.swift` | 3 |
| `macos/GroundControl/Views/ClientListView.swift` | 3 |
| `macos/GroundControl/Views/ConfigView.swift` | 4 |
| `macos/GroundControl/Models/RelayConfig.swift` | 4 |
| `macos/GroundControl/Services/ConfigManager.swift` | 4 |
| `macos/GroundControl/Views/CloudflareTunnelView.swift` | 4 |
| `macos/GroundControl/Views/SecurityView.swift` | 5 |
| `macos/GroundControl/Views/OnboardingView.swift` | 5 |

### Modified Files (relay-side, minimal)

| File | Wave | Change |
|------|------|--------|
| `relay/src/routes/health.ts` | 3 | Extend health endpoint with admin metrics |

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Node.js binary size bloats the app | Medium | arm64-only build for personal use (skip universal). Strip debug symbols. ~40MB is acceptable — Electron apps are 200MB+. |
| node-pty native addon ABI mismatch | High | Pin Node.js version at build time. Rebuild node-pty against the exact bundled Node version. Include in build script. |
| Hardened Runtime breaks node-pty fork/exec | High | Add `com.apple.security.cs.allow-unsigned-executable-memory` and `com.apple.security.cs.disable-library-validation` entitlements. Required for Node + native addons. Notarization accepts these with proper justification. |
| tmux not installed | Low | Clear first-run prompt. Not a blocker — relay already handles tmux-missing gracefully, just the shell feature is degraded. |
| Foundation.Process zombie on crash | Medium | Install SIGCHLD handler. On app termination, send SIGTERM then SIGKILL after 5s timeout. Store PID in a lockfile for recovery. |
| Config file format migration | Low | Version the config schema. ConfigManager handles migration on read. |

---

## Entitlements

For notarization and App Store (if we ever go there), the app needs:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Network: relay server binds a port -->
    <key>com.apple.security.network.server</key>
    <true/>
    <!-- Network: HTTP client for health checks, Cloudflare -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Hardened runtime: Node.js loads native addons (node-pty) -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <!-- File access: relay reads/writes ~/.major-tom/ -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <!-- Keychain: OAuth secrets, tunnel token -->
    <key>com.apple.security.keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.majortom.groundcontrol</string>
    </array>
</dict>
</plist>
```

---

## Build & Distribution

### Development

```bash
cd macos/
swift build            # Build with SwiftPM
swift run              # Run from terminal
# OR
open Package.swift     # Opens in Xcode, build with Cmd+R
```

### Release Build

```bash
cd macos/
./scripts/bundle-node.sh     # Download + extract Node.js binary
./scripts/bundle-relay.sh    # esbuild relay, copy node-pty addon
swift build -c release       # Optimized build
# Package into .app bundle, sign, notarize
```

### Distribution

For now: GitHub Releases with a `.dmg` or `.zip`. Drag to Applications.

Future: Homebrew Cask (`brew install --cask ground-control`).

Not planned: Mac App Store (sandboxing would break node-pty and tmux exec).

---

## Decided Questions

1. **Same repo, `macos/` directory.** Monorepo — shared config types, build scripts need relay source for bundling.

2. **SwiftPM initially.** Simpler for a pure-Swift app, `swift build` from CLI. Migrate to XcodeGen if build phases get complex.

3. **Ground Control manages Cloudflare Tunnel.** When the user enables the tunnel toggle, GC spawns `cloudflared tunnel run` alongside the relay. Same Process management pattern. Check for `cloudflared` binary like we check for tmux.

4. **GitHub release checks for auto-update.** Simple HTTP call to releases API. Add Sparkle later if we want delta updates.
