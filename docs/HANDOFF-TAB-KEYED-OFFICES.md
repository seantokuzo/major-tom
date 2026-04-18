# HANDOFF: Tab-Keyed Offices — Wave 3 Execution Brief

> **You are a fresh Claude Code session.** Previous sessions shipped Wave 1 (spec freeze) and Wave 2 (relay bridge, PR #149). Your job: execute Wave 3 — Protocol + iOS wiring. The spec is LOCKED at `docs/PHASE-TAB-KEYED-OFFICES.md`. Do not re-debate decisions.
>
> If the user's first message is just "next" — that's the trigger. Begin.

---

## Pre-flight (don't skip)

1. `git status` — should be clean on `main` at or past commit `e420962` (docs: Wave 4 scope expansion). Wave 2 is already merged as `d98905a`.
2. `git pull origin main`
3. **Read in full, in order:**
   - `docs/PHASE-TAB-KEYED-OFFICES.md` — the spec. Focus on §5.2 (protocol extension), §7 (iOS changes), §10 (Wave 3 row).
   - `docs/STATE.md` — current phase table.
4. **Read memory files:**
   - `project_tab_keyed_offices_phase.md` — phase context.
   - `project_sprite_qa_in_flight.md` — paused; don't touch sprite code except the minimal plumbing §5.2 asks for.
   - `feedback_pr_comments.md`, `feedback_pr_workflow.md`, `feedback_auto_poll_reviews.md`, `feedback_reply_inline.md`, `feedback_no_auto_merge.md`, `feedback_copilot_auto_review.md`.
5. Confirm the relay still builds: `cd relay && npx tsc --noEmit`.
6. Relay dev server may or may not be running — not required for Wave 3 (unit tests are the primary signal). If you need it: `cd relay && npm run dev` (run_in_background).
7. Branch(es): Wave 3 is two parallel tracks. Use one PR each:
   - Relay: `git checkout -b tab-keyed-offices/wave3-relay`
   - iOS: `git checkout -b tab-keyed-offices/wave3-ios` (sequential or parallel — iOS only needs the wire format, not the relay emit logic, to compile).
   - Ship both via separate PRs. Use worktree isolation if you run them in parallel (`feedback_parallel_agents.md`).

## Execution rules (non-negotiable)

- **TDD discipline.** Test first where it makes sense (new decoders, emit-time tabId population). One behavior per commit.
- **Atomic commits.** Conventional Commits. Scope = `relay` or `ios`.
- **Never `--no-verify`**, never amend a published commit.
- **Use TaskCreate** to track the sub-tasks below.
- **Use Context7** for SwiftUI decoder / Codable edge cases you're not 100% sure of.
- **Verify before reporting done.** Relay: `npm test` all green. iOS: `xcodebuild ... build` clean (see `reference_wireless_device_deploy.md`).

---

## Wave 3 scope

### Non-goals (do NOT touch)
- No UI rewire. Office Manager still lists SDK sessions. Wave 4 does the rebind.
- No auto-spawn-on-empty fix. That's Wave 4 too (see §10).
- No sprite mapping rekey. Still session-keyed. Wave 5 cleans up.

### Sub-tasks

#### Track A: Relay (branch `tab-keyed-offices/wave3-relay`)

1. **Extend protocol messages with optional `tabId?: string`** per spec §5.2:
   - `SpriteLinkMessage`, `SpriteUnlinkMessage`, `SpriteStateMessage`, `SpriteResponseMessage`
   - `AgentSpawnMessage`, `AgentWorkingMessage`, `AgentIdleMessage`, `AgentCompleteMessage`, `AgentDismissedMessage`
   - `SessionMetaMessage` (so `session.list.response` carries tabId for legacy compat)
   - Commit: `feat(relay): add optional tabId to sprite and agent protocol messages`

2. **Populate `tabId` at emit time** in `relay/src/routes/ws.ts`. Every site that constructs one of the above messages should call `tabRegistry.getTabForSession(sessionId)` (nullable) and set `tabId` when present. Legacy SDK sessions yield undefined → field omitted, existing clients unaffected.
   - Add a helper: `function tabIdFor(sessionId: string): string | undefined { return tabRegistry?.getTabForSession(sessionId)?.tabId; }`
   - Thread through the broadcastToSession call sites that emit the affected types.
   - Commit: `feat(relay): populate tabId on sprite and agent broadcasts`

3. **Same for `session.list.response`** — when building `SessionMetaMessage[]`, annotate each entry with tabId if the sessionId has a TabRegistry binding.
   - Commit: `feat(relay): annotate session.list.response with tabId`

4. **Unit tests** — spawn a fake TabRegistry + SessionManager, emit each of the new-shape messages, verify `tabId` is populated for cli-external sessions and omitted for legacy cli sessions.
   - Commit: `test(relay): tabId annotation on sprite/agent messages`

#### Track B: iOS (branch `tab-keyed-offices/wave3-ios`)

5. **Decoders for tab.* events.** Add Codable structs in `ios/MajorTom/Features/Office/Models/` (or wherever SpriteMessages live — follow the existing layout):
   - `TabSessionStartedEvent { tabId, sessionId, workingDirName, startedAt }`
   - `TabSessionEndedEvent { tabId, sessionId, endedAt }`
   - `TabClosedEvent { tabId }`
   - `TabMeta { tabId, workingDirName, status, createdAt, lastSeenAt, sessions: [TabSessionSummary] }`
   - `TabListResponse { tabs: [TabMeta] }`
   - Commit: `feat(ios): tab protocol message models`

6. **Wire decoders into the WebSocket message router.** When a `tab.*` event arrives, decode it and push to a new `TabRegistryStore` `@Observable` on the relay service (mirror the sessionList cache pattern). No UI observer yet — just cache.
   - Commit: `feat(ios): decode tab.* events into TabRegistryStore`

7. **Optional `tabId` on sprite/agent event models.** Add `tabId: String?` to the Swift structs matching the protocol extensions. Don't change behavior yet — just preserve the field.
   - Commit: `feat(ios): thread optional tabId through sprite and agent event models`

8. **`RelayService.requestTabList()` async method.** Fires `{ type: 'tab.list' }`, awaits the response (or emits into the store). Match the existing `requestSpriteState` / `requestSessionList` pattern in the relay service.
   - Commit: `feat(ios): RelayService.requestTabList()`

9. **Feature flag.** Add a bool to wherever iOS feature flags live (UserDefaults or a dedicated flags service). Default `false`. When `true`, iOS uses `tabId` for sprite/agent event routing; when `false`, falls back to `sessionId`. No UI changes regardless — Wave 4 removes the flag.
   - Commit: `feat(ios): tabKeyedOffices feature flag (default off)`

10. **iOS build verification** — `xcodebuild ... build` clean. No warnings added.
    - Commit: `chore(ios): verify Wave 3 compiles clean on device target`

### What Wave 3 does NOT do

- No `OfficeSceneManager` rekey. Still sessionId-keyed.
- No `OfficeManagerView` tab-list UI. Wave 4.
- No auto-spawn-on-empty fix. Wave 4.
- No session cycling animations. Wave 5.

---

## PR & review flow

Two PRs (one per track):

1. **Relay PR** — title `feat(relay): Wave 3 — Tab-Keyed Offices protocol extension`. Body references spec §5.2 + §10 (Wave 3).
2. **iOS PR** — title `feat(ios): Wave 3 — Tab-Keyed Offices protocol + feature flag`. Body references §7 + §10.

For each:
- Copilot auto-requests. Do NOT manually add it.
- Run the canonical PR review workflow from `~/.claude/CLAUDE.md`:
  - First poll: 2 minutes minimum after PR open
  - Subsequent polls: 1 minute intervals
  - Completion detection: count reviews whose body contains "Pull request overview"
  - `<5` comments in round → merge. `≥5` → fix + push + re-poll.
  - Reply inline to every comment, commit SHA for fixes, reasoning for pushback.
- Post-merge: `git checkout main && git pull`, update `docs/STATE.md` Wave 3 row to SHIPPED, prep Wave 4 handoff if time permits.

## If the user says "wait for me"

Stop after PR creation. Don't poll, fix, or merge. See `feedback_review_wait.md`.

---

## Gotchas (from Wave 2)

- **Tab events are broadcast-to-all.** `serverMessageHandler` in `ws.ts` treats `message.type.startsWith('tab.')` as global (Office Manager cares regardless of attached session). Sprite/agent messages stay session-scoped; adding `tabId` to them does NOT change that routing.
- **`tabRegistry` is optional in `WsDeps`.** App bootstrap passes it; tests may not. Guard helper calls: `tabRegistry?.getTabForSession(...)`.
- **Idempotent SessionStart.** Hook-server already dedupes duplicate SessionStart broadcasts (see `relay/src/hooks/hook-server.ts` around line 450). Don't re-implement that guard elsewhere.
- **Protocol field is always OPTIONAL.** Legacy clients must continue to decode payloads without tabId; iOS must not assume tabId is present on sprite/agent events from cli/vscode adapters.
- **Sprite mapping is session-keyed on disk.** Don't rekey yet; Wave 5.

## Success criteria for Wave 3

- [ ] Relay emits tabId on sprite + agent messages when the session has a TabRegistry binding; absent otherwise.
- [ ] `session.list.response` carries tabId per entry when bound.
- [ ] iOS decodes all four `tab.*` server events and caches them in a TabRegistryStore.
- [ ] `RelayService.requestTabList()` exists and is callable from VM / UI layer.
- [ ] Feature flag exists; flipping it toggles tabId-vs-sessionId routing at the sprite/agent event layer. Default off.
- [ ] Both relay + iOS PRs merged with ≤2 review rounds each.
- [ ] `docs/STATE.md` updated with Wave 3 SHIPPED and Wave 4 NEXT.
- [ ] `project_tab_keyed_offices_phase.md` memory updated.

Good luck. Ship it clean.
