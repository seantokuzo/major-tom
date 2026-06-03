# Project State

> Auto-injected into fresh sessions. Keep concise.

## Current Phase

**Relay-identity binding — FULLY SHIPPED.** Relay half: PR #178 (2026-05-27 → main `2a48f79`) — persistent Ed25519 relay identity, fingerprint in mDNS TXT (`fp=`), `GET /identity` (public key) + `POST /identity/challenge` (signs `"major-tom/relay-identity/v1:" + nonce`, base64url). iOS half: PR #176 (2026-05-28 → main `04850e9`) — pins the relay public key at pairing (Keychain `relay_public_key`) and gates `RelayURLResolver`'s LAN preference on a CryptoKit Ed25519 challenge-response verify against the pinned key before handing over the session cookie, **fail-closed** to the tunnel; `BonjourBrowser` parses the TXT `fp` as a fast filter only. Unanimous ship, 0 blocking + impartial-judge merge/high. **The held LAN-preference feature is now fully unblocked** — the app prefers a *verified* local relay over the tunnel at connect time. Follow-ups **#179 + #180 SHIPPED 2026-05-30** — PR #181 (`5171ed4`) snapshots `bestRelayURL` once per terminal connection via `snapshotRelay()` (removed the live-reading `relayURL`/`relayDomain`/`relayBaseURL`/`isRelaySecure` props), PR #182 (`1254ede`) adds a deterministic relay vitest pinning the `/identity/challenge` signed-byte contract in CI + syncs the iOS self-test to the same vector. Both unanimous ship, 0 blocking, CI green; each also passed an independent adversarial pre-PR verify. On-path MITM residual deferred to TLS channel binding. Spec: `docs/HANDOFF-RELAY-IDENTITY-BINDING.md`.

**NEXT — `docs/HANDOFF-POST-IDENTITY-FOLLOWUPS.md`.** Session 1 DONE (#181/#182/#184). Device QA 2026-06-02/03 on Sean's phone: Google login ✅, terminal `/shell` connects + PTY spawns ✅, DEBUG identity self-test passes ✅. **Terminal-connect regression fixed in PR #184 (`cf94401`):** `RelaySnapshot` built `ws://`/`http://` for the public tunnel → iOS ATS blocked `/shell` before it left the device (terminal only ever worked over LAN); now derives scheme via `AuthService.normalizeBaseURL` (`normalizeBaseURL` made `nonisolated`). **STILL OPEN — #183:** LAN preference never engages on Wi-Fi (rides the tunnel); root cause is Bonjour resolve timing (`NWConnection` `.ready` TCP handshake vs `resolvePreferringLAN`'s 2s window), NOT a pin/connect race. App fully works via tunnel. PR #175 Wave-1 touch-input QA still unconfirmed. Session 2 (later): Terminal UX Wave 2 (selection+copy) — **requires an xterm.js touch-selection research scout first** (`project_terminal_ux_phase`).

**Terminal UX** — Wave 1 shipped (PR #175, 2026-05-23). 4-wave bundle pulled from `project_qa_followups_queue.md` top-of-stack. Wave 1 (touch input) ships swipe→arrow keys + long-press→system Paste menu on the WKWebView terminal; round-1 verdict clean across all 3 specialists, 0 blocking, 0 advisory. **Device QA pending on Sean's phone** — now fully unblocked (login + terminal-connect both fixed); folded into the Session 1 Part C device-QA pass. Wave 2 (selection + copy) requires research-agent scout on xterm.js touch-selection in iOS WKWebView before starting per `project_terminal_ux_phase.md` warning. Wave 4 (autocorrect toggle) can slip in parallel if Wave 1 device QA stalls.

### Pairing Reboot (closed 2026-05-23)

Killed the hardcoded LAN IP + the PIN re-entry treadmill. Four PRs shipped: #170 (mDNS + pre-flight ping), #171 (Google OAuth in iOS), #172 (`MAJORTOM_PIN_TTL_MIN` env knob), #173 (OAuth-only consolidation — PIN UI gone from iOS, URL UI gone, `AUTH_PIN_ENABLED=false` 404s PIN routes, tunnel URL hoisted into gitignored `Secrets.swift`). Wave 2 (provenance UX) + Wave 3 (UX polish) marked **OBSOLETE** in the phase doc closeout — every UI surface they were designed to harden is gone. Wave 2A item 3 (biometric) **DEPRIORITIZED** — Google passkey + 7-day OAuth cookie already deliver Face-ID-only re-auth. Memory: `project_pairing_reboot_handoff.md`.


---

## Previous Phase

**Tab-Keyed Offices** — ALL WAVES + L-MATRIX QA SHIPPED (PRs #149–#156). **Wave A shipped (PR #159, 2026-04-22)**: PtyBtwQueue routes `sprite.message` for PTY sessions via a per-subagent FIFO that writes framed text into the PTY and taps `PtyAdapter.onOutput` for reply correlation (2s settle, 30s max-wait, tab-wide serialization, ANSI-stripped tail). Closes QA-FIXES #11 Layer 2. **Wave B shipped (PR #157, 2026-04-21)**: iOS refreshes sprite state on WS reattach + tab.list.response arrival; relay `sprite.state.request` gained sandboxGuard and dropped the per-session attach gate. QA-FIXES #7 closed. **Wave D shipped (PRs #160 + #161 + #162, 2026-04-22)**: PR #160 closes #12 (PTY reconnect cwd restore) + #14 (xterm OSC 0/2 title suppression) + #11b ("Performance HUD" → "SpriteKit Stats" rename + clarified footer). PR #161 closes #9 + #6 — relay randomizes CharacterType per spawn from a 14-char CHARACTER_POOL w/ session-roster dup-avoidance; iOS trusts relay's characterType verbatim; RoleMapper's role→character logic deleted (aura palette stays); spec §Q2 + locked table struck. PR #162 closes the routing half of #8 — Office view auto-pops to the Manager on tab teardown (cold-tap + live teardown via `.onChange(viewModel == nil)`). Remaining Wave D loose ends (both device-QA-gated): animation-timing half of #8 (extend walk-off duration when Office is foregrounded) + #13 (stale-sprite cleanup post-relay-restart — user to re-QA first since Wave B may have subsumed). Spec: `docs/PHASE-TAB-KEYED-OFFICES.md` (Gate D superseded by PR #155). Memory: `project_qa_followups_phase.md`. Sprite 4-6 QA unpaused.

| Wave | Scope | Status |
|------|-------|--------|
| 1 — Research + Spec Freeze | All gates answered, spec at `docs/PHASE-TAB-KEYED-OFFICES.md` | DONE |
| 2 — Relay Bridge | TabRegistry, SessionStart/Stop hooks, `tab.list` RPC, PTY-close teardown | SHIPPED (#149) |
| 3 — Protocol + iOS wiring | `tabId` on sprite/agent messages, iOS decoders, `TabRegistryStore`, `RelayService.requestTabList()`, `tabKeyedOffices` feature flag (default off) | SHIPPED (#150, #151) |
| 4 — iOS Office Rebind + Explicit Terminal Lifecycle | OfficeSceneManager keyed by tabId with fallback cascade, OfficeViewModel roster + lifecycle handlers, OfficeManagerView reads TabRegistryStore, OfficeView(tabId:), banner + notification routing by tabId, feature flag removed, terminal auto-spawn ripped out with ContentUnavailableView empty state | SHIPPED (#152) |
| 5 — Session Cycling + Edge Cases | `AgentState.sessionId` binding, scoped walk-off on `tab.session.ended`, walk-in on `.spawning` confirmed sufficient, walk-off-then-teardown on `tab.closed` with 1.5s grace, Gate A scoped role bindings + per-agent `/btw` routing, sprite-mapping migration with `.migrated-v4` sentinel (fresh-install seeded + fail-closed on non-ENOENT stat), hard-kill PTY test coverage | SHIPPED (#153, #154) |

### Sprite-Agent Wiring (shipped, QA paused)

Makes the sprite metaphor functionally real — tap, /btw, response bubbles, role auras, tool bubbles, progress, local push, disconnect/reconnect, desk overflow, persistence cascade. Spec: `docs/PHASE-SPRITE-AGENT-WIRING.md`.

### Sprite-Agent Wiring

Makes the sprite metaphor functionally real — tapping a sprite does something deterministic, messaging is routed with defined semantics, multi-session Office has a coherent story.

| Wave | Scope | Status |
|------|-------|--------|
| 1 — Research + Spec Freeze | All 7 research gates answered, spec updated | SHIPPED (#137) |
| 2 — Data Model + Protocol | Relay: sprite.* messages, persistence, classifier, sessionId on events. iOS: RoleMapper, clone-not-consume, remove dog fallback | SHIPPED (#138, #139) |
| 3 — Office Manager + Multi-Session | Relay: sprite.state.request query endpoint. iOS: OfficeManagerView, OfficeSceneManager, per-session event routing, LRU scene lifecycle, cold rebuild | SHIPPED (#140, #141) |
| — | **Review Round** | DONE (#142) — protocol alignment, session cleanup, schema migration |
| 4 — `/btw` Messaging Delivery | Relay BtwQueue + JSON-safe constraint framing + single-in-flight guard + dropByMessageId. iOS modal flow, dog canned pools, idle human inspector, cross-session banner, green-glow preview. | SHIPPED (#143, #144) |
| 5 — Visual Differentiation + Notifications | Relay: per-subagent tool events + toolCount/tokenCount metrics. iOS: role aura (locked palette), tool-event bubbles, mini progress, M3 bubble priority, UNUserNotification with Cool Beans action. | SHIPPED (#145, #146) |
| 6 — Edge Cases + Battle Test | Relay: persistence cascade hardening (corrupt-file / disk-full / client-auth fallback), 37 new integration tests. iOS: 21-slot overflow grid, gray-out on disconnect + `sprite.state.request` reconcile, fast-complete animation chain (min 1.5s), scenario-9 tap/send race re-check. | SHIPPED (#147, #148) |

### Optimization phase (COMPLETE)

Wave 2 hit target: **idle Office FPS 11.74 → 59.99 on-device** (PR #135, merged 2026-04-16). Parallax cache + idle-camera early-exit + scene pause off-tab + Live Activities opt-in. Remaining Wave 2/3 items (buildGrid audit, ignoresSiblingOrder) deprioritized — target already met; measure-first if the next phase regresses perf. Memory: `project_optimization_phase.md`. Baseline: `docs/PERF-BASELINE.md`.

| Wave | Scope | Status |
|------|-------|--------|
| 1 — Measurement | SpriteKit HUD + Instruments baseline | SHIPPED (#129) |
| 2 — Cheap wins | Parallax cache, idle-camera exit, scene pause off-tab, LA opt-in | SHIPPED (#135) |
| 3 — SKAction pooling | Deprioritized — target met without it | DEFERRED |
| 4 — Culling + atlas split + tile map | Deprioritized — target met without it | DEFERRED |
| 5 — Verify | Remeasurement done 2026-04-16 — 5x jump | DONE |

### Terminal Polish (COMPLETE)

Three iOS terminal QoL fixes (first-prompt `\W`, reconnect retry, renameable tabs) shipped PRs #131 + #132. Tab-switch crash-loop, xterm overlap, ring-replay all fixed. Memory: `project_terminal_polish_phase.md`.

### Life Engine phase (complete)

| Wave | Scope | PR |
|------|-------|----|
| 1 — Grid pathfinding, haptics, new rooms | DONE | #124 |
| 2 — Activity selection engine (JSON) | DONE | #125 |
| 3 — Activity animations, emotes, asset transitions | DONE | #126 |
| 3b — Roster rewire + asset resplice + inspector preview | DONE | #127 |
| 3c — Crew picker UI | DONE | #128 |

### Space Station phase (complete — superseded by Life Engine)

Spec: `docs/PHASE-SPACE-STATION.md` — office→station revamp folded into Life Engine waves.

### Ground Control (macOS relay manager)

Spec: `docs/GROUND-CONTROL.md`

| Wave | Status | PR |
|------|--------|----|
| 1 — Scaffold & Process Management | DONE | #98 |
| 2 — Log Viewer | DONE | #100 |
| 3 — Dashboard | DONE | #102 |
| 4 — Configuration | DONE | #104, #106, #108 |
| 5 — Security & Polish | DONE | #109 |

### Phase 14 "SwiftTerm" (iOS native terminal)

Spec: `docs/PHASE-14-SWIFTTERM.md`

| Wave | Status | PR |
|------|--------|----|
| 1 — Basic Terminal Rendering | DONE | #97 |
| 2 — Keyboard & Input | DONE | #99 |
| 3 — Multi-Tab Support | DONE | #103 |
| 4 — Customization & Sync | DONE | #105, #107, #108 |
| 5 — Polish & Integration | DONE | #110 |

## Prior Phases (all complete)

| Phase | Name | PRs |
|-------|------|-----|
| 6 | ClaudeGod | #44 |
| 7 | iOS Feature Parity | — |
| 8 | Fleet Command | #62-79 |
| 9 | The Social Layer | #80-81 |
| 10 | Lockdown | #82-85 |
| 11 | The Pipeline | #86-88 |
| 12 | Glow Up | — |
| 13 | The Shell | #89-96 |
| QA | PWA Polish | #101, #111 |
| 14 | SwiftTerm (iOS terminal) | #97-110 |
| — | Terminal Reboot (tmux → plain PTY) | #130 |
