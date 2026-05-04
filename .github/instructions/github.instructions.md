---
applyTo: "**/*"
---

# GitHub Integration

## Repository Details

| Property           | Value |
| ------------------ | ----- |
| **Owner**          | `seantokuzo` |
| **Repo**           | `major-tom` |
| **URL**            | https://github.com/seantokuzo/major-tom |
| **PRs**            | https://github.com/seantokuzo/major-tom/pulls |
| **Git Remote**     | `https://github.com/seantokuzo/major-tom.git` |
| **Default Branch** | `main` |
| **Username**       | `seantokuzo` |

## Branch Strategy

Branches follow the **phase-based** pattern from PLANNING.md:

| Scope | Branch Pattern | Example |
| ----- | -------------- | ------- |
| **Phase work** | `phase-N/feature-name` | `phase-1/relay-scaffold` |
| **Bug fix** | `fix/description` | `fix/websocket-reconnect` |
| **Docs** | `docs/description` | `docs/protocol-spec` |

### Commit Convention

```
type(scope): description
```

**Types**: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
**Scopes**: `ios`, `relay`, `extension`, `docs`, `agents`

Examples:

```bash
git commit -m "feat(relay): add CLI adapter PTY spawn"
git commit -m "fix(ios): handle WebSocket disconnect gracefully"
git commit -m "test(relay): add approval flow integration tests"
```

### PR Naming

```
Phase N: description
```

Examples:

```
Phase 1: Relay server scaffold + CLI adapter
Phase 1: iOS app shell + WebSocket client
```

For bug fixes or non-phase work:

```
fix: WebSocket reconnect on cellular handoff
```

## PR Setup (ALL MANDATORY)

When creating a PR:

1. **Create PR** (not draft)
2. **Assign `@seantokuzo`**
3. **Apply labels**: component + type + `Needs Review`
4. **Claude auto-reviews** via `.github/workflows/claude-code-review.yml` (Tier 2: 3 specialists + verdict synthesizer)
5. **Follow autonomous loop** in `~/.claude/CLAUDE.md` "PR Review Workflow (canonical)" + project extensions in `.github/instructions/pr-review.instructions.md`

## PR Labels

### Component Labels (based on files changed)

| Label | When to Apply |
| ----- | ------------- |
| **Relay** | Changes to `relay/` |
| **iOS** | Changes to `ios/` |
| **Extension** | Changes to `vscode-extension/` |
| **Docs** | Documentation changes |

### Type Labels

| Label | When to Apply |
| ----- | ------------- |
| **Bug Fix** | Fixing a bug |
| **Breaking Change** | Breaking protocol or API changes |

### Status Labels

| Label | When to Apply |
| ----- | ------------- |
| **Needs Review** | PR ready for review (agent applies) |
| **Accepted** | Human approved, ready to merge |
| **claude-deep-review** | Trigger Tier 3 deep review (manual or auto-applied by Tier 2 verdict synthesizer on escalation criteria) |
| **expected-ci-fail** | CI failure is anticipated and tracked — bypasses the green-CI merge gate (early-phase work only) |

### CI Labels (auto-applied by GitHub Actions)

| Label | Trigger |
| ----- | ------- |
| **Lint Failure** | Lint job fails |
| **Type Error** | Typecheck job fails |
| **Test Failure** | Test job fails |
| **Build Failure** | Build job fails |
| **CI Pass** | All jobs pass |

## PR Template

**ALWAYS** use the PR template at `.github/PULL_REQUEST_TEMPLATE.md`. Fill in ALL sections.

## Protected Branches

- `main` — Requires PR, passing CI, 1 approval
- Direct pushes disabled

## MCP Tools for GitHub

### Creating PRs

```
mcp__github__create_pull_request
- owner: "seantokuzo"
- repo: "major-tom"
- title: "Phase 1: Relay server scaffold"
- body: "## Summary\n..."
- head: "phase-1/relay-scaffold"
- base: "main"
```

### Reading PR Comments

```bash
# Get all review comments on a PR
gh api repos/seantokuzo/major-tom/pulls/{number}/comments

# Reply to a specific comment
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{comment_id}/replies \
  -f body="Fixed in abc123"
```
