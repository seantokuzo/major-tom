# Handoff — post relay-identity follow-ups (two queued sessions)

> Queued 2026-05-28 after relay-identity binding shipped fully (relay PR #178 +
> iOS PR #176, merged → main `04850e9`). The LAN-preference feature is live: the
> app prefers a *verified* local relay over the tunnel at connect time. This
> handoff queues the deferred follow-ups + device QA, then the next Terminal-UX
> wave. **Do SESSION 1 first; SESSION 2 is a separate, later session.**

---

## SESSION 1 — close the advisory loop (#179 + #180) + device-QA the LAN feature

> **STATUS (2026-05-30): Parts A + B SHIPPED (PRs #181 + #182 merged to main). Only
> Part C — device QA, which needs Sean's unlocked phone — remains.**

### Part A — Issue #179: snapshot `bestRelayURL` once per connection (iOS)
> ✅ **SHIPPED 2026-05-30 — PR #181 (`5171ed4`).** Implemented via
> `TerminalViewModel.snapshotRelay()` — the lone read of `bestRelayURL`, captured in
> `TerminalWebView.makeUIView` *before any await*; the immutable `RelaySnapshot`
> (single `base`) feeds the `/shell` socket URL + cookie domain + secure flag, so
> they can't diverge. The live-reading `relayURL` / `relayDomain` / `relayBaseURL`
> props and `isRelaySecure()` were **removed** — any mention of them below describes
> the PRE-fix code. Sim build + independent adversarial pre-review both clean;
> unanimous ship, 0 blocking, CI green.

**Bug:** `RelayURLResolver.bestRelayURL` (sync getter, `RelayURLResolver.swift:50`)
can flip tunnel→verified-LAN *across an `await`*, because `verifiedLANAddress` is
mutated asynchronously by `resolvePreferringLAN`. `TerminalWebView` reads it at
three points separated by suspension:
- `injectAuthCookie` → `viewModel.relayDomain` (cookie `.domain`)
- `isRelaySecure` → `viewModel.relayBaseURL`
- JS config → `viewModel.relayURL` (the `/shell` socket host)

If a LAN host gets verified during the `await` inside `injectAuthCookie`, the
cookie pins to the **tunnel** domain while the socket connects to the **LAN**
host → `mt-session` cookie not sent → `/shell` auth fails until the next connect
(transient, self-healing — that's why it was deferred, not blocking).

**Fix:** snapshot `bestRelayURL` **once** at the start of a connection attempt and
derive cookie-domain / secure-flag / socket-URL from that single value so they
can't diverge.
- Files: `ios/MajorTom/Core/Services/RelayURLResolver.swift`,
  `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift`
  (`relayURL`/`relayDomain`/`relayBaseURL` computed props ~382/400/410),
  and the `TerminalWebView` coordinator (`injectAuthCookie` / `isRelaySecure`).
- Cleanest shape: have the connect path capture `let base = relayResolver.bestRelayURL`
  once and pass it into the cookie-inject + socket-build helpers, instead of each
  computed prop re-reading the resolver.
- Low risk but touches terminal-connect coordination — build (XcodeBuildMCP
  `build_sim`) and ideally device-verify alongside Part C.

### Part B — Issue #180: relay CI vector locking the challenge contract (relay)
> ✅ **SHIPPED 2026-05-30 — PR #182 (`1254ede`).** Deterministic vitest in
> `relay/src/routes/__tests__/identity.test.ts` pins the canonical
> `(publicKey, nonce, signature, fingerprint)` quadruple from a fixed-seed
> (`0x01..0x20`) PKCS#8 key loaded via the **real** `RelayIdentity.load()`, with a
> 5th case driving the **live Fastify route** end-to-end. The iOS
> `RelayIdentityVerifier.runSelfTest()` vector was swapped to the SAME quadruple
> (one source of truth) — this **replaces** the throwaway-key vector listed below.
> Canonical quadruple now in source: publicKey `ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ`,
> signature `Q7L_CUIA7y7nO6T7uOd0ipZjlKvVA_wKGXGgZK0ZkEz5aei-B1jB1gRXHYcoLrOUaLKFWysFS84zOdAjpcfmCQ`,
> fingerprint `ZbYGc9btiEvwHCwiLYKtoHQPKawzVdapJcgfF_R6J7g` (nonce unchanged). Relay
> suite 373/373 green; adversarial verify independently re-derived the quadruple
> from the seed. Unanimous ship, 0 blocking.

**Goal:** lock the signed-byte construction in the green relay CI lane so a future
base64 ⇄ base64url "cleanup" on either side can't silently desync the handshake.
- Construction (canonical): `relay/src/routes/identity.ts` `CHALLENGE_CONTEXT =
  "major-tom/relay-identity/v1:"`; signed message = `utf8(CHALLENGE_CONTEXT) ||
  nonceBytes`; Ed25519; signature base64url; nonce decoded from **standard** base64.
- Add a vitest in `relay/src/routes/__tests__/identity.test.ts` (existing identity
  route tests live here; relay-identity unit tests in
  `relay/src/identity/__tests__/relay-identity.test.ts`). Use a **checked-in fixed
  PKCS#8 Ed25519 private key** so the signature is deterministic, derive the
  `(publicKey, nonce, signature)` triple, and assert it byte-for-byte.
- **Bonus / one-source-of-truth:** update the iOS DEBUG self-test
  (`RelayIdentityVerifier.runSelfTest()`) to use the SAME triple the relay test
  pins. The vector currently embedded on iOS was generated from a *random*
  throwaway key (private key not saved), so it can't be reproduced relay-side as-is:
    - publicKey (b64url): `q4pQhxT0AhdTFWnjIPoOMxPAdpvhS3MD3FIH99vdrSg`
    - nonce (std b64):    `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=`
    - signature (b64url): `BEtOQAX7i_EacFiPJmeXoGzlf5P4LCz90oQL3myQB6q9CrumI2N86iHGISPp8cil76iAOeBkq3vQuO1v6jvkCQ`
    - fingerprint:        `wJZelWR9DWLLvgFUBSq1F_N_x8gmTFBp_3z14su95sU`
  So: relay test owns a fixed key → produces the canonical triple → copy that triple
  into `runSelfTest()`, replacing the random-key one.
- This is a relay-only change → ships as its **own relay PR** (clean component
  boundary), not bundled with the iOS #179 fix.

### Part C — Device QA the shipped LAN feature (option 3)
Reinstall **main's** build on Sean's iPhone first — his phone still has the old
pre-identity build. Wireless deploy per memory `reference_wireless_device_deploy`;
device must be **UNLOCKED**; free-team signing may need the Xcode recovery dance
(`project_free_apple_account`). Checklist:
- [ ] **Golden path:** same LAN as the relay, pair via Google OAuth → key pins →
  cold relaunch connects to the **verified LAN** address (not the tunnel); terminal
  `/shell` works. (Confirm LAN by relay log / address shown.)
- [ ] **Rogue responder (best-effort):** stand up another `_majortom._tcp`
  advertiser on the LAN → app must NOT trust it (stays on tunnel). Hard to stage;
  at minimum, with the real relay **off/asleep**, confirm clean tunnel fallback.
- [ ] **Off-LAN / cellular:** tunnel fallback, terminal still connects.
- [ ] **DEBUG launch:** app starts without tripping the `RelayIdentityVerifier`
  self-test assertion (it was verified to pass, but confirm on-device).
- [ ] Also covers the **PR #175 Wave-1 touch-input** device QA that was pending.

**Ordering within Session 1:** Part A (iOS #179) + Part C (device QA) pair naturally
(QA the #179 fix on-device). Part B (#180 relay) is independent — do it whenever.

---

## SESSION 2 — Terminal UX Wave 2: selection + copy (separate later session)
Spec/state: memory `project_terminal_ux_phase.md` (Wave 1 touch-input shipped via
PR #175; Waves 2-4 pending).

**HARD GOTCHA (do not skip):** Wave 2 (selection + copy) **requires an xterm.js
touch-selection research scout FIRST** — spawn a research agent / hit Context7 on
xterm.js touch selection inside an iOS WKWebView before writing any code. The phase
memory explicitly flags this as a prerequisite (touch selection in xterm.js on
WKWebView is non-trivial / has known footguns). Sequence:
1. Research scout → land on a concrete approach (xterm.js selection API + touch
   gesture bridging in WKWebView; how copy interacts with the existing
   long-press→Paste menu shipped in PR #175).
2. Then implement Wave 2 against `docs/TERMINAL-PROTOCOL-SPEC.md` + the iOS terminal
   feature (`ios/MajorTom/Features/Terminal/`).

Wave 4 (autocorrect toggle) can slip in parallel if Wave 2 stalls on research.

---

## Standing context for any session
- Sean drives from his phone — short replies, minimal markdown, no AskUserQuestion
  picker (`feedback_no_askuserquestion_mobile_tmux`); bias to action
  (`feedback_bias_to_action`).
- Autonomous PR loop is the default (poll → triage → judge → merge); see
  `~/.claude/CLAUDE.md` + project `CLAUDE.md`. "wait for me" overrides it.
- Relay `SESSION_SECRET` hardening (P3/P4/P5, `docs/HANDOFF-RELAY-OAUTH-RESTART.md`)
  is still pending, independent, lower urgency.
- On-path MITM residual (cookie on plaintext LAN `ws://`) is the known limitation
  of the shipped identity binding — needs TLS channel binding, separate future task.
