# HANDOFF: Terminal Reboot — Autonomous Execution Brief

> **You are a fresh Claude Code session.** The user has gone to bed. Execute this brief end-to-end without further user input. The user will return in the morning expecting a merged PR and a working iOS terminal with no tmux green status bar at the bottom.
>
> All design decisions are LOCKED. The spec is at `docs/TERMINAL-PROTOCOL-SPEC.md`. The phase plan is at `docs/PHASE-TERMINAL-REBOOT.md`. **Do not re-debate decisions.** Execute.
>
> If the user's first message to you is just "next" — that's the trigger. Begin.

---

## Pre-flight (5 min, but don't skip)

1. `pwd` — must be `.../worktrees/terminal+ditch-tmux-plan`.
   - If you are NOT in the worktree (e.g. user launched the fresh session from the main repo), use `EnterWorktree` with `path: "/Users/seansimpson/Documents/code/dev/major-tom/.claude/worktrees/terminal+ditch-tmux-plan"` to switch into it. Then re-verify `pwd`.
2. `git branch --show-current` — must be `worktree-terminal+ditch-tmux-plan`.
3. `git status` — should be clean (or only show the three new docs in `docs/` if you're picking up after the previous session and they haven't been committed yet — if so, your first commit is to land them).
4. **Read in order, in full:**
   - `docs/TERMINAL-PROTOCOL-SPEC.md` (the contract)
   - `docs/PHASE-TERMINAL-REBOOT.md` (the wave plan)
5. **Read these memory files** for project conventions:
   - `feedback_pr_comments.md`
   - `feedback_pr_workflow.md`
   - `feedback_auto_poll_reviews.md`
   - `feedback_reply_inline.md`
   - `feedback_no_auto_merge.md`
   - `feedback_copilot_auto_review.md`
   - `feedback_keychain_always_allow.md` (relevant if you do device builds — sim is safer)
6. If `.agents/skills/pr-review-pipeline/SKILL.md` exists, read it — that's the canonical merge ritual.
7. `npm view vitest version` and `npm view @types/node version` — pin major versions when installing. Never trust training data for package versions.

## Execution rules (non-negotiable)

- **TDD discipline.** For every behavioral change, write the failing test first, watch it fail, write the implementation, watch it pass, refactor if needed, move on. Don't batch.
- **Atomic commits.** One logical change = one commit. Conventional Commits format. Examples:
  - `chore(relay): bootstrap vitest test harness`
  - `test(relay): pty-adapter spawn + attach`
  - `feat(relay): pty-adapter implementation`
  - `refactor(relay): drop tmux from shell route`
  - `chore(relay): delete tmux-cli, tmux-bootstrap, window-reaper`
  - `feat(ios): handle attached protocol message`
  - `feat(web): handle attached protocol message`
  - `chore(ground-control): drop tmux Homebrew check`
- **Never `--no-verify`**, never amend a published commit (per global CLAUDE.md).
- **Use TaskCreate** to track waves. Mark complete as you go.
- **Spawn subagents** for parallel independent work (e.g., iOS + PWA + Ground Control client edits in parallel during Wave 5). Don't nest subagents.
- **Verify before reporting done.** Read changed files. Run tests. Build clients.
- **Status updates:** brief, between waves only. No essays.
- **Use Context7** for library APIs you're not 100% sure of (`vitest`, `node-pty`, `ws`, Fastify, etc.). Don't trust memorized APIs.

---

## Wave-by-wave execution

Follow `docs/PHASE-TERMINAL-REBOOT.md` Wave 1 → Wave 7 in order. Acceptance criteria listed there. Don't move to next wave until acceptance is met.

### Specific gotchas to internalize before you start

#### node-pty in tests

Spawning real interactive shells in tests is flaky. For unit tests, spawn `cat` (echoes stdin to stdout, exits on EOF) or a tiny shell script. Keep tests under 1 second each.

```ts
import * as pty from 'node-pty';
const child = pty.spawn('cat', [], { name: 'xterm-256color', cols: 80, rows: 24, cwd: process.cwd(), env: process.env });
```

#### Async PTY events

PTY emits `data` async. Wrap in `new Promise((resolve) => pty.onData((d) => resolve(d)))` patterns. Use vitest's `await expect.poll(() => receivedBytes.length).toBeGreaterThan(0)` for "eventually" assertions.

#### Fake timers for the grace period

```ts
import { vi } from 'vitest';
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

// In the grace test:
adapter.detachClient('tab-1');
vi.advanceTimersByTime(30 * 60 * 1000 + 100);
expect(adapter.has('tab-1')).toBe(false);
```

#### Ring buffer

Keep it dead simple. `Buffer[]` array, push on data, evict from front when total bytes > MAX. Don't optimize until benchmarked.

```ts
class RingBuffer {
  private chunks: Buffer[] = [];
  private bytes = 0;
  constructor(private max = 256 * 1024) {}
  push(chunk: Buffer) {
    this.chunks.push(chunk);
    this.bytes += chunk.length;
    while (this.bytes > this.max && this.chunks.length > 0) {
      const dropped = this.chunks.shift()!;
      this.bytes -= dropped.length;
    }
  }
  drain(): Buffer { return Buffer.concat(this.chunks); }
}
```

#### `process.env.SHELL` in tests

Override deterministically:

```ts
const ORIG_SHELL = process.env.SHELL;
beforeEach(() => { process.env.SHELL = '/bin/bash'; });
afterEach(() => { process.env.SHELL = ORIG_SHELL; });
```

Production fallback: `process.env.SHELL || '/bin/bash'`.

#### Multi-WS rejection

When a second WS connects to a tabId already in `ACTIVE` state, send `{type:"error", message:"tab already attached"}` and close with WS code `4001` (custom). Test this. Add a `// FUTURE: multi-user — replace with broadcast` comment.

#### Reconnect to unknown tabId

Server logs at WARN via the existing `pino` logger:

```ts
logger.warn({ event: 'reconnect_orphaned', tabId, action: 'spawn_fresh' });
```

Then proceed as fresh spawn, `restored:false`. NO error to client. Silent fresh terminal.

#### Hybrid approval inject

In the existing hook handler that resolves the approval, look up the `PtySession` by `tabId` (from env), call `session.write(decision + '\n')`. Test this — use the cat-echo pattern: spawn `cat`, call `session.write('y\n')`, expect `'y\n'` to come back via the data event.

#### Session map persistence across attach/detach

The session lives in the `Map`. The WS list (`session.viewers: Set<WS>`) shrinks/grows. The PTY persists until grace expiry or explicit kill. Don't accidentally evict the session on detach — only on kill or grace fire.

#### `setImmediate`/`setTimeout` cleanup

In `dispose()` (which tests call in `afterEach`), iterate the map and clear all timers + kill all PTYs. Otherwise tests leak.

---

## Build commands

| Target | Command |
|--------|---------|
| Relay tests | `cd relay && npm test` |
| Relay build | `cd relay && npm run build` |
| Relay dev | `cd relay && npm run dev` |
| PWA build | `cd web && npm run build` |
| iOS build | XcodeBuildMCP — first `mcp__XcodeBuildMCP__session_show_defaults`, then `mcp__XcodeBuildMCP__build_run_sim` |
| Ground Control | locate build script in `ground-control/`, run it |

If iOS Keychain dialog appears during signing, per `feedback_keychain_always_allow.md` memory the user already set "Always Allow" — should not prompt. If it does, abort and report.

---

## iOS sim smoke test (Wave 5)

After iOS build green, in the sim:

1. App launches, navigates to terminal tab.
2. WS connects, shell prompt appears within 2 seconds.
3. Type `echo hello` + enter → `hello` prints. (Send via `mcp__XcodeBuildMCP__type_text` if needed.)
4. Send sim to background (`mcp__XcodeBuildMCP__press_key` Home, or programmatic equivalent), wait 10 s, foreground → terminal still responsive, prompt visible.
5. Open second tab → second prompt appears, independent of first.
6. Tap close on a tab → goes away, server confirms via logs (`mcp__XcodeBuildMCP__start_sim_log_cap` to capture).

If any step fails, fix and re-test. **Do not proceed to PR until iOS smoke passes.**

---

## PR pipeline (Wave 6)

```bash
# 1. Push
git push -u origin worktree-terminal+ditch-tmux-plan

# 2. Create PR
gh pr create \
  --title "feat(relay): plain PTY per tab — drop tmux" \
  --body "$(cat <<'EOF'
## Summary

Refactors the relay's terminal subsystem from tmux-backed to plain PTY-per-tab. Adds 30-min disconnect grace + 256 KiB ring buffer for backgrounding/reconnect. Drops ~900 LOC of tmux scaffolding (`tmux-cli.ts`, `tmux-bootstrap.ts`, `window-reaper.ts`).

Spec: `docs/TERMINAL-PROTOCOL-SPEC.md`
Phase plan: `docs/PHASE-TERMINAL-REBOOT.md`

## Why

Tmux was the wrong tool: window leaks (saw 70 panes), keybinding bleed-through, status-bar pollution, hard Homebrew dep. User-started tmux (`tmux new -s work` from inside a Major Tom shell) survives independently via launchd, so we get persistence-on-demand without wrapping every tab.

## Test plan

- [x] Relay: 27 unit + integration tests via vitest (new test harness)
- [x] iOS: sim build + smoke test (terminal renders, tabs work, background→foreground reattach with ring buffer replay)
- [x] PWA: `npm run build` green
- [x] Ground Control: build green; tmux Homebrew check removed
- [x] `grep -ri tmux relay/src/` returns no functional code references
- [ ] User physical-phone smoke: open Major Tom on iPhone, see terminal, no green tmux status bar at bottom

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

# 3. Capture PR number
PR_NUM=$(gh pr view --json number -q .number)

# 4. Wait for Copilot
sleep 60

# 5. Poll comments
gh api repos/seantokuzo/major-tom/pulls/$PR_NUM/comments

# 6. Address each (fix → push → reply inline)
# 7. Re-poll, iterate
# 8. After under-5-comment round:
gh pr merge $PR_NUM --merge

# 9. Sync local main
git checkout main && git pull
```

### Per-comment workflow

For each Copilot review comment:

- **Real issue** → fix in code, commit (`fix(relay): address PR review — <one-line>`), push, then reply inline:
  ```bash
  gh api repos/seantokuzo/major-tom/pulls/$PR_NUM/comments/$COMMENT_ID/replies \
    -X POST -f body="Fixed in $(git rev-parse --short HEAD)."
  ```
- **Non-issue / nitpick / already addressed** → reply inline with explanation:
  ```bash
  gh api repos/seantokuzo/major-tom/pulls/$PR_NUM/comments/$COMMENT_ID/replies \
    -X POST -f body="<explanation>"
  ```
- **Defer-worthy** → open GH issue with `tech-debt` label, reply with link:
  ```bash
  ISSUE_URL=$(gh issue create --title "..." --label tech-debt --body "...")
  gh api repos/seantokuzo/major-tom/pulls/$PR_NUM/comments/$COMMENT_ID/replies \
    -X POST -f body="Deferred to $ISSUE_URL"
  ```

After all comments addressed, push, wait 60 s, re-poll. Repeat until a round comes back with under 5 net new comments.

**Do not merge before the threshold round.** Per `feedback_no_auto_merge` memory: merge is EARNED via the review pipeline.

---

## Memory + STATE updates (Wave 7)

After merge:

1. `docs/STATE.md` — mark terminal reboot complete, remove any "NEXT ACTION" pointer.
2. New memory `project_terminal_reboot_complete.md`:
   ```markdown
   ---
   name: Terminal reboot complete
   description: Relay terminal is now plain PTY-per-tab (no tmux). Spec at docs/TERMINAL-PROTOCOL-SPEC.md.
   type: project
   ---
   Shipped <DATE>. PR #<NUM>. Replaced tmux-backed terminal with plain PTY-per-tab + 30-min grace + 256 KiB ring buffer. Deleted ~900 LOC across tmux-cli.ts, tmux-bootstrap.ts, window-reaper.ts. Multi-device attach deferred. User-started tmux inside the shell still works (launchd-managed daemon).

   **Why:** Window leak, keybinding bleed, status-bar pollution, hard Homebrew dep. See PHASE-TERMINAL-REBOOT.md for full rationale.

   **How to apply:** When working on terminal features, the in-memory session map is the source of truth. Don't reintroduce a multiplexer. If multi-device attach becomes a priority (team-server mode), the v2 protocol can grow broadcast — see `// FUTURE: multi-user` markers.
   ```
3. Update memory `project_ssh_architecture.md` — note tmux-leak problem solved by removing tmux entirely; SSH path no longer relevant unless team-server mode lands. Mark as superseded.
4. Update or delete memory `feedback_drive_phone_shell_remotely.md` — `tmux -L major-tom send-keys` debug pattern is gone. New approach: relay logs (pino) + a debug REST endpoint if needed. Or delete the memory if too situational; the new world doesn't need a special pattern.
5. Update `MEMORY.md` index accordingly.
6. Optionally clean up worktree: from main repo, `git worktree remove .claude/worktrees/terminal+ditch-tmux-plan`.

---

## Definition of Done (echo from phase plan)

- [ ] All ~27 tests green (`npm test`)
- [ ] tmux files deleted from relay
- [ ] `grep -ri tmux relay/src/` clean (no functional references)
- [ ] iOS sim build + smoke green
- [ ] PWA build green
- [ ] Ground Control build green
- [ ] PR merged to main
- [ ] STATE.md + memory updated
- [ ] Worktree branch can be cleaned up

---

## When you're done

Leave a brief status note for the user when they wake up:

- PR number + URL
- Test count + result
- Any GH issues you opened (with links)
- Anything they should verify on their phone

If you hit a true blocker (test framework can't run, library doesn't exist, iOS build fails for opaque reason), STOP and leave a clear note explaining what blocked and what you tried. Don't guess your way through. The user prefers a clean stop with context over a half-broken merge.

**Go.**
