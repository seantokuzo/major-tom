# Major Tom — Project Instructions

> Extends global `~/.claude/CLAUDE.md`. Project-specific rules live here.

---

## Project Overview

Major Tom is a native iOS app for controlling Claude Code from your iPhone. It consists of three components:

1. **iOS App** (`ios/`) — SwiftUI + SpriteKit, iOS 17+
2. **Relay Server** (`relay/`) — Node.js + TypeScript, WebSocket hub
3. **VSCode Extension** (`vscode-extension/`) — Companion bridge extension

See [docs/PLANNING.md](docs/PLANNING.md) for architecture, protocol spec, and roadmap.

---

## Before You Code

1. **Read the planning doc** — `docs/PLANNING.md` is the source of truth for architecture and protocol
2. **Read relevant skills** — Use the `Read` tool on `.agents/skills/` before implementing any feature
3. **Check Context7** — For ALL library APIs (SwiftUI, SpriteKit, node-pty, ws, VSCode API). Never trust training data.
4. **Check npm versions** — `npm view <package> version` before adding dependencies
5. **Read agent files** — `.agents/agents/` contains role-specific guidance for each component

---

## Tech Stack & Conventions

### iOS App (`ios/MajorTom/`)

| Concern | Convention |
|---------|-----------|
| Min target | iOS 17.0 |
| UI framework | SwiftUI only (no UIKit unless absolutely necessary) |
| State management | `@Observable` (iOS 17+), NOT `@ObservableObject` |
| Async | Swift Concurrency (async/await, actors), NOT Combine |
| Data | SwiftData for persistence |
| Secrets | Keychain only |
| Game engine | SpriteKit via `SpriteView` |
| Architecture | MVVM — Views observe ViewModels, ViewModels call Services |
| File naming | PascalCase for types, match filename to primary type |
| Feature structure | `Features/{Name}/Views/`, `Features/{Name}/ViewModels/`, `Features/{Name}/Components/` |

### Relay Server (`relay/`)

| Concern | Convention |
|---------|-----------|
| Runtime | Node.js 22+ |
| Language | TypeScript (strict mode) |
| Package manager | npm |
| WebSocket | `ws` library |
| PTY | `node-pty` for Claude Code CLI |
| Architecture | Adapter pattern — each target implements `IAdapter` |
| Error handling | Typed errors, no silent catches |
| Logging | Structured JSON logging (pino) |

### VSCode Extension (`vscode-extension/`)

| Concern | Convention |
|---------|-----------|
| Language | TypeScript |
| API | VSCode Extension API |
| Bundler | esbuild |
| Activation | On command or when Claude Code extension detected |

### Cross-Cutting

| Concern | Convention |
|---------|-----------|
| Protocol | JSON over WebSocket — see `docs/PLANNING.md` protocol section |
| Message types | Always include `type` field for routing |
| IDs | UUID v4 for sessions, requests, agents |
| Dates | ISO 8601 strings in protocol, native Date types internally |

---

## Git Conventions

- **Atomic commits** — one logical change per commit
- **Commit format** — `type(scope): description` (e.g., `feat(relay): add CLI adapter PTY spawn`)
- **Types** — `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- **Scopes** — `ios`, `relay`, `extension`, `docs`, `agents`
- **Branch naming** — `phase-N/feature-name` (e.g., `phase-1/cli-adapter`)

---

## Agent Workflow (GSD-Inspired)

This project uses a **thin orchestrator, fat workers** pattern:

1. **Orchestrator** stays lean — discovers work, groups into parallel waves, spawns subagents
2. **Subagents** get fresh context — each handles one component (iOS, relay, extension, sprites)
3. **No nesting** — subagents never spawn sub-subagents
4. **Atomic tasks** — one task = one commit
5. **PR review pipeline** — after every PR, run the automated review loop (see `.agents/skills/pr-review-pipeline/SKILL.md`)
6. **Auto-merge after clean review** — merge is earned after the review pipeline passes clean

### PR Review Pipeline

Canonical rules live in `~/.claude/CLAUDE.md` under **"PR Review Workflow"**. Summary:

1. **Polling:** 2m first poll, 1m subsequent. Never poll sooner.
2. **Completion detection:** count reviews with body containing `"Pull request overview"`. Round N is complete when N such reviews exist.
3. **5-comment threshold:** `<5` comments in the round → merge. `≥5` → request another round.
4. **Replies:** inline to each comment thread (never batched), with commit SHA for fixes or cited reasoning for pushback.
5. **Post-merge:** `git checkout main && git pull`, update `docs/STATE.md`, prep next phase prompt.
6. **Override:** if the user says "wait for me", stop after PR creation — don't poll/merge.

Execution details (bash commands, triage table, reply formats) are in `.agents/skills/pr-review-pipeline/SKILL.md`. That skill MUST align with the canonical rules — if it drifts, fix the skill.

### Context Management

- Keep main orchestrator context under 50% capacity
- Spawn subagents for any task touching 5+ files
- Pass file **paths** to subagents, not file contents
- Use agent files in `.agents/agents/` for role-specific prompts

### Agent Files

Agent directives live in `.agents/agents/`:

| Agent | Role | Scope |
|-------|------|-------|
| `mt-orchestrator.md` | Thin coordinator | Task decomposition, wave scheduling |
| `mt-ios-engineer.md` | iOS specialist | SwiftUI, SpriteKit, iOS app code |
| `mt-relay-engineer.md` | Backend specialist | Node.js relay server, adapters |
| `mt-extension-engineer.md` | VSCode specialist | Companion extension |
| `mt-sprite-artist.md` | Game/art specialist | SpriteKit scenes, sprites, animations |
| `mt-researcher.md` | Research specialist | Context7, docs, API investigation |

---

## Quality Gates

Before marking any task complete:

1. **Code compiles** — no type errors, no build failures
2. **No regressions** — existing functionality still works
3. **Protocol compliance** — messages match the spec in PLANNING.md
4. **Convention compliance** — follows the conventions in this file
5. **Security** — no secrets in code, no sensitive data in logs

---

## What NOT To Do

- Don't use UIKit in the iOS app (SwiftUI only, iOS 17+)
- Don't use Combine (use async/await)
- Don't use `@ObservableObject` / `@StateObject` (use `@Observable`)
- Don't guess library APIs — always verify with Context7
- Don't guess package versions — always check with `npm view`
- Don't nest subagents (orchestrator → workers, never workers → sub-workers)
- Don't paste file contents into agent prompts (pass paths instead)
