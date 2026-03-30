---
name: pr-review-pipeline
description: Automated PR review pipeline — polls for Copilot review comments, addresses them, pushes fixes, replies inline, and loops for 2-3 rounds until clean. Run this after every PR creation.
---

# PR Review Pipeline

Automated multi-round code review workflow. After creating a PR, run this pipeline to ensure all review comments are addressed before the PR is ready for merge.

## When to Use

**ALWAYS** after creating a PR via `gh pr create`. This is a mandatory step in the workflow.

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

### Step 3: Fix Every Comment

For each comment:
1. **Read the file** at the referenced line
2. **Understand the issue** — don't just blindly apply suggestions
3. **Apply the fix** — use Edit tool for surgical changes
4. **Verify** the fix doesn't break the build

Common comment categories:
- **Bug/logic error** — Fix the actual bug
- **Performance** — Apply the optimization (e.g., avoid sqrt, batch operations)
- **Missing guard** — Add the defensive check
- **Unused import/var** — Remove it
- **Misleading comment** — Fix the comment or add the guard the comment describes
- **API misuse** — Fix to use correct API

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

### Step 7: Poll for Next Round

```bash
sleep 60
NEW_COMMENTS=$(gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments \
  --jq '[.[] | select(.in_reply_to_id == null)] | length')

# Compare against previous count
# If new comments appeared, go back to Step 2
```

### Step 8: Repeat (Max 3 Rounds)

- **Round 1:** Address all initial review comments
- **Round 2:** Address follow-up comments on your fixes
- **Round 3:** Final polish if needed (rare)

If still getting comments after round 3, report to user with summary.

### Step 9: Merge

After a clean round (no new comments), merge the PR:

```bash
gh pr merge {PR_NUMBER} --merge --delete-branch
```

Then pull the merged changes to local main:

```bash
git checkout main && git pull origin main
```

Report the result:

```
PR #{NUMBER} merged after {N} review rounds:
- Round 1: {X} comments addressed
- Round 2: {Y} comments addressed
- Round 3: Clean pass → merged
```

## Reply Format

When replying to comments, be specific about what was fixed:

- "Fixed — added `workStartTime == nil` guard to bored condition"
- "Fixed — using squared distance comparison, no sqrt in render loop"
- "Fixed — set alpha to 0 before fade-in sequence"
- "Acknowledged — added sync documentation comment explaining why models are duplicated"
- "Deferred — tracked as enhancement for v2 (session-scoped deep links)"

## Comment Triage Rules

| Category | Action |
|----------|--------|
| Bug / logic error | Fix immediately |
| Performance concern | Fix if straightforward, defer if architectural |
| Missing guard / safety | Fix immediately |
| Unused code / imports | Remove immediately |
| Misleading docs / comments | Fix immediately |
| API misuse / compile error | Fix immediately |
| Enhancement suggestion | Defer with explanation if scope creep |
| Style preference | Apply if reasonable |

## Integration with Agent Workflow

Subagents spawned for feature work should include this in their instructions:

```
After PR creation, run the review pipeline:
1. Poll for Copilot review comments
2. Address all comments, push fixes, reply inline
3. Re-poll for round 2, address and push
4. Report clean status or escalate after round 3
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
