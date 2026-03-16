# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Pre-Implementation** — Planning complete, infrastructure being set up

## Repo Status

- Architecture & planning: Done (PLANNING.md)
- Agent roles: Done (6 specialists in `.agents/agents/`)
- Skills: Partial (iOS/SwiftUI/VSCode installed, more needed)
- GitHub CI/PR workflow: Done
- Source code: None yet

## What's Next

Phase 1: "Hello Claude" — Foundation + CLI Chat (v1.0)
- Relay server scaffold (WebSocket + adapter interface)
- CLI adapter (PTY spawn, stdin/stdout, session management)
- Hook system (pre-tool-use, approval flow)
- iOS app scaffold (SwiftUI shell, WebSocket client)
- Chat UI + Approval UI

## Skills Needed Before Phase 1

- [ ] WebSocket server patterns (ws library)
- [ ] node-pty usage patterns
- [ ] Claude Code hooks reference
- [ ] SpriteKit game dev (for Phase 3, not urgent)

---

_Last updated: 2026-03-15_
