---
applyTo: "**/*"
---

# PR Review — Addressing Copilot Comments

## Comment Categorization

When Copilot reviews a PR, categorize each comment:

| Category | Action | When to Use |
| -------- | ------ | ----------- |
| **fix-now** | Fix in current PR | Real bugs, type errors, security issues |
| **respond** | Reply explaining why no change | Intentional design, false positives, not applicable |
| **defer** | Acknowledge, note for later | Valid but out of scope for this PR |

## Skeptical Review (CRITICAL)

**You have MORE context than Copilot.** Before accepting a suggestion, ask:

1. **Does this apply to our setup?** (e.g., SSR concerns in a SwiftUI app)
2. **Is this already handled elsewhere?** (e.g., guards upstream)
3. **Is this a real problem or theoretical?** (e.g., edge cases that can't happen)
4. **Does the fix add complexity for marginal benefit?**
5. **Would a human reviewer make this same comment with full project context?**

### Default Posture

| Suggestion Type | Default | Reasoning |
| --------------- | ------- | --------- |
| Actual bugs | **Fix** | Real runtime errors |
| Security vulnerabilities | **Fix** | XSS, injection, auth bypass |
| Type errors | **Fix** | Will break CI |
| Memory leaks | **Fix** | Will degrade performance |
| Platform-specific concerns | **Evaluate** | May or may not apply |
| Over-engineering suggestions | **Respond** | Adds complexity without value |
| Future feature requests | **Respond** | Out of scope |
| Architecture opinions | **Respond** | Design decisions already made |
| Valid but out of scope | **Defer** | Note for future work |

## Workflow

### 1. Fetch Comments

```bash
gh api repos/seantokuzo/major-tom/pulls/{number}/comments
```

### 2. Categorize

Sort every comment into fix-now / respond / defer.

### 3. Fix

Address all fix-now items. Run CI after fixes. Commit with descriptive message.

### 4. Reply to EVERY Comment

Reply individually to each comment explaining what was done:

```bash
# Fixed
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Fixed in commit abc1234."

# Not applicable
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Not applicable — this is a native iOS app using URLSessionWebSocketTask, not a browser WebSocket."

# Deferred
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Valid point. Noted for Phase 2 when we add retry logic."
```

### 5. Summary Comment

After addressing all comments, leave a summary on the PR:

```bash
gh pr comment {number} --body "Addressed Copilot review:
- Fixed: [list]
- Responded: [list]
- Deferred: [list]

All CI passing."
```

## Response Templates

```markdown
# Fixed
Fixed in commit abc1234.

# Not applicable
Not applicable — [specific reason why this doesn't apply to our architecture].

# Intentional
Intentional design decision — [reason]. See PLANNING.md [section].

# Deferred
Valid improvement. Noted for Phase N work.
```

## Key Principles

- **Don't blindly fix everything** — Copilot lacks project context
- **Always reply** — Close the loop on every comment
- **Include commit links** — When fixing, reference the specific commit
- **Batch fixes** — Fix all issues, run CI once, then reply to all
- **Be specific** — "Not applicable because X" not just "Not applicable"
