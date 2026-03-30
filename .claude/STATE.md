# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Phase 8: "Fleet Command"** — Waves 1-4 COMPLETE, Wave 5 next

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

## Completed — Phase 6: "ClaudeGod"

### Track A: ClaudeGod Permission Control (PR #44)
- [x] Permission modes: Manual / Smart / Delay / God (Normal + YOLO)
- [x] Settings.json allowlist matching via PermissionFilter
- [x] Collapsible header, mode switcher pills, countdown toasts
- [x] Mid-response mode switching with pending approval flush
- [x] "Always" button session-scoped allowlist

### Track B: Sprite Bugs (PR #44)
- [x] Subagent desk assignment, alpha recovery, canvas artifacts fixed
- [x] Delay mode freeze fix, Google OAuth button fix

### Track C: Slash Commands — Already existed
- [x] CommandPalette with 13 commands (`/new`, `/clear`, `/compact`, `/model`, `/btw`, etc.)

### Track D: Chat Window Polish (PR #44)
- [x] Code block copy buttons with language header bars
- [x] Smart auto-scroll (only near bottom) + scroll-to-bottom FAB
- [x] Collapsible tool messages with icon/name/status
- [x] Turn separators between conversation cycles
- [x] Relative timestamps on user messages

### Phase 6 Success Criteria — ALL MET
- [x] Permission modes switchable mid-response with pending approval flush
- [x] Settings.json allowlist matching for Smart mode
- [x] Sprite bugs fixed — agents go to desks, stay in bounds
- [x] Chat polish — copy buttons, smart scroll, collapsible tools, timestamps

## Completed — Phase 7: "Multi-Session HQ"

### Track A: IndexedDB Foundation (PR #55)
- [x] Dexie setup — schema v1+v2 (compound PK migration), 5 stores
- [x] Migrate chat messages — per-session [sessionId+messageId] compound PK, bulkPut upserts
- [x] Migrate templates + prompt history + command usage to IndexedDB
- [x] TTL purging — runs on app load, Promise.allSettled for resilient migration
- [x] Dynamic App import — stores don't execute before DB migration

### Track B: Terminal Navigator (PR #55)
- [x] Relay fs handlers — fs.ls, fs.readFile, fs.cwd with path.relative() sandbox + realpath symlink validation
- [x] Relay session.start with workingDir — validated within canonical sandbox root
- [x] PWA terminal UI — cd/ls/cat/pwd parser, monospace output
- [x] "Start Claude Here" button — sandbox-relative path translation

### Track C: Multi-Session UX (PR #55)
- [x] Session panel — slide-out with session list (name, dir, status, cost, agents)
- [x] Per-session isolated state — SessionStateManager with snapshot/restore, serialized persistence
- [x] Session switching — immediate sessionId + localStorage persist, IndexedDB load
- [x] New Session flow — terminal → pick dir → start → auto-switch
- [x] Session naming — auto from dir basename, editable

### Track D: Office Per-Session (PR #55)
- [x] Per-session OfficeEngine + sprite state via OfficeSessionManager
- [x] Lazy rendering — only active session canvas mounted
- [x] Session indicator badge, LRU eviction with rotation guard

### Phase 7 Success Criteria — ALL MET
- [x] IndexedDB replaces localStorage for all persistent data
- [x] Terminal navigator for filesystem browsing and session creation
- [x] Multi-session switching with per-session isolated state
- [x] Office sprites scoped per-session with lazy rendering

## In Progress — Phase 8: "Fleet Command"

### Wave 1: Tech Debt + Error Recovery — COMPLETE

#### Track A: iOS Tech Debt (PR #62, closes #57-61)
- [x] Chat UX polish — scrollToBottomFab animation, scroll position fix, TimelineView countdown, auto-approval badges
- [x] Office scene bugs — dead code removal, demo mode guard, station release, sheet consolidation, cycling timer
- [x] Performance — NSRange bridging, CharacterPreviewScene caching, ToolActivityViewModel dedup
- [x] Data freshness — responseCounter poll pattern, sleep timers removed, workspace tree consolidated, stale device fix
- [x] AppIntents — App Groups UserDefaults IPC for cross-process Siri Shortcuts

#### Track B: Error Recovery (PR #63)
- [x] Health monitor — per-session process watchdog, enhanced /health endpoint
- [x] Push persistence — subscriptions to ~/.major-tom/push-subscriptions.json, VAPID key persistence
- [x] Session resume — EventBufferManager (500 events, 10min TTL), session.resume protocol, seq numbers on broadcasts

### Wave 2: Multi-Instance Relay + Fleet Dashboards — COMPLETE

#### Track C: FleetManager (PR #64)
- [x] FleetManager parent-side orchestrator — forks one worker per unique workingDir
- [x] IPC protocol — typed discriminated unions for parent↔child communication
- [x] Worker script — child process runs ClaudeCliAdapter + SDK session with correct cwd
- [x] Worker lifecycle — crash detection, exponential backoff restart (max 5 attempts)
- [x] Message queuing during worker startup, async session start with acknowledgement
- [x] Parent-side approval mirror for client reconnect re-broadcast
- [x] HealthMonitor refactored to generic HealthMonitorTarget interface
- [x] /health endpoint includes fleet worker status

#### Track D: Fleet Dashboard PWA (PR #65)
- [x] Fleet protocol — fleet.status request/response, fleet.worker.spawned/crashed/restarted events
- [x] Fleet store — Svelte 5 reactive store, auto-polling (5s when panel open), health derivation
- [x] FleetPanel — aggregate stats, per-worker cards with expandable sessions, click-to-switch
- [x] FleetIndicator — header badge with health dot, worker count, 30s background poll
- [x] Toast notifications for worker lifecycle events

#### Track E: Fleet Dashboard iOS (PR #66)
- [x] Fleet message types — FleetStatusResponseEvent, FleetWorkerInfo, FleetSessionInfo in Message.swift
- [x] Fleet data models — FleetStatus, FleetWorker, FleetSession with wire-to-domain conversion
- [x] FleetViewModel — @Observable, 5s auto-refresh, health summary, optimistic UI updates
- [x] FleetDashboardView — sheet with aggregate stat cards, expandable worker list
- [x] FleetWorkerCard — health dot, uptime, restart badge, expandable sessions
- [x] FleetSessionRow — status dot, cost, tap-to-switch
- [x] FleetStatusBadge — compact toolbar pill in ChatView

### Wave 3: Analytics + Smart Notifications — COMPLETE

#### Track F: Analytics Engine (PR #68)
- [x] JSONL analytics log — ~/.major-tom/analytics.jsonl, append per-turn cost/tokens/model/duration/tools
- [x] Relay: analytics collector service — hooks session events, writes JSONL, fleet IPC aggregation
- [x] Relay: GET /api/analytics — time range + groupBy queries, per-session/model/tool aggregation
- [x] PWA: AnalyticsPanel — slide-out with SVG charts (cost bars, token stacked bars, model donut, session ranking, top tools)
- [x] PWA: AnalyticsIndicator — header badge with today's total cost
- [x] iOS: Analytics feature — Swift Charts (BarMark cost, stacked tokens, SectorMark models), session ranking

#### Track G: Smart Notifications (PR #69)
- [x] Relay: priority scorer — high/medium/low based on tool danger, file sensitivity, cost impact
- [x] Relay: quiet hours config — ~/.major-tom/config.json, GET/PUT /api/config/notifications
- [x] Relay: notification digest — batches low-priority, sends summary every N minutes
- [x] PWA: NotificationSettings — quiet hours picker, priority threshold, digest interval
- [x] PWA: priority badges on approval cards — color-coded dots, sorted by priority
- [x] iOS: NotificationSettingsView — quiet hours, priority threshold, digest config synced via relay
- [x] iOS: priority badges on approval cards

### Wave 4: Office 2.0 + Apple Watch + Widgets + Live Activities — COMPLETE

#### Track H: Office 2.0 (PR #70)
- [x] Theme system — day/night cycle tied to real clock, seasonal themes, color palette transitions
- [x] Agent mood system — mood derived from session activity (idle→bored, errors→frustrated, shipping→excited)
- [x] Mood-driven visuals — sprite tinting, speech bubbles, idle behavior preferences
- [x] Agent interactions — idle chat between nearby agents, react to approvals/errors
- [x] PWA: extended OfficeEngine + sprite system with themes/moods/interactions
- [x] iOS: SpriteKit ThemeEngine, MoodEngine, interaction system in OfficeScene

#### Track I: Apple Watch Companion (PR #71)
- [x] watchOS 10+ companion app — WatchConnectivity bridge to iPhone
- [x] Session list and detail views with real-time status updates
- [x] Approve/deny tool requests from watch with haptic feedback
- [x] WidgetKit complications — session count, cost, pending approvals
- [x] PhoneWatchConnectivityService on iPhone side forwarding session data

#### Track J: iOS Widgets (PR #72)
- [x] WidgetKit extension — Small (session count + cost), Medium (top 3 sessions), Large (fleet dashboard)
- [x] App Groups shared container for widget data
- [x] WidgetDataProvider writes session/fleet data to shared UserDefaults
- [x] Timeline refresh on session events via WidgetCenter

#### Track K: Live Activities (PR #73)
- [x] ActivityKit Live Activity for active Claude sessions
- [x] Dynamic Island — compact (session + cost), expanded (full status + approvals)
- [x] Lock Screen — session name, elapsed time, cost, approve/deny buttons via deep links
- [x] LiveActivityManager with debounced updates (3s normal, immediate for approvals)
- [x] MajorTomLiveActivityWidget in shared widget extension bundle

### Wave 5: Achievements + Siri Shortcuts — NEXT

---

_Last updated: 2026-03-30_
