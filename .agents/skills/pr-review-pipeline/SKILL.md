---
name: pr-review-pipeline
description: Automated PR review pipeline — polls for Copilot review comments, addresses them with skepticism, pushes fixes, replies inline, and merges once a round lands with <5 comments. Run this after every PR creation.
---

# PR Review Pipeline

Automated code review workflow. After creating a PR, run this pipeline to ensure all review comments are addressed before the PR is merged.

## When to Use

**ALWAYS** after creating a PR via `gh pr create`. This is a mandatory step in the workflow.

## Core Rules (read first)

1. **5-comment hard threshold.** After addressing a round of comments:
   - **`<5` comments in the round you just addressed → MERGE** (no more review rounds)
   - **`≥5` comments in the round you just addressed → re-request review for another round**

   This is a hard rule, not a guideline. Two small rounds back-to-back is a workflow smell and burns review cycles unnecessarily.

2. **Approach Copilot comments with skepticism.** Copilot is a tool, not an oracle. For every comment, ask:
   - Is this a real bug, a real code-quality issue, or marginal noise?
   - Is it recommending defensive code for a scenario that can't actually happen? (See the global CLAUDE.md rule: *"Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees."*)
   - Is it suggesting an architecture change that wasn't in scope?

   **Push back inline when the comment is wrong or marginal** — reply explaining why you're not applying it. Blindly defaulting to "Copilot is always right" produces cascading complexity: a marginal Round 2 suggestion becomes Round 3 follow-up work becomes Round 4 bug fixes on code that shouldn't have existed.

## Pipeline Steps

### Step 1: Wait for Copilot Review

Copilot is auto-requested as a reviewer on all PRs. Wait for it to post comments.

```bash
# Poll every 30s for up to 3 minutes
for i in {1..6}; do
  COMMENTS=$(gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments --jq 'length')
  if [ "$COMMENTS" -gt 0 ]; then
    echo "Found $COMMENTS review comments"
    break
  fi
  echo "Waiting for review... (attempt $i/6)"
  sleep 30
done
```

### Step 2: Read All Comments

```bash
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments \
  --jq '.[] | {id, path, line: (.line // .original_line), body}'
```

Ignore comments that are replies (from previous fix rounds). Focus on top-level review comments only:

```bash
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments \
  --jq '.[] | select(.in_reply_to_id == null) | {id, path, line: (.line // .original_line), body: (.body | split("\n")[0])}'
```

### Step 3: Triage Every Comment (with skepticism)

For each comment:
1. **Read the file** at the referenced line
2. **Apply the skepticism filter** (see Core Rules above): is this a real issue, or defensive noise for an impossible scenario?
3. **Decide: fix or push back.**
   - **Fix:** use `Edit` tool for surgical changes
   - **Push back:** write a clear inline reply explaining why you're not applying it, citing the specific reason (framework guarantee, impossible branch, out of scope, etc.)
4. **Verify** any fix doesn't break the build

Common comment categories:
- **Bug / logic error** — Fix
- **Missing guard on a real boundary** (user input, external API, race condition) — Fix
- **Performance** — Fix if straightforward, defer with explanation if architectural
- **Unused import/var** — Fix
- **Misleading comment / stale docs** — Fix
- **API misuse / compile error** — Fix
- **Defensive code for impossible scenarios** — **Push back**. Don't add try/catch for framework guarantees (e.g. `<dialog>.showModal()` can't throw when `onMount` just placed it in the DOM), don't add null-checks for values the type system proves non-null, don't validate internal call sites.
- **Speculative architecture changes** — **Push back** if out of scope for the PR
- **Style preference without justification** — Apply if reasonable, push back if it conflicts with project conventions

### Step 4: Build Verify

After all fixes, verify nothing is broken:

```bash
# PWA (if web/ files changed)
cd web && npm run build

# Relay (if relay/ files changed)
cd relay && npm run build

# iOS (if ios/ files changed)
cd ios && xcodebuild -scheme MajorTom \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build 2>&1 | tail -40
```

### Step 5: Commit and Push

```bash
git add -A && git commit -m "$(cat <<'EOF'
fix(scope): address round N Copilot review — brief description

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
git push origin {BRANCH}
```

### Step 6: Reply Inline to Every Comment

Reply to EACH comment in its own thread (never as unlinked PR comments):

```bash
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments/{COMMENT_ID}/replies \
  -f body="Fixed — {brief description of what was done}"
```

### Step 7: Apply the 5-Comment Threshold

**Count the number of top-level comments in the round you just addressed** (not including inline replies from earlier rounds).

```bash
# Get the latest Copilot review ID
LATEST_REVIEW=$(gh api repos/{OWNER}/{REPO}/pulls/{PR}/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]" or .user.login == "Copilot")] | sort_by(.submitted_at) | last | .id')

# Count comments on that review
ROUND_COUNT=$(gh api repos/{OWNER}/{REPO}/pulls/{PR}/comments \
  --jq "[.[] | select(.pull_request_review_id == $LATEST_REVIEW)] | length")

echo "Round had $ROUND_COUNT comments"
```

**Decision:**
- **`<5` comments → MERGE NOW** (skip to Step 9)
- **`≥5` comments → Re-request review, go to Step 8**

### Step 8: Re-Request Review for Another Round (only if ≥5 comments)

```bash
# Copilot reviewer login MUST include the [bot] suffix literally
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/requested_reviewers \
  -X POST \
  --input - <<'EOF'
{"reviewers":["copilot-pull-request-reviewer[bot]"]}
EOF
```

Then poll for the next round:

```bash
sleep 60
NEW_REVIEW=$(gh api repos/{OWNER}/{REPO}/pulls/{PR}/reviews \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]" or .user.login == "Copilot")] | sort_by(.submitted_at) | last | .id')

# If NEW_REVIEW differs from LATEST_REVIEW, a new round landed — go back to Step 2
```

Repeat Steps 2–7 until a round lands with `<5` comments.

### Step 9: Merge

```bash
gh pr merge {PR_NUMBER} --merge --delete-branch
git checkout main && git pull origin main
```

Report the result:

```
PR #{NUMBER} merged after {N} review rounds:
- Round 1: {X} comments addressed
- Round 2: {Y} comments addressed  (merged because Y < 5)
```

## Reply Format

When replying to comments, be specific about what was fixed — or why you're not fixing it:

**Fix replies:**
- "Fixed in {commit_sha} — added `workStartTime == nil` guard to bored condition"
- "Fixed in {commit_sha} — using squared distance comparison, no sqrt in render loop"
- "Fixed in {commit_sha} — set alpha to 0 before fade-in sequence"

**Acknowledgement / deferred replies:**
- "Acknowledged — added sync documentation comment explaining why models are duplicated"
- "Deferred — tracked as enhancement for v2 (session-scoped deep links)"

**Pushback replies** (when the comment is wrong or marginal):
- State what the comment suggested
- State your reasoning for not applying it (framework guarantee, impossible branch, out of scope, etc.)
- Offer to revisit if the scenario is ever observed in practice

Example pushback format:
> Pushing back on this one — I don't think the {change} earns its weight here.
>
> {Technical reasoning: specific conditions, why they can't happen, references to language/framework guarantees}
>
> The project's global style guide calls out avoiding {the pattern being suggested}: *"quote the relevant rule"*.
>
> Happy to revisit if this ever fires in the wild.

## Comment Triage Rules

| Category | Action |
|----------|--------|
| Bug / logic error | Fix immediately |
| Missing guard on a real boundary (user input, external API, race) | Fix immediately |
| Performance concern | Fix if straightforward, defer if architectural |
| Unused code / imports | Remove immediately |
| Misleading docs / comments | Fix immediately |
| API misuse / compile error | Fix immediately |
| Enhancement suggestion | Defer with explanation if scope creep |
| Style preference | Apply if reasonable, push back if it conflicts with conventions |
| Defensive code for impossible scenarios | **Push back** — cite framework guarantee |
| Speculative architecture change | **Push back** if out of scope for the PR |

## Integration with Agent Workflow

Subagents spawned for feature work should include this in their instructions:

```
After PR creation, run the review pipeline:
1. Poll for Copilot review comments
2. Triage each comment with skepticism — fix real issues, push back on marginal/impossible-scenario ones
3. Push fixes, reply inline to every comment (fix + pushback both)
4. Apply the 5-comment threshold: <5 in the round → merge. ≥5 → re-request review and loop.
5. Pull merged main after merge
```

## GitHub API Reference

```bash
# List PR comments (review comments on diff)
gh api repos/{OWNER}/{REPO}/pulls/{PR}/comments

# Reply to a specific comment
gh api repos/{OWNER}/{REPO}/pulls/{PR}/comments/{ID}/replies -f body="..."

# List PR reviews (approve/request changes)
gh api repos/{OWNER}/{REPO}/pulls/{PR}/reviews

# Check PR status
gh pr view {PR} --json mergeable,mergeStateStatus,statusCheckRollup
```
