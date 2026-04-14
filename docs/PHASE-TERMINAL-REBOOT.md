# Phase: Terminal Reboot — Ditch Tmux

> Refactor the relay's terminal subsystem from tmux-backed to plain PTY-per-tab. Big-bang merge. TDD throughout. Touches relay + iOS + PWA + Ground Control.
>
> Status: PLANNED. Spec at `docs/TERMINAL-PROTOCOL-SPEC.md`. Execution brief at `docs/HANDOFF-TERMINAL-REBOOT.md`.
>
> Branch: `worktree-terminal+ditch-tmux-plan`.

---

## Why

Tmux was the wrong tool. It was chosen for free multi-tab + persistence, but the cost has been steep:

- **Window leak** — `window-reaper.ts` races with tmux, windows pile up (production observed 70 panes across 5 view sessions × 14 windows).
- **Keybinding leak** — `Ctrl+B` and copy-mode bleed into the iOS terminal experience.
- **Status bar pollution** — green tmux status bar at the bottom of every shell.
- **Reinvents SSH poorly** — per-client `view-<tabId>-<rand>` grouped sessions exist solely to paper over "tmux is single-client-focused".
- **Hard dep** — Ground Control checks for Homebrew tmux at startup, fails happy path if missing.
- **`refresh` hack** — `shell.ts:304-327` does a `cols-1 → cols` resize wobble just to force tmux to redraw hidden panes.

The user's "if I want persistence, I'll start tmux myself inside the shell" model is strictly better. User-started tmux sessions (`tmux new -s work` from inside a Major Tom tab) **double-fork into launchd-managed daemons on macOS**, surviving the relay process entirely. We get the best of both worlds: simple ephemeral relay, optional user-managed persistence.

## Goals

1. Plain PTY-per-tab via `node-pty`. No multiplexer.
2. 30-min disconnect grace + 256 KiB ring buffer for backgrounding + reconnect UX.
3. In-memory session map only. No SQLite. PTY is the source of truth.
4. TDD with vitest. Relay had zero tests pre-refactor; ship with a real suite (~20+ tests).
5. Clean cut. Delete tmux from relay AND Ground Control. Remove tmux-specific UI bits on clients (status bar references, Homebrew check, tmux-missing error paths). No tech debt remaining.

## Non-Goals

- Multi-device simultaneous attach (deferred — `// FUTURE: multi-user` markers + GH issue).
- Relay-restart session survival (acceptable: user-started tmux survives anyway).
- Tmux pane splits.
- Native iOS PTY (still client → relay over WS).
- Disturbing the user's `SpecialtyKeyGrid` tmux keys — they want them retained for driving user-started tmux inside the shell.
- Disturbing PWA copy-mode toggle — useful for any terminal, not tmux-specific.

---

## Architectural Diff

### Before

```
WS /shell/:tabId
  └─ pty.spawn('tmux', ['attach-session', '-t', view-tabId-rand])
       └─ tmux client process
            └─ tmux server (named socket 'major-tom')
                 └─ window 'tab-tabId'
                      └─ bash -l
                           └─ claude / vim / whatever
```

Per-client view sessions. Window reaper. Hybrid mode does `tmux send-keys`. Bootstrap singleton. ~1,090 LOC of tmux scaffolding to manage all this.

### After

```
WS /shell/:tabId
  ├─ first connect: pty.spawn($SHELL, ['-l'], {cwd, env})
  │    └─ bash -l
  │         └─ (whatever the user runs, optionally tmux themselves)
  └─ reconnect within grace: reattach existing PTY, replay ring buffer
```

In-memory `Map<tabId, PtySession>`. Grace timer per session. Ring buffer per session. ~250 LOC.

---

## File Change Manifest

### DELETE entirely
- `relay/src/utils/tmux-cli.ts` (388 LOC)
- `relay/src/adapters/tmux-bootstrap.ts` (110 LOC)
- `relay/src/adapters/window-reaper.ts` (184 LOC)

### REWRITE
- `relay/src/adapters/pty-adapter.ts` — replace with `PtyAdapter` class managing the session map, grace timers, ring buffer, hook approval injection (~250 LOC, down from 412)

### UPDATE
- `relay/src/routes/shell.ts` — drop `refresh` handler, drop `tmuxBootstrap.ensure()` call, use new `PtyAdapter` API
- `relay/src/app.ts` — remove `tmuxBootstrap.ensure()` and `windowReaper.start()` / `windowReaper.dispose()` invocations
- `relay/src/sessions/session-manager.ts` — drop multi-PID-per-tab tracking (only relevant under tmux's grouped sessions)
- `relay/src/installer/install-hooks.ts` — verify no tmux refs (likely none, just confirm)
- `relay/package.json` — add `vitest`, test scripts
- `relay/tsconfig.json` — verify vitest types resolve; add `vitest/globals` if needed
- `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` — handle `{type:"attached"}` message (log only for now), update `/shell/tabs` parsing to new shape
- `ios/MajorTom/Features/Terminal/Views/TerminalWebView.swift` — pass through new attached message to JS bridge (or drop before JS — TBD during implementation)
- `web/src/lib/stores/shell.svelte.ts` — same protocol updates as iOS
- Ground Control source (location TBD during impl) — find tmux Homebrew check, remove. Find any "tmux missing" error UI, remove.

### KEEP unchanged
- `ios/MajorTom/Features/Terminal/Views/SpecialtyKeyGrid.swift` — user retains tmux keys for driving user-started tmux inside the shell.
- `web/src/lib/stores/shell.svelte.ts` copy-mode toggle — useful for any terminal.
- All hook scripts (`pretooluse.sh`, etc.) — env-var routed, no tmux awareness.
- `relay/src/protocol/messages.ts` — terminal not in this file, no change.

### NEW
- `docs/TERMINAL-PROTOCOL-SPEC.md` ✅ (already written)
- `docs/PHASE-TERMINAL-REBOOT.md` ✅ (this doc)
- `docs/HANDOFF-TERMINAL-REBOOT.md` ✅
- `relay/vitest.config.ts`
- `relay/src/adapters/__tests__/pty-adapter.test.ts`
- `relay/src/routes/__tests__/shell.test.ts`
- `relay/src/__tests__/setup.ts` (vitest setup, fake timers helpers)

---

## Wave Plan

### Wave 1 — Spec & Test Harness

1. Verify pinned versions: `npm view vitest version`, `npm view @types/node version`. Install with explicit major.
2. Create `relay/vitest.config.ts` (node environment, globals enabled, setup file path).
3. Add `test`, `test:watch` scripts to `relay/package.json`.
4. Create `relay/src/__tests__/setup.ts` — vitest fake-timer helpers.
5. Stub `relay/src/adapters/__tests__/pty-adapter.test.ts` and `relay/src/routes/__tests__/shell.test.ts` with one passing sanity test each (`expect(1+1).toBe(2)`).
6. `npm test` → green.

**Acceptance:** `npm test` exits 0 with two passing sanity tests.

### Wave 2 — TDD: PtyAdapter unit tests

Write each test first, watch fail, implement, watch pass. Order:

1. `spawnSession(tabId, dims, env)` creates PTY, registers in map.
2. `attachClient(tabId, ws)` sends `{type:"attached", restored:false}` on first attach.
3. `sendInput(tabId, bytes)` writes to PTY.
4. `resize(tabId, cols, rows)` resizes PTY.
5. PTY data event broadcasts to attached WS as binary.
6. PTY data event captures into ring buffer (FIFO, 256 KiB cap by default).
7. `detachClient(tabId)` enters `DETACHED`, starts grace timer.
8. `attachClient(tabId, ws)` reattach within grace cancels timer, sends `{type:"attached", restored:true}`, replays ring buffer (binary frame).
9. Grace timer fires → PTY killed (SIGTERM, then SIGKILL after 5 s), evicted from map.
10. `kill(tabId)` immediate termination, no grace.
11. PTY natural exit broadcasts `{type:"exit", exitCode, signal}` and closes WS.
12. Reconnect to unknown tabId logs WARN, spawns fresh, `restored:false`.
13. Multiple WS to same tabId: second attach REJECTED with `{type:"error", message:"tab already attached"}`, WS close `4001`.
14. Hook approval injection: `sessionMap.get(tabId).write("y\n")` reaches PTY (verify via cat-echo pattern).
15. Spawn uses `process.env.SHELL || '/bin/bash'`.

**Acceptance:** all 15 tests pass. `PtyAdapter` implementation complete.

### Wave 3 — TDD: shell.ts route integration

Stand up Fastify in test harness on a random port, connect with `ws` client, exchange messages.

1. WS connect with valid auth → 200 upgrade, `{type:"attached"}` received.
2. WS connect with bad auth → 401.
3. WS binary frame → echo back through PTY (cat-echo pattern).
4. WS resize control frame → no error, PTY actually resized.
5. WS `kill` control frame → `{type:"exit"}` sent + WS closes + tab evicted.
6. WS close → tab persists in `GET /shell/tabs` as `attached:false` for grace period.
7. `GET /shell/tabs` returns map contents in new shape.
8. `POST /shell/:tabId/kill` works; returns 204.
9. `POST /shell/:tabId/kill` on unknown tabId returns 404.
10. Oversized binary frame → WS close `1009`.
11. Invalid `cols`/`rows` query → 400.
12. Invalid tabId regex → 400.

**Acceptance:** all 12 integration tests pass. Route refactor complete.

### Wave 4 — Wire it up + delete tmux

1. Update `app.ts` — remove `tmuxBootstrap` + `windowReaper` initialization and disposal.
2. Delete `tmux-cli.ts`, `tmux-bootstrap.ts`, `window-reaper.ts`.
3. Update `session-manager.ts` (drop multi-PID complexity).
4. Audit `installer/install-hooks.ts` (confirm no tmux refs).
5. `npm run build` and `npm test` both green.
6. Manual smoke: `npm run dev`, curl `/health`, open WS via `wscat`, type some bytes, see echo.
7. Verify: `grep -ri tmux relay/src/ | grep -v test | grep -v node_modules` returns ZERO functional code references (only references in comments about user-started tmux are allowed; spec doc references in `docs/` are fine).

**Acceptance:** relay builds, all 27 tests green, manual smoke works, grep clean.

### Wave 5 — Client updates

Spawn parallel subagents for iOS + PWA + Ground Control if independent.

**iOS:**
1. `TerminalViewModel.swift` — add `{type:"attached"}` decoder branch (log only); rewire `/shell/tabs` parsing to new shape (`tabId`, `attached`, `lastActivityAt`).
2. `TerminalWebView.swift` — bridge layer: pass `attached` through to JS or drop server-side; either is fine, keep simple.
3. Build via XcodeBuildMCP — `session_show_defaults` first, then `build_run_sim`.
4. Smoke in sim: launch app, navigate to terminal tab, see prompt, type `echo hello` + enter, see hello, background sim 10s, foreground, verify still responsive.
5. Open second tab, verify independence.
6. Tap close on a tab, verify it goes away.

**PWA:**
1. `web/src/lib/stores/shell.svelte.ts` — same protocol updates as iOS.
2. `cd web && npm run build` — green.
3. (Manual sim test deferred unless time permits — PWA is secondary to iOS.)

**Ground Control:**
1. Locate tmux check (likely in startup health check or onboarding flow). Remove.
2. Locate any "tmux missing" UI (toasts, error views). Remove.
3. Build Ground Control. Green.

**Acceptance:** iOS sim build + smoke green; PWA build green; Ground Control build green; `grep -ri tmux ios/ web/ ground-control/ 2>/dev/null` returns only legitimate hits (specialty key labels in `SpecialtyKeyGrid.swift`, doc references).

### Wave 6 — PR + review pipeline

1. Atomic commits per logical change (use conventional format: `feat(relay): ...`, `test(relay): ...`, `refactor(relay): ...`, `feat(ios): ...`, etc.).
2. Push branch.
3. `gh pr create` with title `feat(relay): plain PTY per tab — drop tmux` and body referencing this doc + spec doc.
4. Wait ~60 s for Copilot reviewer auto-attach (per memory `feedback_copilot_auto_review`).
5. Poll comments via `gh api repos/seantokuzo/major-tom/pulls/<NUM>/comments`.
6. For each comment: fix in code + push + reply inline `gh api .../comments/<id>/replies -X POST -f body="Fixed in <SHA>"`. If non-issue, reply with explanation. If defer-worthy, open issue + reply with link.
7. Re-poll. Repeat rounds.
8. After a round comes back with under 5 net new comments (per user instruction), `gh pr merge <NUM> --merge`.
9. `git checkout main && git pull`.

**Acceptance:** PR merged to main.

### Wave 7 — Memory + STATE updates

1. Update `docs/STATE.md` — terminal reboot complete; remove "NEXT ACTION" pointer.
2. Add memory `project_terminal_reboot_complete.md` — describe new architecture, link to spec doc.
3. Update memory `project_ssh_architecture.md` — note tmux-leak problem solved by removing tmux entirely; SSH path no longer relevant unless team-server mode lands.
4. Update memory `feedback_drive_phone_shell_remotely.md` — `tmux -L major-tom send-keys` debug pattern is gone. New debug pattern: relay logs + `pty.write` from a debug REST endpoint, OR delete the memory if too situational.
5. Update `MEMORY.md` index.
6. Optionally: clean up worktree post-merge (`git worktree remove ...` from main repo).

**Acceptance:** STATE.md and memory reflect the new world.

---

## Test Strategy

- **Unit tests** (Wave 2) for `PtyAdapter` — spawn `cat` (echoes stdin to stdout) or a tiny shell script as the child to keep tests fast and avoid spawning real interactive shells in CI.
- **Integration tests** (Wave 3) for `shell.ts` — stand up the relay's Fastify app on a random port, connect a real `ws` client, exchange messages.
- **Manual smoke** on iOS simulator (Wave 5) — XcodeBuildMCP `build_run_sim` then verify terminal renders, tabs persist across sim background/foreground.
- **User smoke** on physical iPhone (post-merge, user-driven tomorrow morning) — they boot Major Tom on phone, verify terminal works, no green tmux status bar at bottom.

Expected total test count: **~27** (15 unit + 12 integration).

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| TDD workflow stalls on async PTY events | Use vitest `await expect.poll(...)` for "eventually" assertions. Wrap event emitters in promises. Document in setup.ts. |
| Hooks break when tmux removed | Hooks already use HTTP; only hybrid mode used `tmux send-keys`. Replace with `pty.write()` lookup via session map. Test in Wave 2. |
| iOS app crashes on unknown protocol message | Defensive parse — unknown `type` → log + ignore, never throw. Add explicit test. |
| PR review pipeline finds something missed | That's the point. Address per `feedback_pr_workflow` memory: fix now or open issue + reply. |
| User's existing tmux sessions on Mac affected | Refactor only touches the relay's named tmux socket (`-L major-tom`). User's default tmux untouched. Verified by grepping for the socket name — only in deleted files. |
| Ground Control bundle still ships tmux somehow | Search Ground Control source for any tmux refs. Remove. Do NOT modify Homebrew install — that's user's machine. |
| PTY zombies in tests | Always `dispose()` the adapter in `afterEach`. Use vitest's automatic cleanup hooks. |
| Ring buffer memory growth | Cap at 256 KiB per tab; with default eviction this is bounded. ~10 tabs × 256 KiB = 2.5 MiB worst case. |
| `process.env.SHELL` unset in CI | Test setup overrides to `/bin/bash` deterministically. Production fallback also `/bin/bash`. |

---

## Definition of Done

- [ ] All 27 unit + integration tests pass (`npm test` green)
- [ ] `relay/src/adapters/{tmux-cli,tmux-bootstrap,window-reaper}.ts` deleted (or `tmux-cli.ts` actually lives in `utils/` — confirmed deleted)
- [ ] `grep -ri tmux relay/src/ | grep -v node_modules` returns ZERO functional hits (only doc-string mentions of "user-started tmux" are acceptable)
- [ ] iOS sim build green via XcodeBuildMCP
- [ ] iOS sim manual smoke green (terminal renders, tabs work, background→foreground reattach works, ring buffer replay visible)
- [ ] PWA build green (`npm run build` in `web/`)
- [ ] Ground Control build green
- [ ] PR merged to main with under-5-comment final review round
- [ ] STATE.md updated
- [ ] Memory updated
- [ ] User opens Major Tom on phone in the morning, sees terminal, NO green tmux status bar at bottom, types `echo hello` + enter, sees hello echo back. ✨
