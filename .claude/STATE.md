# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook.
> Update after each phase milestone.

---

## Current Phase

**Wave 3 — Two Parallel Tracks** (Phase 14 SwiftTerm + Ground Control)
Both tracks at Wave 3, independent, zero shared files. Run on separate branches.

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

## Completed — Phase 8: "Fleet Command"

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

### Wave 5: Achievements + Siri Shortcuts — COMPLETE

#### Track L: Relay Achievement Engine (PR #76)
- [x] 30 achievements across 7 categories (Sessions, Approvals, Cost, Agents, Tools, Fleet, Meta)
- [x] AchievementService — atomic writes to ~/.major-tom/achievements.json, debounced 2s persistence
- [x] Counter, event, duration, and composite condition types
- [x] Protocol messages — achievement.unlocked, achievement.progress, achievement.list request/response
- [x] HTTP API — GET /api/achievements, POST /api/achievements/reset
- [x] Event hooks — approval timing, tool tracking, session lifecycle, fleet events, god mode
- [x] Analytics integration — achievement_unlocked event type in JSONL

#### Track M: iOS Siri Shortcuts Expansion (PR #77)
- [x] FleetStatusIntent — inline result with worker count, cost, sessions (no app open)
- [x] SendPromptIntent — text parameter, writes to shared UserDefaults, app sends on foreground
- [x] QuickApproveIntent — approves most recent pending request, opens app for safety
- [x] SessionSummaryIntent — inline result with name, cost, tokens, duration, turns (no app open)
- [x] ToggleGodModeIntent — toggles Manual/God, confirmation dialog (no app open)
- [x] WidgetDataProvider expanded — fleet snapshot, pending approvals, session summary for Siri
- [x] 8 total Siri Shortcuts (3 existing + 5 new)

#### Track N: PWA Achievement UI (PR #78)
- [x] Achievement store — Svelte 5 runes, REST fetch, WebSocket event handlers, auto-polling
- [x] Achievement panel — slide-out with category tabs, progress bars, locked/unlocked states
- [x] Achievement indicator — header badge with trophy icon, pulse on unlock, 60s background poll
- [x] Unlock celebration — success toast with icon on achievement.unlocked events
- [x] IndexedDB persistence — Dexie v3 achievements table, cache-first loading
- [x] Wired into App header and overlay layout

#### Track O: iOS Achievement UI (PR #79)
- [x] Achievement model — Codable struct with category enum, progress computation
- [x] AchievementsViewModel — @Observable, REST fetch, WebSocket events, category filtering
- [x] Achievement views — list with category filter, detail with progress ring, unlock celebration overlay
- [x] Components — AchievementCard, AchievementBadge, ProgressRing
- [x] Office integration — celebration animation with random agent on unlock
- [x] Haptic feedback on unlock (.success pattern)
- [x] CheckAchievementsIntent Siri Shortcut (9 total)

### Phase 8 Success Criteria — ALL MET

- [x] Wave 1: iOS tech debt resolved, error recovery with health monitor + session resume
- [x] Wave 2: Fleet mode with multi-worker relay, fleet dashboards on PWA + iOS
- [x] Wave 3: Analytics engine with charts, smart notifications with priority scoring
- [x] Wave 4: Office 2.0 themes/moods, Apple Watch companion, iOS Widgets, Live Activities
- [x] Wave 5: Achievement engine (30 achievements), expanded Siri Shortcuts (9 total), achievement UI on PWA + iOS

## Completed — Phase 9: "The Social Layer"

### Wave 1: Shared Observation — COMPLETE

#### Track A: Relay — Multi-User Auth + Presence (PR #80)
- [x] User registry — JSON persistence in ~/.major-tom/users/, invite code generation/redemption
- [x] First-user bootstrap — first Google OAuth login auto-creates admin, zero-config migration
- [x] Invite flow — admin generates 8-char code, invitee presents during OAuth, registered with role
- [x] JWT extension — SessionPayload gains userId + role, legacy token fallback via email lookup
- [x] Auth refactor — factory pattern createAuthRoutes(deps), requireRole() helper with role hierarchy
- [x] PresenceManager — tracks userId↔WebSocket↔watchingSession, multi-device support
- [x] Session-scoped broadcast — broadcastToSession() + broadcastToAll() replaces global broadcast()
- [x] Role guard — VIEWER_ALLOWED and ADMIN_ONLY sets in WS message router
- [x] User management messages — user.list/invite/revoke/updateRole handlers

#### Track B: PWA — Presence UI + Shared Sessions (PR #80)
- [x] Presence store — Svelte 5 runes, reactive watcher tracking per session
- [x] PresenceAvatars — avatar stack with picture/initials/overflow, deterministic colors
- [x] UserMenu — header dropdown with avatar, role badge, online count, sign-out
- [x] WatchingIndicator — "X is watching" bar in chat view
- [x] Login flow — invite code detection on 403, pendingCredential re-submit
- [x] Viewer mode — disabled input for viewer role
- [x] Session panel presence — avatar dots on session rows
- [x] IndexedDB v4 — teamUsers table

### Wave 2: Collaboration Features — COMPLETE

#### Track C: Relay — Annotations + Handoff + Activity (PR #81)
- [x] AnnotationStore — per-session JSON persistence at ~/.major-tom/annotations/, debounced writes
- [x] Annotation handlers — annotation.add/list with session-scoped broadcast
- [x] Session ownership — ownerId field on Session, handoff logic (owner/admin only)
- [x] ActivityFeed — in-memory ring buffer (200 entries), records key team actions
- [x] Activity broadcast — session.start, approval resolution events auto-recorded

#### Track D: iOS — Multi-User Experience (PR #81)
- [x] iOS models — TeamUser, UserRole, UserPresence, SessionAnnotation, ActivityEntry
- [x] iOS message types — 22 new types (11 client, 11 server) with Codable structs
- [x] RelayService extension — team state, 7 callbacks, 10 send methods, 11 message handlers
- [x] AuthService — userId + userRole from login response
- [x] TeamSettingsView — member list with online indicators, role badges, invite code generation
- [x] TeamActivityView — chronological feed with action-specific icons, relative timestamps
- [x] Settings navigation — links to Team and Activity views

#### Track E: PWA — Activity + Notifications (PR #81)
- [x] ActivityFeed component — slide-out panel with team activity entries
- [x] ActivityIndicator — header badge toggling feed panel
- [x] NotificationSettings — per-channel toggles (Approvals, @Mentions, Team Activity)
- [x] Relay store — activityEntries/annotations state, annotation/handoff/activity methods

### Phase 9 Success Criteria — ALL MET

- [x] Wave 1: Multi-user auth with invite-based signup, real-time presence tracking, shared session observation
- [x] Wave 1: Role enforcement (admin/operator/viewer), viewer mode with disabled input
- [x] Wave 1: First-user bootstrap with zero-config migration for existing single-user setups
- [x] Wave 2: Session annotations with @mention support
- [x] Wave 2: Session ownership and handoff between users
- [x] Wave 2: Team activity feed recording key actions
- [x] Wave 2: iOS multi-user experience with team settings and activity views
- [x] Wave 2: Per-channel notification settings

## Completed — Phase 10: "Lockdown"

- [x] Wave 1: Audit trail — AuditLogger, per-session JSON logs, admin viewer (PR #82)
- [x] Wave 2: Per-role rate limiting — sliding window, configurable limits (PR #83)
- [x] Wave 3: Directory sandboxing — SandboxGuard, per-user chroot, fs/git path validation (PR #84-85)

## Completed — Phase 11: "The Pipeline"

### Wave 1: Git Viewer (PR #86)
- [x] Relay: git.ts handler factory — status, diff, log, branches, show via execFile
- [x] PWA: GitPanel slide-out with Status/Log/Branches tabs, inline diff viewer
- [x] iOS: GitPanelView sheet with matching tabs and diff renderer

### Wave 2: GitHub Integration (PR #87)
- [x] Relay: github.ts handler using gh CLI proxy — PRs, Issues, PR detail, Issue detail
- [x] PWA: GitHubPanel with expandable detail (checks, reviews, comments), state filters
- [x] iOS: GitHubPanelView with PR/Issues views, tap-to-expand detail

### Wave 3: CI Dashboard (PR #88)
- [x] Relay: ci.ts handler — run list, run detail with jobs via gh CLI
- [x] PWA: CIDashboardPanel with auto-refresh (30s), branch filter, job status/duration
- [x] iOS: CIPanelView with auto-refresh timer, status icons, conclusion badges

### Phase 11 Architecture
- All ops proxy through gh/git CLI via execFile (no shell, no tokens exposed)
- Handler factory pattern (closure-based) — git.ts, github.ts, ci.ts
- VIEWER_ALLOWED role access — read-only by default
- Session-scoped working directory for all operations

### Phase 11 Success Criteria — ALL MET
- [x] Git status, diff, log, branches, show from mobile
- [x] GitHub PRs with checks/reviews/comments
- [x] GitHub issues with labels/assignees/detail
- [x] CI run monitoring with auto-refresh and job detail
- [x] All operations sandboxed to session working directory

## Completed — Phase 13: "The Shell"

Phase 13 turned the PWA's main surface into a real tmux-backed terminal. Full spec: `docs/PHASE-13-THE-SHELL.md`.

### Wave 1: PTY Foundation (PRs #89-91)
- [x] tmux-backed terminal via xterm.js, `node-pty` PTY adapter
- [x] Env injection (`CLAUDE_CONFIG_DIR`, `MAJOR_TOM_RELAY_PORT`, `MAJOR_TOM_TAB_ID`)
- [x] Termius-style three-layer soft keyboard (accessory, specialty, customize sheet)
- [x] Login shell, cwd handling, prompt-line lock
- [x] Shell tab behind `?shell=1` feature flag (removed in Wave 2.5)

### Wave 2: Approval Routing + Three Modes (PR #92)
- [x] Three orthogonal routing modes: `local` (TUI owns), `remote` (phone owns, hook blocks), `hybrid` (race)
- [x] Hook installer — idempotent, sha256 hash-versioned, NEVER touches `~/.claude/`
- [x] Hook templates: `pretooluse.sh`, `subagent-start.sh` (Wave 2 placeholder)
- [x] Hook HTTP server on loopback port 9091 (separate from Fastify WS 9090)
- [x] REST endpoints: `/api/approvals/pending`, `/api/approvals/:id/decision`, `/api/settings/approval-mode`
- [x] `tool_use_id` dedup between SDK + hook paths
- [x] Push notification batching, bypass-mode escape hatch, SW action buttons

### Wave 2.5: Shell QA / Mobile Polish (PR #93)
- [x] CLI tab is now default on every load (feature flag removed)
- [x] Mobile padding + font zoom, collapsible "Add a key" panel
- [x] Tab activation redraw via relay control frame + tmux resize wobble
- [x] Sticky Ctrl latch in shared `keybarModifiers` singleton
- [x] Default accessory row includes pgup/pgdn/lbracket

### Wave 2.6: Precise tmux session handling (PR #94)
- [x] Per-attach grouped view sessions (`view-${tabId}-${hex}`) — fixes multi-device attach stomping
- [x] Tab close: `{type:'kill'}` control frame + REST fallback `POST /shell/:tabId/kill`
- [x] `CloseTabConfirm.svelte` — native `<dialog>.showModal()` for safe close UX
- [x] `dispose()` is single source of truth for handle cleanup
- [x] killWindow/killSession error surfacing with race-recheck

### Wave 2.7: Drag-to-scroll + iOS QuickType suppression (PR #95)
- [x] Tap-and-drag scroll through tmux copy mode on touch devices
- [x] Per-tab copy-mode state with toggle dispatch
- [x] Pointer capture drag handlers (touch-only gate for iPadOS trackpad compat)
- [x] iOS QuickType bar suppression on xterm helper textarea
- [x] Visual fix: tmux-scroll button highlight gated on `copyModeActive`

### Wave 3: Sprite Re-Wire (PR #96)
- [x] SDK adapter: inline `PreToolUse(Task)`, `SubagentStart`, `SubagentStop` hooks on `unstable_v2_createSession`
- [x] FIFO correlation via `pendingTaskByToolUseId` map (30s TTL GC) recovers task description for sprite labels
- [x] Deleted old `task_started`/`task_progress`/`task_notification` system-event heuristic — dead
- [x] PTY shell hooks: new `FleetManager.reportAgentLifecycle()` seam, `/hooks/subagent-stop` endpoint
- [x] New `subagent-stop.sh` hook template, installer registers `SubagentStop` in `settings.json`
- [x] Both SDK + PTY paths funnel into `fleetManager.emit('agent-lifecycle')` → ws.ts downstream fanout

### Phase 13 Hard Constraints (still apply)
1. NEVER touch user's real `~/.claude/` — Major Tom uses `$HOME/.major-tom/claude-config/` via `CLAUDE_CONFIG_DIR`
2. NEVER use default tmux socket — always `tmux -L major-tom`
3. Preserve `manual`/`auto`/`delay`/`god` modes (inner dimension) and `local`/`remote`/`hybrid` routing (outer dimension)
4. iOS frozen at chat model until Phase 14+ (SwiftTerm)
5. Chat layer preserved as reference implementation for future VSCode chat participant phase

---

## What's Next — TWO PARALLEL TRACKS (Wave 3)

PWA + Relay MVP shipped 2026-04-09. Both tracks independent — zero shared files, parallel branches.

### Track 1: Phase 14 "SwiftTerm" — Wave 3: Multi-Tab Support
**Spec:** `docs/PHASE-14-SWIFTTERM.md` (Wave 3 section)
**Branch:** `phase-14/swiftterm-wave3`
**Previous:** Wave 1 (PR #97) + Wave 2 (PR #99) merged — terminal rendering + native keybar working

**Wave 3 deliverables:**
- `TerminalTabBar.swift` — horizontal scrolling tab bar with + button
- `CloseTabConfirm.swift` — confirmation sheet for closing tabs with active processes
- `TerminalViewModel.swift` — extend with multi-tab state management, tab CRUD
- `TerminalView.swift` — stack tab bar above WKWebView

**Acceptance criteria:**
- Tab bar shows current tabs with titles
- "+" button creates new tmux window
- Tapping a tab switches to that window
- Close button with confirmation dialog
- Tab titles update from xterm title sequence

**Known issue:** Widget extension (MajorTomWidgets.appex) fails to install on simulator — "Invalid placeholder attributes" / missing NSExtension in auto-generated Info.plist. App itself works fine without it. Not blocking.

### Track 2: Ground Control — Wave 3: Dashboard
**Spec:** `docs/GROUND-CONTROL.md` (Wave 3 section)
**Branch:** `ground-control/wave3-dashboard`
**Previous:** Wave 1 (PR #98) + Wave 2 (PR #100) merged — menu bar app + log viewer working

**Wave 3 deliverables:**
- `DashboardView.swift` — overview cards with live data (status, uptime, clients, sessions)
- `RelayClient.swift` — HTTP client hitting relay's `/api/health` endpoint
- `HealthData.swift` — parsed health response model
- `ClientListView.swift` — connected clients list with device info
- Relay-side: extend `/api/health` with admin metrics (client count, per-client info, node memory)

**Acceptance criteria:**
- Dashboard shows server status, uptime, port, client count
- Connected clients list with IP, user agent, connection duration
- Active sessions with ID, working dir, status
- Process resource usage (CPU%, memory)
- Auto-refresh every 5 seconds

**Build notes:** Ground Control uses SwiftPM (`macos/`). Build with `cd macos && swift build`. Uses system node in dev (auto-discovers `relay/dist/server.js` by walking up from cwd). Requires `npm run build` in relay/ first.

### Completed Waves (for reference)
- **SwiftTerm Wave 1** (PR #97): WKWebView + bundled xterm.js, terminal.html, TerminalView, TerminalWebView, TerminalViewModel
- **SwiftTerm Wave 2** (PR #99): NativeKeybar.swift, SpecialtyKeyGrid.swift, KeySpec.swift, haptic feedback
- **Ground Control Wave 1** (PR #98): MenuBarExtra, RelayProcess, NodeBundleManager, start/stop relay
- **Ground Control Wave 2** (PR #100): ManagementWindow, LogView, LogEntry, LogStore (10k ring buffer, level filtering)
- **QA Polish** (PR #101): NavigationDrawer, keybar sync, viewport lock, done notification, build.sh

### Deferred Tracks (not scheduled)
- Phase 12 "Glow Up" — sprite makeover (skipped, still valid)
- VSCode Chat Bridge — `@major-tom` chat participant (see `docs/FUTURE-PHASE-VSCODE-CHAT-BRIDGE.md`)
- Tech debt burn-down — 10 open GitHub issues

---

_Last updated: 2026-04-09_
