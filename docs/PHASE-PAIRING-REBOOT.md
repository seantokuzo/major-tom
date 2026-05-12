# Phase — Pairing Reboot

Sean's pairing UX has a hardcoded LAN IP (`PairingView.swift:8 — case lan = "192.168.1.210:9090"`). When his Mac's DHCP lease drifts (last seen `.210 → .254`), the "auto-recommended" LAN chip points at a dead IP, the app shows a generic "Connection failed" with no actionable signal, and the user has to either guess the new IP, fall back to Tailscale, or type it manually. This is a 100%-of-the-time blocker every time DHCP renews.

Root cause: PR #166 wired `NetworkPathMonitor` correctly but mapped reachability → a frozen string literal. There is no live discovery and no reachability probing of saved URLs.

## Scope

Replace the hardcoded LAN constant with live mDNS/Bonjour discovery. Probe URLs before saving them. Surface real errors instead of "Connection failed".

## Waves

### Wave 1 — mDNS discovery + pre-flight ping (this PR)

**Relay**
- Add `bonjour-service` (v1.3.0) dep. Advertise `_majortom._tcp.local.` on `PORT` at startup. Cleanup on shutdown.
- Service `txt` record exposes basic metadata: `version`, `protocol` ("ws"), `auth` ("pin,google").

**iOS**
- New `Core/Services/BonjourBrowser.swift` using `NWBrowser` (iOS 17+) browsing `_majortom._tcp`. Resolves found endpoints to `host:port` strings.
- `Info.plist`: add `NSLocalNetworkUsageDescription` ("Major Tom uses local network discovery to find your relay automatically") and `NSBonjourServices` array with `_majortom._tcp`.
- `ServerPreset` enum: **drop the hardcoded `.lan` case**. Discovered services become a NEW chip group rendered above the static fallback chips (tailscale, cloudflare, localhost).
- `PairingViewModel.applyInitialRecommendationIfNeeded`: prefers a discovered service over `NetworkPathMonitor`'s `recommendedPreset`.
- `submitPIN` and chip-tap: **pre-flight `/auth/methods` ping** before saving the URL. If unreachable, set `authState = .error("Server unreachable at <URL>")` instead of attempting the PIN exchange.

### Wave 2 — provenance + tunnel discovery (deferred)

- `GET /api/discovery` on relay returns live `lan` / `tailscale` URLs from `os.networkInterfaces()` for clients connected via the stable tunnel.
- Track URL provenance (user-typed vs discovered vs auto) so we know which we can safely re-resolve.
- Auto-clear stale stored URLs on app foreground when pre-flight ping fails.

### Wave 3 — UX polish (deferred)

- Chip labels show RTT from pre-flight ping.
- "Recently used" history with last-known reachability.
- Manual override flagged with a 🔒 lock icon to prevent surprise overwrites.

## Success criteria (Wave 1)

- User opens MajorTom on a fresh phone, on the same Wi-Fi as the relay → a chip labeled "📡 Local (<mDNS name>)" appears within 2s, tapping it auto-fills the URL and verifies reachability.
- DHCP renewal between sessions does NOT break re-pairing — mDNS resolves to the current IP every time.
- When the relay is down or unreachable, the user sees "Server unreachable at <URL>" — not "Connection failed". When the URL is reachable but the PIN is wrong, the existing PIN-error path stays.
- Tailscale / Cloudflare tunnel chips remain available as manual fallbacks for off-LAN access.

## Non-goals (Wave 1)

- No mDNS cross-subnet (it's link-local by design — cellular falls back to tunnel).
- No relay-side `/api/discovery` endpoint (Wave 2).
- No `tunnel:setup`/cloudflared changes.
- No PWA changes — PWA discovery is handled by `window.location` already.
