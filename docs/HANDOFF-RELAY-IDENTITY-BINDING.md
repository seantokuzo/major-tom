# Handoff — relay-identity binding (unblocks the held LAN-preference feature)

> Queued 2026-05-26 for a fresh session (prior session context got heavy). The
> terminal-connect P0 is **SHIPPED**; this is the follow-up that lets the
> LAN-preference optimization ship **safely**.

---

## TL;DR

- **Already shipped (PR #177 → main `adf2711`):** `%en0` Bonjour fix + tunnel
  HTTP/2. Terminal connects fine over the stable tunnel. Nothing to redo.
- **Held (draft PR #176, branch `fix/ios-relay-lan-connect`):** the
  LAN-preference feature — app-level `BonjourBrowser` + `RelayURLResolver` so the
  app prefers a live LAN relay address over the tunnel frozen into
  `auth.serverURL`.
- **Why it is held — the security bug to fix:** `RelayURLResolver.bestRelayURL`
  returns `browser.services.first?.address` (the first `_majortom._tcp` mDNS
  responder) and the app then sends the **authenticated session cookie** to it
  (main socket + terminal `/shell`). mDNS is unauthenticated, so a LAN peer that
  advertises `_majortom._tcp` *after* pairing can be the "first responder,"
  harvest the session token, replay it to the real relay, and get a **shell**.
  Round-1 Tier-2 review verdict was ship/0-blocking but flagged this as
  high-impact. Sean chose **option 2**: ship the safe fixes, hold the LAN feature
  until the relay's identity is bound.
- **This task:** give the relay a stable identity, advertise/expose it, pin it at
  pairing, and verify it at connect time before any discovered LAN host is
  trusted with credentials. Then integrate into `RelayURLResolver`, rebase #176
  onto main, re-review, ship.

Security review comment (full threat model + the reviewer's recommendation):
PR #176, inline on `RelayURLResolver.swift:30` (comment id 3306862586). My reply
there summarizes the agreed direction.

---

## Design — what "identity binding" means here

Goal: the app must only send its session cookie to a LAN host it can prove is the
**same relay it paired with** (OAuth'd against), not just "whoever answered mDNS
first."

Shape (all three pieces needed):

1. **Relay has a stable identity.** There is currently **none** suitable — the
   only persisted keypair is the VAPID push key (`relay/src/push/push-manager.ts`,
   wrong semantics, do not reuse). Create a dedicated relay identity keypair (e.g.
   Ed25519) generated once and persisted (alongside other relay state in
   `~/.major-tom/` — check how VAPID / SESSION_SECRET are persisted for the
   pattern). Do **not** derive it from `SESSION_SECRET` (that key has its own
   regenerate footgun — see [[project_relay_oauth_restart_bug]]).

2. **Advertise + expose the identity.**
   - Advertise a fingerprint of the public key in the Bonjour **TXT record** at
     `relay/src/discovery/mdns.ts` (the `bonjour.publish({...})` call ~L30 — add
     `txt: { fp: <fingerprint> }`).
   - Also expose it over HTTP for the pairing capture (e.g. include it in an
     existing `/auth/*` payload, or a small `GET /identity`) so the pin is
     established against the OAuth'd host, not against an mDNS claim.

3. **Pin at pairing, verify at connect (iOS).**
   - At pairing (post-OAuth, against the host the user actually authed to),
     capture the relay fingerprint and persist it in the **Keychain** (new
     `KeychainKey`). The pairing flow lives in `PairingViewModel.signInWithGoogle`
     / `AuthService`.
   - `BonjourBrowser.DiscoveredService` must carry the advertised TXT fingerprint
     (today it only has `id`/`displayName`/`address` — parse the TXT record in
     `BonjourBrowser.address(from:)`/`startResolve`).
   - `RelayURLResolver.bestRelayURL` must only return a discovered LAN host whose
     advertised fingerprint **matches the pinned one**; otherwise fall through to
     `auth.serverURL` (tunnel). Optional hardening: a challenge-response (app
     nonce, relay signs with the identity key) so a replayed TXT fingerprint alone
     is not enough — decide if TXT-pin is sufficient for the threat model or if
     signing is warranted.

### Decision to make first (ask Sean if unsure)
- **TXT-fingerprint pin** (simplest: compare advertised fp to pinned fp) vs
  **challenge-response signing** (strongest: proves possession of the private
  key, defeats a host that merely echoes the fingerprint). Recommend starting
  with the TXT-pin + a connect-time signature check if cheap; the pin alone
  already closes the "first responder steals the cookie" hole because an attacker
  cannot produce the paired host's fingerprint unless they also compromised
  pairing.

---

## Files

**Relay:**
- `relay/src/discovery/mdns.ts` — add TXT fingerprint to the advertisement.
- `relay/src/server.ts` — wires `startMdns(PORT)` (L64); pass the identity in.
- new: relay identity keypair generation + persistence (model on VAPID /
  SESSION_SECRET persistence).
- `relay/src/routes/` + `relay/src/auth/` — expose the identity for pairing
  capture (HTTP) and, if doing signing, a verify endpoint.

**iOS (all already on branch `fix/ios-relay-lan-connect` / #176):**
- `ios/MajorTom/Core/Services/BonjourBrowser.swift` — parse the TXT fingerprint
  into `DiscoveredService`.
- `ios/MajorTom/Core/Services/RelayURLResolver.swift` — gate `bestRelayURL` /
  `resolvePreferringLAN` on fingerprint match.
- `ios/MajorTom/Features/Pairing/ViewModels/PairingViewModel.swift` +
  `Core/Services/AuthService.swift` — capture + persist the pin at pairing.
- Keychain helper — new key for the pinned fingerprint.

---

## How to land it
1. Branch off `fix/ios-relay-lan-connect` (don't start from main — the
   LAN-preference code lives on #176). The correctness nit (Task.sleep
   cancellation) is already fixed there (commit `bcb8085`).
2. Build relay side + iOS side; the relay change ships as its own PR (separate
   component), the iOS identity-check folds into #176.
3. Rebase #176 onto main (the `%en0` + tunnel commits will drop as already-merged;
   you keep the LAN-preference + the new identity binding).
4. Mark #176 ready (it is currently a **draft**), re-run Tier-2 review, address,
   merge.

---

## Ops / QA notes
- Relay + tunnel are running from this session (`nohup bash start.sh`, relay log
  `/tmp/relay.log`; tunnel relaunched on http2, log `/tmp/tunnel.log`). Check
  `lsof -nP -iTCP:9090 -sTCP:LISTEN` before restarting. [[feedback_relay_detach]]
- The build on Sean's phone is the FULL Step-B build (includes the held LAN
  feature) — harmless for him, but not what is on main. Reinstall main's build
  when convenient. [[reference_wireless_device_deploy]] (device must be UNLOCKED
  to install).
- Sean drives from his phone — keep responses short, minimal markdown, no
  AskUserQuestion picker. [[feedback_no_askuserquestion_mobile_tmux]]
  [[feedback_bias_to_action]]
- Relay `SESSION_SECRET` hardening (P3/P4/P5, `docs/HANDOFF-RELAY-OAUTH-RESTART.md`)
  still pending, independent, lower urgency.
