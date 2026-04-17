# HANDOFF: Tab-Keyed Offices — Wave 2 Execution Brief

> **You are a fresh Claude Code session.** Previous session did Wave 1 (research + spec freeze). Your job: execute Wave 2 (Relay Bridge). The spec is LOCKED at `docs/PHASE-TAB-KEYED-OFFICES.md`. Do not re-debate decisions.
>
> If the user's first message is just "next" — that's the trigger. Begin.

---

## Pre-flight (don't skip)

1. `git status` — should be clean on `main` at or past commit `23e9278` (docs: sprite-agent wiring complete). The spec doc + memory updates from Wave 1 are already committed or uncommitted docs — check and land them as your first commit if needed.
2. `git pull origin main`
3. **Read in full, in order:**
   - `docs/PHASE-TAB-KEYED-OFFICES.md` — the spec, especially §4–§6 (data model, protocol, hooks) and §10 (wave breakdown)
   - `docs/STATE.md` — current phase table
4. **Read memory files** for project conventions (canonical PR review flow lives in `~/.claude/CLAUDE.md`):
   - `project_tab_keyed_offices_phase.md` — the phase context
   - `project_sprite_qa_in_flight.md` — what's paused (don't touch sprite code until Wave 5)
   - `feedback_pr_comments.md`, `feedback_pr_workflow.md`, `feedback_auto_poll_reviews.md`, `feedback_reply_inline.md`, `feedback_no_auto_merge.md`, `feedback_copilot_auto_review.md`
5. Confirm the relay dev server state. User's local relay background task `byp2ggbux` may have died. If you need it for manual testing: `cd relay && npm run dev` (run_in_background). For Wave 2 work, unit tests are the primary signal — relay runtime not strictly required.
6. `npm view vitest version` before adding test deps. Never trust memorized package versions.
7. Create branch: `git checkout -b tab-keyed-offices/wave2-relay`. Use a worktree if you prefer isolation (`feedback_parallel_agents.md`), but Wave 2 is a single contributor, single branch.

## Execution rules (non-negotiable)

- **TDD discipline.** Test first, implementation second. One behavior per commit.
- **Atomic commits.** Conventional Commits format. Scope is `relay`.
- **Never `--no-verify`**, never amend a published commit.
- **Use TaskCreate** to track the Wave 2 sub-tasks (listed below).
- **Spawn subagents** only if needed — Wave 2 is mostly relay code. Don't parallelize for its own sake.
- **Use Context7** for Fastify, `ws`, `node-pty` APIs you're not 100% sure of.
- **Verify before reporting done.** Run `npm test` in `relay/`. All green before PR.

---

## Wave 2 scope (relay only, zero iOS changes)

### Sub-tasks (target one commit each unless noted)

1. **Scaffold `TabRegistry`** at `relay/src/tabs/tab-registry.ts` per spec §4.1. Just the class + types. No persistence yet.
   - Commit: `feat(relay): add TabRegistry in-memory state`

2. **Unit tests for TabRegistry** — lifecycle (registerSessionStart → registerSessionEnd → tabClosed), reverse-lookup by sessionId, `listTabs(userId)` filter.
   - Commit: `test(relay): TabRegistry lifecycle`

3. **Persistence for TabRegistry** — write/read `$HOME/.major-tom/tabs/{tabId}.json` on every state change. Hydrate on construct. Delete file on `tabClosed`. Match the sprite-mapping-persistence pattern in `relay/src/sprites/sprite-mapping-persistence.ts`.
   - Commit: `feat(relay): TabRegistry disk persistence`
   - Commit: `test(relay): TabRegistry persistence roundtrip`

4. **`SessionManager.registerExternal()`** — new method in `relay/src/sessions/session-manager.ts`. Creates a `Session` with caller-supplied id + adapter=`'cli-external'`. Add `'cli-external'` to the `AdapterType` union in `session.ts`.
   - Commit: `feat(relay): sessionManager.registerExternal for hook-registered sessions`
   - Commit: `test(relay): registerExternal uses caller-supplied id`

5. **Hook templates** — add `relay/scripts/hook-templates/session-start.sh` and `stop.sh`. Mirror the shape of `pretooluse.sh` (env read, curl POST with `X-MT-Tab` header). Payload: `{ session_id, cwd }` read from stdin.
   - Commit: `feat(relay): SessionStart and Stop hook templates`

6. **Installer update** — `relay/src/installer/install-hooks.ts`:
   - Add both scripts to `HOOK_FILES[]`.
   - Extend the bundled `SETTINGS_JSON` constant with `SessionStart` and `Stop` hook entries. Match the existing shape for PreToolUse / SubagentStart.
   - Content-hash self-heal will pick them up on relay restart.
   - Commit: `feat(relay): install SessionStart/Stop hooks in private config dir`

7. **Hook-server endpoints** — `relay/src/hooks/hook-server.ts`:
   - `POST /hooks/session-start` → `sessionManager.registerExternal(session_id, cwd)` → `tabRegistry.registerSessionStart(session_id, tabId, cwd, userId)` → emit `tab.session.started` + `session.info`.
   - `POST /hooks/stop` → `sessionManager.get(session_id)?.close()` → `tabRegistry.registerSessionEnd(session_id)` → emit `tab.session.ended` + `session.ended`.
   - Thread a new dep: `tabRegistry` + a broadcast callback. Mirror how `reportAgentLifecycle` is injected today.
   - Commit: `feat(relay): /hooks/session-start and /hooks/stop endpoints`

8. **UserId lookup by tabId** — in `relay/src/routes/shell.ts`, when a PTY attaches authenticated, stash `tabId → userId` in a `Map<string, string>` that hook-server can read. Export it via the same deps bundle. Keep it simple: module-scoped Map, cleared when the tab's PTY closes for good.
   - Commit: `feat(relay): track tabId→userId at PTY attach for hook correlation`

9. **PTY-close → tab teardown** — extend `relay/src/adapters/pty-adapter.ts` to fire a callback when the grace-expire path runs (line ~354 area where `sessions.set(tabId, session)` happens — find the teardown sibling). Wire to `tabRegistry.tabClosed(tabId)` in the app wiring. Broadcast `tab.closed`.
   - Commit: `feat(relay): PTY grace-expire tears down TabRegistry entry`

10. **`tab.list` RPC** — in `relay/src/protocol/messages.ts` add request + response types. In `relay/src/routes/ws.ts` add the `case 'tab.list':` handler next to the existing `case 'session.list':` (around line 1228). Filter by `userId` via `presenceManager.getUserId(ws)` + sandboxGuard, matching the session.list pattern.
    - Commit: `feat(relay): tab.list RPC`
    - Commit: `test(relay): tab.list filters by user`

11. **Wiring** — `relay/src/app.ts` (or wherever the app is composed) needs to construct `TabRegistry`, pass it to hook-server + ws.ts, and hook the PTY-close callback. One integration commit.
    - Commit: `feat(relay): wire TabRegistry into app bootstrap`

12. **End-to-end integration test** — spawn a fake PTY, fire a `SessionStart` hook POST, verify session appears in `tab.list` response with correct tabId + userId. Then `Stop` hook, verify session removed. Then close PTY, verify `tab.closed` broadcast.
    - Commit: `test(relay): end-to-end tab lifecycle via hook server`

### What Wave 2 does NOT do

- No iOS changes. The `tabId` field on existing sprite/agent messages comes in Wave 3.
- No Office UI rebind — that's Wave 4.
- No session cycling animations — Wave 5.
- No migration of existing sprite-mapping files — do that in Wave 5 as part of the cleanup pass.

---

## PR & review flow

- Open PR against `main` titled `feat(relay): Wave 2 — Tab-Keyed Offices relay bridge`.
- Body: reference `docs/PHASE-TAB-KEYED-OFFICES.md` §4.1, §6, §10 (Wave 2 row).
- Copilot auto-requests. Do NOT manually add it.
- Run the canonical PR review workflow from `~/.claude/CLAUDE.md`:
  - First poll: 2 minutes minimum after PR open
  - Subsequent polls: 1 minute intervals
  - Completion detection: count reviews with body containing "Pull request overview"
  - <5 comments in round → merge. ≥5 → fix + push + re-poll.
  - Reply inline to every comment in its thread, with commit SHA for fixes or reasoning for pushback.
- Post-merge: `git checkout main && git pull`, update `docs/STATE.md` Wave 2 row to DONE, prep Wave 3 handoff if time permits.

## If the user says "wait for me"

Stop after PR creation. Don't poll, fix, or merge. See `feedback_review_wait.md`.

---

## Gotchas internalized from Wave 1 research

- **Hook-server is plain Node `http`**, not Fastify. When adding endpoints, follow the existing `if (method === 'POST' && url === '/hooks/X')` pattern in `hook-server.ts`. Don't import Fastify plumbing.
- **`X-MT-Tab` header flows already.** Existing hook scripts read `MAJOR_TOM_TAB_ID` env and pass it as a header (`relay/scripts/hook-templates/pretooluse.sh:18,48` etc.). You don't need to invent new plumbing — your new scripts follow the same shape.
- **`$CLAUDE_CONFIG_DIR` is expanded at invoke time, not install time.** So the settings.json template can reference `$CLAUDE_CONFIG_DIR/hooks/session-start.sh` literally.
- **Claude Code Stop hook, not SessionEnd.** Stream-events doc (`docs/STREAM-EVENTS.md:253`) lists `SessionStart` but the session-end equivalent is `Stop` (line 252, `Stop | Main agent stopping | reason`). Use `Stop` in the settings.json. Our endpoint is still named `/hooks/stop` for clarity.
- **SessionManager.create() currently generates a UUID.** Don't modify `create()`. Add `registerExternal()` as a separate method so the existing iOS-initiated `session.start` flow is untouched.
- **sandboxGuard filters session.list by user path.** Do the same in `tab.list`. Copy the existing pattern (`relay/src/routes/ws.ts:1228–1253`) and substitute `tabRegistry.listTabs()` + filter by `workingDir`.
- **Cold-boot cleanup exists** at `relay/src/routes/ws.ts:2182–2197` (sprite mapping orphans). Add a parallel cleanup for orphaned TabRegistry files in the same pass.

## Success criteria for Wave 2

- [ ] All new tests pass (`cd relay && npm test`).
- [ ] Existing tests still pass (no regressions).
- [ ] Manual smoke: start relay, spawn PTY, run `claude`, confirm a tab entry appears in-memory via a debug log or test probe.
- [ ] PR merged with ≤2 review rounds.
- [ ] `docs/STATE.md` updated with Wave 2 DONE and Wave 3 NEXT.
- [ ] `project_tab_keyed_offices_phase.md` memory updated with Wave 2 status.

Good luck. Ship it clean.
