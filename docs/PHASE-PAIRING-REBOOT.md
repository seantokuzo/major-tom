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
- Relay fingerprint UX — surface a cert/pubkey hash both on the Mac's terminal at boot and on the iOS chip after discovery; require explicit verification before PIN save. This is the targeted mitigation for the mDNS impersonation surface flagged in the PR #170 round-1 security advisory (`relay/src/discovery/mdns.ts`) and the chip-as-trust-signal advisory (`ios/MajorTom/Core/Services/BonjourBrowser.swift`).
- Sanitize control / RTL / zero-width / combining chars from `displayName` rendering so attacker-controlled Bonjour names can't impersonate the real chip via homoglyphs (round-1 advisory `PairingView.swift:186`).

### Wave 2A — frictionless re-pair (parallel with Wave 2)

The 6-digit PIN with 5-min TTL is fine for *first* pair but becomes a UX wall whenever the user signs out or the cookie expires. Field reality: Sean hits PIN re-entry repeatedly during dev/QA cycles and times out every time. Termius solves this for SSH by saving credentials once — the user just taps "connect to my Mac" and the saved cred auto-authenticates. MajorTom can match that without inventing anything new — the relay already supports Google OAuth, the iOS app just doesn't surface it.

This wave is **independent of Wave 2** — different files, different concerns, can ship in either order.

- ✅ **Surface Google OAuth in `PairingView`** when `authMethods.google == true`. **Shipped (this PR.)** Native flow uses `ASWebAuthenticationSession` + PKCE (no SDK), exchanges Google's `id_token` against the relay's existing `/auth/google` endpoint, and lands the same `mt-session` cookie in Keychain as the PIN path. The relay's audience check now accepts both `GOOGLE_CLIENT_ID` (PWA / GIS) and `GOOGLE_CLIENT_ID_IOS` (native iOS client). `/auth/google/client-id` surfaces the iOS client ID so the button only renders when the relay is actually configured for it — no broken state when the env knob is unset.
- **`MAJORTOM_PIN_TTL_MIN` env knob** in `relay/src/auth/pin-manager.ts` — the hardcoded `PIN_EXPIRY_MS = 5 * 60 * 1000` becomes `parseInt(process.env['MAJORTOM_PIN_TTL_MIN'] ?? '5', 10) * 60_000`. Default stays 5 min for prod; the personal-machine deployment can bump it to 30. Trivial change, big QoL win for dev sessions.
- **Biometric quick-pair (optional, nice-to-have)** — after first successful PIN pair, store the PIN in Keychain protected by `kSecAccessControlBiometryCurrentSet`. On next sign-in-from-scratch, offer "Use Face ID to re-pair" so the user authenticates with their face instead of retyping the 6 digits. Useful only if the user signs out often; skip if the OAuth path lands first.

#### Wave 2A item 1 — operator setup

To actually use Sign-in-with-Google from the iOS app, the relay operator needs to:

1. **Create an iOS OAuth client in Google Cloud Console.**
   APIs & Services → Credentials → Create credentials → OAuth client ID → Application type *iOS*. Bundle ID = `com.majortom.app`. Save the resulting client ID (format `<num>-<suffix>.apps.googleusercontent.com`).
2. **Set `GOOGLE_CLIENT_ID_IOS` in the relay's `.env`.** Restart the relay. `/auth/google/client-id` will now expose `iosClientId`, and the iOS app's pairing view will render the "Sign in with Google" button.
3. **No iOS rebuild needed.** `ASWebAuthenticationSession` intercepts the reverse-client-ID callback scheme at the OS level for the duration of the session — no `CFBundleURLTypes` registration required.

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

---

## Phase Closeout (2026-05-23)

Pairing Reboot is **closed**. The original pain (DHCP-drift LAN IP + 5-min PIN treadmill) is fully resolved by what shipped, and the remaining waves are obsolete because the PR-#173 consolidation simplified the UX past what they were designed to fix.

### Shipped

| Wave | PR | Merged | Effect |
|------|----|--------|--------|
| 1 — mDNS discovery + pre-flight ping | #170 | 2026-05-12 | LAN-IP drift fixed; "Server unreachable" replaces "Connection failed" |
| 2A item 1 — Google OAuth in iOS PairingView | #171 | 2026-05-20 | ASWebAuthenticationSession + PKCE; 7-day session cookie |
| 2A item 2 — `MAJORTOM_PIN_TTL_MIN` env knob | #172 | 2026-05-21 | PIN TTL now configurable (dormant after OAuth-only flip) |
| OAuth-only consolidation | #173 | 2026-05-23 | PIN UI gone from iOS, URL UI gone, `AUTH_PIN_ENABLED=false` on relay returns 404 on PIN routes, tunnel URL hoisted into gitignored `Secrets.swift` |

### Wave 2 — provenance + security UX → **OBSOLETE**

The OAuth-only consolidation removed every UI surface Wave 2 was designed to harden:

- `GET /api/discovery` was for surfacing the live tunnel URL on chips → no chips render anymore.
- URL provenance tracking + stale-URL auto-clear → no URL input field for the user to manage.
- Relay fingerprint chip → no chips.
- Sanitize Bonjour `displayName` rendering → `displayName` no longer rendered anywhere (Bonjour is now silent infrastructure feeding `currentRelayURL`).

The realistic threat model is now `ALLOWED_EMAIL`-gated: even if an attacker fronts an mDNS lookalike `_majortom._tcp` service on a hostile LAN, the OAuth flow won't mint a session unless the Google account's email matches `seantokuzo@gmail.com` on the real relay. Documented as an explicit design trade-off in PR #173's review responses.

### Wave 2A item 3 — biometric quick-pair → **DEPRIORITIZED (subsumed)**

Google passkey on the user's Google account + 7-day OAuth session cookie + ASWebAuthenticationSession's cookie reuse already deliver the Face-ID-only re-auth Wave 2A item 3 was designed to add. Revisit only if Sean reports signing out often.

### Wave 3 — UX polish → **OBSOLETE**

- Chip RTT labels → no chips.
- "Recently used" history → no URL UI to history.
- Manual override 🔒 lock icon → no manual override.

The login screen is now logo + "Sign in with Google to connect" + one button. There is nothing left to polish at this layer.

### Out of phase (still queued)

- `docs/QA-FIXES.md` follow-ups — see `project_qa_followups_phase.md` and `project_qa_p3_handoff.md`.
- README setup doc for fresh clones (someone has to copy `Secrets.swift.example` → `Secrets.swift` before iOS builds) — see PR #173 advisory thread for context.
