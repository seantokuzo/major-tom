# Project State

> The full record. `.claude/STATE.md` is the short version the session-start hook
> injects — keep the two in sync.

## Current Phase

**Terminal UX + iOS hardening.** Two iOS fixes shipped 2026-08-01, both surfaced by adversarial review rather than by QA.

**PR #185 (`bc08c5e`) — terminal paste, dead since April.** `terminal.html`'s paste handler referenced `encoder`, which is `var`-declared inside `initTerminal()` while `window.MajorTom` is assembled in the outer IIFE — every paste threw `ReferenceError`. Silent because `TerminalViewModel` calls `evaluateJavaScript(js) { _, _ in }` and discards the error (#190). It broke in `6db7835` (2026-04-10, "reuse existing TextEncoder in paste()" — itself a code-review suggestion), **not** in PR #175 as first diagnosed; both call sites (keybar and long-press menu) have been dead since. The first fix was then caught using the wrong mechanism: raw `ws.send` bypasses **bracketed paste**, so multi-line clipboard content auto-executes in zsh and hands the `claude` TUI N prompt turns instead of one. Final fix routes through `term.paste()` — restores `ESC[200~`/`ESC[201~` wrapping gated on DEC 2004, plus `\r\n → \r` normalization — and adds `identifier: .paste` to the Paste `UIAction` so the pasteboard read doesn't trip the iOS 16 consent modal.

**PR #191 (`2054a50`) — LAN preference actually engages (#183).** Root cause was Bonjour resolve timing. Ships browser pre-warm at `.onAppear`, a discovery grace anchored at browser start (2s nominal, 250ms floor, 4s ceiling), a per-resolver watchdog, `.failed` cancel + teardown, handler identity guards, and `os_log` instrumentation. Review found worse than a timing bug: on `main` the verified-LAN cache was keyed on a forgeable address string with no invalidation, and this PR is what promoted that dead branch to the hot path. The cache is now bound to `(address, pinnedKey, browserGeneration)` behind a single gate, `.background` invalidation is paired with an `.active` re-resolve, and `resolvePreferringLAN` is single-flight with fail-closed cancellation. **Behavior change Sean explicitly approved:** the Bonjour branch is gone from `PairingViewModel.currentRelayURL`, so first-time pairing now requires the tunnel or Tailscale — an attacker on the LAN could otherwise have served their own OAuth client-id, taken the Google ID token, and had their relay key pinned. Post-pairing LAN preference is unaffected. Plain-Wi-Fi pairing against a `start.sh --local` relay stays broken until #198.

**Neither PR has run on a physical device.** iOS has no CI job (#197), so a local `xcodebuild` is the only gate that exists for `ios/`.

**Process — review is local now (commit `0ce0308`).** The Claude Code GitHub App is uninstalled permanently: no `@claude`, no auto-review on PR open, no verdict stickies, no bot inline comments. The orchestrating agent runs review itself by spawning read-only specialist subagents chosen from what the diff touches; `CLAUDE.md` "Local Code Review" is the brief. CI (`ci.yml`, `release.yml`) still runs on GitHub and still gates merge. The main agent is now an orchestrator — research, planning, spec writing, implementation, review, and shipping all go to subagents.

**Signing — Sean is on the paid Apple Developer program.** Team `4B8499Z59P` converted in place, so `project.pbxproj` needs no change. The 7-day expiry that used to bite was a provisioning-profile TTL, not a cert limit. Walkthrough: `docs/APPLE-SIGNING-SETUP.md` (`a1570ed`). **This unblocks device QA.**

**Research banked.** `docs/RESEARCH-XTERM-TOUCH-SELECTION.md` (`7ec2cd9`), verified against `@xterm/xterm@6.0.0` sources — the mandatory prereq for Terminal UX Wave 2. It recommends splitting the wave: **2a** is a selection ladder built on `term.select()` / `selectLines()` surfaced in the existing edit menu (~half a day, no gesture conflict); **2b** is touch-drag selection with DOM handles, edge auto-scroll, and Swift-owned mode arbitration.

## NEXT

**Device QA — the top outstanding item. Runs in parallel with the code task below.**

1. **Paste** — multi-line clipboard content must land **inert awaiting Enter**, not auto-execute. Exercise both call sites: keybar and long-press menu.
2. **QA item 8 on #191** — background round-trip on the same Wi-Fi, then open a new tab. That's the direct regression test for the foreground re-resolve.
3. PR #175 Wave-1 touch-input QA, still unconfirmed since May.

**Terminal UX Wave 2a — queued next code task, gated on nothing.** The selection ladder per the research doc, with **#186** (`setCopyMode` picks the wrong line when scrollback is non-empty — viewport vs absolute row) and **#187** (`onSelectionChange` stomps the user clipboard and ships the whole selection over the bridge) folded into the same PR; both are prerequisites. Wave 2b follows once 2a has been on a device.

### Open issues filed 2026-08-01

| Area | Issues |
|------|--------|
| Terminal | #186 `setCopyMode` row math · #187 `onSelectionChange` clipboard stomping · #188 scrollback unreachable by touch · #189 >64 KiB paste silently lost · #190 `evaluateJavaScript` errors discarded · #192 keybar paste consent prompt |
| LAN / discovery | #193 advertiser slot starvation · #194 split timing invariant · #195 misplaced helpers · #196 LAN proof survives a foreground network change · #198 no non-mDNS LAN pairing fallback |
| Infra gaps | **#197 no iOS job in CI** · **#199 missing App Group entitlement — widget/watch/Shortcuts data bridge silently dead** · #200 `registerForRemoteNotifications` with no `aps-environment` |

---

## Previous Phase

**Relay-identity binding (closed 2026-05-30).** The app pins the relay's Ed25519 public key at pairing and gates LAN preference on a CryptoKit challenge-response verify against it, fail-closed to the tunnel. Relay half PR #178 (`2a48f79`) — persistent identity, fingerprint in the mDNS TXT (`fp=`, a discovery filter only), `GET /identity` + `POST /identity/challenge` signing `"major-tom/relay-identity/v1:" + nonce`. iOS half PR #176 (`04850e9`). Follow-ups: #181 (`5171ed4`) snapshots `bestRelayURL` once per terminal connection, killing the cookie-domain/socket-host desync; #182 (`1254ede`) pins the signed-byte contract in a deterministic relay vitest and syncs the iOS self-test to the same vector; #184 (`cf94401`) derives the relay scheme via `AuthService.normalizeBaseURL` after ATS silently blocked `/shell` over the tunnel. On-path MITM residual is deferred to TLS channel binding. Spec: `docs/HANDOFF-RELAY-IDENTITY-BINDING.md`.

**Pairing Reboot (closed 2026-05-23).** Killed the hardcoded LAN IP and the PIN re-entry treadmill across PRs #170-#173 — mDNS discovery, Google OAuth in iOS, and an OAuth-only consolidation that removed the PIN and URL UI entirely and hoisted the tunnel URL into a gitignored `Secrets.swift`. Waves 2 and 3 were closed out **obsolete**: every surface they were designed to harden is gone.

**Terminal UX Wave 1 (PR #175, 2026-05-23).** Swipe→arrow keys and long-press→system Paste menu on the WKWebView terminal. Wave 4 (autocorrect toggle) is unscheduled.

---

## Archive

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
