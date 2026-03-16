# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Phase 1: "Hello Claude"** — Foundation + CLI Chat (v1.0)

## Strategy

**Dual client approach:**
- **PWA** (web/) — Fast path to Hello Claude. Relay serves it. No Xcode friction.
- **Native iOS** (ios/) — Premium track for gamified office, Apple Watch, haptics. Sideloaded, not App Store.
- Both connect to the same relay server — it's client-agnostic.

## Completed

- Architecture & planning: Done (PLANNING.md)
- Agent roles: Done (6 specialists in `.agents/agents/`)
- GitHub CI/PR workflow: Done
- **Relay server scaffold** (PR #2, merged) — WebSocket server, CLI adapter, hook system, approval queue, event bus, session management, protocol types
- **iOS app scaffold** (PR #3, merged) — SwiftUI shell, WebSocket client, RelayService, ChatView, ConnectionView, ApprovalCard, MessageBubble, Theme system

## What's Next — PWA Hello Claude Sprint

- [ ] **PWA scaffold** — Web client with WebSocket, chat UI, approval cards, connection management
- [ ] **Hook schema verification** — Verify field names against actual Claude Code hook schema
- [ ] **End-to-end smoke test** — Start relay, open PWA, send prompt, see response
- [ ] **Markdown rendering** — Render Claude's output as markdown

## Phase 1 Success Criteria (from PLANNING.md)

- [ ] Can connect to relay server from phone browser
- [ ] Can send a prompt and see streaming response
- [ ] Can approve/deny tool calls from phone
- [ ] Connection auto-reconnects

## Later — Native iOS Track

- [ ] Xcode project setup (.xcodeproj)
- [ ] SpriteKit gamified office (Phase 3)
- [ ] Apple Watch companion app (Phase 5)

---

_Last updated: 2026-03-16_
