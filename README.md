# Remote Pilot 🛩️

> Control VS Code Copilot from your iPhone. Approve code changes from your couch.

<!-- TODO: Add demo gif -->
<!-- ![Demo](docs/assets/demo.gif) -->

## What is this?

Remote Pilot is a native iOS app that lets you interact with VS Code Copilot running on your Mac—without touching your keyboard.

**The killer feature:** When Copilot asks "Allow/Skip" or "Keep/Discard", you approve it from your phone. Peak lazy productivity.

## Features

🤖 **Remote Copilot Chat** — Send prompts, see responses in real-time

✅ **Approval Controls** — Allow/Skip tool calls, Keep/Discard changes from your phone

🔀 **Model & Mode Switching** — Change models (GPT-4o, Claude) and modes (Agent/Ask/Edit)

📁 **File Context** — Browse workspace files, add @file references remotely

📋 **Jira Integration** — View sprint board, backlog, and issues

📖 **Confluence Integration** — Read project docs for context

📊 **Live Visibility** — See what files Copilot is editing, terminal output, git status

🎤 **Voice Prompts** — Dictate prompts with Speech Recognition

⌚ **Apple Watch** — Approve actions from your wrist (coming soon)

## Tech Stack

| Component         | Technology                    |
| ----------------- | ----------------------------- |
| iOS App           | Swift 5.9+, SwiftUI, iOS 17+  |
| Relay Server      | Node.js + WebSocket           |
| VS Code Extension | TypeScript                    |
| Auth              | OAuth 2.0 (GitHub, Atlassian) |

## Architecture

```
┌─────────────────┐         ┌─────────────────────────┐
│   iOS App       │   WSS   │   Mac (Relay Server)    │
│   (SwiftUI)     │◄───────►│   + VS Code Extension   │
└─────────────────┘         └─────────────────────────┘
        │                              │
        │ HTTPS                        │ VS Code API
        ▼                              ▼
┌─────────────────┐         ┌─────────────────────────┐
│  Atlassian API  │         │  GitHub Copilot Chat    │
└─────────────────┘         └─────────────────────────┘
```

## Project Status

🚧 **In Development** — Building toward v1.0 MVP

See [docs/PLANNING.md](docs/PLANNING.md) for detailed roadmap, user stories, and requirements.

## Getting Started

> Full setup guide coming soon. For now, see [docs/PLANNING.md](docs/PLANNING.md#setup-guide).

### Quick Start

```bash
# Clone the repo
git clone https://github.com/seantokuzo/remote-pilot.git
cd remote-pilot

# iOS app - open in Xcode
open ios/RemotePilot.xcodeproj

# Relay server
cd relay && npm install && npm start
```

## Documentation

| Doc                                     | Description                               |
| --------------------------------------- | ----------------------------------------- |
| [PLANNING.md](docs/PLANNING.md)         | Full roadmap, user stories, requirements  |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Technical deep-dive (coming soon)         |
| [SETUP.md](docs/SETUP.md)               | Detailed setup instructions (coming soon) |

## Why?

Because sometimes you want to:

- Monitor a long Copilot task from another room
- Approve code changes while making coffee
- Check your sprint board without context switching
- Feel like a wizard controlling your IDE remotely

## Contributing

This is a personal/portfolio project, but the code is open. Feel free to fork and adapt for your workflow.

## License

MIT

---

_Built for lazy productivity by [@seantokuzo](https://github.com/seantokuzo)_
