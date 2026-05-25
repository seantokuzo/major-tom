# Handoff — "Restart relay → can't log in → OAuth not available"

> Written 2026-05-25 mid-session. Start a FRESH session with this doc + the
> two memories linked at the bottom. Goal: fix the restart→login footguns
> thoroughly, then close out. Do NOT trust the original "env didn't load"
> theory — it was disproven (see below). Read the EVIDENCE section first.

---

## Symptom (Sean's report)

> "I restarted the relay and can't login. Google OAuth not available. I
> stopped the server but this ain't a great UX."

Reproduced by Sean via `bash start.sh` **with and without** `--local`. Same
result both times: the iOS pairing screen does not offer Google sign-in /
sign-in fails, surfaced as "OAuth not available."

## TL;DR root cause (best-supported, NOT yet confirmed live)

Two **independent** problems wearing one trenchcoat:

1. **Misleading iOS UX (most likely what Sean saw).** When the iOS app can't
   reach the relay, the Google button silently disappears and the user reads
   it as "OAuth not available" — even though the relay is fine. The relay
   side serves OAuth correctly (proven below). The failure is on the
   app↔relay path, and the app conflates "unreachable" with "OAuth not
   configured."

2. **Relay `SESSION_SECRET` footgun (real, independent, confirmed by code +
   the corrupted `.env`).** `getSessionSecret()` regenerates a new secret and
   **appends** it to `.env` whenever `SESSION_SECRET` isn't in the
   environment. Any env-less start → new secret → every existing session JWT
   invalidated (mass logout) → another dup line in `.env`. Sean's `.env`
   already has **3** stacked `SESSION_SECRET` lines from this.

These can compound: an env-less start would BOTH disable OAuth (no
`GOOGLE_CLIENT_ID`) AND mint a new session secret (logout). But the canonical
start path loads env fine, so #2's mass-logout is the more durable hazard.

---

## EVIDENCE — what's PROVEN (re-run these to verify)

All from repo root unless noted. `relay/.env` contains valid
`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_ID_IOS`, `GOOGLE_CLIENT_SECRET`,
`ALLOWED_EMAIL`, `AUTH_PIN_ENABLED=false`, and (currently) **3×**
`SESSION_SECRET`.

1. **`.env` loads correctly via every canonical loader:**
   ```
   cd relay
   node --env-file=.env -e "console.log(!!(process.env.GOOGLE_CLIENT_ID||process.env.GOOGLE_CLIENT_ID_IOS))"   # true
   npx tsx --env-file=.env <script>           # google:true session:true
   npx tsx watch --env-file=.env <script>     # google:true session:true  (child process DOES get the env)
   ```
   tsx is v4.19.4, node v24.12.0. `tsx watch` forwards `--env-file` to the
   child — that hypothesis was tested and is FALSE.

2. **The real `server.ts` with the real env serves OAuth fully.** Ran it
   isolated (temp `.env` copy so it couldn't append to the real one; alt
   ports 9595/9596; throwaway HOME):
   ```
   GET /auth/methods            → {"google":true,"pin":false,"multiUser":false}
   GET /auth/google/client-id   → {"clientId":"<set>","iosClientId":"198289476970-…apps.googleusercontent.com"}
   banner                       → "Auth:      Google OAuth (seantokuzo@gmail.com)"
   ```
   Bound to 127.0.0.1, LAN 192.168.1.210, Tailscale 100.69.151.117 — all :9595.
   The isolated run did NOT append to the real `.env` (stayed at 3 lines).

**Conclusion:** the relay enables Google OAuth correctly with Sean's env. The
original "env didn't load → AUTH_GOOGLE_ENABLED=false" theory is **disproven**
for the canonical start path.

## What's DISPROVEN

- ❌ "`tsx watch --env-file` doesn't propagate env to the child." It does.
- ❌ "The `.env` is malformed / parsing aborts." It's clean; only cosmetic
  issue is the 3 dup `SESSION_SECRET` lines (Node `--env-file` takes the
  last, so runtime is stable).
- ❌ "Relay-side `AUTH_GOOGLE_ENABLED` is false with the real env." It's true.

## What's NOT yet confirmed (the gap a fresh session must close)

We **never captured the actual failing request from Sean's phone.** We proved
the relay *should* work; we did not observe *what the app received* when it
failed. Needs Sean + phone + relay live.

---

## Root-cause hypothesis — the iOS connectivity/UX bug (code-grounded)

`ios/MajorTom/Features/Pairing/ViewModels/PairingViewModel.swift`:

- `currentRelayURL` (lines ~82-90) resolves in order:
  1. First Bonjour/mDNS-discovered service (LAN, lowest latency)
  2. Reachability preset (lines 21-28): `.tailscale → Tailscale addr`,
     **`.lan → Cloudflare tunnel`**, `.cellular → Cloudflare`, `.offline → nil`
  3. Final fallback: `Secrets.tunnelURL`
- `fetchAuthMethods()` (lines ~109-133): `GET /auth/methods`; on **non-200 or
  network error** it sets `authMethods = nil` (no distinction between "relay
  said no google" and "couldn't reach relay") and clears `googleIOSClientID`.
- `isGoogleEnabled` (lines 74-76) = `authMethods?.google && googleIOSClientID
  != nil`. Either failure → button hidden.
- `signInWithGoogle()` guard (line 169) → "Relay isn't configured for iOS
  Google sign-in" when `googleIOSClientID` is nil.

**The trap:** when the device is on plain LAN and mDNS does NOT surface the
relay, step 2 sends the app to the **Cloudflare tunnel URL — there is no
LAN-IP fallback.** So:

- `bash start.sh --local` (tunnel OFF) + mDNS miss → app hits dead tunnel URL
  → `/auth/methods` unreachable → `authMethods=nil` → "OAuth not available."
  **This exactly matches the `--local` failure.**
- `bash start.sh` (tunnel ON) → app hits tunnel; should work. If it still
  failed for Sean, suspects: tunnel slow to come up / misconfigured, stale
  sticky state from the prior `--local` attempt, mDNS surfacing a stale
  service, or reachability returning something unexpected.

LAN connectivity currently hinges entirely on mDNS working. When mDNS misses,
there's no plain-LAN-IP path — it jumps to the public tunnel.

---

## Fix plan (Sean approved "full hardening")

Prioritized. Treat relay auth as a SENSITIVE PATH — careful review, the Tier 2
panel will scrutinize it.

### P1 — iOS: stop conflating "unreachable" with "OAuth not configured"
`PairingViewModel.fetchAuthMethods()` + `PairingView`.
- Distinguish three states: (a) reached relay, `google:true` → show button;
  (b) reached relay, `google:false` → "relay has no Google auth configured";
  (c) **could not reach relay** → "Can't reach relay at `<currentRelayURL>`"
  with the URL shown, NOT a vanished button.
- This is the actual "ain't a great UX" fix. A user should never confuse a
  dead tunnel with a missing OAuth config again.

### P2 — iOS: LAN fallback that doesn't require mDNS
`currentRelayURL` / `ServerPreset`.
- When on `.lan` and Bonjour found nothing, try a LAN address before the
  public tunnel (or at least make `--local`'s "no tunnel" obvious). Decide:
  do we persist the last-known-good LAN IP? Surface a manual entry? (Manual
  URL entry was removed in PR #173 OAuth-only consolidation — check
  `project_ios_secrets_indirection.md` before re-adding any URL UI.)

### P3 — relay: kill the `SESSION_SECRET` append/regenerate footgun
`relay/src/auth/session.ts:24-48` (`getSessionSecret`).
- Never silently regenerate when a `.env` with a `SESSION_SECRET` exists on
  disk but isn't in the environment — that's an operator error (started
  without `--env-file`); FAIL LOUDLY instead of minting a new secret and
  logging everyone out.
- If genuinely first-run (no `.env` or no secret in it), generating once is
  fine — but **replace/write idempotently, never `appendFileSync` a new line
  each time.** Current code appends → dup keys accumulate.

### P4 — relay: startup preflight (Sean's "full hardening" core)
`relay/src/server.ts` before `buildApp`.
- If `relay/.env` exists on disk but its keys aren't present in
  `process.env` (e.g., `GOOGLE_CLIENT_ID`/`SESSION_SECRET` on disk but unset
  in env), the operator forgot `--env-file` (or wrong cwd). Print a loud,
  specific error and `exit(1)`:
  "Found relay/.env but its variables aren't loaded — start with `./start.sh`
  / `npm run dev` / `node --env-file=.env`." Turns a silent double-footgun
  into a one-line fix.

### P5 — cleanup: collapse the 3 dup `SESSION_SECRET` lines in `relay/.env`
- Keep the **last** value (that's what Node `--env-file` currently uses, so
  runtime is unchanged and no further logout). Do this as a manual edit with
  Sean present — it's his live secrets file, gitignored. After P3 lands it
  won't re-accumulate.

### Out of scope / verify-don't-assume
- Don't re-add manual URL entry UI without checking the PR #173 consolidation
  rationale (`project_pairing_reboot_handoff.md`,
  `project_ios_secrets_indirection.md`).
- The relay banner already warns "No auth methods enabled!" only when BOTH
  google AND pin are off — fine to keep, but P4's preflight is the real guard.

---

## Exact next diagnostic steps (do FIRST, with Sean + phone + relay live)

This closes the "what did the app actually receive" gap before writing fixes.

1. `bash start.sh` (tunnel on). Capture the startup banner — confirm
   "Auth: Google OAuth (…)" prints and note the bound addresses.
2. On the phone's pairing screen, determine which URL `currentRelayURL`
   resolves to (add a temp debug print, or check whether Bonjour discovered
   anything vs falling back to tunnel/Tailscale).
3. From a laptop on the SAME network as the phone:
   `curl <that-exact-url>/auth/methods` — does it return `{"google":true,…}`?
   - **Yes** → relay + URL are fine; bug is app-side timing/caching/state →
     focus P1. Add logging in `fetchAuthMethods` to see the real failure.
   - **No / hang** → connectivity (tunnel down, mDNS stale, wrong addr) →
     focus P2.
4. Repeat with `bash start.sh --local` and confirm the prediction: app falls
   to the dead tunnel URL → unreachable → "not available."

Once (3) tells you app-side vs path-side, implement P1+P2 accordingly, then
P3+P4 (relay, independent — can be a separate PR), then P5 cleanup.

---

## Key files + line refs (as of 2026-05-25)

- `relay/src/auth/session.ts:24-48` — `getSessionSecret` append/regenerate footgun (P3)
- `relay/src/server.ts:17-26` — env-derived config incl. `AUTH_GOOGLE_ENABLED` fallback; add preflight here (P4)
- `relay/src/routes/auth.ts:46-72` — `/auth/methods` + `/auth/google/client-id` (503 when unconfigured)
- `ios/.../Pairing/ViewModels/PairingViewModel.swift:21-28` — `ServerPreset` (`.lan → cloudflare`, the no-LAN-fallback trap)
- `ios/.../Pairing/ViewModels/PairingViewModel.swift:74-90` — `isGoogleEnabled`, `currentRelayURL`
- `ios/.../Pairing/ViewModels/PairingViewModel.swift:109-154` — `fetchAuthMethods`/`fetchGoogleClientID` (conflate unreachable w/ no-google) (P1)
- `relay/.env` — 3 dup `SESSION_SECRET` lines to collapse (P5)
- `relay/package.json` — `dev`/`start` both use `--env-file=.env`; `start.sh` calls them

## Don't repeat my mistakes

- I asserted "env doesn't load" / "tsx watch drops --env-file" **without
  reproducing the real path.** Both wrong. Capture the live failing request
  (step 3 above) before theorizing.
- The relay side is PROVEN good. Anchor on that.
