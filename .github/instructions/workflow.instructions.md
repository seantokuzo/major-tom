---
applyTo: "**/*"
---

# Agent Workflow — GSD-Inspired

Major Tom uses a **phase-based, GSD-inspired workflow**. No Jira, no sprints, no ceremonies. Phases deliver observable user capabilities.

---

## The Loop

```
1. PLAN PHASE (Agent) -> 2. EXECUTE PHASE (Agent) -> 3. VERIFY (Agent)
       ^                                                      |
6. UPDATE ROADMAP  <-  5. ADDRESS COMMENTS  <-  4. PR REVIEW
```

---

## Phase-Triggered Role Loading

| Trigger | Role to Load |
| ------- | ------------ |
| "Plan phase N", "What's next?" | `mt-orchestrator.md` + `mt-researcher.md` |
| "Build it", "DESTROY IT!", "Execute" | `mt-orchestrator.md` → spawns specialists |
| "Has comments", "Address feedback" | Read pr-review.instructions.md |
| "Merged!", "Phase done" | Update PLANNING.md progress, STATE.md |

---

## Phase Execution (GSD Pattern)

### 1. Research Phase

Before implementing, the orchestrator spawns `mt-researcher.md` to:
- Investigate APIs, libraries, capabilities
- Verify assumptions from PLANNING.md
- Mark confidence: HIGH (Context7), MEDIUM (official docs), LOW (web search)
- Output prescriptive recommendations ("Use X because Y")

### 2. Plan Phase

The orchestrator decomposes work into **atomic tasks**:
- Each task = one commit
- Tasks grouped into **dependency waves**
- Wave 1 = independent tasks (run in parallel)
- Wave 2+ = tasks depending on Wave 1 outputs

### 3. Execute Phase

For each wave:
1. **Spawn specialists** — `mt-ios-engineer.md`, `mt-relay-engineer.md`, etc.
2. **Each specialist gets fresh context** — paths only, not content
3. **Verify after each wave** — does it compile? does it integrate?
4. **Commit after each task** — atomic commits

### 4. Internal Review (BLOCKING)

Before ANY push:
1. Review all changed files
2. Check protocol compliance (messages match PLANNING.md spec)
3. Check convention compliance (CLAUDE.md rules)
4. Fix issues, commit fixes
5. Run CI locally

### 5. PR + Claude Auto-Review

1. Push branch
2. Create PR (not draft) with template
3. Apply labels, assign @seantokuzo
4. **Claude auto-reviews** via `.github/workflows/claude-code-review.yml` — Tier 2 (3 specialists + verdict synthesizer) fires on PR open/sync. The verdict sticky (`<!-- MT-VERDICT-STICKY -->`) is the round-completion signal.
5. Follow the autonomous loop in `~/.claude/CLAUDE.md` "PR Review Workflow (canonical)" — poll, address, judge, merge.

### 6. Address Comments

See `.github/instructions/pr-review.instructions.md` for project-specific extensions and `~/.claude/CLAUDE.md` "PR Review Workflow (canonical)" for the canonical autonomous loop + judge sub-agent step.

---

## Context Management (GSD Pattern)

### Thin Orchestrator

The orchestrator stays LEAN:
- Discovers work, decomposes, spawns specialists
- Never executes heavy implementation itself
- Stays under 50% context capacity
- Passes **paths** to subagents, not file contents

### Context Exhaustion Signals

- Forgetting recent decisions
- Repeating similar searches
- Response quality degrading

**When signals appear:** Finish current task, commit, tell user: _"Context is heavy — suggest fresh session."_

### Anti-Patterns

- **Analysis paralysis**: If agent reads files 5+ times without writing code → stop and report blocker
- **Context bloat**: Never paste file contents into agent prompts
- **Deep nesting**: Subagents never spawn sub-subagents

---

## Implementer Selection

Before implementing ANY task, select the right specialist:

| Domain | Specialist | Skills to Load |
| ------ | ---------- | -------------- |
| iOS / SwiftUI | `mt-ios-engineer.md` | ios-swiftui-patterns, Context7 (SwiftUI, SpriteKit) |
| Relay / Node.js | `mt-relay-engineer.md` | Context7 (ws, node-pty, pino) |
| VSCode Extension | `mt-extension-engineer.md` | vscode-extension-builder, Context7 (VSCode API) |
| Sprites / SpriteKit | `mt-sprite-artist.md` | Context7 (SpriteKit) |
| Research | `mt-researcher.md` | Context7 (any library) |

---

## Context7 (MANDATORY for Library Work)

**NEVER trust training data for library APIs.** Always fetch current docs:

```
1. mcp__context7__resolve-library-id -> libraryName: "swiftui" | "ws" | etc.
2. mcp__context7__query-docs -> id from step 1, topic, tokens: 10000
```

| Domain | Libraries to Fetch |
| ------ | ------------------ |
| iOS | SwiftUI, SpriteKit, URLSession |
| Relay | ws, node-pty, pino |
| Extension | vscode (extension API) |
| Protocol | ws (shared between relay + extension) |

---

## Quality Gates

Before marking any task complete:

1. **Code compiles** — no type errors, no build failures
2. **No regressions** — existing functionality still works
3. **Protocol compliance** — messages match PLANNING.md spec
4. **Convention compliance** — follows CLAUDE.md rules
5. **Security** — no secrets in code, no sensitive data in logs
