# Review Workflow — Tier 3 bot-guard fix

> One-task spec for a future Claude session. Self-contained — pull a fresh
> agent, point them here, they should be able to ship the fix without
> chasing context.

## The bug

PR #167 (and any future PR exceeding 500 lines) auto-escalates from Tier 2
to Tier 3 because `claude-code-review.yml`'s verdict synthesizer applies
the `claude-deep-review` label whenever `diff_lines > 500` (or any other
escalation trigger — see `.github/workflows/claude-deep-review.yml:34-43`).

That label-add event triggers `claude-deep-review.yml` under a bot
actor (`claude[bot]`, the GitHub App that posts the verdict sticky). All
5 `anthropics/claude-code-action@v1` invocations in the deep workflow
then immediately fail with:

```
Action failed with error: Workflow initiated by non-human actor: claude
(type: Bot). Add bot to allowed_bots list or use '*' to allow all bots.
```

Result: every deep-review job is FAILURE, no real analysis runs, and the
PR gets a red CI gate that can only be cleared by manually dropping the
label or adding `expected-ci-fail` (what we did for PR #167).

Tier 2 itself works fine — it auto-fires on `pull_request: opened`, which
is a human actor (the PR author).

## The fix

Add `allowed_bots: claude` to every `claude-code-action@v1` `with:` block
in `.github/workflows/claude-deep-review.yml`. There are **5 sites**:

```bash
grep -n "uses: anthropics/claude-code-action@v1" \
  .github/workflows/claude-deep-review.yml
# 63:      - uses: anthropics/claude-code-action@v1
# 156:      - uses: anthropics/claude-code-action@v1
# 234:      - uses: anthropics/claude-code-action@v1
# 304:      - uses: anthropics/claude-code-action@v1
# 387:      - uses: anthropics/claude-code-action@v1
```

The 5 jobs are: 🔒 Security (deep), 🏗️ Architecture (deep), ✅ Correctness
(deep), 🎯 Threat Model (deep), 📋 Deep verdict synthesizer.

Per-site edit pattern — insert one line under each `with:`:

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    anthropic_api_key:        ${{ secrets.ANTHROPIC_API_KEY }}
    allowed_bots: claude          # ← ADD THIS LINE
    additional_permissions: |
      actions: read
    prompt: |
      ...
```

`claude` is the exact bot username the verdict synthesizer posts under
(check `gh api repos/seantokuzo/major-tom/issues/167/comments
--jq '.[].user.login' | sort -u` to confirm — should include
`claude[bot]`, which `allowed_bots: claude` matches per the action docs).

**Do NOT use `allowed_bots: '*'`.** That would let any bot trigger deep
review — overkill, and lets a future misconfigured bot burn through the
Anthropic budget.

## How to verify the fix

1. Apply the 5 single-line edits.
2. `gh workflow run claude-deep-review.yml --ref main` — manual dispatch
   (a human-initiated workflow_dispatch sidesteps the bot guard, so this
   test only confirms the prior-passing path still works).
3. Real verification needs a fresh PR over 500 lines:
   - Create a throwaway PR with >500 added/modified lines (e.g. a doc
     dump or a deliberate large refactor).
   - Wait for Tier 2 to auto-escalate (sticky reason should say
     "large-diff").
   - Confirm Tier 3 jobs run and produce a verdict sticky tagged
     `<!-- MT-DEEP-VERDICT-STICKY -->` instead of failing on the bot
     guard.
4. If verification PR is overkill, the live signal will be the next
   real PR over 500 lines — keep an eye on the deep workflow's first
   step (`Run anthropics/claude-code-action@v1`) for the same error
   message disappearing.

## Related — Tier 2's `claude-code-review.yml`

Round-2+ are agent-dispatched via `workflow_dispatch` from the
orchestrating CLI agent (per `docs/STATE.md` round protocol). When the
orchestrator is running under Claude CLI on Sean's laptop the dispatch
is from a human OAuth token, so the bot guard doesn't trip. But:

- If `claude-code-review.yml` ever gets refactored to auto-fire on
  `synchronize` (currently NOT a trigger to avoid this exact problem),
  add `allowed_bots: claude` there too.
- Same goes for the round-2 lane in any new specialist workflow.

## Out of scope for this fix

- Re-litigating whether Tier 3 should auto-escalate at all. Sean has been
  fine with it; the only complaint is the bot-guard failure mode.
- Changing the diff-size threshold (500 lines). Could revisit later if
  large-but-low-risk PRs (mostly tests / mostly docs) trip it too often.
- Switching to a different bot identity. Sticking with `claude` is
  simplest.

## When this doc can be deleted

When the 5-line edit ships and a >500-line PR has confirmed-clean Tier 3
runs (so we know the guard fix works in practice, not just in theory).
