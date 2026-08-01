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

This project uses a **thin orchestrator, fat workers** pattern. The role split is canonical in `~/.claude/CLAUDE.md` under **"Orchestrator Role"** — research, planning, spec writing, implementation, review, and shipping all go to subagents; the orchestrator keeps task decomposition, wave scheduling, conflict analysis, judging/merge, and reporting.

1. **Orchestrator** stays lean — discovers work, groups into parallel waves, spawns subagents; it does not implement
2. **Subagents** get fresh context — each handles one component (iOS, relay, extension, sprites)
3. **No nesting** — subagents never spawn sub-subagents
4. **Atomic tasks** — one task = one commit
5. **Local review pipeline** — after every PR, run the review loop below with specialist subagents
6. **Auto-merge after clean review** — merge is earned after the review pipeline passes clean

### Code Review Pipeline

Canonical autonomous loop lives in `~/.claude/CLAUDE.md` under **"Code Review Workflow"**. Reviews run **locally**: the orchestrating agent spawns read-only specialist subagents against the diff. Nothing reviews this repo automatically — no bot comments, no PR-open review, no verdict stickies. The brief you hand each reviewer is **"Local Code Review"** below.

| What's live on GitHub | Status |
|---|---|
| `.github/workflows/ci.yml` | **Live** — lint / typecheck / test / build relay. Merge gate. |
| `.github/workflows/release.yml` | **Live** |
| `claude.yml`, `claude-code-review.yml`, `claude-deep-review.yml` | **Dormant** — the Claude GitHub App is not installed. Left on disk; they never fire. Don't rely on them, don't wire anything to them. |

Loop:

1. **Pick the panel from the diff.** `gh pr diff <N> --name-only`, then choose specialists per the selection table in "Local Code Review". Never a fixed panel — 1-4 reviewers, spawned in parallel in one message.
2. **Brief each reviewer** with the PR number, branch, stated scope, the paths to the standing priorities + "What NOT to flag" list, and the evidence rule. Reviewers are READ-ONLY.
3. **Triage** every finding as `fix-now` / `respond` / `defer`. Read the file at the referenced line first — never operate blind. Drop any finding that arrives without a concrete failure scenario.
4. **Push back with evidence, don't comply.** Reject findings that demand defensive code for impossible cases, scope creep, or anything conflicting with `CLAUDE.md` / `docs/PLANNING.md` — citing the specific guarantee, convention, or line. Reviewers here have been confidently wrong in ways that broke shipped features.
5. **Fix, then verify the fixes independently.** Every fix round gets a fresh verifier subagent — not the implementer, not the reviewer who raised the finding. It checks that the fix addresses the finding, introduced no regression, and that the claims in the commit / PR body are true.
6. **Verify build claims** — see "Build verification" below. Relay is covered by CI; **iOS is not** (#197), so an iOS build claim is only as good as the local run behind it.
7. **Record dispositions in the PR body** — fixed (with SHA), rejected (with reasoning), deferred (with issue number). That record is the review's only artifact and it's what the judge reads.
8. **Round-N judge.** Spawn an impartial judge subagent per the global protocol — fresh, no review history. Decision is `merge | re-review | human-decides`. `re-review` re-runs only the specialists with open findings. Hard cap at 4 rounds, then surface to the user.
9. **CI gate:** must be green before merge unless the PR is labeled `expected-ci-fail`.
10. **Merge:** `gh pr merge <N> --merge --delete-branch`.
11. **Post-merge:** `git checkout main && git pull`, update `docs/STATE.md`, prep next phase prompt.
12. **Override:** if the user says "wait for me", stop after PR creation — don't review or merge.

### Context Management

- Keep main orchestrator context under 50% capacity
- Spawn subagents for any task touching 5+ files
- Pass file **paths** to subagents, not file contents
- Conflict-analyse file sets **before** spawning — two concurrent agents never write the same file
- Parallel agents on different branches get **worktree isolation**, never a shared checkout
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

---

## Local Code Review

Reviews are run by the orchestrating agent using specialist subagents matched to the diff. **This section is the brief** — hand reviewers the path to it, don't paste it.

**Reviewers are READ-ONLY.** No `Edit`, `Write`, or `NotebookEdit`; no commits, no pushes, no merges. They report findings; the orchestrator decides.

### Choosing specialists

| Diff touches | Spawn | Sharpened on |
|---|---|---|
| `relay/src/auth/`, `relay/src/oauth/`, `ios/…/Keychain*`, identity/pinning, WS boundary, PTY spawn, tunnel | 🔒 **Security** | token + cookie flow, trust boundaries, what an attacker on the LAN or the tunnel can reach |
| Swift actors, `async`/`Task` lifecycle, cancellation, caches + invalidation, reconnect/retry paths | ✅ **Correctness + concurrency** | isolation violations, races, missing cancellation checks, state that outlives its trust context |
| new files, cross-component boundaries, `IAdapter`, protocol mirroring, iOS framework rules | 🏗️ **Architecture + conventions** | layering, god files, the rules in "What NOT To Do" |
| a PR body making empirical claims — benchmarks, "verified", "this can't happen", root-cause narratives, build results | 🎯 **Adversarial verifier** | every claim checked against the code, claim by claim; report each as confirmed / wrong / unverifiable |

1-4 reviewers, spawned in parallel in one message. Two with sharp briefs beat five generic ones. Anything on a sensitive path (auth, identity, tunnel, release) gets the adversarial verifier from round 1.

### Standing review priorities (in order)

1. **SECURITY** — auth / token handling (Google OAuth, Keychain, session tokens), WebSocket boundary input validation, PTY / Claude Code spawn safety (command injection / env injection / cwd escape), path traversal in fs ops driven by network input, PWA XSS (markdown / xterm rendering), Cloudflare Tunnel exposure, prompt-injection paths, GitHub Actions safety
2. **ARCHITECTURE** — component boundaries (relay / iOS / web / vscode-extension are independent), adapter pattern in relay (`IAdapter`), protocol compliance (`type` field on every WebSocket message, mirrored types across clients), iOS conventions (SwiftUI only, `@Observable` only, Swift Concurrency only, MVVM, feature folder layout, Keychain + SwiftData), file organization (per-feature types, no god files)
3. **CORRECTNESS** — strict TS (no `any`, use `unknown`+narrow), ESM `.js` import suffixes, async/await hygiene, `??` not `||`, typed errors with no silent catches; Swift no-force-unwraps + actor isolation correctness
4. **CONVENTIONS** — see "What NOT To Do" above

### Path-aware focus

| Path | Primary specialist focus |
|------|--------------------------|
| `relay/src/server.ts`, `relay/src/sessions/` | Security (WS boundary) + Architecture (no god files) |
| `relay/src/auth/`, `relay/src/oauth/` | Security (token storage / refresh / leakage) |
| `relay/src/adapters/` | Architecture (`IAdapter` contract) + Security (PTY spawn safety) |
| `relay/src/tunnel/`, `tunnel/` | Security (public exposure surface) |
| `relay/src/protocol*`, `web/src/lib/protocol*` | Architecture (protocol mirroring across clients) |
| `web/src/lib/ws/`, `web/src/lib/auth/` | Security + protocol mirroring |
| `ios/MajorTom/Services/Keychain*`, `ios/MajorTom/Features/Auth/` | Security (Keychain access policies) |
| `ios/MajorTom/Features/*/Views/`, `ViewModels/` | Architecture (MVVM, `@Observable`, Concurrency) |
| `.github/workflows/` | Security (Actions safety, fork guards, action SHA pinning) |

### The evidence rule

Hand this to every reviewer verbatim:

> Every finding must come with a concrete failure scenario: the inputs or state that trigger it, and the bad outcome that results. "This could be unsafe" is not a finding. If you cannot write the scenario, drop the finding.

Enforced on intake too — a finding that arrives without a scenario gets dropped, not debated.

### What NOT to flag

- **Defensive code for impossible cases** — trust framework / type-system guarantees. Validate only at system boundaries (user input, external APIs, WebSocket inbound).
- **Test coverage gaps** — vitest is wired only for relay; iOS / PWA test harnesses aren't in CI yet. Don't ask for tests outside relay until they land.
- **Architecture re-litigation** — locked decisions live in `docs/PLANNING.md` and the shipped `docs/PHASE-*.md` docs. Don't propose alternatives.
- **Premature abstraction** — three similar lines is BETTER than a bad abstraction. Don't suggest DRY without strong evidence.
- **Scope creep** — review the PR's stated scope, not adjacent work or future features.
- **Style nits** — Prettier / SwiftFormat handle formatting; ignore.
- **Comment density** — code without comments is fine if names are clear; only flag missing comments when WHY is non-obvious.

### Reviewer output

Each reviewer returns findings ranked blocking → advisory — `file:line`, the failure scenario, a suggested fix — plus one verdict line:

```
verdict: ship | fix-then-ship | rethink
blocking: N   advisory: N   sensitive_paths_touched: yes|no
```

The orchestrator triages (`fix-now` / `respond` / `defer`) and records every disposition in the PR body: fixed with SHA, rejected with cited reasoning, deferred with issue number.

### Verifying fixes

Fix commits are otherwise entirely unreviewed — they land after the review that would have caught them. **Every fix round gets an independent verifier subagent**: not the implementer, not the reviewer who raised the finding. It answers three questions:

1. Does the fix address the finding, or just silence the symptom?
2. Did it introduce a regression — especially in a path the original review never looked at?
3. Are the claims in the fix commit and the updated PR body true?

### Build verification

**Relay** is covered by `ci.yml` (lint / typecheck / test / build). **iOS is not** — the `xcodebuild` job in `ci.yml` is commented out (#197), so a local build is the only gate that exists for `ios/`. Never assert an iOS build you didn't watch complete in the tree under review.

```bash
xcodebuild -project <worktree>/ios/MajorTom.xcodeproj -scheme MajorTom \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath <worktree>/.build/verify build
```

| Requirement | Why |
|---|---|
| Explicit `-project <worktree>/ios/MajorTom.xcodeproj` | A discovered/default project can resolve to another worktree. |
| Dedicated `-derivedDataPath` under `.build/` | Shared DerivedData keys on `WorkspacePath` and will return `** BUILD SUCCEEDED **` for a *different* checkout's copy of `main`. This has already produced a false green in this repo. `.build/` is gitignored; a bare `.build-verify/` is not. |
| Confirm the product contains the change | Exit code proves a build happened, not that it built *your* code. |

Two ways to confirm inclusion — do at least one:

- **Provenance:** the `.d` dependency file for a changed type records the compiled source path. It must point into the worktree under review.
- **Inclusion:** grep a string the change introduced out of the built product. **Trap:** `Major Tom.app/Major Tom` is a small stub — the Swift code lives in `Major Tom.app/Major Tom.debug.dylib`. Grep the dylib, not the app binary. For `terminal.html` and other bundled resources, hash or grep the copy inside the `.app`.

### Rounds, judge, merge

- **Round-N judge** — impartial subagent, fresh, no review history, per `~/.claude/CLAUDE.md`. Decision JSON: `{"decision":"merge|re-review|human-decides","confidence":"high|medium|low","reasoning":"..."}`.
- **`re-review`** re-runs only the specialists with open findings, plus the fix verifier.
- **Hard cap: 4 rounds**, then stop and surface to the user.
- **`rethink`, or any ambiguous trade-off** → stop, surface to the user. Don't auto-merge through it.
- **CI must be green** before merge unless the PR is labeled `expected-ci-fail` (early-phase work).
- **Merge:** `gh pr merge <N> --merge --delete-branch`.
