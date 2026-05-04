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

Canonical autonomous loop lives in `~/.claude/CLAUDE.md` under **"PR Review Workflow"**. Reviews are powered by the Claude GitHub App via three workflows in `.github/workflows/` — see "Reviewing with @claude" below for the tier table. Summary:

1. **Trigger model.** Tier 2 (`claude-code-review.yml`) auto-fires ONLY on `pull_request: opened` and `ready_for_review` (draft → ready also counts as round 1). It does NOT auto-rerun on `synchronize` — pushing fix commits is silent. **Subsequent rounds are agent-dispatched** via `workflow_dispatch`, so we only re-run lanes that had blocking findings instead of the whole panel every push.
2. **Round completion = sticky updated for head SHA.** Each auto-review round posts/updates the verdict sticky `<!-- MT-VERDICT-STICKY -->` (Tier 2) or `<!-- MT-DEEP-VERDICT-STICKY -->` (Tier 3). The sticky is the round-completion signal — NOT inline comment counts.
3. **Polling:** first poll 5m after round dispatch (specialists run in parallel, ~3-5 min each + synth). Subsequent polls every 2m until the sticky lands or updates.
4. **Triage:** every comment is `fix-now` / `respond` / `defer`. Push back inline when the comment recommends defensive code for impossible cases, scope creep, or anything that conflicts with `CLAUDE.md` / `docs/PLANNING.md`.
5. **Replies:** inline to each comment thread (never batched), with commit SHA for fixes or cited reasoning for pushback.
6. **Decide what's next** based on the synth sticky:
   - `verdict: ship` + CI green → **merge** (`gh pr merge --merge --delete-branch`)
   - `verdict: fix-then-ship` + addressable blocking → fix, push, dispatch a TARGETED follow-up round (see below)
   - `verdict: rethink` OR ambiguous trade-offs → **stop, surface to user** (don't auto-merge)
   - 4 rounds reached → **stop, surface to user** (hard cap)
7. **Targeted re-review dispatch.** After pushing fixes, identify which specialist(s) had blocking findings from the sticky and re-fire only those:
   ```bash
   gh workflow run claude-code-review.yml \
     --ref <branch> \
     --field pr_number=<N> \
     --field specialists=correctness \
     --field focus="Re-check the X fix in <sha> — Security and Architecture passed cleanly in round 1"
   ```
   `specialists` accepts any comma-separated subset of `security,architecture,correctness`. The synth always runs and uses the prior round's sentinels for skipped lanes (still authoritative until you say otherwise).
8. **Quick inline Q&A vs full re-review.** For one-off questions on a specific finding ("does this still apply after my fix?"), prefer Tier 1 — drop `@claude addressed in <sha> — confirm fix in security finding line 42` as an inline reply, no full round needed. Use targeted Tier 2 dispatch only when you want fresh sentinels and a sticky update.
9. **Round-N judge.** When the round-N sticky lands, spawn an impartial judge sub-agent per the global protocol — fresh general-purpose agent, no review history. Decision is `merge | re-review | human-decides`. Hard cap at 4 rounds.
10. **CI gate:** must be green before merge unless the PR is labeled `expected-ci-fail`.
11. **Post-merge:** `git checkout main && git pull`, update `docs/STATE.md`, prep next phase prompt.
12. **Override:** if the user says "wait for me", stop after PR creation — don't poll/merge.

Execution details (bash commands, reply templates) are in `.agents/skills/pr-review-pipeline/SKILL.md`. That skill MUST align with the canonical rules + this section — if it drifts, fix the skill.

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

---

## Reviewing with @claude

Three review tiers powered by the Claude GitHub App. **The action loads THIS file at runtime** — everything below is standing instructions for both the human and the reviewer.

### Review tiers

| Tier | Trigger | Model | Effort | Use for |
|------|---------|-------|--------|---------|
| **1: `@claude` Q&A** | mention in issue / PR / review comment | Opus 4.6 | `max` | targeted questions, one-off code reads, CI-failure inspection |
| **2: Auto-review** | every non-draft PR (open / sync / ready) | Opus 4.7 | `xhigh` | canonical multi-specialist review |
| **3: Deep review** | label `claude-deep-review` (manual or auto-escalated) | Opus 4.7 | `max`, 30 turns | security-sensitive, large, or escalated changes |

Workflows: `.github/workflows/claude.yml` (Tier 1), `claude-code-review.yml` (Tier 2), `claude-deep-review.yml` (Tier 3). Tier 2 runs three specialists in parallel (🔒 Security / 🏗️ Architecture / ✅ Correctness) plus a verdict synthesizer. Tier 3 adds a 🎯 Threat Model specialist.

All tiers are **READ-ONLY** — `Edit`, `Write`, and `NotebookEdit` are explicitly disallowed. No tier can modify code, push commits, or merge.

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

### What NOT to flag

- **Defensive code for impossible cases** — trust framework / type-system guarantees. Validate only at system boundaries (user input, external APIs, WebSocket inbound).
- **Test coverage gaps** — vitest is wired only for relay; iOS / PWA test harnesses aren't in CI yet. Don't ask for tests outside relay until they land.
- **Architecture re-litigation** — locked decisions live in `docs/PLANNING.md` and the shipped `docs/PHASE-*.md` docs. Don't propose alternatives.
- **Premature abstraction** — three similar lines is BETTER than a bad abstraction. Don't suggest DRY without strong evidence.
- **Scope creep** — review the PR's stated scope, not adjacent work or future features.
- **Style nits** — Prettier / SwiftFormat handle formatting; ignore.
- **Comment density** — code without comments is fine if names are clear; only flag missing comments when WHY is non-obvious.

### Mention syntax cheatsheet

```text
# Targeted question
@claude does this introduce any prompt-injection vectors via the terminal output path?

# Re-review after fixes
@claude addressed in <sha> — re-review the security findings only

# Inspect CI
@claude check why CI is failing on this PR and surface the root cause

# Explain
@claude walk me through how the relay's session manager handles WebSocket reconnect

# Trigger deep review
# Add the `claude-deep-review` label, or run claude-deep-review.yml via workflow_dispatch
```

### Round protocol

**Round 1** fires automatically on `pull_request: opened` and `ready_for_review` (draft → ready). **Round 2+ are agent-dispatched** via `workflow_dispatch` — `synchronize` is intentionally NOT a trigger, so a `git push` does not re-fire the panel. The orchestrating CLI agent reads the round-1 sticky, decides what to fix, pushes commits, and dispatches a TARGETED follow-up round on only the specialists that flagged issues. The verdict synthesizer posts a sticky (`<!-- MT-VERDICT-STICKY -->`) that's updated in place each round; skipped specialists keep their prior round's sentinel.

Targeted dispatch:

```bash
gh workflow run claude-code-review.yml --ref <branch> \
  --field pr_number=<N> \
  --field specialists=correctness \
  --field focus="Re-check the X fix in <sha> — Security/Architecture passed in round 1"
```

`specialists` accepts any comma-separated subset of `security,architecture,correctness`. Default is `all` (used implicitly on auto-fire).

- **Hard cap: 4 rounds.** After round 4 the synthesizer escalates to a human decision regardless of remaining issues.
- **Auto-escalation to Tier 3** when the synthesizer detects: any specialist verdict = `rethink`, OR `sensitive_paths_touched: true` AND blocking>0, OR total blocking > 5, OR PR diff > 500 lines.
- **CI must be green** before merge unless the PR is explicitly labeled `expected-ci-fail` (early-phase work).

### Reviewer JSON sentinel format

Each specialist embeds a sentinel in its summary comment for the synthesizer to parse:

```html
<!-- MT-REVIEW-JSON-{SECURITY|ARCHITECTURE|CORRECTNESS|THREATMODEL}
{"verdict":"ship|fix-then-ship|rethink","blocking_count":N,"advisory_count":N,"sensitive_paths_touched":bool,"top_issues":[...],"rationale":"..."}
-->
```

Don't edit these by hand — they're regenerated each round.
