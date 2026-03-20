# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Phase 2: "Mission Control" + "The Office"** — Two parallel tracks

## Strategy

**Dual client approach:**
- **PWA** (web/) — Fast path to Hello Claude. Relay serves it. No Xcode friction.
- **Native iOS** (ios/) — Premium track for gamified office, Apple Watch, haptics. Sideloaded, not App Store.
- Both connect to the same relay server — it's client-agnostic.

## Completed — Phase 1: "Hello Claude"

- [x] Architecture & planning (PLANNING.md)
- [x] Agent roles (6 specialists in `.agents/agents/`)
- [x] GitHub CI/PR workflow
- [x] Relay server scaffold (PR #2) — WebSocket server, session management, protocol types
- [x] iOS app scaffold (PR #3) — SwiftUI shell, WebSocket client, ChatView, ConnectionView
- [x] PWA scaffold (PRs #4–#9) — Svelte 5, WebSocket, chat UI, approval cards, markdown rendering
- [x] Relay CLI adapter rewrite (PR #13) — Agent SDK replaces raw CLI spawn, proper permission handling
- [x] Auto-connect + rendering fix (PR #14) — PWA detects relay origin, text renders from SDK events
- [x] End-to-end phone test via Cloudflare Tunnel — full round trip verified

### Phase 1 Success Criteria — ALL MET

- [x] Can connect to relay server from phone browser
- [x] Can send a prompt and see response
- [x] Can approve/deny tool calls from phone
- [x] Connection auto-reconnects (WebSocket reconnect built in)

## Phase 2 — In Progress

### Track A: "Mission Control" (PWA)
- [x] Inline diff viewer — LCS algorithm, unified/split views, auto-collapse (PR #20)
- [x] Enhanced approval cards — danger scoring, tool-specific details, swipe gestures, Skip button (PR #21)
- [ ] Cost display, streaming indicators
- [ ] Tool activity feed
- [ ] Reconnection UX

### Track B: "The Office" (Native iOS)
- [x] Pixel art sprites — programmatic 16x16 art for all 9 characters, template caching (PR #18)
- [x] Dachshund blanket mechanic — shiver animation, snowflake indicator, cozy overlay (PR #19)
- [ ] Isometric office layout
- [ ] Agent state machines tied to lifecycle events

## Later

- [ ] Stable Cloudflare Tunnel (named tunnel + custom domain, ~$10/yr)
- [ ] Apple Watch companion app (Phase 5)

---

_Last updated: 2026-03-20_
