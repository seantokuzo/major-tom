# Major Tom — Planning Document

> Control Claude Code from your iPhone. Watch your AI agents work in a gamified Zelda-style office. Ship code from the couch.

---

## Vision

Major Tom is a native iOS app that gives you **complete mobile control** over Claude Code sessions running on your Mac — both CLI sessions and the VSCode extension. When you leave your desk, your AI keeps working. You steer it from your phone.

**But we're not just building a remote control.** We're building a fucking beautiful, gamified visualization of your AI workforce. Think tiny Zelda-style pixel office where your Claude orchestrator and subagents are little characters — moving to their desks when you spawn them on tasks, hanging in the break room when idle, and tappable to see their thought streams in real-time.

### Core Pillars

1. **Complete Mobile Control** — Type prompts, approve/deny tool calls, press every button Claude Code shows you
2. **Multi-Target Support** — Claude Code CLI, Claude Code VSCode extension, (legacy Copilot if needed)
3. **Gamified Agent Visualization** — Zelda-style pixel office with animated agent characters
4. **Steve Jobs Would Cry UI** — Beautiful, intuitive, zero-friction interface
5. **Personal Use** — iOS only, built for one user, optimized for joy

---

## Architecture

### High-Level Overview

```
┌───────────────────────┐              ┌─────────────────────────────────┐
│    iOS App            │              │    Mac                          │
│    ┌───────────────┐  │     WSS      │    ┌───────────────────────┐   │
│    │ Control UI    │  │◄────────────►│    │   Relay Server        │   │
│    │ (SwiftUI)     │  │              │    │   (Node.js + TS)      │   │
│    ├───────────────┤  │              │    ├───────────┬───────────┤   │
│    │ Agent Office  │  │              │    │ CLI       │ VSCode    │   │
│    │ (SpriteKit)   │  │              │    │ Adapter   │ Adapter   │   │
│    └───────────────┘  │              │    └─────┬─────┴─────┬─────┘   │
└───────────────────────┘              │          │           │         │
                                       │    ┌─────▼─────┐ ┌──▼───────┐ │
                                       │    │Claude Code│ │Claude    │ │
                                       │    │CLI (PTY + │ │Code VSC  │ │
                                       │    │Hooks)     │ │Extension │ │
                                       │    └───────────┘ └──────────┘ │
                                       └─────────────────────────────────┘
```

### Components

#### 1. iOS App (Swift + SwiftUI + SpriteKit)

The app has two primary modes:

**Control Mode** — Full Claude Code remote control
- Chat interface for sending prompts
- Approval action sheets (Allow / Skip / Deny / Allow Always)
- Live streaming output viewer
- File context browser
- Session management

**Office Mode** — Gamified agent visualization
- SpriteKit-rendered pixel art office
- Animated characters representing orchestrator + subagents
- Characters move between desks (working) and break areas (idle)
- Tap character → see live thought stream + steer if desired
- Real-time updates via WebSocket events

| Concern | Technology |
|---------|-----------|
| UI Framework | SwiftUI (iOS 17+, @Observable) |
| Game Engine | SpriteKit (embedded in SwiftUI via SpriteView) |
| Networking | URLSessionWebSocketTask + async/await |
| Auth | PIN-based device pairing → token auth (no OAuth — personal use). See Security & Pairing Protocol. |
| Storage | SwiftData (sessions), Keychain (secrets), UserDefaults (prefs) |
| Voice | Speech framework (dictation) |
| Notifications | APNs via local relay |

#### 2. Relay Server (Node.js + TypeScript)

The relay server is the hub — runs on your Mac, bridges iOS app to Claude Code.

**Core Responsibilities:**
- WebSocket server for iOS app connections
- Adapter pattern for multiple targets (Claude Code CLI, Claude Code VSCode)
- Event bus for agent lifecycle events
- Session management and persistence

**Adapter: Claude Code CLI**
- Spawns Claude Code in a PTY (pseudo-terminal) via `node-pty`
- Captures all stdout/stderr for streaming to iOS
- Sends stdin for user input (prompts)
- Configures Claude Code hooks for structured event capture:
  - `PreToolUse` → sends approval request to iOS, waits for response
  - `PostToolUse` → sends tool result to iOS
  - `Notification` → forwards agent lifecycle events
- Hooks communicate with relay via local HTTP (hook script → relay → iOS → relay → hook script)

**Adapter: Claude Code VSCode Extension**
- Companion VSCode extension that bridges to relay server
- Intercepts Claude Code's webview panel interactions
- Forwards chat input/output, approval dialogs, and UI state
- Enables typing into Claude Code's chat and pressing action buttons remotely

**Key Design Decisions:**
- **Adapter Pattern** — Each target (CLI, VSCode) implements a common interface
- **Event-Driven** — All communication is event-based (not polling)
- **Hook-Based Approval** — Claude Code's native hook system handles the approval flow
- **No Cloud** — Everything runs locally on your network (Tailscale for remote)

#### 3. Claude Code Hook Scripts

Small scripts configured in Claude Code's settings that bridge to the relay server:

```
Claude Code → Hook Script → HTTP POST to Relay → WebSocket to iOS
                                                         ↓
Claude Code ← Hook Script ← HTTP Response from Relay ← User Decision
```

**Hook: `pre-tool-use.sh`**
- Receives tool call JSON on stdin
- POSTs to relay server `/hooks/pre-tool-use`
- Blocks until relay returns approval decision
- Outputs `{"decision": "allow|deny|skip"}` to stdout

**Hook: `post-tool-use.sh`**
- Receives tool result JSON on stdin
- POSTs to relay server `/hooks/post-tool-use`
- Non-blocking (fire and forget)

**Hook: `notification.sh`**
- Receives notification JSON on stdin
- POSTs to relay server `/hooks/notification`
- Captures agent spawn/complete events for office visualization

#### 4. Companion VSCode Extension

Lightweight extension that provides the bridge between Claude Code's VSCode UI and the relay server.

**Capabilities:**
- Detect Claude Code extension presence and state
- Intercept/forward approval dialogs
- Programmatically interact with Claude Code's chat input
- Forward UI state changes (model selection, active file, etc.)
- Stream editor events (file changes, terminal output, diagnostics)

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **iOS App** | Swift 5.9+, SwiftUI, SpriteKit, iOS 17+ | Modern Swift concurrency, @Observable, native game engine |
| **Relay Server** | Node.js 22+, TypeScript, `ws`, `node-pty` | PTY support, WebSocket, fast iteration |
| **Hook Scripts** | Bash + curl (or Node.js) | Minimal footprint, Claude Code native |
| **VSCode Extension** | TypeScript, VSCode Extension API | Required for VSCode integration |
| **Pixel Art** | Aseprite / Pixelorama → SpriteKit atlas | Zelda-style 16x16 or 32x32 sprites |
| **Communication** | WebSocket (binary + JSON) | Real-time, bidirectional, low latency |

---

## Project Structure

```
major-tom/
├── CLAUDE.md                          # Project-level AI instructions
├── README.md
├── docs/
│   ├── PLANNING.md                    # This file
│   ├── ARCHITECTURE.md                # Technical deep-dive
│   └── PROTOCOL.md                    # WebSocket message protocol spec
│
├── ios/                               # Xcode project
│   └── MajorTom/
│       ├── App/
│       │   └── MajorTomApp.swift
│       ├── Features/
│       │   ├── Control/               # Chat, approvals, remote control
│       │   │   ├── Views/
│       │   │   ├── ViewModels/
│       │   │   └── Components/
│       │   ├── Office/                # Gamified agent visualization
│       │   │   ├── Scenes/            # SpriteKit scenes
│       │   │   ├── Sprites/           # Character sprites & animations
│       │   │   ├── Views/             # SwiftUI wrappers
│       │   │   └── Models/            # Agent state models
│       │   ├── Connection/            # Server pairing & status
│       │   └── Settings/
│       ├── Core/
│       │   ├── Networking/            # WebSocket client, message codec
│       │   ├── Models/                # Shared domain models
│       │   ├── Services/              # Business logic services
│       │   └── Theme/                 # Design system, colors, typography
│       └── Resources/
│           ├── Assets.xcassets
│           └── Sprites/               # Sprite atlases
│
├── relay/                             # Relay server
│   ├── src/
│   │   ├── server.ts                  # Entry point
│   │   ├── adapters/
│   │   │   ├── adapter.interface.ts   # Common adapter interface
│   │   │   ├── claude-cli.adapter.ts  # CLI PTY adapter
│   │   │   └── claude-vsc.adapter.ts  # VSCode extension adapter
│   │   ├── events/                    # Event bus, agent lifecycle
│   │   ├── hooks/                     # HTTP endpoints for hook scripts
│   │   ├── protocol/                  # Message types, codec
│   │   └── sessions/                  # Session management
│   ├── hooks/                         # Claude Code hook scripts
│   │   ├── pre-tool-use.sh
│   │   ├── post-tool-use.sh
│   │   └── notification.sh
│   ├── package.json
│   └── tsconfig.json
│
├── vscode-extension/                  # Companion VSCode extension
│   ├── src/
│   │   └── extension.ts
│   ├── package.json
│   └── tsconfig.json
│
└── .agents/                           # AI agent directives
    ├── skills/                        # Installed skills
    └── agents/                        # GSD-style agent files
        ├── mt-orchestrator.md         # Thin orchestrator
        ├── mt-ios-engineer.md         # iOS/SwiftUI specialist
        ├── mt-relay-engineer.md       # Node.js relay specialist
        ├── mt-extension-engineer.md   # VSCode extension specialist
        ├── mt-sprite-artist.md        # SpriteKit/pixel art specialist
        └── mt-researcher.md           # Research & Context7 specialist
```

---

## Features

### v1.0 — Foundation ✅ COMPLETE

| ID | Feature | Status |
|----|---------|--------|
| F01 | **Claude Code CLI Chat** | ✅ Send prompts, see responses |
| F02 | **Approval Flow** | ✅ Allow / Skip / Deny / Allow Always |
| F03 | **Live Output Stream** | ✅ Streaming markdown-rendered output |
| F04 | **Connection Management** | ✅ Auto-connect, auto-reconnect, tunnel support |
| F05 | **Session Management** | ✅ Start sessions via Agent SDK |

### v1.1 — Mission Control MVP ✅ COMPLETE

| ID | Feature | Status |
|----|---------|--------|
| F06 | **Session Persistence** | ✅ Chat history + session ID in localStorage (PR #16) |
| F07 | **ClaudeGod Mode** | ✅ Auto-approve with delay countdown (PR #16) |
| F08 | **Command Palette** | ✅ `/` trigger, searchable, frequency-sorted (PR #16) |
| F09 | **Slash Commands** | ✅ `/new`, `/clear`, `/plan`, `/compact`, `/model`, `/btw` (PR #16) |
| F10 | **Cost & Usage Display** | ✅ Per-turn cost, running total, token breakdown (PR #22) |
| F11 | **Streaming Indicator** | ✅ Thinking/tool spinners, active tool name (PR #22) |
| F12 | **CLI-Like Chat UI** | ✅ Monospace, tightened layout (PR #16) |

### v1.2 — Mission Control+ ✅ COMPLETE

| ID | Feature | Status |
|----|---------|--------|
| F13 | **Mobile Diff Viewer** | ✅ LCS algorithm, unified/split views, auto-collapse (PR #20) |
| F14 | **Tool Activity Feed** | ✅ Real-time timeline, duration/success, collapsible I/O (PR #25) |
| F15 | **Agent Activity Panel** | ✅ Agent inspector with status, task, uptime (PR #24) |
| F16 | **Better Approval Cards** | ✅ Danger scoring, tool-specific details, swipe gestures (PR #21) |
| F17 | **Push Notifications** | ⬜ Deferred to v3.0 |
| F17b | **Reconnection UX** | ✅ Toast notifications, status bar, error handling (PR #23) |

### v2.0 — The Office ✅ COMPLETE (PWA)

| ID | Feature | Status |
|----|---------|--------|
| F18 | **Office Scene** | ✅ Canvas-based office with desks, break areas, door (PR #24) |
| F19 | **9 Characters** | ✅ Pixel art sprites, 5 humans + 4 dogs (PR #18, #24) |
| F20 | **Agent Lifecycle** | ✅ Spawn → desk → work → idle → celebrate → exit (PR #24) |
| F21 | **Dachshund Blanket Mechanic** | ✅ Shiver animation, snowflake, cozy overlay (PR #19) |
| F22 | **Mini-Map + Follow** | ⬜ Deferred |
| F23 | **Tap to Inspect** | ✅ Agent inspector with status, task, rename (PR #24) |
| F24 | **Rename Characters** | ✅ Rename from inspector panel (PR #24) |

### v2.1 — Delight

| ID | Feature | Description |
|----|---------|-------------|
| F25 | **Voice Prompts** | Speech-to-text input |
| F26 | **Prompt Templates** | Save, organize, reuse |
| F27 | **Desk Customization** | Tap desk → upload photo or pick from files |
| F28 | **Agent Steering** | Send prompts to specific agents from inspector |
| F29 | **Custom Characters** | README guide for prompting Claude to create new sprites |
| F30 | **Haptic Feedback** | Satisfying haptics for approvals (native) |
| F31 | **Push Notification Actions** | Allow/Deny directly from iOS notification |

### v3.0 — Everywhere

| ID | Feature | Description |
|----|---------|-------------|
| F32 | **Apple Watch** | Approve/deny from wrist, connection status |
| F33 | **Home Screen Widget** | WidgetKit — status, pending approvals, agent count |
| F34 | **Stable Tunnel** | Named Cloudflare Tunnel + custom domain for PWA install |

### Deprioritized (Backlog)

| ID | Feature | Notes |
|----|---------|-------|
| F-B1 | VSCode Extension Bridge | CLI-only for foreseeable future |
| F-B2 | GitHub PR Status | Use GitHub app directly |
| F-B3 | CI/CD Pipeline View | Same |
| F-B4 | Copilot Support | Legacy, unlikely needed |

---

## User Stories

### Connection & Setup

- **US-001:** As a user, I can pair my device with my Mac's relay server via PIN code (v1.0) or QR code (v2.0+)
- **US-002:** As a user, I can see connection status (connected/disconnected/reconnecting) at a glance
- **US-003:** As a user, my connection auto-reconnects if interrupted
- **US-004:** As a user, I can have the relay server auto-start on Mac login

### Claude Code CLI Control

- **US-010:** As a user, I can start a new Claude Code CLI session from my phone
- **US-011:** As a user, I can attach to an already-running Claude Code CLI session
- **US-012:** As a user, I can send text prompts to Claude Code
- **US-013:** As a user, I can see Claude Code's responses streaming in real-time with markdown rendering
- **US-014:** As a user, I can see tool calls as they happen (file reads, edits, bash commands, etc.)
- **US-015:** As a user, I can approve or deny tool calls (Allow / Skip / Deny / Allow Always)
- **US-016:** As a user, I can cancel/interrupt a running operation
- **US-017:** As a user, I can see the current context usage (tokens used / remaining)

### Claude Code VSCode Control

- **US-020:** As a user, I can type into Claude Code's VSCode chat input from my phone
- **US-021:** As a user, I can press action buttons (Allow, Skip, Disallow, etc.) in the VSCode chat
- **US-022:** As a user, I can see the full conversation in the VSCode chat panel mirrored on my phone
- **US-023:** As a user, I can switch between CLI and VSCode targets

### Live Visibility

- **US-030:** As a user, I can see which files Claude Code is currently reading or editing
- **US-031:** As a user, I can see terminal output from commands Claude Code runs
- **US-032:** As a user, I can see syntax-highlighted diffs of code changes
- **US-033:** As a user, I can see git status (branch, uncommitted changes, ahead/behind)
- **US-034:** As a user, I can see errors/warnings count in the workspace

### Agent Office (Gamification)

- **US-040:** As a user, I can see a pixel art office with desks, break rooms, and decorations
- **US-041:** As a user, I can see a character for the main Claude orchestrator
- **US-042:** As a user, I can see new characters appear when subagents are spawned
- **US-043:** As a user, I can see characters walk to their desk when assigned a task
- **US-044:** As a user, I can see characters walk to a break room when their task completes
- **US-045:** As a user, I can tap a character to see their current task and output stream
- **US-046:** As a user, I can send a message to a specific agent from the inspection view
- **US-047:** As a user, I can see visual indicators of agent state (working animation, idle animation, error state)
- **US-048:** As a user, characters disappear when subagents are dismissed

### Smart Prompting

- **US-050:** As a user, I can dictate prompts using voice-to-text
- **US-051:** As a user, I can save prompts as reusable templates
- **US-052:** As a user, I can browse and search my prompt history
- **US-053:** As a user, I can add file context (@file) by browsing the workspace tree

### Workspace Context

- **US-060:** As a user, I can browse the workspace file tree
- **US-061:** As a user, I can add files to chat context (@file reference)
- **US-062:** As a user, I can add folders to chat context (@folder reference)
- **US-063:** As a user, I can see which files are currently in context
- **US-064:** As a user, I can quick-add recently edited files

### Notifications

- **US-070:** As a user, I receive push notifications when approval is needed
- **US-071:** As a user, I receive notifications when long-running tasks complete
- **US-072:** As a user, I receive alerts when errors are detected
- **US-073:** As a user, I receive idle alerts when Claude Code is waiting for input
- **US-074:** As a user, I can configure which notifications I want

### Session Management

- **US-080:** As a user, I can see a list of past sessions
- **US-081:** As a user, I can resume a previous session
- **US-082:** As a user, I can start a fresh session
- **US-083:** As a user, I can see session metadata (duration, tokens used, files changed)

### Settings & UX

- **US-090:** As a user, the app defaults to dark mode with a beautiful design
- **US-091:** As a user, I get haptic feedback on approval actions
- **US-092:** As a user, I can configure my relay server connection
- **US-093:** As a user, I can view code with syntax highlighting

---

## Requirements

### Functional Requirements

| ID | Requirement | Features |
|----|-------------|----------|
| FR-001 | App must establish and maintain WebSocket connection to relay server | F04 |
| FR-002 | App must send/receive structured JSON messages per the protocol spec | F01, F02 |
| FR-003 | Relay must spawn and manage Claude Code CLI sessions via PTY | F01 |
| FR-004 | Relay must configure Claude Code hooks for structured event capture | F02 |
| FR-005 | Hook scripts must POST to relay and block until approval decision is returned | F02 |
| FR-006 | App must render streaming markdown output in real-time | F03 |
| FR-007 | App must display approval requests with action buttons | F02 |
| FR-008 | App must send approval decisions back through the relay → hook pipeline | F02 |
| FR-009 | Relay must support multiple adapter types (CLI, VSCode) | F01, F06 |
| FR-010 | VSCode companion extension must bridge Claude Code UI interactions | F06 |
| FR-011 | App must render SpriteKit office scene with animated characters | F11, F12 |
| FR-012 | Relay must emit agent lifecycle events (spawn, working, idle, complete) | F13 |
| FR-013 | App must map agent lifecycle events to character animations and positions | F13 |
| FR-014 | App must support tapping characters to inspect agent state | F14 |
| FR-015 | App must forward messages to specific agents via relay | F15 |
| FR-016 | App must expose workspace file tree for context management | F07 |
| FR-017 | App must support iOS Speech Recognition for voice input | F16 |
| FR-018 | App must persist prompt templates locally via SwiftData | F17 |
| FR-019 | Relay must support APNs for push notifications | F18 |
| FR-020 | App must auto-reconnect with exponential backoff | F04 |

### Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-001 | iOS 17.0+ (for @Observable, SwiftData, modern concurrency) |
| NFR-002 | WebSocket round-trip latency < 200ms on local network |
| NFR-003 | SpriteKit scene must maintain 60fps on iPhone 13+ |
| NFR-004 | Battery-efficient WebSocket management (heartbeat, background modes) |
| NFR-005 | App launch to connected state < 2 seconds |
| NFR-006 | Streaming output must feel instantaneous (< 50ms render lag) |

### Security Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SR-001 | Relay server only accepts connections from paired devices | v1.0 |
| SR-002 | WebSocket connections use WSS when over public network | v1.0 |
| SR-003 | No sensitive data (tokens, API keys) in logs or UserDefaults | v1.0 |
| SR-004 | Pairing secrets stored in iOS Keychain (native) / encrypted localStorage (PWA) | v1.0 |
| SR-005 | Hook scripts must validate relay server origin | v1.0 |
| SR-006 | PIN-based device pairing with rate limiting (max 5 attempts per minute) | v1.0 |
| SR-007 | Device tokens are cryptographically random (256-bit), issued after PIN verification | v1.0 |
| SR-008 | Token sent on WebSocket upgrade via `Sec-WebSocket-Protocol` or first message auth | v1.0 |
| SR-009 | Relay can list and revoke paired devices via CLI command | v1.0 |
| SR-010 | Unpaired WebSocket connections are dropped within 5 seconds | v1.0 |
| SR-011 | QR code pairing as convenience layer over PIN flow | v2.0+ |
| SR-012 | Optional token rotation (configurable expiry, default: no expiry) | v2.0+ |

### Security & Pairing Protocol

#### Overview

Major Tom uses a **PIN-based device pairing** model. The relay server is the trust anchor — it generates a one-time PIN, the client proves knowledge of it, and the relay issues a long-lived device token. Subsequent connections use the token directly (no re-pairing).

This is **personal-use security** — we're not building OAuth or multi-tenant auth. The threat model is: prevent unauthorized devices from connecting to your relay, especially when exposed via Cloudflare Tunnel.

#### Threat Model

| Threat | Mitigation |
|--------|------------|
| Random person hits your Tunnel URL | Token required on connect — rejected in < 5s |
| PIN brute force (6 digits = 1M combos) | Rate limit: 5 attempts/min, lockout after 15 failures for 15 min |
| Token theft from device | Keychain (iOS) / encrypted storage (PWA) — same security as any saved password |
| Token theft from relay | Tokens stored as SHA-256 hashes in relay config — raw token never persisted server-side |
| Network sniffing | WSS required over public networks; PIN pairing should happen on local network |
| Replay attacks | Token is tied to device ID — can't be reused from a different device |

#### Pairing Flow (PIN)

```
┌──────────┐                              ┌──────────────┐
│  Client   │                              │    Relay     │
│ (PWA/iOS) │                              │   Server     │
└─────┬─────┘                              └──────┬───────┘
      │                                           │
      │    1. User runs: relay pair               │
      │    ─────────────────────────────────────►  │
      │                                           │ Generates 6-digit PIN
      │                                           │ Displays in terminal
      │                                           │ PIN valid for 5 minutes
      │                                           │
      │    2. POST /api/pair                      │
      │       { pin, deviceName, deviceId }       │
      │    ─────────────────────────────────────►  │
      │                                           │ Validates PIN
      │                                           │ Generates 256-bit token
      │                                           │ Stores hash(token) + deviceId + name
      │                                           │ Invalidates PIN
      │    3. 200 OK                              │
      │       { token, expiresAt: null }          │
      │    ◄─────────────────────────────────────  │
      │                                           │
      │    Stores token in Keychain/localStorage  │
      │                                           │
      │    4. WS upgrade                          │
      │       First message: { type: "auth",      │
      │         token, deviceId }                 │
      │    ─────────────────────────────────────►  │
      │                                           │ hash(token) lookup
      │                                           │ deviceId match
      │    5. { type: "auth.success" }            │
      │    ◄─────────────────────────────────────  │
      │                                           │
      │    Connection is now authenticated ✓      │
      └───────────────────────────────────────────┘
```

#### Key Design Decisions

1. **PIN over QR for v1.0** — Works for both PWA and native iOS. No camera/QR infrastructure needed. QR is a v2.0+ convenience layer that wraps the same token exchange.

2. **Token on first WS message, not upgrade headers** — `Sec-WebSocket-Protocol` header abuse is hacky and some proxies strip custom headers. A first-message auth handshake is cleaner and works universally. Connection has 5 seconds to authenticate before the relay drops it.

3. **Hash-only server storage** — Relay stores `SHA-256(token)` + device metadata, never the raw token. If someone reads relay config, they can't impersonate a device.

4. **Device ID binding** — Token is tied to a `deviceId` (generated on first pairing, persisted with the token). Prevents token reuse from a different device if somehow exfiltrated.

5. **No expiry by default** — This is personal-use. Token lives until explicitly revoked. Optional rotation can be added in v2.0+.

6. **Local-network-only pairing** — PIN exchange should only happen over local network (HTTP is fine for `localhost` / LAN IP). The PIN endpoint is disabled when accessed through Cloudflare Tunnel headers.

#### Relay CLI Commands

```bash
# Generate a pairing PIN (valid 5 minutes)
major-tom pair

# List paired devices
major-tom devices

# Revoke a specific device
major-tom revoke <deviceId>

# Revoke all devices (nuclear option)
major-tom revoke --all
```

#### Device Token Storage

| Platform | Storage | Details |
|----------|---------|---------|
| iOS (native) | Keychain | `kSecClassGenericPassword`, service: `com.majortom.relay` |
| PWA | localStorage | Key: `majortom_device_token`, value: `{ token, deviceId, relayUrl }` |

> **Note on PWA storage:** localStorage isn't encrypted, but it's origin-scoped and same-origin policy protects it. For a personal-use app on your own phone, this is acceptable. If we want hardening later, we can use the Web Crypto API to encrypt with a user-derived key.

#### Protocol Messages (Auth)

```typescript
// Client → Server (first message after WS connect)
{ type: "auth", token: string, deviceId: string }

// Server → Client (auth success)
{ type: "auth.success", deviceName: string }

// Server → Client (auth failure — connection will close)
{ type: "auth.error", code: "invalid_token" | "unknown_device" | "rate_limited", message: string }
```

#### Implementation Touchpoints

This protocol touches the following components — listed here so we don't build anything that conflicts:

| Component | What to build | Phase |
|-----------|--------------|-------|
| `relay/src/auth/` | Token store, PIN generation, hash/verify, rate limiter | v1.0 |
| `relay/src/server.ts` | Auth handshake on WS connect, 5s timeout, reject unauthenticated | v1.0 |
| `relay/src/api/pair.ts` | `POST /api/pair` endpoint, PIN validation | v1.0 |
| `relay/src/cli.ts` | `pair`, `devices`, `revoke` CLI commands | v1.0 |
| `web/src/lib/stores/auth.svelte.ts` | Token storage, deviceId generation, auth message on connect | v1.0 |
| `ios/.../Core/Networking/` | Keychain storage, auth message on connect | Later (native track) |
| Cloudflare Tunnel config | Block `/api/pair` when `Cf-Connecting-Ip` header present | v1.0 |

---

## Roadmap

> Phases are organized around **coherent user capabilities** (GSD pattern), not tech layers.
> Each phase delivers something a user can actually use end-to-end.
> VSCode extension is deprioritized — CLI-only for MVP and foreseeable future.

### Phase 1: "Hello Claude" — Foundation + CLI Chat (v1.0) ✅ COMPLETE

**Goal:** Send a prompt to Claude Code from your phone and see the response.

**Delivers:** End-to-end message flow from Phone → Relay → Claude Code CLI → back

| Deliverable | Status |
|------------|--------|
| Relay server scaffold (WebSocket, sessions, protocol) | ✅ PR #2 |
| iOS app scaffold (SwiftUI shell, WebSocket, chat) | ✅ PR #3 |
| PWA scaffold (Svelte 5, WebSocket, chat, approvals, markdown) | ✅ PRs #4–#9 |
| CLI adapter rewrite (Agent SDK, permission handling) | ✅ PR #13 |
| Auto-connect + rendering fix (tunnel/LAN support) | ✅ PR #14 |
| End-to-end phone test via Cloudflare Tunnel | ✅ Verified |

**Success Criteria — ALL MET:**
- [x] Can connect to relay server from phone browser
- [x] Can send a prompt and see response
- [x] Can approve/deny tool calls from phone
- [x] Connection auto-reconnects

---

### Phase 2: "Mission Control" — The Real Mobile Workflow (v1.1)

**Goal:** Do everything you can do at your laptop, from your phone. For real.

**Delivers:** A PWA that feels like Claude Code CLI but mobile-native. Persistent sessions, auto-approve modes, slash commands, and a UI that doesn't make you want to go back to your desk.

#### MVP (v1.1) — "I can actually work from my phone"

| ID | Feature | Description | Wave |
|----|---------|-------------|------|
| MC-01 | **Session persistence** | Chat history + session ID in localStorage. Phone sleeps, you come back, everything's there. `session.attach` on reconnect. | 1 |
| MC-02 | **ClaudeGod mode** | Auto-approve settings: (a) full auto-approve, (b) delay mode — X-second countdown toast, auto-accept if no action, (c) manual (current). Per-tool overrides later. | 1 |
| MC-03 | **Command palette** | Type `/` → searchable palette pops up. Sorted by most recent/frequent. Client-side intercept translates to SDK actions. Hardcoded list for MVP. | 1 |
| MC-04 | **Slash commands** | `/new` (fresh session), `/clear` (clear display, keep session), `/plan` (plan mode), `/compact` (compact context), `/model` (switch model). Intercepted client-side. | 1 |
| MC-05 | **`/btw` quick-ask** | Send a quick question into the current session without disrupting flow. Prefixed so Claude knows it's a side-question with full context. | 1 |
| MC-06 | **Streaming indicator** | "Claude is thinking..." animation while waiting. Tool use preview: "Using Read on `/src/main.ts`...". | 2 |
| MC-07 | **Session result broadcast** | New `session.result` message from relay with `total_cost_usd`, `num_turns`, `duration_ms`, `token_usage`. Currently logged but not sent to clients. | 2 |
| MC-08 | **Cost & usage display** | Per-prompt cost, running session total, token usage bar. Data from MC-07. | 2 |
| MC-09 | **Approval countdown toast** | For ClaudeGod delay mode: toast notification with countdown bar, tool name, input preview. Tap to cancel auto-approve. | 2 |
| MC-10 | **Protocol sync** | Unify web client protocol types with relay — add agent lifecycle events, session.result, all missing types. | 1 |
| MC-11 | **CLI-like chat UI** | Monospace, streaming text, same visual language as Claude Code CLI. Better than current but not a redesign — just tighten it up. | 2 |

#### v1.2 — "This is actually better than my laptop"

| ID | Feature | Description |
|----|---------|-------------|
| MC-12 | **Mobile diff viewer** | Side-by-side or unified diff view for changed files. Syntax highlighted. |
| MC-13 | **Tool activity feed** | Scrollable timeline of tool calls — name, duration, success/fail, collapsible input/output. |
| MC-14 | **Agent activity panel** | Active subagents with tasks, elapsed time. Ties into Office visualization later. |
| MC-15 | **Better approval cards** | Tool icons (Read=magnifying glass, Bash=terminal, Edit=pencil), formatted JSON input preview, timeout countdown. |
| MC-16 | **System event display** | Context compaction, API retries, rate limit warnings — categorized and styled. |
| MC-17 | **Push notifications (web-push)** | iOS push notifications for approval requests. Tap → opens PWA to approval. Requires home screen install. |

#### v1.3+ — Nice to Have

| ID | Feature | Description |
|----|---------|-------------|
| MC-18 | **Push notification inline actions** | Allow/Deny directly from iOS notification without opening app. |
| MC-19 | **File context browser** | Workspace tree, tap to view files, @file/@folder references. |
| MC-20 | **Session history** | List past sessions, resume, see metadata (date, cost, turns). |
| MC-21 | **Git status** | Branch, uncommitted files, ahead/behind. |
| MC-22 | **Reconnection UX** | Backoff timer display, manual retry, last message timestamp. |
| MC-23 | **Voice prompts** | Speech-to-text input via Web Speech API. |
| MC-24 | **Prompt templates** | Save, organize, reuse common prompts. |

#### Implementation Waves

**Wave 1 — Foundation (Protocol + State + Persistence)**
- Sync web protocol types with relay (MC-10)
- Session persistence in localStorage (MC-01)
- ClaudeGod mode settings + approval queue logic (MC-02)
- Command palette + slash command intercept (MC-03, MC-04)
- `/btw` quick-ask (MC-05)
- ~4-5 days, 2-3 PRs

**Wave 2 — Visibility + Polish**
- `session.result` broadcast from relay (MC-07)
- Cost & usage display (MC-08)
- Streaming indicator (MC-06)
- Approval countdown toast for delay mode (MC-09)
- CLI-like chat tightening (MC-11)
- ~3-4 days, 2-3 PRs

**Wave 3 — v1.2 Features** (after MVP ships)
- Diff viewer, tool feed, agent panel, better approvals, system events, push notifications
- ~6-8 days, 4-5 PRs

---

### Phase 3: "The Office" — Gamified Agent Visualization (v2.0)

**Goal:** Watch your AI workforce in a pixel-art tech office. Characters with personality, break-time behaviors, and a Meta-pre-COVID vibe.

**Delivers:** SpriteKit office scene (iOS native) with animated characters representing Claude agents. Each character has unique break behaviors. Multiple areas to explore.

#### Characters

**9 characters at launch.** Roles assigned via config, not hardcoded. User can rename and reassign.

**Humans (5):**

| Character | Look | Break Behavior |
|-----------|------|----------------|
| Dev | Hoodie, headphones, energy drink on desk | Gym, plays ping pong, naps on beanbag |
| Office Worker | Button-down, coffee mug, organized desk | Kitchen (coffee runs), break room couch, errands |
| PM | Polo, clipboard, sticky notes everywhere | Meeting room (alone, lol), phone call walk, rollercoaster |
| Clown | Full clown outfit, balloon animal on desk | Juggles in break room, rides tiny bike around office, rollercoaster |
| Frankenstein | Bolts, green skin, sparking cables on desk | Charging station (robot-style), wanders confused, scared of coffee machine |

**Dogs (4 — the user's actual dogs):**

| Character | Look | Break Behavior |
|-----------|------|----------------|
| Dachshund | Auburn short-hair, long boi | **MUST find a blanket** to hang in office (demands one if missing — one-click give). Dog park, walks, burrows under desk |
| Cattle Dog | Red heeler body, GSD-style face | Dog park (herds other dogs), patrol walk around office, food/water |
| Schnauzer #1 | All black, distinguished beard | Dog park, curls up on couch, stands guard at door |
| Schnauzer #2 | Salt & pepper (mostly black), scruffy | Dog park, follows Schnauzer #1 everywhere, food/water, zoomies |

> **Custom characters:** See README for how to prompt Claude to create new character sprites and behaviors. PRs welcome from friends.

#### Office Environment

**Vibe:** Silicon Valley tech campus, pre-COVID Meta energy. Cool workstations, ping pong, snack bar, bean bags, neon signs, standing desks, monitor walls.

**Areas:**

| Area | Description | Who Goes Here |
|------|-------------|---------------|
| **Main Floor** | Open plan, 6-8 desks with personality, monitor walls, standing desks | Everyone (working) |
| **Server Room** | Blinky lights, cable spaghetti, cold blue lighting | Orchestrator's desk |
| **Break Room** | Couches, vending machine, TV, ping pong table, bean bags | Humans (break) |
| **Kitchen** | Coffee machine, snack bar, mini fridge, water cooler | Humans (break), dogs (food/water) |
| **Dog Corner** | Dog beds, blankets, toy basket, water bowls | Dogs (indoor break) |
| **Dog Park** | Grass, fence, tennis balls, fire hydrant | Dogs (outdoor break) |
| **Gym** | Treadmill, weights, yoga mat | Humans (outdoor break) |
| **Rollercoaster** | Yes, a rollercoaster. It's that kind of office. | PM, Clown (outdoor break) |

#### Agent Lifecycle → Character Behavior

| Event | What Happens |
|-------|-------------|
| `agent.spawn` | Character appears at office entrance, walks to available desk |
| `agent.working` | Sits at desk, typing/working animation (looping). Dogs lay on desk or sit in chair. |
| `agent.idle` | Stands up, picks a break activity based on character type. Random selection weighted by personality. |
| `agent.complete` | Celebration animation at desk (fist pump, tail wag, honk nose, spark bolts). Short-lived. |
| `agent.dismissed` | Walks to exit, disappears |

**Dachshund Blanket Mechanic:**
When the dachshund goes idle indoors, it looks for a blanket in Dog Corner. If no blanket is available, it sits and starts "demanding" (thought bubble with blanket icon, increasingly agitated animation). User gets a one-tap "Give Blanket" button. Once given, dachshund burrows under blanket contentedly.

#### Navigation

**Mini-map + Follow mode (Option A + C):**
- Corner mini-map shows all areas as icons with character count badges
- Greyed out areas = empty, glowing = activity
- Tap area on mini-map → camera pans there
- Tap character → optional "Follow" toggle, camera tracks them between areas
- Pinch to zoom on main view

#### Interactions

| Interaction | Description | Priority |
|-------------|-------------|----------|
| **Tap to inspect** | Overlay sheet: agent ID, role, current task, live output stream | MVP |
| **Rename** | Long press → rename character | MVP |
| **Follow** | Tap character → toggle follow mode, camera tracks them | MVP |
| **Give blanket** | One-tap when dachshund demands it | MVP |
| **Reassign role** | Change which agent type a character represents | v2.1 |
| **Customize desk** | Tap desk → upload photo or pick from files for desk decoration | v2.1 |
| **Guide with prompt** | Send a message to steer a specific agent from inspection view | v2.1 |

#### Art & Sprites

**Style:** 32x32 pixel art, top-down perspective. Low-bit but **distinguishable** — each dog breed must read clearly as that breed at small sizes.

**Per character (9 characters × asset set):**
- 4-direction walk cycle (4 frames each = 16 walk frames)
- Work animation (2-4 frames, looping)
- Idle/breathing animation (2 frames)
- Break-specific animations (varies per character)
- Celebration animation (2-4 frames)
- Error state (red tint flash overlay)

**Environment tileset:**
- Floor tiles (wood, carpet, grass, concrete)
- Wall/partition tiles
- Furniture sprites (desks, chairs, couches, ping pong, coffee machine, vending machine, bean bags, dog beds, blankets)
- Decorations (plants, neon signs, monitors, cable spaghetti, fire hydrant, tennis balls)

**Placeholder strategy:** Start with colored rectangles/circles differentiated by role. Get the movement system and state machine working. Pretty sprites come later (or we commission them / AI-generate base assets).

#### Implementation Waves

**Wave 1 — Infrastructure (~3-4 days)**
- `Features/Office/` directory structure
- Wire iOS `RelayService` to handle `agent.*` events
- `OfficeViewModel` (@Observable) tracking agent states + desk occupancy
- Basic `OfficeScene` with grid rendering and placeholder sprites
- Mini-map component

**Wave 2 — Movement & Animation (~4-5 days)**
- `AgentSprite` class (SKSpriteNode subclass) with placeholder art
- Walk cycle animation system (4 directions)
- Grid-based A* pathfinding
- Desk assignment and occupancy tracking
- Character walks to desk on spawn, to break areas on idle

**Wave 3 — Character Personalities (~3-4 days)**
- Break behavior system (weighted random per character type)
- Dachshund blanket mechanic
- Celebration animations on complete
- Multiple area transitions (office → dog park, gym, etc.)
- Area-specific idle animations

**Wave 4 — Interactions & Polish (~3-4 days)**
- Tap to inspect → `AgentInspectorView` overlay
- Rename via long press
- Follow mode (camera tracks character)
- Mini-map badges and navigation
- Give Blanket button
- Particle effects, ambient animations

**Wave 5 — Real Sprites (~timeline TBD)**
- Commission or create actual 32x32 pixel art
- All 9 characters with full animation sets
- Environment tileset and furniture
- Sprite atlases for GPU batching

---

### Phase 4: "Delight" — Smart Features + Polish (v2.1)

**Goal:** Make it so good you never want to sit at your desk again.

**Delivers:** Voice, push notifications, desk customization, prompt templates

| Task Group | Key Deliverables |
|------------|-----------------|
| Voice Prompts | Speech Recognition (iOS native + Web Speech API) |
| Prompt Templates | Save, organize, search, and reuse prompts |
| Push Notifications | Native iOS APNs + PWA web-push with inline actions |
| Desk Customization | Tap desk → upload photo or pick from file system |
| Character Expansion | Custom character creation guide in README |
| Agent Steering | Guide specific agents with prompts from inspector |
| Haptics | Satisfying feedback for approvals and key actions (native) |

---

### Phase 5: "Everywhere" — Platform Expansion (v3.0)

**Goal:** Major Tom on your wrist and home screen.

**Delivers:** Apple Watch app, Home Screen widgets, stable remote access

| Task Group | Key Deliverables |
|------------|-----------------|
| Watch App | Approve/deny from wrist, connection status, basic prompting |
| Widgets | WidgetKit — connection status, pending approvals, agent count |
| Stable Tunnel | Named Cloudflare Tunnel + custom domain (~$10/yr) for PWA home screen install |

**Success Criteria:**
- [ ] Can approve tool calls from Apple Watch
- [ ] Home screen widget shows live status
- [ ] Stable URL for PWA install

---

### Version Summary

| Version | Phase | Theme | Key Deliverable |
|---------|-------|-------|-----------------|
| **v1.0** | 1 ✅ | Hello Claude | Chat + approve from phone via PWA |
| **v1.1** | 2 | Mission Control MVP | Persistent sessions, ClaudeGod mode, slash commands, cost display |
| **v1.2** | 2 | Mission Control+ | Diff viewer, tool feed, push notifications |
| **v2.0** | 3 | The Office | Gamified agent visualization with 9 characters |
| **v2.1** | 4 | Delight | Voice, templates, desk customization, haptics |
| **v3.0** | 5 | Everywhere | Watch, widgets, stable tunnel |

> **Reality check:** v1.0 is done. v1.1 makes this actually usable as a daily workflow tool. The Office is the fun part — but Mission Control MVP comes first because you need the tool to actually work before you make it pretty.

---

## WebSocket Protocol (Draft)

All messages are JSON with a `type` field for routing.

### Client → Server (iOS → Relay)

```typescript
// Send a prompt to Claude Code
{ type: "prompt", sessionId: string, text: string, context?: string[] }

// Respond to an approval request
{ type: "approval", requestId: string, decision: "allow" | "deny" | "skip" | "allow_always" }

// Cancel current operation
{ type: "cancel", sessionId: string }

// Start new session
{ type: "session.start", adapter: "cli" | "vscode", workingDir?: string }

// Attach to existing session
{ type: "session.attach", sessionId: string }

// Send message to specific agent (for steering)
{ type: "agent.message", agentId: string, text: string }

// Request workspace file tree
{ type: "workspace.tree", path?: string }

// Add file to context
{ type: "context.add", path: string, type: "file" | "folder" }

// Update approval settings (ClaudeGod mode)
{ type: "settings.approval", mode: "manual" | "auto" | "delay", delaySeconds?: number }
```

### Server → Client (Relay → iOS)

```typescript
// Streaming output chunk
{ type: "output", sessionId: string, chunk: string, format: "markdown" | "plain" }

// Approval request
{ type: "approval.request", requestId: string, tool: string, description: string, details: object }

// Tool call started
{ type: "tool.start", sessionId: string, tool: string, input: object }

// Tool call completed
{ type: "tool.complete", sessionId: string, tool: string, output: string, success: boolean }

// Agent lifecycle events (for office visualization)
{ type: "agent.spawn", agentId: string, parentId?: string, task: string, role: string }
{ type: "agent.working", agentId: string, task: string }
{ type: "agent.idle", agentId: string }
{ type: "agent.complete", agentId: string, result: string }
{ type: "agent.dismissed", agentId: string }

// Connection status
{ type: "connection.status", status: "connected" | "disconnected", adapter: string }

// Session info
{ type: "session.info", sessionId: string, adapter: string, startedAt: string, tokenUsage?: object }

// Workspace file tree
{ type: "workspace.tree.response", files: FileNode[] }

// Session result (prompt completed — cost, tokens, duration)
{ type: "session.result", sessionId: string, cost_usd: number, num_turns: number, duration_ms: number, token_usage?: { input: number, output: number } }

// Error
{ type: "error", code: string, message: string }
```

---

## Design Direction

### UI Aesthetic
- **Dark mode first** — deep blacks, subtle gradients, vibrant accents
- **Glassmorphism** — frosted glass panels, depth through blur
- **Monospace code** — SF Mono for all code, system font for UI
- **Accent colors** — Claude's orange/amber for primary actions, green for allow, red for deny
- **Animations** — smooth spring animations, meaningful transitions, no gratuitous motion
- **Information density** — show what matters, hide what doesn't, progressive disclosure

### Office Aesthetic
- **32x32 pixel art** — clean, readable at small sizes, distinguishable characters
- **Top-down perspective** — classic Zelda/Pokemon style
- **Silicon Valley tech campus** — Meta pre-COVID energy, cool workstations, neon signs
- **9 launch characters** — 5 humans (Dev, Office Worker, PM, Clown, Frankenstein) + 4 dogs (Dachshund, Cattle Dog, 2 Schnauzers)
- **Personality-driven breaks** — each character has unique idle behaviors (gym, dog park, blanket hunting, juggling)
- **Animation states** — walk cycle (4 frames × 4 directions), work (2-4 frames), idle (2 frames), celebration (2-4 frames), error (red flash)
- **Multiple areas:**
  - **Main floor** — open plan, 6-8 desks with personality
  - **Server room** — blinky lights, orchestrator's desk
  - **Break room** — couches, ping pong, bean bags, TV
  - **Kitchen** — coffee machine, snack bar, mini fridge
  - **Dog corner** — dog beds, blankets, toy basket
  - **Dog park** — grass, fence, tennis balls (outdoor)
  - **Gym** — treadmill, weights (outdoor)
  - **Rollercoaster** — because why not (outdoor)
- **Navigation** — mini-map with area badges + character follow mode

### Interaction Patterns
- **Swipe between modes** — Control ↔ Office (horizontal swipe or tab)
- **Long press** — context menus for advanced actions
- **Pull to refresh** — reconnect / refresh state
- **Shake to undo** — revert last action (if applicable)

---

## Key Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Claude Code hook system limitations | Can't intercept all events | Research hook capabilities early; fallback to PTY parsing |
| SpriteKit performance with many agents | Frame drops on older devices | Cap agent count, use texture atlases, profile early |
| WebSocket reliability on cellular | Dropped connections | Exponential backoff, message queuing, offline mode |
| Claude Code VSCode extension internals | Can't programmatically interact | Start with CLI-only; VSCode bridge is Phase 2 |
| PTY output parsing | Unstructured text is hard to parse | Use hooks for structured events; PTY for raw stream only |

---

## Hosting & Deployment Strategy

### Decision: Same-Origin (Relay Serves PWA)

The relay server serves the PWA static files from `web/dist/`. One process, one port.

| Concern | Approach |
|---------|----------|
| Local network | Phone hits `http://<mac-ip>:9090` — gets PWA + WebSocket on same origin |
| Remote access | Cloudflare Tunnel (free) or Tailscale to expose local relay |
| CORS | Non-issue — same origin for local; WebSocket doesn't enforce same-origin anyway |
| Build | `npm run build:all` builds relay + web, `npm run dev` runs everything |
| Why not separate host? | PWA is useless without a running relay (it spawns Claude Code locally via PTY) |

### Why Not Other Options

- **Separate static host (Vercel/Cloudflare Pages)**: Adds deployment complexity for zero gain. The relay must run on your dev machine anyway, and you'd still need a tunnel for phone access.
- **Full cloud deploy**: Not viable — relay spawns Claude Code in a local PTY on your project directory.

### Remote Access (Phase 2+)

When we want to control Claude from outside the local network:
1. **Cloudflare Tunnel** (free) — `cloudflared tunnel` exposes `localhost:9090` to a public URL
2. **Tailscale** — zero-config mesh VPN, phone and Mac on same virtual network
3. **Auth is built-in** — device pairing (PIN → token) is required for all connections. Pair on local network first, then connect remotely using the stored token. The `/api/pair` endpoint is blocked when accessed through Cloudflare Tunnel to prevent remote PIN brute-force.

---

## Skills Needed

### Currently Installed
- `ios-swiftui-patterns` — SwiftUI state management, navigation, composition
- `swiftui-performance-audit` — Performance profiling and optimization
- `vscode-extension-builder` — VSCode extension scaffolding and APIs

### To Install
- SpriteKit / 2D game development patterns (if available)
- Node.js WebSocket server patterns
- Claude Code hooks & Agent SDK reference

### Always Use
- **Context7** — For ALL library API lookups (SwiftUI, SpriteKit, node-pty, ws, VSCode API)
- **npm view** — For ALL package version checks before installing

---

## Agent Skills (Installed)

```bash
# iOS Development
npx skills add https://github.com/thebushidocollective/han --skill ios-swiftui-patterns
npx skills add https://github.com/dagba/ios-mcp --skill swiftui-performance-audit

# VS Code Extension Development
npx skills add https://github.com/kjgarza/marketplace-claude --skill vscode-extension-builder

# Project Planning & Roadmaps
npx skills add https://github.com/anthropics/knowledge-work-plugins --skill roadmap-management
npx skills add https://github.com/borghei/claude-skills --skill product-manager-toolkit
```

