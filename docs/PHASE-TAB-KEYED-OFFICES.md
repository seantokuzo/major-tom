# Phase — Tab-Keyed Offices

> Rekey Office identity from Claude SDK session → iOS terminal tab. Auto-register `claude` sessions via Claude Code's native `SessionStart`/`Stop` hooks so terminal-tab `claude` invocations become first-class Offices.

**Status:** Wave 1 — Research + Spec Freeze (2026-04-17)
**Supersedes:** Nothing. Builds on Sprite-Agent Wiring (PRs #137–#148).
**Pauses:** Sprite waves 4-6 QA (`project_sprite_qa_in_flight.md`) — resume after this ships.

---

## 1. Goal

Make the Office metaphor match the user's mental model:

- An **Office** is a persistent room tied to a **terminal tab**, not to a Claude session.
- **Dogs** (pet sprites) live in the Office and persist across claude start/stop cycles.
- **Humans** (agent sprites) cycle in and out as `claude` sessions start and end inside that tab.
- The Office Manager lists **tabs**, not sessions.
- Running `claude` in a terminal tab auto-registers with the relay via hooks, so no iOS-initiated RPC is needed to create a session.

Today the middle-man plumbing is already in place — `shell.ts` injects `CLAUDE_CONFIG_DIR` into every PTY, hooks fire against the relay — but hook payloads never register a `SessionManager` entry, so Claude sessions running in terminal tabs are invisible to the Office Manager UI.

## 2. Mental model

```
Terminal tab  ─── 1 : N ─── Claude sessions (inside that tab's PTY over its lifetime)
      │
      └── 1 : 1 ── Office (SKScene in iOS)
                     │
                     ├── Dogs (persist for the Office lifetime)
                     └── Humans (bound to the currently-active claude session(s))
```

**Office lifecycle = Tab lifecycle.** (Mental-model flip post-#155.)
- Tab created: card appears in Office Manager immediately as "No Office — tap to create". Office scene is NOT auto-materialized.
- `SessionStart` hook for that tab: card subtitle updates with the claude session count. Scene still not auto-created.
- Office created: user taps the card → `createOffice(for: tabId)` → SKScene materializes → `populateIdleSprites()` seeds all dogs + active human crew scattered across random station modules. Life Engine drives idle activity.
- Office destroyed (scene-only): context-menu "Close Office" → SKScene torn down, tab/PTY/registry all untouched → card flips back to "No Office — tap to create".
- Tab destroyed: `exit`/Ctrl+D in shell OR user closes tab → iOS POSTs `/shell/:tabId/kill` → PTY killed immediately → `tab.closed` broadcasts → Office scene walks sprites off and tears down → card removed.

**Session lifecycle = sprite roster churn inside an Office.**
- `SessionStart` (inside a tab that already has an Office): new humans fade in as subagents spawn.
- `Stop` (session ends): humans walk off. Dogs stay. Office remains, quiet.
- Next `SessionStart` in the same tab: new humans fade back in. Same Office, same dogs.

## 3. Non-goals

- **Not rewriting the PWA.** This phase is iOS + relay only.
- **Not redesigning sprite semantics.** Role→sprite mapping, /btw queue, tool bubbles, progress indicators all behave as they do today.
- **Not changing how the hook middle-man works.** PreToolUse / SubagentStart / SubagentStop routing stays. We're only *adding* `SessionStart` and `Stop` hooks.
- **Not merging sessions across tabs.** A session lives in exactly one tab. If `claude` is run from a shell that doesn't have a `MAJOR_TOM_TAB_ID` env (e.g. Ground Control), it doesn't become an Office at all — it stays the legacy SDK-session path.

## 4. Data model

### 4.1 `TabRegistry` (new, relay-side)

In-memory + persisted map of known tabs and their current sessions.

```ts
// relay/src/tabs/tab-registry.ts
export interface TabMeta {
  tabId: string;
  userId: string | undefined;          // owner (from hook-server auth)
  workingDir: string | undefined;      // cwd at first SessionStart
  createdAt: string;                   // ISO — first hook landing
  lastSeenAt: string;                  // ISO — bumped on any hook for this tab
  sessionIds: Set<string>;             // live claude sessions in this tab
  status: 'active' | 'idle' | 'closed';
}

export class TabRegistry {
  registerSessionStart(sessionId: string, tabId: string, cwd: string, userId?: string): void;
  registerSessionEnd(sessionId: string): void;   // leaves TabMeta alive; sets 'idle' if empty
  tabClosed(tabId: string): void;                // PTY grace expired — hard teardown
  getTabForSession(sessionId: string): TabMeta | undefined;
  listTabs(userId?: string): TabMeta[];          // filtered by sandboxGuard at call sites
  touch(tabId: string): void;                    // bump lastSeenAt
}
```

**Persistence:** `$HOME/.major-tom/tabs/{tabId}.json` — write on every state change, read on relay boot to hydrate. Deleted on `tabClosed`. Tabs without any `SessionStart` never persist. (One file per tab keeps writes small.)

### 4.2 `SessionManager` changes (minimal)

- Add a new adapter type: `'cli-external'` (alongside existing `'cli'` and `'vscode'`). Used for sessions registered by `SessionStart` hooks, not by iOS-initiated `session.start` RPCs.
- Add a new method `registerExternal(sessionId: string, workingDir: string): Session` that creates a session *with the caller-supplied id* (claude's own session_id) instead of generating a UUID.
- Everything else stays: `listMeta()`, `toMeta()`, persistence file layout (by `sessionId`), transcript handling.

### 4.3 `SessionMeta` extension

Add optional `tabId?: string` to `SessionMeta` (relay) and `SessionMetaInfo` (iOS). Populated on `cli-external` sessions by looking up the TabRegistry. Unused on `cli`/`vscode` sessions.

### 4.4 Sprite mapping — stays session-keyed

**Do not rekey** `sprite-mapping-persistence` files or the `spriteMappings` in-memory cache. Sprites are tied to subagents; subagents are tied to sessions. The Office groups them by tab via TabRegistry lookups.

## 5. Protocol changes

### 5.1 New messages

```ts
// Client → server
{ type: 'tab.list' }

// Server → client
{ type: 'tab.list.response', tabs: TabMetaMessage[] }

interface TabMetaMessage {
  tabId: string;
  workingDirName: string;              // basename of workingDir
  status: 'active' | 'idle' | 'closed';
  createdAt: string;
  lastSeenAt: string;
  sessions: SessionMetaMessage[];      // already sessionId-keyed; now includes tabId
}
```

### 5.2 Extend existing messages

Add optional `tabId?: string` to:
- `SessionMetaMessage` (for `session.list.response` backward compat).
- `SpriteLinkMessage`, `SpriteUnlinkMessage`, `SpriteStateMessage`, `SpriteResponseMessage` — so iOS can route events to the right Office-by-tab without reverse-lookup.
- Agent lifecycle messages (`AgentSpawnMessage`, `AgentWorkingMessage`, `AgentIdleMessage`, `AgentCompleteMessage`, `AgentDismissedMessage`).

Relay fills these by calling `tabRegistry.getTabForSession(sessionId)` at emit time. If no tab (legacy `cli`/`vscode` session), field is omitted.

### 5.3 Session start/end broadcasts

Add two new server → client events so iOS can react to tab-scoped changes without polling:

```ts
{ type: 'tab.session.started', tabId, sessionId, workingDirName, startedAt }
{ type: 'tab.session.ended',   tabId, sessionId, endedAt }
{ type: 'tab.closed',          tabId }
```

## 6. Hook installation

### 6.1 New templates

Add to `relay/scripts/hook-templates/`:
- `session-start.sh` — reads `MAJOR_TOM_TAB_ID` env, POSTs `{ session_id, cwd }` to `localhost:${MAJOR_TOM_RELAY_PORT}/hooks/session-start` with `X-MT-Tab: $TAB_ID` header.
- `stop.sh` — same shape, POSTs to `/hooks/stop`. (`Stop` is Claude Code's name for session-end.)

Update `relay/src/installer/install-hooks.ts`:
- Add both scripts to `HOOK_FILES[]`.
- Extend the bundled `settings.json` template to include `SessionStart` and `Stop` hook entries alongside `PreToolUse` / `SubagentStart` / `SubagentStop`.

Existing install flow is content-hashed self-heal, so any running relay picks up the new hooks on next startup.

### 6.2 Hook-server endpoints

`relay/src/hooks/hook-server.ts`:

```
POST /hooks/session-start
  → read session_id from payload, tabId from X-MT-Tab header, cwd from payload
  → sessionManager.registerExternal(sessionId, cwd)
  → tabRegistry.registerSessionStart(sessionId, tabId, cwd, userId)
  → emit tab.session.started to all authorized clients
  → emit session.info (so existing iOS handlers work)

POST /hooks/stop
  → read session_id, tabId
  → sessionManager.get(sessionId)?.close()
  → tabRegistry.registerSessionEnd(sessionId)
  → emit tab.session.ended
  → emit session.ended (so existing cleanup paths fire)
  → does NOT remove the tab from the registry — tab persists until PTY closes
```

### 6.3 Correlating hook calls to users

`hook-server` already reads the session cookie from the originating WebSocket context for approval routing. For `SessionStart`, the correlation is: PTY was spawned under an authenticated WebSocket → shell.ts knows the `userId` → stash it in a `Map<tabId, userId>` in shell.ts when the PTY attaches → hook-server looks up by `X-MT-Tab` at SessionStart time.

### 6.4 PTY-close → tab teardown

`PtyAdapter` already holds a PTY across 30-min disconnect grace. Add a callback on final grace-expire → call `tabRegistry.tabClosed(tabId)` → emit `tab.closed` to all subscribers. Any still-running sessions in that tab get `sessionManager.close()`d too.

## 7. iOS changes

### 7.1 `OfficeSceneManager` — rekey to tabId

- `offices: [String: OfficeViewModel]` → still String-keyed, but the key is now `tabId`.
- `createOffice(for tabId: String)` replaces `createOffice(for sessionId:)`.
- Route incoming sprite/agent events to the right Office by looking up `event.tabId` (from the new protocol field). Fall back to `event.sessionId` → reverse-lookup via TabRegistry info cached client-side.
- LRU eviction policy unchanged — still scene-level.

### 7.2 `OfficeViewModel` — session roster

Add `activeSessionIds: Set<String>` to each Office VM. Humans are scoped by `(tabId, sessionId)`, dogs are tab-level only.

- `tab.session.started` → add to `activeSessionIds`, no immediate sprite change (humans spawn when their first `agent.spawn` event lands).
- `tab.session.ended` → remove from `activeSessionIds`, walk humans off with existing dismiss animation, leave dogs in place.

### 7.3 `OfficeManagerView` — lists tabs

- Add `.task { try? await relay.requestTabList() }` on appear — fixes the "sessionList never populated" bug by design.
- Active Offices section: tabs the user has already created an Office for.
- Available Tabs section: tabs with active claude sessions but no Office yet.
- Status badge shows tab status (`active` if any session running, `idle` otherwise).
- Tap unlinked tab → `sceneManager.createOffice(for: tabId)` → push to `OfficeView(tabId:)`.

### 7.4 Banner + notification routing

`SpriteResponseBanner` already carries `sessionId`. Switch to include `tabId` from the event (now on the wire per §5.2). Cross-session banner tap → navigate to `tabId` instead of `sessionId`. Notification deep links update the same way.

### 7.5 Model renames

- `OfficeSceneManager.createOffice(for:)` parameter renames `sessionId` → `tabId`.
- `RelayService.requestSpriteState(for:)` — called less often, but when a tab-office cold-rebuilds, iterate over sessions in that tab and request state for each.

No iOS-level dog/human animation code changes — sprites already fade/walk in and out; the trigger source just moves from "office created/destroyed" to "session started/ended within tab."

## 8. Lifecycle scenarios (reference)

> **Post-PR #155 mental-model flip.** Office Manager lists every terminal tab — not just tabs with an active claude session. Each tab is one card: "No Office — tap to create" (dashed `+`) or an Open-Office card (building icon + agent/session counts). Office creation is 100% user-initiated via card tap. Closing a tab kills the PTY immediately via REST `/shell/:tabId/kill`; the 30-min PTY grace only applies to force-quit / WS-drop recovery. Rename is bidirectional via `TabTitleStore`. Gate D is superseded: iOS reads `TerminalViewModel.tabs` as source of truth, not `TabRegistry`.

| # | Scenario | Expected behavior |
|---|---|---|
| L1 | User opens a new terminal tab, types nothing | Tab card appears in Office Manager as "No Office — tap to create" (dashed `+` icon, no status badge). No Office scene, no TabRegistry entry yet. |
| L2 | User types `claude` in that tab | `SessionStart` hook → TabRegistry records the session → card subtitle updates to "N claude session(s) — tap to create Office". Still no Office scene. |
| L3 | User taps the card (either state) | `createOffice(for: tabId)` → SKScene materializes → `populateIdleSprites()` seeds **all dogs** + active human crew as idle sprites scattered across random `StationLayout` modules. Life Engine takes over (they drift to activity stations). Card flips to Open-Office style (building icon, agent/session counts `0/1`, status badge "idle"). |
| L4 | Subagents spawn inside that tab's claude session | Real agent sprite appears at `OfficeLayout.doorPosition` (airlock), takes over a matching idle slot per role-mapping (clone-not-consume), walks to an assigned desk/station. Agent count on the card increments. |
| L5 | User types `exit` in claude (graceful — claude only, not shell) | `Stop` hook → humans walk off. Dogs stay. Office scene idles. Tab + PTY stay alive. |
| L6 | User re-runs `claude` in the same tab | New `SessionStart` → session registered under same `tabId` → humans fade back in to the same Office. Dogs unchanged. |
| L7 | User types `exit` or Ctrl+D in the shell itself (PTY exits) | Relay closes shell WS with code 1000 + reason `pty-exited` → iOS auto-`closeTab(id:)` → tab disappears → Office scene walks sprites off and tears down → card removed. |
| L8 | User taps close on the terminal tab bar | iOS POSTs `/shell/:tabId/kill` → PTY killed immediately (no 30-min grace) → `tab.closed` broadcasts → Office scene walks sprites off and tears down → card removed. |
| L9 | User force-quits the app mid-session (WS drops) | 30-min PTY grace holds relay-side. On relaunch, cold-launch connects primary `/ws` (PR #155 fix) → `tab.list` rehydrates → cards repopulate. Previously-open Office scenes must be re-tapped (SKScene is per-session iOS state). |
| L10 | User picks "Close Office" from the context menu on an Open-Office card | SKScene destroyed → card flips back to "No Office — tap to create". Tab, PTY, and TabRegistry entry all untouched. |
| L11 | User runs `claude` in two separate tabs simultaneously | Two tab cards, two Offices (once each is tapped). `/btw` and sprite events route by `tabId`. No cross-talk. |
| L12 | User runs a second `claude &` inside the *same* tab (Gate A) | Both sessions register under the same `tabId`. One Office shows humans from both rosters. |
| L13 | Relay restart mid-session | TabRegistry persistence rehydrates on relay boot. iOS re-requests `tab.list` on Office-tab appear → cards come back. Session rehydration drives humans back in. |
| L14 | User runs `claude` from Ground Control (no PTY) | No `MAJOR_TOM_TAB_ID` env → no `SessionStart` registration → falls through to the synthetic-tabId fallback inside `OfficeSceneManager`. Does NOT appear as a terminal-tab card. |
| L15 | User renames tab from the terminal bar | `TabTitleStore` updates → Office Manager card name updates instantly. Single source of truth. |
| L16 | User renames Office from the Office Manager context menu | Same `TabTitleStore` update → terminal tab name updates too. Alert warns "This renames the terminal tab too — they share a name." |

## 9. Gates — resolved

| Gate | Decision | Why |
|---|---|---|
| **A — Multi-claude in one tab** | **Supported (1:N tab:session).** Humans from all concurrent sessions share the tab's Office. | Nested or parallel `claude` is rare but real; rejecting it would require PTY-side enforcement we don't want. Sprites already dedup on `tool_use_id`. |
| **B — Persistence migration** | **Scrap existing sprite-mapping files on upgrade.** One-time cleanup on relay boot. | Still in QA; no production data. Rekey cost is trivial. |
| **C — Cross-device tabId collisions** | **No composite key needed.** Each hook call carries `session_id` (globally unique UUID from claude); TabRegistry indexes sessions → tabs via `sessionId`. Two devices generating the same tabId would register separately per-user because sandboxGuard filters by `userId` at list time. | Collision space on 8-char UUID prefix is 2^32 per user — astronomically unlikely within one user's session history. |
| **D — Track tabs without claude?** | **Superseded by PR #155.** iOS `OfficeManagerView` reads `TerminalViewModel.tabs` as the source of truth, so every terminal tab (claude or not) surfaces as a card. Pure shell tabs still don't register in `TabRegistry` relay-side; the card subtitle simply reads "No Office — tap to create" until a `SessionStart` hook fires and adds a claude session count. | Office is a per-tab iOS decision, not derived from claude lifecycle. |
| **E — Which hook registers the binding?** | **`SessionStart`.** Not PreToolUse (may never fire) or SubagentStart (may never spawn a subagent). | `SessionStart` is guaranteed on every claude boot per Claude Code hook schema (`docs/STREAM-EVENTS.md:253`). |
| **F — New `tab.list` or extend `session.list`?** | **New `tab.list`.** `session.list` stays for legacy sessions. | Cleaner semantics. iOS Office Manager calls `tab.list`; iOS "old SDK sessions" (if any ever reappear) use `session.list`. No type-union gymnastics. |

## 10. Wave breakdown

| Wave | Scope | Branches |
|---|---|---|
| **1 — Research + Spec Freeze** | This doc. Audit complete, design gates closed. | — |
| **2 — Relay Bridge** | `TabRegistry` + persistence. `sessionManager.registerExternal()`. Hook templates (`session-start.sh`, `stop.sh`). Hook-server endpoints (`/hooks/session-start`, `/hooks/stop`). Installer update. PTY-close → `tab.closed` emission. New `tab.list` RPC. Unit tests: registry lifecycle, persistence roundtrip, hook-server dispatch. | `tab-keyed-offices/wave2-relay` |
| **3 — Protocol + iOS wiring** | Add `tabId` to protocol messages (see §5.2). iOS: `RelayService.requestTabList()`, decode `tab.*` events, plumb tabId through sprite/agent event handlers. **No UI rewire yet.** Feature-flag the Office Manager switch. | `tab-keyed-offices/wave3-protocol` |
| **4 — iOS Office Rebind + Explicit Terminal Lifecycle** | `OfficeSceneManager` keyed by tabId. `OfficeManagerView` lists tabs. `OfficeView(tabId:)` route. Banner + notification routing. Remove feature flag. **Also rip out auto-spawn-on-empty in the Terminal tab** — user explicitly creates every terminal (Termius-style). Closing the last tab leaves an empty state screen with a "New Terminal" action; never auto-respawns. Prevents the Office Manager from showing ghost/zombie tabs the user didn't ask for. | `tab-keyed-offices/wave4-ios` |
| **5 — Session Cycling + Edge Cases** | Humans walk-off on `Stop`, walk-in on `SessionStart` within existing tab-Office. L5–L12 scenario tests. Hard-kill PTY path. Multi-claude-in-one-tab smoke test. Persistence migration cleanup. | `tab-keyed-offices/wave5-cycling` |

Each wave ships as a relay PR + iOS PR pair where applicable (matches sprite-agent wiring pattern). Target one Copilot review round per PR; merge at <5 comments.

## 11. Deferred / out of scope

- **Ground Control tab surfacing.** GC-spawned sessions don't have a tab. Could add a synthetic "Ground Control" office in a later phase.
- **Cross-tab agent movement** (e.g. drag-to-transfer). Not planned.
- **Multi-device attach to the same tab.** Orthogonal. `project_ssh_architecture.md` tracks.

> **Formerly deferred, now shipped:** Bidirectional rename from either the terminal bar or the Office Manager via `TabTitleStore` (PR #155).

## 12. Success criteria

- [ ] Every terminal tab appears in Office Manager as a card — "No Office — tap to create" by default, flips to Open-Office on tap.
- [ ] `claude` in a terminal tab → card subtitle updates to "N claude session(s) — tap to create Office" within ~1 s.
- [ ] Tap the card → Office opens, dogs walk in.
- [ ] Subagent spawn → human fades in at a desk.
- [ ] Graceful claude `exit` (claude only) → humans walk off, dogs stay, Office survives.
- [ ] Restart claude in same tab → humans fade back in.
- [ ] `exit` / Ctrl+D in shell → tab auto-closes → Office tears down with walk-off.
- [ ] Tap close on the tab bar → PTY killed via REST `/shell/:tabId/kill` → Office tears down (no 30-min grace).
- [ ] "Close Office" from Office Manager context menu → SKScene destroyed, tab + PTY + TabRegistry intact, card flips to "No Office".
- [ ] Rename from terminal tab bar → Office Manager card updates. Rename from Office Manager → terminal tab title updates.
- [ ] Closing the last terminal tab does NOT auto-spawn a new one — empty state with explicit "New Terminal" action.
- [ ] Cold app launch does NOT auto-spawn — user taps "New Terminal" to start.
- [ ] Cold launch on an already-paired device opens the primary `/ws` automatically (no empty "No Claude Tabs" hang).
- [ ] Relay restart → tab cards rehydrate from persistence; roster re-fires as sessions reconnect.
- [ ] `tab.list.response` surfaces multiple concurrent tabs correctly.
- [ ] Edge-swipe-back only pops to Office Manager from col1; pan-left on col2+ scrolls the camera.
- [ ] No regressions on Sprite Wave 4-6 QA test matrix (resume that QA on top of this).
