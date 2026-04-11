# Ground Control Hardening — Spec

> Hand this doc to a fresh Claude session on a worktree branch.
> Branch name: `ground-control/hardening`

---

## Goal

Make Ground Control truly "launch and forget" — relay auto-recovers from crashes, cloudflared tunnel starts/stops alongside the relay, permanent URL just works.

---

## Task 1: Auto-Restart on Relay Crash

**File:** `macos/GroundControl/Services/RelayProcess.swift`

**Current behavior:** `handleTermination()` (line 180) sets state to `.error` and stops. No recovery.

**Desired behavior:**
- On unexpected termination (exit code != 0), auto-restart after a brief delay
- Exponential backoff: 1s → 2s → 4s → 8s → max 30s
- Reset backoff on successful run (process stays alive > 30s)
- Cap at 5 consecutive restart attempts, then stop and show error: "Relay crashed 5 times — check logs"
- Log each restart attempt to `logStore`
- Add a `restartCount` / `lastRestartAt` to `RelayState` so the UI can show restart status

**Implementation sketch:**
```swift
private var restartCount = 0
private var lastSuccessfulStart: Date?

private func handleTermination() {
    // ... existing code ...
    
    // If unexpected crash and under retry limit
    if status != 0 && restartCount < 5 {
        let delay = min(pow(2.0, Double(restartCount)), 30.0)
        restartCount += 1
        state.processState = .restarting(attempt: restartCount)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            await start()
        }
    }
}
```

Add `.restarting(attempt: Int)` case to `ProcessState` enum in `RelayState`.

---

## Task 2: Cloudflared Tunnel Auto-Management

**Files:**
- NEW: `macos/GroundControl/Services/TunnelProcess.swift`
- MODIFY: `macos/GroundControl/Services/RelayProcess.swift` (coordinate lifecycle)
- MODIFY: `macos/GroundControl/Services/ConfigManager.swift` (tunnel config fields)
- MODIFY: `macos/GroundControl/Views/ConfigView.swift` (tunnel UI)

**Current state:**
- `ConfigManager` has `cloudflareEnabled` bool and `cloudflareToken` Keychain secret
- Relay reads `CLOUDFLARE_TUNNEL=true` env var but doesn't spawn the tunnel
- User runs `cloudflared` manually in a separate terminal

**Desired behavior:**
- When `cloudflareEnabled` is true in config, Ground Control spawns `cloudflared tunnel run` as a child process alongside the relay
- Tunnel starts after relay is confirmed running (port is listening)
- Tunnel stops when relay stops
- Tunnel crashes trigger auto-restart (same backoff as relay)
- Config fields needed:
  - `cloudflareEnabled: Bool` (already exists)
  - `cloudflareTunnelName: String` — the named tunnel (e.g., "major-tom")
  - Cloudflare token in Keychain (already plumbed as `cloudflare-token`)

**TunnelProcess spec:**
```swift
@Observable
final class TunnelProcess {
    private(set) var state: TunnelState = .idle  // idle | starting | running | error(String)
    
    func start(tunnelName: String, token: String) async
    func stop() async
    
    // Finds cloudflared binary — check /opt/homebrew/bin, /usr/local/bin, brew --prefix
    private func findCloudflared() -> URL?
    
    // Spawns: cloudflared tunnel --no-autoupdate run --token <token>
    private func launchProcess(binary: URL, token: String) throws
}
```

**Lifecycle coordination in RelayProcess or a new Orchestrator:**
```
start() → start relay → wait for port listening → start tunnel
stop()  → stop tunnel → stop relay
```

**Config UI additions (ConfigView.swift):**
- Toggle: "Enable Cloudflare Tunnel"
- Text field: "Tunnel Token" (stored in Keychain, masked)
- Status indicator: tunnel state (idle/running/error)
- "Test Tunnel" button that hits the public URL health endpoint

---

## Task 3: Process Health Monitoring

**Nice-to-have, not critical.**

- Periodic health check: hit `http://localhost:{port}/health` every 30s
- If health check fails 3 consecutive times while process is "running", trigger restart
- Catches zombie processes that are alive but unresponsive

---

## Key Files to Read First

| File | Why |
|------|-----|
| `macos/GroundControl/Services/RelayProcess.swift` | Main process manager — modify for auto-restart |
| `macos/GroundControl/Services/ConfigManager.swift` | Config persistence + Keychain secrets |
| `macos/GroundControl/App/GroundControlApp.swift` | App lifecycle, where relay is created |
| `macos/GroundControl/Views/ConfigView.swift` | Config UI — add tunnel settings |
| `macos/GroundControl/Views/MenuBarView.swift` | Menu bar — may need tunnel status |
| `relay/src/routes/health.ts` | Health endpoint for monitoring |

## Build & Test

Ground Control is a SwiftPM macOS app:
```bash
cd macos
swift build
# Or open in Xcode:
open Package.swift
```

Test checklist:
- [ ] Relay crash → auto-restarts within backoff delay
- [ ] 5 consecutive crashes → stops with error message
- [ ] Successful run > 30s → resets restart counter
- [ ] Cloudflare toggle ON → tunnel spawns after relay starts
- [ ] Cloudflare toggle OFF → tunnel doesn't spawn
- [ ] Relay stop → tunnel stops too
- [ ] Tunnel crash → auto-restarts independently
- [ ] Missing cloudflared binary → clear error message
- [ ] Config changes saved → next relay restart picks them up
