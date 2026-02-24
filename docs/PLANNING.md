# Remote Pilot 🛩️

> Control your VS Code Copilot remotely from your iPhone. Monitor Jira sprints, read Confluence docs, and send prompts to Copilot—all from the couch.

## Overview

Remote Pilot is a native iOS app that lets you orchestrate AI-powered development workflows without being tethered to your desk. Connect to your Mac running VS Code, view your project context (Jira/Confluence), and guide Copilot through complex tasks with simple prompts.

**The Vision:** Set up your project scaffolding (Confluence docs, Jira board, GitHub repo, Copilot directives) and let the AI handle coding, documentation updates, ticket management, and PR workflows. Your job? Monitor and prompt. Step in via native apps only when needed (merging PRs, manual ticket moves).

## Features

### Current Scope (MVP)

| Tab              | Description                     | Mode        |
| ---------------- | ------------------------------- | ----------- |
| **Confluence**   | View project documentation      | Read-only   |
| **Sprint Board** | Current sprint Jira board       | Read-only   |
| **Backlog**      | Jira backlog view               | Read-only   |
| **Issues**       | Jira issue list/search          | Read-only   |
| **Copilot Chat** | Send prompts to VS Code Copilot | Interactive |

### Authentication

- **Primary:** GitHub OAuth
- **Fallback:** Google OAuth

### Core Functionality

- Real-time chat with VS Code Copilot on your Mac
- **Remote Approval Controls** - Approve/reject Copilot actions from your phone:
  - **Tool Calls:** Allow / Skip tool execution
  - **Code Changes:** Keep / Discard edits
  - **File Operations:** Approve / Deny creates, deletes, moves
  - Push notifications for pending approvals
- **Model & Mode Selection:**
  - Switch between models (GPT-4o, Claude Sonnet, etc.)
  - Toggle modes: Agent / Ask / Edit
  - See current model/mode status
- **File Context Controls:**
  - Browse workspace files from your phone
  - Add files to chat context (@file)
  - View currently attached files
  - Quick-add recently edited files
  - Add folder context (@folder)
- **Skills & Participants:**
  - Tag built-in participants (@workspace, @terminal, @vscode)
  - Tag custom skills installed in workspace
  - See available skills with descriptions
  - Favorite frequently-used skills
- **Session History:**
  - Browse previous chat sessions (workspace-bound)
  - Resume prior conversations
  - Search session history
- **Live Workspace Visibility:**
  - Real-time file activity (which files Copilot is reading/editing)
  - Terminal output streaming (watch commands execute live)
  - Git status dashboard (uncommitted changes, branch, ahead/behind)
  - Problems/diagnostics count (errors/warnings at a glance)
  - Open files list (what's currently open in VS Code)
  - Syntax-highlighted code diff viewer
- **Remote Control:**
  - Stop/cancel runaway Copilot operations
  - Undo last Copilot action (one-tap revert)
  - Run terminal commands directly (`npm test`, `git pull`, etc.)
  - Quick Git actions (commit, push, branch, stash)
  - Trigger builds/tests and watch results
  - Force-open specific files in VS Code
- **Smart Prompting:**
  - Voice-to-text prompts (dictate while walking the dog)
  - Prompt templates (save & reuse common prompts)
  - Prompt history (quick re-send recent prompts)
  - Context-aware suggestions based on current file/errors
- **Notifications & Alerts:**
  - Build/test completion notifications
  - New error alerts (TypeScript/ESLint errors detected)
  - Task completion alerts (long-running Copilot tasks)
  - Idle detection (Copilot waiting for you)
- **Developer UX:**
  - Syntax-highlighted code previews
  - Dark mode (obviously)
  - Haptic feedback for approvals
  - iOS Home Screen widgets (status + pending approvals)
  - Apple Watch companion app (approve from your wrist 🔥)
- **CI/CD & GitHub Integration:**
  - GitHub PR status (CI passed, reviews pending)
  - Pipeline view (GitHub Actions status)
- View Confluence pages for project context
- Monitor Jira sprint progress and backlog
- Session persistence across app restarts

## Architecture

### High-Level Overview

```
┌─────────────────┐         ┌─────────────────────────┐
│   iOS App       │   WSS   │   Mac (Relay Server)    │
│   (SwiftUI)     │◄───────►│   + VS Code + Copilot   │
└─────────────────┘         └─────────────────────────┘
        │                              │
        │ HTTPS                        │ MCP
        ▼                              ▼
┌─────────────────┐         ┌─────────────────────────┐
│  Atlassian API  │         │  GitHub, Confluence,    │
│  (Jira/Confl.)  │         │  Jira (via MCP tools)   │
└─────────────────┘         └─────────────────────────┘
```

### Components

#### 1. iOS App (Swift + SwiftUI)

- **UI Framework:** SwiftUI with tab-based navigation
- **Networking:** URLSession for REST, URLSessionWebSocketTask for WebSocket
- **Auth:** ASWebAuthenticationSession (OAuth flows)
- **Storage:** Keychain (tokens), UserDefaults (preferences), SwiftData (local cache)
- **Min Target:** iOS 17.0

#### 2. Relay Server (runs on your Mac)

A lightweight local server that bridges the iOS app to VS Code Copilot.

- **Runtime:** Node.js or Swift CLI
- **Protocol:** WebSocket for real-time chat
- **Integration:** Communicates with VS Code Copilot via:
  - VS Code Extension API, or
  - Copilot CLI proxy, or
  - Local HTTP server exposed by a VS Code extension
- **Security:** Local network only (or tunneled via ngrok/Tailscale for remote)

#### 3. Atlassian Integration

- Direct API calls from iOS app to Atlassian Cloud
- OAuth 2.0 (3LO) for authentication
- Endpoints: Confluence REST API, Jira REST API v3

## Tech Stack

| Layer               | Technology                                         |
| ------------------- | -------------------------------------------------- |
| **Mobile App**      | Swift 5.9+, SwiftUI, Combine                       |
| **Local Relay**     | Node.js (ws, express) or Swift (Vapor/Hummingbird) |
| **Auth**            | OAuth 2.0 (GitHub, Google, Atlassian)              |
| **Communication**   | WebSocket (app ↔ relay), REST (app ↔ Atlassian)    |
| **Storage**         | Keychain, SwiftData, UserDefaults                  |
| **IDE Integration** | VS Code Extension API / Copilot CLI                |

## Project Structure

```
remote-pilot/
├── README.md
├── .agents/                    # Copilot directives & skills
│   ├── skills/
│   └── workflows/
├── ios/                        # Xcode project
│   └── RemotePilot/
│       ├── App/
│       │   └── RemotePilotApp.swift
│       ├── Features/
│       │   ├── Auth/
│       │   ├── Chat/
│       │   ├── Confluence/
│       │   ├── Jira/
│       │   └── Settings/
│       ├── Core/
│       │   ├── Networking/
│       │   ├── Models/
│       │   └── Services/
│       └── Resources/
├── relay/                      # Local relay server
│   ├── src/
│   └── package.json
└── docs/
    ├── SETUP.md
    ├── ARCHITECTURE.md
    └── API.md
```

## User Stories

### Authentication

- [ ] **US-001:** As a user, I can sign in with GitHub OAuth to authenticate
- [ ] **US-002:** As a user, I can sign in with Google OAuth as an alternative
- [ ] **US-003:** As a user, I can connect my Atlassian account for Jira/Confluence access
- [ ] **US-004:** As a user, my sessions persist so I don't re-auth on every launch

### Confluence

- [ ] **US-010:** As a user, I can view a list of Confluence spaces
- [ ] **US-011:** As a user, I can browse pages within a space
- [ ] **US-012:** As a user, I can read page content with proper formatting

### Jira - Sprint Board

- [ ] **US-020:** As a user, I can view the current sprint board
- [ ] **US-021:** As a user, I can see ticket status (To Do, In Progress, Done)
- [ ] **US-022:** As a user, I can tap a ticket to view details

### Jira - Backlog

- [ ] **US-030:** As a user, I can view the product backlog
- [ ] **US-031:** As a user, I can see story points and priority

### Jira - Issues

- [ ] **US-040:** As a user, I can search/filter issues
- [ ] **US-041:** As a user, I can view issue details (description, comments, attachments)

### Copilot Chat

- [ ] **US-050:** As a user, I can connect to my Mac's relay server
- [ ] **US-051:** As a user, I can send text prompts to VS Code Copilot
- [ ] **US-052:** As a user, I can see Copilot's responses in real-time
- [ ] **US-053:** As a user, I can view chat history within a session
- [ ] **US-054:** As a user, I can see connection status (connected/disconnected)

### Remote Approval Controls

- [ ] **US-055:** As a user, I can see pending Copilot actions requiring approval
- [ ] **US-056:** As a user, I can Allow or Skip tool execution requests
- [ ] **US-057:** As a user, I can Keep or Discard code changes
- [ ] **US-058:** As a user, I can Approve or Deny file operations (create/delete/move)
- [ ] **US-059:** As a user, I receive push notifications when approval is needed

### Model & Mode Controls

- [ ] **US-070:** As a user, I can see the current Copilot model in use
- [ ] **US-071:** As a user, I can switch between available models (GPT-4o, Claude, etc.)
- [ ] **US-072:** As a user, I can toggle between Agent / Ask / Edit modes
- [ ] **US-073:** As a user, I can see mode-specific UI hints (e.g., Agent shows tool activity)

### Session History

- [ ] **US-080:** As a user, I can view a list of previous chat sessions for the connected workspace
- [ ] **US-081:** As a user, I can tap a session to view its full conversation history
- [ ] **US-082:** As a user, I can resume a previous session (continue the conversation)
- [ ] **US-083:** As a user, I can search across session history
- [ ] **US-084:** As a user, I can delete old sessions

### File Context

- [ ] **US-090:** As a user, I can browse the workspace file tree from my phone
- [ ] **US-091:** As a user, I can add files to chat context (@file) by selecting them
- [ ] **US-092:** As a user, I can see which files are currently attached to the chat
- [ ] **US-093:** As a user, I can remove files from context
- [ ] **US-094:** As a user, I can quick-add recently edited files
- [ ] **US-095:** As a user, I can add entire folders to context (@folder)
- [ ] **US-096:** As a user, I can search for files by name

### Skills & Participants

- [ ] **US-100:** As a user, I can see a list of available chat participants (@workspace, @terminal, etc.)
- [ ] **US-101:** As a user, I can tap a participant to add it to my prompt
- [ ] **US-102:** As a user, I can see custom skills installed in the workspace
- [ ] **US-103:** As a user, I can view skill descriptions before using them
- [ ] **US-104:** As a user, I can favorite frequently-used skills for quick access
- [ ] **US-105:** As a user, I can see which skills are currently tagged in my prompt

### Live Workspace Visibility

- [ ] **US-110:** As a user, I can see which files Copilot is currently reading/editing in real-time
- [ ] **US-111:** As a user, I can stream terminal output and watch commands execute live
- [ ] **US-112:** As a user, I can see Git status (uncommitted changes, current branch, ahead/behind)
- [ ] **US-113:** As a user, I can see Problems/Diagnostics count (errors and warnings)
- [ ] **US-114:** As a user, I can see a list of currently open files in VS Code
- [ ] **US-115:** As a user, I can view syntax-highlighted diffs of Copilot's changes

### Remote Control

- [ ] **US-120:** As a user, I can stop/cancel a runaway Copilot operation
- [ ] **US-121:** As a user, I can undo the last Copilot action with one tap
- [ ] **US-122:** As a user, I can run terminal commands directly from my phone
- [ ] **US-123:** As a user, I can perform quick Git actions (commit, push, branch, stash)
- [ ] **US-124:** As a user, I can trigger builds/tests and watch results stream in
- [ ] **US-125:** As a user, I can force-open a specific file in VS Code

### Smart Prompting

- [ ] **US-130:** As a user, I can use voice-to-text to dictate prompts
- [ ] **US-131:** As a user, I can save prompt templates for reuse
- [ ] **US-132:** As a user, I can quickly re-send prompts from my history
- [ ] **US-133:** As a user, I can see context-aware prompt suggestions based on current file/errors
- [ ] **US-134:** As a user, I can organize prompt templates into categories

### Notifications & Alerts

- [ ] **US-140:** As a user, I receive push notifications when builds/tests complete
- [ ] **US-141:** As a user, I receive alerts when new TypeScript/ESLint errors are detected
- [ ] **US-142:** As a user, I receive notifications when long-running Copilot tasks finish
- [ ] **US-143:** As a user, I receive idle alerts when Copilot has been waiting for my input
- [ ] **US-144:** As a user, I can configure which notification types I want to receive

### Developer UX

- [ ] **US-150:** As a user, I can toggle dark/light mode
- [ ] **US-151:** As a user, I get haptic feedback for approval actions
- [ ] **US-152:** As a user, I can add an iOS Home Screen widget showing connection status and pending approvals
- [ ] **US-153:** As a user, I can use an Apple Watch companion app to approve/reject actions
- [ ] **US-154:** As a user, I can view code with syntax highlighting

### CI/CD & GitHub

- [ ] **US-160:** As a user, I can see the status of my GitHub PRs (CI status, reviews)
- [ ] **US-161:** As a user, I can view GitHub Actions pipeline status
- [ ] **US-162:** As a user, I receive notifications when CI/CD jobs complete

### Settings & Config

- [ ] **US-060:** As a user, I can configure my relay server URL
- [ ] **US-061:** As a user, I can select which Jira project to display
- [ ] **US-062:** As a user, I can select which Confluence space to display

## Requirements

### Functional Requirements

1. **FR-001:** App must authenticate via OAuth 2.0 (GitHub primary, Google fallback)
2. **FR-002:** App must maintain WebSocket connection to relay server
3. **FR-003:** App must fetch and display Confluence pages via REST API
4. **FR-004:** App must fetch and display Jira boards/issues via REST API
5. **FR-005:** App must send/receive chat messages to/from VS Code Copilot
6. **FR-006:** App must handle offline gracefully (cached data, reconnection)
7. **FR-007:** App must display pending approval requests from Copilot in real-time
8. **FR-008:** App must send approval/rejection decisions back to VS Code extension
9. **FR-009:** VS Code extension must intercept Copilot approval prompts and relay to app
10. **FR-010:** App must query and display available Copilot models from VS Code
11. **FR-011:** App must send model change commands to VS Code extension
12. **FR-012:** App must toggle Copilot mode (Agent/Ask/Edit) via extension commands
13. **FR-013:** App must fetch session history from VS Code workspace storage
14. **FR-014:** App must support resuming previous chat sessions
15. **FR-015:** Extension must expose workspace file tree via API
16. **FR-016:** App must send file paths to attach as @file context
17. **FR-017:** App must send folder paths to attach as @folder context
18. **FR-018:** Extension must track and report currently attached context
19. **FR-019:** Extension must enumerate available chat participants/skills
20. **FR-020:** App must send participant tags with prompts (@workspace, @terminal, etc.)
21. **FR-021:** App must display skill metadata (name, description, source)
22. **FR-022:** App must persist favorite skills locally
23. **FR-023:** Extension must stream real-time file activity to app
24. **FR-024:** Extension must stream terminal output to app
25. **FR-025:** Extension must expose Git status via API
26. **FR-026:** Extension must report diagnostics/problems count
27. **FR-027:** Extension must list currently open editor tabs
28. **FR-028:** Extension must generate and send syntax-highlighted diffs
29. **FR-029:** App must send stop/cancel commands to terminate Copilot operations
30. **FR-030:** Extension must support undo of last Copilot action
31. **FR-031:** App must execute terminal commands via extension
32. **FR-032:** App must execute Git commands via extension
33. **FR-033:** App must trigger build/test tasks via extension
34. **FR-034:** App must force-open files in VS Code via extension
35. **FR-035:** App must support iOS Speech Recognition for voice input
36. **FR-036:** App must persist and manage prompt templates locally
37. **FR-037:** App must store and display prompt history
38. **FR-038:** Extension must provide context-aware prompt suggestions
39. **FR-039:** App must register for and receive push notifications (APNs)
40. **FR-040:** Extension must send notification payloads for key events
41. **FR-041:** App must support WidgetKit for Home Screen widgets
42. **FR-042:** App must support WatchKit for Apple Watch companion
43. **FR-043:** App must fetch GitHub PR status via GitHub API
44. **FR-044:** App must fetch GitHub Actions workflow status

### Non-Functional Requirements

1. **NFR-001:** iOS 17.0+ support
2. **NFR-002:** Response time < 500ms for local relay communication
3. **NFR-003:** Secure token storage (Keychain)
4. **NFR-004:** App should work on local network without internet (except Atlassian)
5. **NFR-005:** Battery-efficient WebSocket management

### Security Requirements

1. **SR-001:** All tokens stored in iOS Keychain
2. **SR-002:** WebSocket connections use WSS when over public network
3. **SR-003:** No sensitive data in logs or UserDefaults
4. **SR-004:** Relay server only accepts connections from authenticated clients

## Setup Guide

### Prerequisites

- macOS 14+ (Sonnet)
- Xcode 15+
- Node.js 20+ (for relay server)
- VS Code with GitHub Copilot extension
- Atlassian Cloud account (Jira + Confluence)
- GitHub account

### iOS App Setup

```bash
# Clone the repo
git clone https://github.com/yourusername/remote-pilot.git

# Open in Xcode
cd remote-pilot/ios
open RemotePilot.xcodeproj

# Configure OAuth credentials in Config.plist
# Build and run on your device/simulator
```

### Relay Server Setup

```bash
cd remote-pilot/relay

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Start the server
npm start
```

### Atlassian OAuth Setup

1. Go to [Atlassian Developer Console](https://developer.atlassian.com/console/myapps/)
2. Create a new OAuth 2.0 app
3. Add scopes: `read:confluence-content.all`, `read:jira-work`, `read:jira-user`
4. Set callback URL to your app's custom URL scheme
5. Copy Client ID/Secret to app config

## Roadmap

> Using Now/Next/Later framework for realistic planning. Features move between phases as priorities evolve.

### 🚀 v1.0 - MVP ("Now" - Sprint 1-3)

**Goal:** Get chatting with Copilot remotely ASAP

| Feature                         | Priority | Story IDs      |
| ------------------------------- | -------- | -------------- |
| GitHub OAuth login              | P0       | US-001         |
| Basic relay server (Node.js)    | P0       | US-050         |
| WebSocket connection management | P0       | US-054         |
| Send prompts to Copilot         | P0       | US-051         |
| Receive Copilot responses       | P0       | US-052         |
| Basic chat UI                   | P0       | US-053         |
| Confluence space browser        | P1       | US-010, US-011 |
| Confluence page viewer          | P1       | US-012         |
| Jira sprint board view          | P1       | US-020, US-021 |
| Jira issue details              | P1       | US-022         |

**Technical Milestones:**

- [ ] Xcode project scaffolded with SwiftUI
- [ ] Relay server accepts WebSocket connections
- [ ] VS Code extension skeleton (minimal - just relay bridge)
- [ ] End-to-end message flow working
- [ ] Basic Atlassian API integration

---

### ⚡ v1.1 - Core Remote Controls ("Next" - Sprint 4-6)

**Goal:** Control Copilot like you're sitting at your desk

| Feature                         | Priority | Story IDs      |
| ------------------------------- | -------- | -------------- |
| **Remote Approvals**            | P0       | US-055-059     |
| Allow/Skip tool execution       | P0       | US-056         |
| Keep/Discard code changes       | P0       | US-057         |
| Approve/Deny file operations    | P0       | US-058         |
| Model selection                 | P1       | US-070, US-071 |
| Mode switching (Agent/Ask/Edit) | P1       | US-072, US-073 |
| File context (@file)            | P1       | US-090-096     |
| Skills & participants tagging   | P2       | US-100-105     |

**Technical Milestones:**

- [ ] Extension intercepts Copilot approval dialogs
- [ ] Bidirectional approval flow working
- [ ] Model/mode switching via extension commands
- [ ] File tree API exposed over WebSocket

---

### 📊 v1.2 - Live Visibility ("Next" - Sprint 7-9)

**Goal:** See what Copilot is doing in real-time

| Feature                        | Priority | Story IDs |
| ------------------------------ | -------- | --------- |
| Live file activity indicator   | P0       | US-110    |
| Terminal output streaming      | P0       | US-111    |
| Syntax-highlighted diff viewer | P0       | US-115    |
| Git status dashboard           | P1       | US-112    |
| Problems/diagnostics count     | P1       | US-113    |
| Open files list                | P2       | US-114    |

**Technical Milestones:**

- [ ] Extension streams editor events
- [ ] Terminal output captured and forwarded
- [ ] Diff generation with syntax highlighting
- [ ] Git status polling implemented

---

### 🎮 v2.0 - Full Remote Control ("Later" - Sprint 10-12)

**Goal:** Do everything without touching your Mac

| Feature                        | Priority | Story IDs  |
| ------------------------------ | -------- | ---------- |
| Stop/cancel Copilot operations | P0       | US-120     |
| Undo last action               | P0       | US-121     |
| Run terminal commands          | P1       | US-122     |
| Quick Git actions              | P1       | US-123     |
| Trigger builds/tests           | P1       | US-124     |
| Force-open files               | P2       | US-125     |
| Session history browser        | P1       | US-080-084 |
| Resume previous sessions       | P1       | US-082     |

**Technical Milestones:**

- [ ] Command execution via extension
- [ ] Git operations via extension
- [ ] Task runner integration
- [ ] Session persistence in workspace storage

---

### 🎤 v2.1 - Smart Prompting ("Later" - Sprint 13-14)

**Goal:** Prompt smarter, not harder

| Feature                   | Priority | Story IDs      |
| ------------------------- | -------- | -------------- |
| Voice-to-text prompts     | P0       | US-130         |
| Prompt templates          | P1       | US-131, US-134 |
| Prompt history            | P1       | US-132         |
| Context-aware suggestions | P2       | US-133         |

**Technical Milestones:**

- [ ] iOS Speech Recognition integration
- [ ] Template storage and management
- [ ] Suggestion engine based on workspace state

---

### 🔔 v2.2 - Notifications & Alerts ("Later" - Sprint 15-16)

**Goal:** Never miss what matters

| Feature                          | Priority | Story IDs |
| -------------------------------- | -------- | --------- |
| Push notifications for approvals | P0       | US-059    |
| Build/test completion alerts     | P1       | US-140    |
| Error detection alerts           | P1       | US-141    |
| Task completion notifications    | P1       | US-142    |
| Idle detection                   | P2       | US-143    |
| Notification preferences         | P2       | US-144    |

**Technical Milestones:**

- [ ] APNs integration
- [ ] Relay server pushes to APNs
- [ ] Notification payload design
- [ ] User preference storage

---

### ⌚ v3.0 - Platform Expansion ("Future")

**Goal:** Remote Pilot everywhere

| Feature                      | Priority | Story IDs |
| ---------------------------- | -------- | --------- |
| iOS Home Screen widgets      | P1       | US-152    |
| Apple Watch companion app    | P1       | US-153    |
| GitHub PR status view        | P2       | US-160    |
| GitHub Actions pipeline view | P2       | US-161    |
| CI/CD notifications          | P2       | US-162    |
| Dark mode                    | P0       | US-150    |
| Haptic feedback              | P1       | US-151    |

**Technical Milestones:**

- [ ] WidgetKit extension
- [ ] WatchKit app target
- [ ] GitHub GraphQL API integration
- [ ] Shared data layer for widget/watch

---

### 🌐 v3.1 - Multi-Device & Sharing ("Future")

**Goal:** Use it anywhere, share with your team

| Feature                           | Priority | Story IDs |
| --------------------------------- | -------- | --------- |
| Remote access via Tailscale/ngrok | P1       | -         |
| Multi-device support              | P2       | -         |
| Share relay with team members     | P2       | -         |
| iPad optimized layout             | P2       | -         |
| macOS Catalyst port               | P3       | -         |

---

### 📈 Version Summary

| Version  | Theme      | Key Deliverable                  | Est. Sprints |
| -------- | ---------- | -------------------------------- | ------------ |
| **v1.0** | MVP        | Chat with Copilot remotely       | 3            |
| **v1.1** | Control    | Remote approvals + model/mode    | 3            |
| **v1.2** | Visibility | Live workspace monitoring        | 3            |
| **v2.0** | Power      | Full remote terminal/git control | 3            |
| **v2.1** | Efficiency | Voice + templates                | 2            |
| **v2.2** | Awareness  | Push notifications               | 2            |
| **v3.0** | Platform   | Widget + Watch                   | 3            |
| **v3.1** | Scale      | Multi-device + sharing           | 2            |

**Total estimated: ~21 sprints (42 weeks / ~10 months)**

> 💡 Reality check: v1.0-v1.1 is the real MVP. Everything else is gravy. Ship fast, iterate faster.

## Agent Skills

This project uses [skills.sh](https://skills.sh) skills for AI-assisted development. All skills below have **PASS** ratings on all three security audits (Agent Trust Hub, Socket, Snyk).

### Installed Skills

```bash
# iOS Development
npx skills add https://github.com/thebushidocollective/han --skill ios-swiftui-patterns
npx skills add https://github.com/dagba/ios-mcp --skill swiftui-performance-audit

# Atlassian Integration
npx skills add https://github.com/alirezarezvani/claude-skills --skill atlassian-admin

# VS Code Extension Development
npx skills add https://github.com/kjgarza/marketplace-claude --skill vscode-extension-builder

# Project Planning & Roadmaps
npx skills add https://github.com/anthropics/knowledge-work-plugins --skill roadmap-management
npx skills add https://github.com/borghei/claude-skills --skill product-manager-toolkit
```

### Skill Safety Ratings

| Skill                       | Agent Trust Hub | Socket  | Snyk    | Purpose                                 |
| --------------------------- | --------------- | ------- | ------- | --------------------------------------- |
| `ios-swiftui-patterns`      | ✅ PASS         | ✅ PASS | ✅ PASS | SwiftUI state, navigation, architecture |
| `swiftui-performance-audit` | ✅ PASS         | ✅ PASS | ✅ PASS | Performance profiling & optimization    |
| `atlassian-admin`           | ✅ PASS         | ✅ PASS | ✅ PASS | Jira/Confluence API patterns            |
| `vscode-extension-builder`  | ✅ PASS         | ✅ PASS | ✅ PASS | VS Code extension development           |
| `roadmap-management`        | ✅ PASS         | ✅ PASS | ✅ PASS | Now/Next/Later planning, prioritization |
| `product-manager-toolkit`   | ✅ PASS         | ✅ PASS | ✅ PASS | PRDs, RICE scoring, user research       |

## Contributing

This is a personal project, but the repo is public for portfolio purposes. If you want to use it:

1. Fork the repo
2. Set up your own OAuth apps
3. Configure your relay server
4. Customize for your workflow

## License

MIT

---

_Built for lazy productivity by [@seantokuzo](https://github.com/seantokuzo)_
