# Project State

> Auto-injected into fresh sessions. Keep concise.

## Current Phase (in flight)

**Sprite-Agent Wiring** — Waves 1-5 shipped, Wave 6 (edge cases + battle test) in flight — final wave. Spec: `docs/PHASE-SPRITE-AGENT-WIRING.md`. Memory: `project_sprite_agent_wiring_phase.md`.

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
| 6 — Edge Cases + Battle Test | Race conditions, disconnect/reconnect, persistence cascade, fast-complete animations | IN FLIGHT |

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
