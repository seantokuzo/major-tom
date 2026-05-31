# Handoff — iOS terminal won't connect (rides flapping tunnel) + LAN-preference fix

> ✅ **STATUS: COMPLETED / SUPERSEDED (2026-05-30).** Every item in this handoff
> shipped: the `%en0` Bonjour fix + tunnel HTTP/2 stabilization (PR #177, merged
> `adf2711`), and the "prefer a *verified* LAN relay at connect time" feature —
> app-level Bonjour + `RelayURLResolver` + challenge-response identity verify
> (iOS PR #176, relay PR #178). Kept for historical record (root-cause notes on
> the `%en0` zone-id bug + the QUIC-flap diagnosis). Current state and the live
> follow-up queue live in `docs/HANDOFF-POST-IDENTITY-FOLLOWUPS.md` and
> `.claude/STATE.md` — read those, not this. Relay `SESSION_SECRET` hardening
> (P3/P4/P5) remains open in `docs/HANDOFF-RELAY-OAUTH-RESTART.md`.

> Written 2026-05-25 mid-session (prior session context got heavy — Sean asked
> to queue this for a fresh start). The original P0 "OAuth not available" login
> bug is **root-caused and the auth half is FIXED + verified on device**. A new
> issue surfaced during device QA: the terminal can't connect. Sean chose
> **option 3** below (quick tunnel fix now + proper LAN fix). Execute that.

---

## TL;DR

1. **"OAuth not available" → SOLVED.** Root cause was a malformed Bonjour
   address (`192.168.1.210%en0:9090`). Fix applied to
   `ios/MajorTom/Core/Services/BonjourBrowser.swift`, built, installed, and
   **login verified working on Sean's phone**. ⚠️ **The fix is UNCOMMITTED on
   `main`'s working tree** — first job is to commit it (bundle into the PR below).
2. **New bug: terminal won't connect.** After login, the app's WebSocket (main
   channel + terminal `/shell`) rides the **Cloudflare tunnel**, which is
   **flapping** (cloudflared QUIC `timeout: no recent network activity` in a
   tight loop). The socket connects (authenticated) then drops in seconds; the
   PTY never spawns. On Wi-Fi it should use the LAN, not the public tunnel.
3. **Plan (Sean approved option 3):** (A) stabilize the tunnel with
   `--protocol http2` for an immediate unblock, then (B) the proper fix — make
   the app prefer the LAN at connect time. One PR for the iOS changes.

---

## What was FIXED this session (UNCOMMITTED — commit first)

**Symptom:** Sean tapped Google sign-in and got "Server unreachable at
`192.168.1.210%en0:9090`."

**Root cause:** `BonjourBrowser.address(from:)` IPv4 branch did
`hostString = "\(ip)"`. `IPv4Address` string-interpolation **appends the
resolved interface as a zone id** → `192.168.1.210%en0`. The `%` breaks
`URL(string:)`, so the address is unreachable. The code *already* guarded the
IPv6 case against exactly this (`.ipv6` returns nil, see the comment ~line
128-130) but missed IPv4.

**Fix applied** (`ios/MajorTom/Core/Services/BonjourBrowser.swift`, ~line 137):
```swift
case .ipv4(let ip):
    // IPv4Address interpolation can append a "%en0" zone id; the '%'
    // breaks URL(string:), and a literal IPv4 never needs one.
    hostString = String("\(ip)".prefix { $0 != "%" })
```
Composes with `AuthService.normalizeBaseURL` (clean IPv4 → `http://…:9090`).
Built (`generic/platform=iOS`), installed to device, **login confirmed working**
(phone reached the relay and OAuth succeeded). Not yet committed.

---

## The NEW bug — terminal can't connect (evidence)

Relay was started this session via `nohup bash start.sh > /tmp/relay.log 2>&1 &`
(likely STILL running — check before restarting). Log at `/tmp/relay.log`.

- **Phone logged in THROUGH THE TUNNEL:**
  `POST /auth/google hostname="majortom.seantokuzodevtunnel.space"`. Every
  `/auth/methods` from the phone hit the tunnel too. (Bonjour was racy at
  tap-time, so `currentRelayURL` fell through to the tunnel preset.)
- **So `auth.saveServerURL(target)` froze the TUNNEL URL** as `auth.serverURL`.
- **Everything then rides the tunnel:** main socket connects via
  `MajorTomApp.swift:74-81` → `relay.connect(to: auth.serverURL)`; the terminal
  builds `wss://…/shell/:tabId` from `auth.serverURL` in
  `TerminalViewModel.relayURL` (lines 376-386).
- **The tunnel is flapping:** cloudflared logs a tight loop of
  `ERR failed to accept QUIC stream: timeout: no recent network activity`,
  `WRN Connection terminated`, `INF Retrying connection`. The WS connects
  (authenticated, client IP = phone's public IPv6 forwarded by Cloudflare) then
  disconnects within seconds, repeatedly. **`/shell` never appears in the log**
  → the PTY never establishes → "can't get a terminal to connect."
- **LAN/Tailscale/loopback are all healthy and instant:** direct curls to
  `192.168.1.210:9090`, `100.69.151.117:9090`, `127.0.0.1:9090` all return
  `{"google":true}` immediately. Relay banner: `Auth: Google OAuth
  (seantokuzo@gmail.com)`, `Session secret loaded from environment` (the
  SESSION_SECRET footgun did NOT fire — env loaded fine).

---

## Option 3 — the plan to execute

### Step A — quick unblock: stabilize the tunnel (HTTP/2)
- `tunnel/start.sh:28` runs `cloudflared tunnel --config <cfg> run <id>` with
  **no `--protocol`** → defaults to QUIC (the thing flapping).
- Force HTTP/2 (TCP) instead: add `--protocol http2` to the `run` invocation,
  or `protocol: http2` in `tunnel/config.yml`. Restart cloudflared (kill the
  process, relaunch — the relay can keep running).
- Verify the tunnel stays stable: `curl https://majortom.seantokuzodevtunnel.space/auth/methods`
  repeatedly, watch `/tmp/relay.log` for the QUIC error loop to stop. Have Sean
  retry the terminal — should connect over the now-stable tunnel.
- Bonus: HTTP/2 also helps genuine remote/cellular access.

### Step B — proper fix: app prefers LAN at connect time (Sean picked approach #1)
**Core idea:** stop freezing one URL at login. Resolve LAN-vs-tunnel at
**connect time** — prefer a reachable LAN relay (Bonjour), fall back to the
tunnel only when there's no local path (genuinely remote/cellular).

- Today `BonjourBrowser` is owned privately by `PairingViewModel`
  (`init` ~line 57) and only runs on the pairing screen (start/stop on
  appear/disappear). Post-login there is **no discovery**, so connections fall
  back to the frozen `auth.serverURL`.
- **Make Bonjour app-level:** instantiate it in `MajorTomApp` (alongside the
  other `@State` services), keep it discovering while the app is active. Inject
  it into `PairingViewModel` (replace its private browser) and into a shared
  resolver.
- **Add a resolver** returning the best base URL:
  **live Bonjour-discovered LAN address → else `auth.serverURL`** (tunnel/last-used).
- **Use the resolver in:**
  - `MajorTomApp.swift:79` connect path — start Bonjour, give it a short grace
    (~2s) to resolve, then connect via the resolved URL. If Bonjour resolves a
    LAN address *after* an initial tunnel connect, reconnect to the LAN.
  - `TerminalViewModel.relayURL` / `relayBaseURL` / `relayDomain` (lines
    376-408) — inject the shared browser and prefer the LAN address.
- **Files:** `MajorTomApp.swift`, `PairingViewModel.swift`, `TerminalViewModel.swift`,
  `BonjourBrowser.swift`, + a small resolver. Auth flow stays as-is; the tunnel
  remains the genuine remote fallback.
- **Design note:** manual URL entry was removed in PR #173 (OAuth-only
  consolidation) — do NOT re-add a URL field. See
  [[project_ios_secrets_indirection]] / [[project_pairing_reboot_handoff]].

### Step C — commit + PR
- Bundle the `%en0` BonjourBrowser fix (uncommitted from this session) **plus**
  the Step B LAN-preference changes into ONE PR (branch e.g.
  `fix/ios-relay-lan-connect`). This is a sensitive-ish path (relay connection
  + auth) — expect a careful Tier 2 review. The Step A tunnel change is a local
  ops/script tweak; include it or note it separately.

---

## Still pending from the ORIGINAL relay handoff (independent, lower urgency)
From `docs/HANDOFF-RELAY-OAUTH-RESTART.md` — these did NOT cause this incident
(env loaded fine, footgun didn't fire) but are still valid hardening for a
separate **relay** PR:
- **P3:** `relay/src/auth/session.ts` `getSessionSecret` regenerate/append
  footgun → fail loudly when `.env` has a secret on disk but it's not in env;
  write idempotently (never `appendFileSync`).
- **P4:** `relay/src/server.ts` startup env preflight → `exit(1)` with a loud
  message if `relay/.env` exists on disk but its vars aren't in `process.env`.
- **P5:** collapse the 3 dup `SESSION_SECRET` lines in `relay/.env` (manual,
  with Sean — keep the LAST value).

---

## Environment / ops notes for the fresh session
- **Relay + tunnel + PWA are likely STILL RUNNING** from this session
  (`nohup bash start.sh`). Check `lsof -nP -iTCP:9090 -sTCP:LISTEN` before
  restarting. Log: `/tmp/relay.log`.
- **Spawn the relay with `nohup … > /tmp/relay.log 2>&1 &`, NOT Bash
  run_in_background** (harness reaps it and kills PTYs). [[feedback_relay_detach]]
- **Device deploy (wireless, no USB):**
  - Build: `xcodebuild -project ios/MajorTom.xcodeproj -scheme MajorTom -destination 'generic/platform=iOS' -allowProvisioningUpdates build`
    (use `generic/platform=iOS`, not `id=…` — the device-specific destination
    times out if the phone is mid-reconnect).
  - Install: `xcrun devicectl device install app --device 00008130-001625913CF0001C "<DerivedData>/…/Build/Products/Debug-iphoneos/Major Tom.app"`
  - **Phone must be UNLOCKED** for install (DDI mount fails on a locked device).
  - [[reference_wireless_device_deploy]] [[project_free_apple_account]]
- **Do NOT use the AskUserQuestion option-picker with Sean** — it mangles in
  his mobile tmux session. Present choices as a plain-text numbered list.
  [[feedback_no_askuserquestion_mobile_tmux]]
