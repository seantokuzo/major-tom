# Project State

> Auto-injected into fresh sessions. Keep concise.

## NEXT ACTION (queued for autonomous execution)

**Terminal Reboot — Ditch Tmux** is queued and ready to execute autonomously.

If you are a fresh session and the user types "next" or otherwise green-lights you, read and execute:

- `docs/HANDOFF-TERMINAL-REBOOT.md` (execution brief — start here)
- `docs/PHASE-TERMINAL-REBOOT.md` (wave plan)
- `docs/TERMINAL-PROTOCOL-SPEC.md` (wire protocol contract)

All design decisions are LOCKED. Execute end-to-end: TDD → big-bang refactor → PR → review pipeline until under-5-comment round → merge → memory + STATE updates. Worktree branch: `worktree-terminal+ditch-tmux-plan`.

A parallel session is on `optimization/wave1-measurement` for iOS battery work — do NOT touch iOS optimization files. Terminal refactor scope: relay + iOS terminal feature + PWA + Ground Control tmux check removal.

## Current Phase (in flight)

**Life Engine** complete (PRs #124–#128). Two parallel phases now:

1. **Optimization phase** — iOS battery drain fix (`optimization/wave1-measurement` branch). Memory: `project_optimization_phase.md`.
2. **Terminal Reboot** — relay tmux removal (this worktree). Memory: `project_terminal_reboot_handoff.md`.

### Optimization phase (NEXT — queued)

Research 2026-04-14 refuted the "PNG is killing us" hypothesis. Real hotspots are SKAction allocation churn + per-frame overhead, not texture format. Sprite-redraw experiment scrapped.

| Wave | Scope | Status |
|------|-------|--------|
| 1 — Measurement | SpriteKit HUD + Instruments baseline | IN PROGRESS |
| 2 — Cheap wins | ignoresSiblingOrder, cache parallax refs, frame budget | QUEUED |
| 3 — SKAction pooling | Reuse action graphs in AgentSprite, dirty-flag mood | QUEUED |
| 4 — Culling + atlas split + tile map | Pause offscreen, split CrewSprites, SKTileMapNode floor | QUEUED |
| 5 — Verify | Re-measure. Target: Instruments energy "Low" | QUEUED |

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
