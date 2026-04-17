---
applyTo: "**/*"
---

# PR Review — Addressing Copilot Comments

> Canonical polling/threshold rules live in `~/.claude/CLAUDE.md` (PR Review Workflow section) and `CLAUDE.md` (project). This file covers the triage posture for individual comments.

## Polling & Threshold (summary)

- **First poll:** 2 minutes minimum after PR creation or pushing fixes
- **Subsequent polls:** 1 minute intervals
- **Completion:** count reviews with body containing `"Pull request overview"` — round N is done when N such reviews exist
- **Threshold:** `<5` comments in the round → merge. `≥5` → request another round.

Full bash flow: `.agents/skills/pr-review-pipeline/SKILL.md`

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
| Defensive code for impossible scenarios | **Respond** | Cite framework guarantee |

## Workflow

### 1. Fetch Comments

```bash
gh api repos/seantokuzo/major-tom/pulls/{number}/comments \
  --jq '.[] | select(.in_reply_to_id == null) | {id, path, line: (.line // .original_line), body: (.body | split("\n")[0])}'
```

Ignore replies from previous rounds — focus on top-level comments only.

### 2. Categorize

Sort every comment into fix-now / respond / defer.

### 3. Fix

Address all fix-now items. Verify build after fixes. Commit with descriptive message.

### 4. Reply Inline to EVERY Comment

Reply individually to each comment in its thread — **never** as an unlinked PR-level comment.

```bash
# Fixed
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Fixed in commit abc1234 — brief description of the change."

# Not applicable
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Not applicable — this is a native iOS app using URLSessionWebSocketTask, not a browser WebSocket."

# Deferred
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Valid point. Tracked as issue #N — tech-debt."

# Pushback (comment is wrong or marginal)
gh api repos/seantokuzo/major-tom/pulls/{number}/comments/{id}/replies \
  -f body="Pushing back — {reasoning}. {Framework/type guarantee that makes the comment wrong}."
```

### 5. Apply Threshold & Merge or Re-round

Count top-level comments in the round you just handled.

- **`<5` → merge immediately.** `gh pr merge {number} --merge --delete-branch`
- **`≥5` → request another round.** Poll again with 2m→1m cadence.

Do NOT leave a summary PR-level comment — inline replies are the audit trail.

## Response Templates

```markdown
# Fixed
Fixed in commit abc1234 — {what changed}.

# Not applicable
Not applicable — {specific reason why this doesn't apply to our architecture}.

# Intentional
Intentional design decision — {reason}. See PLANNING.md {section}.

# Deferred
Valid improvement. Tracked as issue #N (tech-debt).

# Pushback
Pushing back — {reasoning}. {Framework/type/convention guarantee}.
Happy to revisit if this ever fires in the wild.
```

## Key Principles

- **Don't blindly fix everything** — Copilot lacks project context
- **Reply inline to every comment** — close the loop on each thread individually
- **Include commit SHA** — when fixing, reference the specific commit
- **Batch fixes, not replies** — fix all issues in one push, then reply inline to each
- **Be specific** — "Not applicable because X" not just "Not applicable"
- **No summary comment** — inline replies are the audit trail; PR-level summaries are noise
