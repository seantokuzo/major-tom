# HANDOFF: Tab-Keyed Offices — Wave 4 Execution Brief

> **You are a fresh Claude Code session.** Previous sessions shipped Wave 1 (spec freeze), Wave 2 (relay bridge, #149), and Wave 3 (protocol + iOS wiring, #150 + #151). Your job: execute Wave 4 — **iOS Office Rebind + Explicit Terminal Lifecycle**. The spec is LOCKED at `docs/PHASE-TAB-KEYED-OFFICES.md`. Do not re-debate decisions.
>
> If the user's first message is just "next" — that's the trigger. Begin.

---

## Pre-flight (don't skip)

1. `git status` — should be clean on `main` at or past commit `957f12b` (PR #151 merge).
2. `git pull origin main`.
3. **Read in full, in order:**
   - `docs/PHASE-TAB-KEYED-OFFICES.md` — focus on **§7 (iOS changes), §8 (L1–L12 lifecycle scenarios), §10 (Wave 4 row), §12 (success criteria)**.
   - `docs/STATE.md` — current phase table.
4. **Read memory files:**
   - `project_tab_keyed_offices_phase.md` — phase context.
   - `project_sprite_qa_in_flight.md` — paused; don't break the sprite 4-6 test matrix.
   - `feedback_pr_comments.md`, `feedback_pr_workflow.md`, `feedback_auto_poll_reviews.md`, `feedback_reply_inline.md`, `feedback_no_auto_merge.md`, `feedback_copilot_auto_review.md`, `feedback_keychain_always_allow.md`, `reference_wireless_device_deploy.md`.
5. Confirm the iOS project still builds:
   `cd ios && xcodebuild -project MajorTom.xcodeproj -scheme MajorTom -destination 'generic/platform=iOS Simulator' -allowProvisioningUpdates build`
6. Relay dev server may or may not be running — not required for Wave 4 unless you want an on-device smoke test. If you need it: `cd relay && npm run dev` (run_in_background).
7. Branch: Wave 4 is a single iOS PR (no relay changes). Use worktree isolation per `feedback_parallel_agents.md`:
   `git checkout -b tab-keyed-offices/wave4-ios`

## Execution rules (non-negotiable)

- **Incremental migration — compile between every step.** Feature-flag is currently off; flipping the OfficeSceneManager rekey touches routing throughout the sprite/agent event path. Do the work in the commit order below to keep every commit green.
- **Atomic commits.** Conventional Commits. Scope = `ios`.
- **Never `--no-verify`**, never amend a published commit.
- **Use TaskCreate** to track sub-tasks.
- **Use Context7** for SwiftUI / SpriteKit edge cases (iOS 17+ `@Observable` navigation patterns, SKScene reparenting, deep-link handling).
- **Verify before reporting done.** Simulator build clean. Also do a device build sanity check per `reference_wireless_device_deploy.md` if the PR touches notification/banner deep links.

---

## Wave 4 scope

### Non-goals (do NOT touch)
- No new protocol messages. Wire format is frozen from Waves 2–3.
- No relay code changes. If you find yourself editing `relay/`, stop and rethink.
- No sprite mapping persistence rekey — still sessionId-keyed. Wave 5 cleans that up when we do the walk-off animations.
- No session cycling animations or hard-kill PTY edge cases. Wave 5.

### Sub-tasks

#### Track: iOS (branch `tab-keyed-offices/wave4-ios`)

1. **`OfficeSceneManager` — rekey `offices` dictionary to tabId.**
   - `offices: [String: OfficeViewModel]` — same type, key semantics change.
   - Rename `createOffice(for sessionId:)` → `createOffice(for tabId:)`.
   - LRU eviction policy unchanged — still scene-level.
   - At this step, route `sprite.*` / `agent.*` events to the right Office by looking up `event.tabId` first (now on the wire per Wave 3 `§5.2`). Fall back to reverse-lookup via `TabRegistryStore.getTabForSession(sessionId)` when the incoming event has a nil `tabId` (legacy `cli` / `vscode` paths — still supported).
   - If a tab has an active Office but the incoming event's sessionId is new, ADD it to the Office's `activeSessionIds` rather than creating a new Office. Spec §7.1 + §7.2.
   - Commit: `refactor(ios): rekey OfficeSceneManager to tabId with sessionId fallback`

2. **`OfficeViewModel` — session roster.**
   - Add `activeSessionIds: Set<String>` to each Office VM. Humans are scoped by `(tabId, sessionId)`; dogs are tab-level only.
   - `tab.session.started` → insert into `activeSessionIds`, no immediate sprite change.
   - `tab.session.ended` → remove from `activeSessionIds`, walk humans off with existing dismiss animation, dogs stay.
   - Commit: `feat(ios): OfficeViewModel tracks activeSessionIds for tab-scoped roster`

3. **`OfficeManagerView` — lists tabs.**
   - Swap the data source from `relay.sessionList` → `relay.tabRegistryStore.tabs`.
   - Add `.task { try? await relay.requestTabList() }` on appear — fixes the "sessionList never populated" bug the original Office Manager had, by design.
   - Two sections:
     - **Active Offices** — tabs the user has already materialized into an Office (entries where `officeSceneManager.offices[tabId] != nil`).
     - **Available Tabs** — tabs with active claude sessions (TabMeta with non-empty `sessions` and status != "closed") that the user has not yet opened.
   - Status badge: show "active" if any session running in the tab, "idle" if tab exists but sessions all ended.
   - Tap an Available Tab → `officeSceneManager.createOffice(for: tab.tabId)` → push `OfficeView(tabId:)`.
   - Commit: `feat(ios): OfficeManagerView lists tabs via TabRegistryStore`

4. **`OfficeView(tabId:)` route.**
   - Rename the entry point from `OfficeView(sessionId:)` → `OfficeView(tabId:)`. Update all call sites (Office Manager, deep links, banner navigation, etc.).
   - Internally the view still resolves the Office VM via `officeSceneManager.offices[tabId]`.
   - Commit: `feat(ios): OfficeView route keyed by tabId`

5. **Banner + notification routing.**
   - `SpriteResponseBanner` (and sibling banners) carry `sessionId` today. Switch primary routing to `tabId` from the event, keeping `sessionId` for disambiguation only when `tabId == nil` (legacy path).
   - Cross-session banner tap → navigate to `OfficeView(tabId:)` resolved from the event's `tabId`.
   - UNUserNotification deep-link payload: include `tabId`. Update `NotificationService` + any shortcut / widget tap handlers so "Cool Beans" and similar actions land in the right Office.
   - Commit: `feat(ios): banner + notification routing by tabId`

6. **Remove the `tabKeyedOffices` feature flag.**
   - Delete the flag from `FeatureFlags.swift`.
   - Any conditional branches that gated on it collapse to the tabId-primary path.
   - Commit: `chore(ios): remove tabKeyedOffices feature flag`

7. **Rip out terminal auto-spawn-on-empty.**
   - Find the TerminalView / TerminalViewModel code that auto-creates a new tab when no tabs exist (cold launch, "closed the last tab", etc.). Common offender: an `onAppear` or scene-phase handler that calls `createNewTab()` unconditionally.
   - Replace with an empty-state screen: a `ContentUnavailableView` (iOS 17+) with a "New Terminal" action button that explicitly creates a tab on user tap.
   - Spec success criterion: "Closing the last terminal tab does NOT auto-spawn a new one" + "Cold app launch does NOT auto-spawn".
   - Commit: `feat(ios): explicit terminal lifecycle — no auto-spawn on empty`

8. **L1–L12 manual verification** (§8 lifecycle scenarios) on simulator or device:
   - L1–L3: open tab, type `claude`, tap Available Tab → Office opens, dogs walk in.
   - L5–L6: graceful exit → humans walk off, dogs stay; restart claude → humans fade back in.
   - L7: close terminal tab → Office tears down after PTY grace.
   - L9: two concurrent tabs → two Offices, independent sprites.
   - L11: relay restart mid-session → Office + roster rehydrate.
   - If any scenario breaks, file a GitHub issue with `tech-debt` label; decide per §12 success criteria whether to fix now or defer to Wave 5.
   - No commit needed — verification step. Note results in the PR body.

9. **iOS build verification** — simulator build clean, device build clean (`reference_wireless_device_deploy.md`). No warnings added beyond baseline.

## PR & review flow

**Single PR** (no relay changes in Wave 4):

- **Title:** `feat(ios): Wave 4 — Tab-Keyed Offices Office rebind + explicit terminal lifecycle`
- **Body:** references spec §7, §8, §10 (Wave 4 row), §12 (success criteria). Include the L1–L12 verification checklist and note which scenarios were actually exercised vs deferred.

Run the canonical PR review workflow from `~/.claude/CLAUDE.md`:
- First poll: 2 minutes minimum after PR open.
- Subsequent polls: 1 minute intervals.
- Completion detection: count reviews whose body contains "Pull request overview".
- `<5` comments in round → merge. `≥5` → fix + push + re-poll.
- Reply inline to every comment, commit SHA for fixes, reasoning for pushback.
- Post-merge: `git checkout main && git pull`, update `docs/STATE.md` Wave 4 row to SHIPPED, rewrite this HANDOFF for Wave 5, update `project_tab_keyed_offices_phase.md`.

## If the user says "wait for me"

Stop after PR creation. Don't poll, fix, or merge. See `feedback_review_wait.md`.

---

## Gotchas (from Wave 3)

- **Legacy sessions still exist.** `cli` and `vscode` adapter sessions have no TabRegistry binding → `event.tabId` is nil. OfficeSceneManager must keep a sessionId fallback path (via `TabRegistryStore.getTabForSession(sessionId)` — or equivalent — first, then a "legacy Office" synthetic tabId if you want to surface them in the UI). Simplest pragmatic answer: don't surface legacy sessions in Office Manager at all in Wave 4; let them continue to be invisible (they were already invisible before this phase). Document the decision in the PR body.
- **`TabRegistryStore` is network-fed.** Defend against duplicate or malformed payloads the same way Wave 3's `replaceAll` does. Don't introduce new `Dictionary(uniqueKeysWithValues:)` traps.
- **`AgentDismissedEvent`** has `tabId` on the wire as of Wave 3 (b5d68da). If you add new agent events or rewire existing ones, preserve the field.
- **Sprite mapping disk files are still session-keyed.** Do NOT rekey them — Wave 5 owns that migration. The office-level aggregation happens at runtime via TabRegistry lookup.
- **Terminal auto-spawn has edge cases.** Launch-from-shortcut, launch-from-notification, launch-from-widget may all have their own "open terminal immediately" paths. Audit all launch entry points, not just cold app launch.
- **Watch for navigation regressions.** Switching the primary key in `OfficeView` changes how NavigationStack paths encode. Test restore-from-background behaviour if the app uses scene storage.

## Success criteria for Wave 4

- [ ] `OfficeSceneManager` keyed by tabId; sessionId events fall back via TabRegistryStore lookup.
- [ ] `OfficeManagerView` lists tabs (Active + Available), Available tap creates the Office.
- [ ] `OfficeView(tabId:)` entry point is the single source of Office routing.
- [ ] Banner + notification deep links route by tabId.
- [ ] `tabKeyedOffices` feature flag deleted.
- [ ] Terminal never auto-spawns a tab on empty (cold launch, last-tab-closed, etc.).
- [ ] L1–L9 lifecycle scenarios pass manual check (L10–L12 optional if time-pressed — defer with issue).
- [ ] PR merged with ≤2 review rounds.
- [ ] `docs/STATE.md` Wave 4 row updated to SHIPPED, Wave 5 marked NEXT.
- [ ] `project_tab_keyed_offices_phase.md` memory updated.
- [ ] `docs/HANDOFF-TAB-KEYED-OFFICES.md` rewritten for Wave 5.

Good luck. Ship it clean.
