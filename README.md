# Major Tom

> Control Claude Code from your iPhone. Watch your AI agents work in a pixel art office.

## What is this?

Major Tom is a native iOS app that gives you **complete mobile control** over Claude Code sessions running on your Mac. Leave a CLI session running, head out the door, and keep steering from your phone.

**The killer feature:** When Claude Code asks "Allow tool call?", you approve it from the couch. Or the park. Or the grocery store.

**The fun feature:** A gamified Zelda-style pixel art office where your Claude orchestrator and subagents are little animated characters. They walk to their desks when working, hang in the break room when idle, and you can tap them to see what they're thinking.

## Features

**Remote Control** — Send prompts, see streaming responses, approve/deny tool calls

**Full Approval Flow** — Allow / Skip / Deny / Allow Always — every button, from your phone

**Multi-Target** — Control Claude Code CLI sessions and the VSCode extension

**Agent Office** — SpriteKit pixel art office with animated agent characters

**Tap to Inspect** — Tap any agent to see their task, output stream, and steer them

**Live Visibility** — See files being edited, terminal output, git status in real-time

**Voice Prompts** — Dictate prompts while walking the dog

## Architecture

```
┌──────────────┐         ┌──────────────────────────┐
│  iOS App     │   WSS   │  Mac                     │
│  SwiftUI +   │◄───────►│  Relay Server (Node.js)  │
│  SpriteKit   │         │  ├── CLI Adapter (PTY)   │
└──────────────┘         │  └── VSCode Adapter      │
                         └──────────────────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS App | Swift 5.9+, SwiftUI, SpriteKit, iOS 17+ |
| Relay Server | Node.js 22+, TypeScript, ws, node-pty |
| VSCode Extension | TypeScript, VSCode Extension API |
| Communication | WebSocket (JSON protocol) |

## Project Status

**In Development** — Building toward v1.0 (CLI chat + approval flow)

See [docs/PLANNING.md](docs/PLANNING.md) for the full roadmap, architecture, and protocol spec.

## Roadmap

| Version | Theme | What You Get |
|---------|-------|-------------|
| v1.0 | Foundation | Chat + approve tool calls from phone |
| v1.1 | Full Control | VSCode bridge, live visibility, file context |
| v2.0 | The Office | Gamified agent visualization |
| v2.1 | Delight | Voice, templates, notifications |
| v3.0 | Everywhere | Apple Watch, widgets |

## Getting Started

> Full setup guide coming with v1.0.

```bash
# Clone
git clone https://github.com/seantokuzo/major-tom.git
cd major-tom

# Relay server
cd relay && npm install && npm start

# iOS app — open in Xcode
open ios/MajorTom.xcodeproj
```

## License

MIT

---

_Built for lazy productivity._
