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
| Auth | Local pairing (no OAuth needed — personal use) |
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

### Tier 1: Foundation (Must Have for v1.0)

| ID | Feature | Description |
|----|---------|-------------|
| F01 | **Claude Code CLI Chat** | Send prompts to a running Claude Code CLI session, see streaming responses |
| F02 | **Approval Flow** | See pending tool calls, tap Allow / Skip / Deny — full hook-based approval |
| F03 | **Live Output Stream** | Real-time streaming of Claude Code's output (markdown rendered) |
| F04 | **Connection Management** | Pair with relay server, connection status, auto-reconnect |
| F05 | **Session Management** | Start new sessions, see active session, basic session history |

### Tier 2: Full Control (v1.1)

| ID | Feature | Description |
|----|---------|-------------|
| F06 | **VSCode Extension Bridge** | Control Claude Code's VSCode chat panel remotely |
| F07 | **File Context** | Browse workspace files, add @file/@folder references |
| F08 | **Terminal Streaming** | See terminal output from Claude Code's commands |
| F09 | **Cancel/Interrupt** | Stop runaway operations with one tap |
| F10 | **Git Status** | See current branch, uncommitted changes, diffs |

### Tier 3: Agent Office (v2.0)

| ID | Feature | Description |
|----|---------|-------------|
| F11 | **Office Scene** | SpriteKit pixel art office with furniture, rooms, decorations |
| F12 | **Agent Characters** | Animated sprites for orchestrator + subagents |
| F13 | **Agent Lifecycle** | Characters spawn at desks when working, move to break rooms when idle |
| F14 | **Tap to Inspect** | Tap an agent to see their current task, output stream, progress |
| F15 | **Steer Agents** | Send messages to specific subagents from the inspection view |

### Tier 4: Polish & Delight (v2.1+)

| ID | Feature | Description |
|----|---------|-------------|
| F16 | **Voice Prompts** | Dictate prompts via iOS Speech Recognition |
| F17 | **Prompt Templates** | Save, organize, and reuse common prompts |
| F18 | **Push Notifications** | Approval requests, task completion, errors, idle alerts |
| F19 | **Haptic Feedback** | Satisfying haptics for approvals and key actions |
| F20 | **Dark Mode** | Beautiful dark theme (default) with light option |
| F21 | **Smart Suggestions** | Context-aware prompt suggestions based on workspace state |

### Tier 5: Platform (v3.0)

| ID | Feature | Description |
|----|---------|-------------|
| F22 | **Home Screen Widget** | Connection status, pending approvals, agent count |
| F23 | **Apple Watch** | Approve/deny from your wrist |
| F24 | **Prompt History** | Search and re-send previous prompts |

### Deprioritized (Backlog)

| ID | Feature | Notes |
|----|---------|-------|
| F-B3 | GitHub PR Status | Can use GitHub app directly |
| F-B4 | CI/CD Pipeline View | Same |
| F-B5 | Copilot Support | Legacy — only if you need it alongside Claude Code |

---

## User Stories

### Connection & Setup

- **US-001:** As a user, I can pair my iPhone with my Mac's relay server via QR code or manual IP entry
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

| ID | Requirement |
|----|-------------|
| SR-001 | Relay server only accepts connections from paired devices |
| SR-002 | WebSocket connections use WSS when over public network |
| SR-003 | No sensitive data (tokens, API keys) in logs or UserDefaults |
| SR-004 | Pairing secrets stored in iOS Keychain |
| SR-005 | Hook scripts must validate relay server origin |

---

## Roadmap

> Phases are organized around **coherent user capabilities** (GSD pattern), not tech layers.
> Each phase delivers something a user can actually use end-to-end.

### Phase 1: "Hello Claude" — Foundation + CLI Chat (v1.0)

**Goal:** Send a prompt to Claude Code from your phone and see the response.

**Delivers:** End-to-end message flow from iOS → Relay → Claude Code CLI → back

| Task Group | Key Deliverables |
|------------|-----------------|
| Relay Server Scaffold | WebSocket server, adapter interface, message protocol |
| CLI Adapter | PTY spawn, stdin/stdout capture, session management |
| Hook System | pre-tool-use hook script, relay HTTP endpoints, approval flow |
| iOS App Scaffold | SwiftUI app shell, WebSocket client, connection pairing |
| Chat UI | Message list, input bar, streaming markdown renderer |
| Approval UI | Action sheet with Allow / Skip / Deny buttons |

**Success Criteria:**
- [ ] Can pair iPhone with relay server
- [ ] Can send a prompt and see streaming response
- [ ] Can approve/deny tool calls from phone
- [ ] Connection auto-reconnects

---

### Phase 2: "Full Control" — VSCode + Visibility (v1.1)

**Goal:** Control Claude Code in VSCode too. See everything it's doing.

**Delivers:** VSCode extension bridge, live file/terminal/git visibility

| Task Group | Key Deliverables |
|------------|-----------------|
| VSCode Extension | Companion extension, Claude Code UI bridge, message forwarding |
| File Context | Workspace tree browser, @file/@folder context management |
| Terminal Stream | Terminal output capture and forwarding |
| Git Status | Branch, uncommitted changes, diff viewer |
| Cancel/Interrupt | One-tap operation cancellation |
| Session History | List, resume, and manage past sessions |

**Success Criteria:**
- [ ] Can type into Claude Code's VSCode chat from phone
- [ ] Can press approval buttons in VSCode from phone
- [ ] Can see files being edited in real-time
- [ ] Can see terminal output streaming
- [ ] Can browse workspace files and add to context

---

### Phase 3: "The Office" — Gamified Agent Visualization (v2.0)

**Goal:** Watch your AI team work in a pixel art office.

**Delivers:** SpriteKit office scene with animated agent characters

| Task Group | Key Deliverables |
|------------|-----------------|
| Office Scene | Pixel art office with rooms (desks, break room, kitchen, lounge) |
| Sprite System | Character sprites with walk, work, idle, and error animations |
| Agent Lifecycle | Event-driven character spawning, movement, and dismissal |
| Pathfinding | A* or simple grid-based pathfinding between rooms |
| Agent Inspector | Tap-to-inspect overlay with live thought stream |
| Agent Steering | Send messages to specific agents from inspector |

**Success Criteria:**
- [ ] Can see pixel office with orchestrator character
- [ ] Subagent characters appear when spawned
- [ ] Characters walk to desks when working, break rooms when idle
- [ ] Can tap character to see their current task/output
- [ ] Can send a message to steer a specific agent

---

### Phase 4: "Delight" — Smart Features + Polish (v2.1)

**Goal:** Make it so good you never want to sit at your desk again.

**Delivers:** Voice, templates, notifications, beautiful polish

| Task Group | Key Deliverables |
|------------|-----------------|
| Voice Prompts | Speech Recognition integration, voice-to-text input |
| Prompt Templates | Save, organize, search, and reuse prompts |
| Notifications | APNs for approvals, completions, errors, idle |
| Haptics | Satisfying feedback for approvals and key actions |
| UI Polish | Animations, transitions, micro-interactions, dark mode perfection |
| Prompt History | Searchable history with re-send capability |

**Success Criteria:**
- [ ] Can dictate prompts while walking
- [ ] Receive push notifications for pending approvals
- [ ] App feels premium with smooth animations and haptics

---

### Phase 5: "Everywhere" — Platform Expansion (v3.0)

**Goal:** Major Tom on your wrist and home screen.

**Delivers:** Apple Watch app, Home Screen widgets

| Task Group | Key Deliverables |
|------------|-----------------|
| Watch App | Approve/deny from wrist, connection status, basic prompting |
| Widgets | WidgetKit — connection status, pending approvals, agent count |
| Remote Access | Tailscale integration for controlling Mac from anywhere |

**Success Criteria:**
- [ ] Can approve tool calls from Apple Watch
- [ ] Home screen widget shows live status
- [ ] Works over Tailscale from outside local network

---

### Version Summary

| Version | Phase | Theme | Key Deliverable |
|---------|-------|-------|-----------------|
| **v1.0** | 1 | Foundation | Chat with Claude Code from phone, approve tool calls |
| **v1.1** | 2 | Full Control | VSCode bridge, live visibility, file context |
| **v2.0** | 3 | The Office | Gamified agent visualization |
| **v2.1** | 4 | Delight | Voice, templates, notifications, polish |
| **v3.0** | 5 | Everywhere | Watch, widgets, remote access |

> **Reality check:** Phase 1 is the real MVP. If you can send prompts and approve tool calls from your phone, you've already won. Everything else is gravy — delicious, beautiful gravy.

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
- **16x16 or 32x32 pixel art** — clean, readable at small sizes
- **Top-down perspective** — classic Zelda/Pokemon style
- **Warm color palette** — cozy office vibes (wood tones, soft lighting)
- **Character differentiation** — each agent type has a distinct sprite (color, accessories)
- **Animation states** — walk cycle (4 frames), work (typing at desk, 2-4 frames), idle (breathing, 2 frames), error (red flash)
- **Room types:**
  - **Main floor** — desks for active agents (one per desk)
  - **Break room** — couches, vending machine (idle agents hang here)
  - **Kitchen** — coffee machine, snacks (random idle destination)
  - **Server room** — blinky lights (orchestrator's desk is here)
  - **Lounge** — beanbags, plants (another idle destination)

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

