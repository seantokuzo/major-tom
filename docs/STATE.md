# Project State

> Auto-injected into fresh sessions. Keep concise.

## Current Phase

Two parallel tracks running on `main` (no long-lived branches — each wave is a short-lived PR branch):

### Ground Control (macOS relay manager)

Spec: `docs/GROUND-CONTROL.md`

| Wave | Status | PR |
|------|--------|----|
| 1 — Scaffold & Process Management | DONE | #98 |
| 2 — Log Viewer | DONE | #100 |
| 3 — Dashboard | DONE | #102 |
| **4 — Configuration** | **NEXT** | — |
| 5 — Security & Polish | TODO | — |

**Wave 4 scope:** GUI settings editor (ConfigView), Keychain secrets (OAuth creds, tunnel token), config.json read/write, CloudflareTunnelView, "Apply & Restart" flow.

### Phase 14 "SwiftTerm" (iOS native terminal)

Spec: `docs/PHASE-14-SWIFTTERM.md`

| Wave | Status | PR |
|------|--------|----|
| 1 — Basic Terminal Rendering | DONE | #97 |
| 2 — Keyboard & Input | DONE | #99 |
| 3 — Multi-Tab Support | DONE | #103 |
| **4 — Customization & Sync** | **NEXT** | — |
| 5 — Polish & Integration | TODO | — |

**Wave 4 scope:** Keybar reorder/customize (KeybarCustomizer), theme picker (TerminalTheme, TerminalSettingsView), font size slider, relay preference sync via `/api/user/preferences`.

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
| QA | PWA Polish | #101 |
