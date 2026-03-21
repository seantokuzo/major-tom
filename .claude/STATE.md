# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Phase 5: "Power User"** — Voice, templates, history, sessions, pairing, file context — COMPLETE

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

## Completed — Phase 2: "Mission Control" + "The Office"

### Track A: "Mission Control" (PWA)
- [x] Inline diff viewer — LCS algorithm, unified/split views, auto-collapse (PR #20)
- [x] Enhanced approval cards — danger scoring, tool-specific details, swipe gestures, Skip button (PR #21)
- [x] Cost display, streaming indicators — per-turn cost, token breakdown, thinking/tool spinners (PR #22)
- [x] Reconnection UX — toast notifications, status bar, connection error handling (PR #23)
- [x] Tool activity feed — real-time tool tracking, collapsible panel, duration/success (PR #25)

### Track B: "The Office" (PWA)
- [x] Pixel art sprites — programmatic 16x16 art for all 9 characters, template caching (PR #18)
- [x] Dachshund blanket mechanic — shiver animation, snowflake indicator, cozy overlay (PR #19)
- [x] Office canvas + agent state machine — pixel art office, agent sprites, lifecycle events, inspector (PR #24)

### Phase 2 Success Criteria — ALL MET

- [x] Cost and token usage visible per-turn and cumulative
- [x] Streaming/thinking/tool indicators visible during agent work
- [x] Reconnection with toast feedback and status bar
- [x] Tool activity feed with real-time tracking
- [x] The Office: agents visualized as pixel art characters in an office scene
- [x] Agent lifecycle (spawn → work → idle → complete → dismiss) drives office animations

## Completed — Phase 3: "Never Miss an Approval"

- [x] Relay: Web push notification support — VAPID keys, subscription endpoints, notification batcher (PR #26)
- [x] PWA: Service worker + push notification UI — SW registration, permission toggle, notification click routing (PR #27)
- [x] Cloudflare named tunnel — setup script, start script, npm scripts, README (PR #28)

### Phase 3 Success Criteria — ALL MET

- [x] Push notifications fire on approval requests (native OS notifications)
- [x] Notification batcher prevents spam (2s debounce window)
- [x] Clicking notification opens/focuses the app
- [x] NotificationToggle UI for enable/disable
- [x] Named Cloudflare Tunnel with one-time setup + daily `npm run dev:remote`
- [x] SW gated behind production mode (no dev HMR breakage)

## Completed — Phase 4: "Steering & Security"

### Track A: Agent Steering
- [x] Agent message routing with context wrapping — relay wraps user text with agent role/task (PR #29)
- [x] Agent inspector message UI — text input + send in Office inspector (PR #29)
- [x] Agent tracker populated on lifecycle events for context lookup (PR #29)

### Track B: Auth & Security Hardening
- [x] Shared HTTP helpers — readBody (with size limit), sendJson, getCorsOrigin, requireAuth (PR #30)
- [x] Token auth — auto-generated 32-char hex token, WS upgrade auth, push endpoint auth (PR #30)
- [x] CORS hardening — origin whitelist, Vary: Origin headers (PR #30)
- [x] PWA auth settings UI — token input, localStorage persistence, reconnect on change (PR #30)
- [x] Dotenv loading — inline loader + --env-file flag for .env persistence (PR #30)

### Phase 4 Success Criteria — ALL MET
- [x] Click agent in Office → type message → send → routed with context to main session
- [x] WS connections without valid token rejected with 401
- [x] Push subscribe/unsubscribe require Bearer token
- [x] Health check and VAPID key remain public
- [x] CORS uses configured origins (not hardcoded `*`)
- [x] hook-server readBody has size limit (fixes DoS)
- [x] PWA settings UI for token entry, persists in localStorage

## Completed — Phase 5: "Power User"

### Wave 1
- [x] A1: Voice Input (PR #31) — Web Speech API mic button
- [x] A2: Prompt Templates (PR #32) — save/search/reuse prompts
- [x] A3: Prompt History (PR #33) — arrow-up cycling, search overlay
- [x] B1: Session List + Metadata (PR #34) — session drawer, cost/token tracking
- [x] C1: PIN Pairing Relay (PR #35) — 6-digit PIN, device registry, rate limiting

### Wave 2
- [x] B2: Session Persistence (PR #37) — transcript replay, disk persistence
- [x] C2: PWA Pairing Flow (PR #36) — PIN entry screen, auto-connect
- [x] C3: Device Management (PR #38) — device list, revoke paired devices
- [x] A4: @file Context (PR #39) — workspace tree browser, context chips

### Phase 5 Success Criteria — ALL MET
- [x] Voice input via Web Speech API
- [x] Prompt templates with save/search/reuse
- [x] Prompt history with arrow-up cycling and search
- [x] Session list with metadata and history replay
- [x] Session persistence across relay restarts
- [x] PIN pairing for new device onboarding
- [x] Device management with revoke capability
- [x] @file context attachment for workspace files

---

_Last updated: 2026-03-21_
