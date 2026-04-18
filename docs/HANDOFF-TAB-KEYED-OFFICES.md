# HANDOFF: Tab-Keyed Offices — Wave 5 Execution Brief

> **You are a fresh Claude Code session.** Previous sessions shipped Wave 1 (spec freeze, 8e1c56f), Wave 2 (relay bridge, PR #149), Wave 3 (protocol + iOS wiring, PRs #150 + #151), and Wave 4 (iOS Office rebind + explicit terminal lifecycle, PR #152). Your job: execute Wave 5 — **Session Cycling + Edge Cases**. The spec is LOCKED at `docs/PHASE-TAB-KEYED-OFFICES.md`. Do not re-debate decisions.
>
> If the user's first message is just "next" — that's the trigger. Begin.

---

## Pre-flight (don't skip)

1. `git status` — should be clean on `main` at or past commit `9ba3821` (PR #152 merge).
2. `git pull origin main`.
3. **Read in full, in order:**
   - `docs/PHASE-TAB-KEYED-OFFICES.md` — focus on **§7 (iOS changes), §8 (L1–L12 lifecycle scenarios — Wave 5 owns L5, L6, L10, and the hard-kill path), §10 (Wave 5 row), §12 (success criteria)**.
   - `docs/STATE.md` — current phase table.
4. **Read memory files:**
   - `project_tab_keyed_offices_phase.md` — phase context.
   - `project_sprite_qa_in_flight.md` — still paused; Wave 5 landing unblocks the sprite 4-6 test matrix resume.
   - `feedback_pr_comments.md`, `feedback_pr_workflow.md`, `feedback_auto_poll_reviews.md`, `feedback_reply_inline.md`, `feedback_no_auto_merge.md`, `feedback_copilot_auto_review.md`, `feedback_keychain_always_allow.md`, `reference_wireless_device_deploy.md`.
5. Confirm the iOS project still builds:
   `cd ios && xcodebuild -project MajorTom.xcodeproj -scheme MajorTom -destination 'generic/platform=iOS Simulator' -allowProvisioningUpdates build`
6. Relay dev server may or may not be running. Wave 5 will need it running on device for L5–L12 manual verification: `cd relay && npm run dev` (run_in_background).
7. Branch: Wave 5 may touch both iOS and relay (hard-kill PTY + persistence migration). Open pairs on `tab-keyed-offices/wave5-relay` + `tab-keyed-offices/wave5-ios` per `feedback_parallel_agents.md`. If the scope collapses to iOS-only during planning, keep one branch.

## Execution rules (non-negotiable)

- **Incremental migration — compile between every step.** Wave 5 adds a sessionId binding to AgentState which ripples through every sprite/agent handler. Do the data-model change first, compile, then wire walk-off/walk-in.
- **Atomic commits.** Conventional Commits. Scope = `ios` or `relay` per commit.
- **Never `--no-verify`**, never amend a published commit.
- **Use TaskCreate** to track sub-tasks.
- **Use Context7** for SwiftUI / SpriteKit specifics if the walk-off/walk-in animations need iOS 17+ API verification (they shouldn't — the existing `handleAgentDismissed` path is reused).
- **Verify before reporting done.** Simulator build clean + device build clean per `reference_wireless_device_deploy.md`. Run the L1–L12 scenarios manually on device before marking the wave done.

---

## Wave 5 scope

### Non-goals (do NOT touch)

- No new protocol messages. Wire format is still frozen from Waves 2–3.
- No sprite mapping persistence format change — but the **one-time migration cleanup** (Gate B) is this wave's responsibility. Scrap existing sprite-mapping disk files on relay boot.
- No Office Manager UI rework — Wave 4 owns that.
- No Ground Control-side Office surfacing — spec §11 keeps that out of scope.

### Sub-tasks

#### Track: iOS — per-session agent scoping (branch `tab-keyed-offices/wave5-ios`)

1. **`AgentState.sessionId` binding.**
   - Add `var sessionId: String?` to `AgentState`. Populate on `agent.spawn` / `sprite.link` from `event.sessionId`. `sprite.state` rehydration should populate too.
   - Threads through `OfficeViewModel.handleAgentSpawn`, `handleSpriteLink`, `handleSpriteState`. `removeAgent` / walk-off paths don't need it but must preserve it during state transitions.
   - Commit: `feat(ios): bind AgentState to originating sessionId`

2. **Refine `handleTabSessionEnded` — walk off only the ending session's humans.**
   - Today (Wave 4) walks off ALL humans because AgentState had no session binding. Filter `vm.agents` to agents where `sessionId == endingSessionId`. Dogs (idle sprites) still stay.
   - Rotation of `vm.sessionId` to a remaining `activeSessionIds` stays — unchanged.
   - Commit: `feat(ios): scope tab.session.ended walk-off to owning session`

3. **Walk-in on `tab.session.started` within an existing Office.**
   - Today the first `agent.spawn` of a new session inside an already-open Office causes the human to fade in via `syncScene`. That works. What's missing: a dedicated "new crew joining" feel — e.g. a quick greeting emote on walk-in. Spec §7.2 implies parity with the walk-off animation.
   - Minimum viable: explicitly trigger a spawn entrance on first `agent.spawn` per `(tabId, sessionId)` pair. If the existing `.spawning` animation already covers this, this sub-task is a no-op with a docstring update.
   - Commit: `feat(ios): explicit walk-in animation for newly joining sessions` (or a no-op commit noting the existing path is sufficient).

4. **Hard-kill PTY handling.**
   - When the relay broadcasts `tab.closed` without a preceding graceful `tab.session.ended`, iOS needs to walk off humans AND tear down the Office. Wave 4's `handleTabSessionEnded` is called separately, but `tab.closed` jumps straight to `closeOffice`, leaving no walk-off frame.
   - Fix: in the `tab.closed` handler (currently `tabRegistryStore.remove(tabId:)` + `officeSceneManager?.closeOffice(for: event.tabId)`), first walk off every agent scoped to any session in that tab, then close the office after a short grace (~1.5s — matches the existing dismiss animation).
   - Commit: `feat(ios): walk humans off before tearing down on tab.closed`

5. **Multi-claude-in-one-tab smoke (Gate A).**
   - With per-session scoping in place, running `claude` twice in the same tab should produce two rosters of humans in the same Office. Dogs are shared.
   - The agent events should already route correctly via sessionToOfficeKey. Verify manually in L10 and write any corrections as follow-up commits.
   - No commit needed unless a bug turns up.

#### Track: Relay — persistence migration cleanup (branch `tab-keyed-offices/wave5-relay`)

6. **Scrap legacy sprite-mapping files on relay boot (Gate B).**
   - On startup, sweep `$HOME/.major-tom/sprite-mappings/` (or the equivalent directory path) and delete files older than the TabRegistry cutover. Relay logs a single "cleared N legacy sprite mappings" line on boot.
   - Guard: only runs once per relay version. Track via a `.migrated-v4` sentinel file in the same directory.
   - Commit: `feat(relay): clear legacy sprite-mapping files on boot (Wave 5 migration)`
   - Tests: persistence migration test covering sentinel creation + idempotence.

7. **Relay test coverage for the migration + hard-kill path.**
   - Add integration tests around `PtyAdapter` grace-expire that emit `tab.closed` without prior `tab.session.ended`. iOS handles the walk-off (Wave 5 iOS commit #4); relay just needs to verify the event fires.
   - Commit: `test(relay): cover hard-kill PTY tab.closed broadcasting`

#### L1–L12 manual verification on device

8. Run through every scenario listed in spec §8. Follow the PR body checklist that shipped with Wave 4 (#152) — L1–L4 likely still pass, L5–L12 are what this wave is targeting. File any regressions as `tech-debt`-labelled issues; fix blockers inline.

---

## PR & review flow

**Two PRs** (iOS and relay) if the relay migration lands this wave. If the scope stays iOS-only, open one PR.

- **iOS Title:** `feat(ios): Wave 5 — Tab-Keyed Offices session cycling + edge cases`
- **Relay Title:** `feat(relay): Wave 5 — sprite-mapping migration + hard-kill tests`
- **Body:** references spec §7, §8, §10 (Wave 5 row), §12 (success criteria). Include the L1–L12 verification checklist with actual pass/fail state after device exercise.

Run the canonical PR review workflow from `~/.claude/CLAUDE.md`:
- First poll: 2 minutes minimum after PR open.
- Subsequent polls: 1 minute intervals.
- Completion detection: count reviews whose body contains "Pull request overview".
- `<5` comments in round → merge. `≥5` → fix + push + re-poll.
- Reply inline to every comment, commit SHA for fixes, reasoning for pushback.
- Post-merge: `git checkout main && git pull`, update `docs/STATE.md` Wave 5 row to SHIPPED, delete this HANDOFF (phase complete) or rewrite for the next phase if one exists, update `project_tab_keyed_offices_phase.md`, unpause `project_sprite_qa_in_flight.md`.

## If the user says "wait for me"

Stop after PR creation. Don't poll, fix, or merge. See `feedback_review_wait.md`.

---

## Gotchas (from Wave 4)

- **`AgentState` is Equatable / used in SwiftUI diffing** — adding `sessionId: String?` changes the synthesized Equatable. Verify the scene-sync `onChange(of: viewModel.agents, initial: true)` still diffs correctly; spurious re-syncs would re-trigger walk-in animations.
- **`handleAgentDismissed` is the current walk-off primitive**. Reusing it for `tab.session.ended` in Wave 4 works because it doesn't hit the relay — it's purely a local sprite dismissal. Keep that contract.
- **`sessionToOfficeKey` is populated by `ensureViewModel` + `handleTabSessionStarted` + `seedRosterFromTabRegistry`.** If you add a new event path that creates an Office, populate the map or you'll lose routing for later sessionId-only events.
- **`session.ended` guard in `RelayService`** — Wave 4 added `vm?.tabId != event.sessionId` check to avoid nuking tab-backed Offices. Preserve it when touching that case.
- **`sprite.state` rehydration does not know about tabId** on the wire (Wave 3 added optional `tabId` on the event itself, but the inner `SpriteMapping` struct doesn't carry one). Session-scoping AgentState means sprite.state must stamp the originating sessionId onto each agent — the event's top-level `sessionId` is the source.
- **`handleAgentDismissed` in `OfficeSceneManager.handleTabSessionEnded`** is called synchronously in a for-loop; the dismissal Tasks run concurrently, which is fine. But if the Office is already being torn down by `tab.closed` happening milliseconds later, the walk-off Tasks may race with `closeOffice`. Wave 4 trusts the relay to sequence tab.session.ended → tab.closed; don't break that assumption in Wave 5's hard-kill commit.
- **Relay persistence cleanup** is a one-shot per-version job. If you re-run the migration every boot you'll wipe legitimate user data. Sentinel file is the gate.

## Success criteria for Wave 5

- [ ] `AgentState.sessionId` populated on spawn/link/state events.
- [ ] `tab.session.ended` walks off only the ending session's humans (not all).
- [ ] Walk-in on `tab.session.started` inside an existing Office looks deliberate (or the existing `.spawning` animation is confirmed sufficient and documented).
- [ ] `tab.closed` triggers walk-off of all sessions' humans before tearing the Office down.
- [ ] L1–L9 lifecycle scenarios pass manual check. L10–L12 (multi-claude, relay restart, Ground Control) exercised at least once.
- [ ] Legacy sprite-mapping files cleared on relay boot with sentinel file preventing re-runs.
- [ ] Sprite 4-6 QA test matrix re-run clean on top of Wave 5 (unpause `project_sprite_qa_in_flight.md`).
- [ ] PR(s) merged with ≤2 review rounds each.
- [ ] `docs/STATE.md` Wave 5 row updated to SHIPPED, phase table reflects completion.
- [ ] `project_tab_keyed_offices_phase.md` memory updated to "phase complete" (all 5 waves shipped).
- [ ] `docs/HANDOFF-TAB-KEYED-OFFICES.md` deleted or points at whatever's next.

Good luck. Ship it clean.
