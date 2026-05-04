# QA Fixes — Running List

> Issues surfaced during live QA that need fix / investigation. Grouped by priority. Close items with a PR link and date.

---

## P0 — Blocking usability

### 1. Relay-launched `claude` does not inherit user's permission allowlist

**Symptom:** every tool call in a relay-launched `claude` session (Read, Bash, Write, Grep, …) hits PreToolUse → routes to iOS → spawns an "Approval Required" notification. User reports "100 notifications just getting sprites to link."

**Root cause (two layers):**
1. `install-hooks.ts` writes `~/.major-tom/claude-config/settings.json` with only the `hooks` block. User's allowlist in `~/.claude/settings.json` was never imported.
2. Even with the allowlist imported, `pretooluse.sh` in `local` mode **always** returns `{"permissionDecision":"ask"}`. That overrides Claude Code's own allowlist check, so every tool call still enqueues an approval and fires a push.

**Fix:** two-part.
- **Part A (`b63e367`, shipped).** Installer reads `~/.claude/settings.json` read-only and merges `permissions.allow` + `permissions.ask` into the private settings.json. Honors the "never write to ~/.claude/" constraint.
- **Part B (follow-up commit).** New module `relay/src/hooks/permission-matcher.ts` implements Claude Code rule syntax (`ToolName`, `ToolName(*)`, `ToolName(prefix:*)`, `mcp__foo_*`). The `/hooks/pre-tool-use` handler evaluates allow + ask lists before enqueuing — matches on allow short-circuit to `"allow"` (no enqueue, no push). Ask rules still take precedence so `Bash(rm:*)` prompts even if `Bash(*)` is allowed.

**Files involved:**
- `relay/src/installer/install-hooks.ts` — `importUserPermissions()`, `buildSettingsJson()`.
- `relay/src/hooks/permission-matcher.ts` — `evaluatePermission()`, `readPermissionSettings()`.
- `relay/src/hooks/hook-server.ts` — short-circuit inside `/hooks/pre-tool-use`.
- Tests: `relay/src/installer/__tests__/install-hooks.test.ts` (9), `relay/src/hooks/__tests__/permission-matcher.test.ts` (16).

**Verification:** after both parts land, Bash/mcp__* calls in the user's allowlist should pass silently (no notification). `Bash(rm:*)` still prompts. Non-allowlisted tools (Read, Grep, Glob, Agent) still prompt by default — covered separately by upcoming PTY-mode work (item #3).

**Still on fire after Part B:** project-level `.claude/settings.local.json` (cwd-scoped) is not imported. That's where accumulated "allow always" choices live. Track as P1.

---

## P1 — Needs investigation / scoping

### 2. Notification QA matrix (never run)

**What's wired up (audit 2026-04-18):**

| Type | Identifier | Category | Actions | Trigger site |
|---|---|---|---|---|
| Approval request | `approval-<requestId>` | `APPROVAL_REQUEST` | Allow / Deny | `postApprovalNotification` from approval routing |
| Session event — agent spawn | `session-agent.spawn-<uuid>` | `SESSION_EVENT` | (none) | `postAgentSpawnNotification` on subagent-start |
| Session event — agent complete | `session-agent.complete-<uuid>` | `SESSION_EVENT` | (none) | `postAgentCompleteNotification` on subagent-stop |
| Session event — session end | `session-end-<uuid>` | `SESSION_EVENT` | (none) | `postSessionEndNotification` on session close |
| `/btw` response | `btw-<subagentId>-<uuid>` | `SPRITE_BTW_RESPONSE` | Cool Beans | `postBtwResponseNotification`, only when `applicationState != .active` |

**What needs QA (after P0 #1 lands — otherwise the approval flood drowns everything):**

- [ ] **N1 — Approval allow** from lock screen / notification drawer. Tap Allow → tool call proceeds without re-prompting in-app.
- [ ] **N2 — Approval deny** from notification. Tap Deny → claude receives denial, no tool call executes.
- [ ] **N3 — Approval default tap** (no button). Deep link lands in the Approval queue in-app.
- [ ] **N4 — Approval ignored** (notification dismissed without action). Expect timeout or still-pending state in-app; confirm behavior.
- [ ] **N5 — Agent spawn notification** fires when a subagent starts. Title/body copy correct.
- [ ] **N6 — Agent complete notification** fires on subagent stop. Title/body copy correct.
- [ ] **N7 — Session end notification** fires on claude `Stop` hook. Includes cost in body.
- [ ] **N8 — `/btw` response while foreground** — should NOT notify (app is active). Inspector shows response inline instead.
- [ ] **N9 — `/btw` response while backgrounded** — notifies with `[role] spriteName` / truncated body. Cool Beans action present.
- [ ] **N10 — Cool Beans tap** clears the sprite's unread glow in the right Office.
- [ ] **N11 — Default tap on `/btw` notification** deep-links to the originating Office (by tabId when present, else sessionId).
- [ ] **N12 — Per-channel toggles** (Approvals, Session events, `/btw`) in `NotificationSettingsView` actually gate emission.
- [ ] **N13 — Interruption level** — approval uses `.timeSensitive`; verify it breaks through Focus modes as expected.

**Notification settings toggle audit:** confirm `NotificationSettingsViewModel` actually short-circuits each post-call, not just surfaces the toggle in UI.

---

## P1 (cont.)

### 3. PTY permission modes (terminal parity with SDK)

**Symptom:** SDK-launched claude sessions have modes — **god / yolo / smart / delay / strict** — that shape how approvals flow. Terminal-launched claude has none of this today; every approval defaults to routing/mode configured for the SDK path. Started during Phase 13 Wave 2 (inner-dimension modes survived the reboot), never exposed for PTY tabs.

**Fix direction:**
- Expose per-tab mode selector in the terminal UI (same picker surface the SDK uses, or a dedicated one keyed by `tabId`).
- Wire mode into `pretooluse.sh` behavior (today it just routes through `/hooks/pretooluse`). Hook server needs to consult the per-tab mode and apply the same logic as the SDK adapter (auto-allow / delay / strict / etc.).
- Persist per-tab mode in `TabRegistry` or a sidecar so it survives relay restart.
- **NOT a QA fix** — this is a new wave of work. List here so we don't forget.

**Files likely involved:**
- `relay/src/hooks/hook-server.ts` — per-tab mode lookup before routing.
- `relay/src/tabs/tab-registry.ts` — add `approvalMode` field.
- `ios/MajorTom/Features/Terminal/…` — mode picker UI.
- `ios/MajorTom/Core/Services/RelayService.swift` — `tab.setApprovalMode` RPC.

**Shared safety invariant (yolo/god mode):** `trustedCwdPrefixes` — a
config list (default `["/Users/seansimpson/Documents/code/dev"]`) that
gates destructive Bash ops (rm, rm -rf, chmod, mv over existing, dd,
truncate-style redirects, etc.) even when yolo/god is on:

1. Tab's cwd must be under a trusted prefix.
2. Parse Bash command arguments. Any **absolute** path (leading `/`)
   must also be under a trusted prefix. `rm /etc/passwd` from inside a
   repo still prompts.
3. Relative paths — allowed (they resolve inside a trusted cwd, covered
   by #1).
4. Parent traversal (`..`) — conservative: ask. Too easy to escape.
5. Compound commands with `cd`/`pushd`/`exec` that re-root cwd —
   conservative: ask (cwd is no longer trivially knowable).

This invariant belongs inside the permission-matcher, consulted by all
modes. yolo = "wide-open except trusted-cwd guard"; god = "wide-open,
no guard" (double-opt-in); smart/delay/strict = the current fine-grained
rule matching. Requires a minimal Bash-arg parser (shlex equivalent
using `argv-split` or a tiny hand-rolled tokenizer handling quotes,
escapes, `;`/`&&`/`||` separators).

---

### 4. Terminal UI fixes (bundle)

Collection of terminal-render issues surfaced during live iOS use. All `ios/MajorTom/Features/Terminal/…`.

#### 4a. Prompt rendering is inconsistent

**Symptom:** On tab open / reconnect / keyboard toggle, the shell prompt sometimes renders at the top, sometimes jumps halfway down the page, sometimes is hidden above the first visible line of the terminal box. User's hypothesis: terminal box is clipping the first row.

**Fix direction:** audit `TerminalWebView` viewport + xterm.js `fit` addon timing. Likely a race between `resize` events and the keyboard offset. Need a deterministic reflow sequence on: tab activate, keyboard show/hide, specialty-key panel toggle, orientation change.

#### 4b. tmux extra jank

**Symptom:** attaching to a tmux session makes the prompt jank worse. The tmux bottom status bar (green info bar) drifts instead of staying pinned.

**Fix direction:** status bar must always be glued to the bottom edge of the terminal display box. When the keyboard rises, the status bar must ride up with it — it is logically "bottom of terminal" not "bottom of screen." Suspect the keyboard-avoidance layout is only shifting the input surface, not the terminal surface.

#### 4c. Keyboard collapse/expand/panel-swap must keep prompt still

**Symptom:** collapsing the soft keyboard or switching specialty-key panels shifts the visible content. We're different from Termius (whose keyboard can't collapse); we have to handle the collapse case gracefully — prompt line stays locked at whatever row it was on.

**Fix direction:** pin the active prompt row in xterm coordinates across keyboard events. Repaint the viewport around the pinned row, not around the top of the buffer. Likely needs a `TerminalViewModel` state: `pinnedPromptRow` + `restoreScrollAfterLayout()`.

#### 4d. Swipe = line-by-line scroll

**Symptom:** we used to have vertical swipes act like ↑/↓ arrow keys for line-by-line navigation (Termius parity). Confirmed desirable especially in tmux copy-mode. Currently missing or broken.

**Fix direction:** touch gesture on the terminal surface → send `\e[A` / `\e[B` per N pixels of travel. Needs a velocity threshold so fast flicks feel right. Gate by tmux-copy-mode state (already tracked per-tab from Phase 13 Wave 2.7).

#### 4f. Terminal stale on foreground/reconnect until user taps

**Symptom:** app backgrounded → foregrounded, terminal WS reconnects (per the 30-min grace), but the visible buffer stays frozen on the pre-background snapshot. Tapping into the terminal (which dismisses/re-opens the keyboard) triggers a redraw and content catches up.

**Fix direction:** on the iOS side, emit a resize/refresh on every reconnect — either a no-op xterm `fit` addon call, or send the relay a `resize` control frame so tmux (and the PTY) repaint the viewport. Same hook that fires when the keyboard shows/hides should fire on WS reattach.

**Files:** `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` (reattach handler), `ios/MajorTom/Features/Terminal/Resources/terminal.html` (xterm fit / refresh entry point).

#### 4e. Scrollbar shows inconsistently

**Symptom:** a right-edge scrollbar sometimes appears that can be tap-hold-dragged — user can't figure out when. Nice to have, but reliability is the ask.

**Fix direction:** define when the scrollbar shows — likely: "when buffer > viewport AND touch has been on the terminal surface for >200 ms without a gesture." Auto-hide after ~1s of no touch. Needs a spec decision before implementation — check with user once we get there.

---

### 7b. `/exit` orphans subagents — `Stop` hook never fires (FIXED)

**Symptom:** user typed `/exit` in claude (L5). 4 Explore subagents' `SubagentStop` hooks fired cleanly; the 5th (`claude-code-guide`) never did; no session `Stop` hook fired either. 12+ minutes later the sprite is still `working` in the iOS Office and the relay has no record of session end.

Reproducible: happens specifically when a custom subagent type (e.g. `claude-code-guide`) is active at exit time. Standard types (Explore) dismiss cleanly.

**Impact:** sprite stuck visible-but-zombie forever. User loses trust in the Office state. Breaks the L5 lifecycle scenario + Office-survives-session-end semantics in `docs/PHASE-TAB-KEYED-OFFICES.md` §8.

**Fix (shipped):** `relay/src/hooks/orphan-sweep.ts` is a pure helper that finds every subagent still linked to a session in the `agentTracker` singleton and emits synthetic `agent-lifecycle: dismissed` events through the same fanout SDK / worker paths use. Wired into two call sites:

1. **Stop-hook sweep** — `/hooks/stop` calls the sweep after `registerSessionEnd` and before the `session.ended` broadcast. Catches the case where the parent session's Stop fires but a custom subagent's SubagentStop didn't.
2. **PTY-exit sweep** — `onTabClosed` (the PTY-adapter eviction callback in `app.ts`) captures the `tabRegistry.tabClosed(tabId)` return and sweeps every sessionId that was still registered on the tab. Catches the L5 scenario where claude `/exit`-ed without firing Stop at all; closing the tab (REST kill or grace expiry) dismisses the orphans.

**Verify after fix:** retry L5 matrix — spawn custom subagent, `/exit` claude, then close the tab in iOS. Sprites must dismiss with no stuck-`working` state.

**iOS fallback stale-sweep (deferred, not shipped):** any linked sprite with no event in N minutes → gray out + auto-dismiss. Defense in depth if relay-side gaps reappear; track as P2 follow-up if needed.

**Files:**
- `relay/src/hooks/orphan-sweep.ts` — new helper.
- `relay/src/hooks/hook-server.ts` — Stop-hook call site.
- `relay/src/app.ts` — PTY-exit call site.
- `relay/src/hooks/__tests__/orphan-sweep.test.ts` — 4 unit tests.

---

### 10. PTY-launched subagent sprites stuck on "Spawning" status forever

**Symptom (L11 QA, 2026-04-20):** when claude runs inside a terminal tab (PTY path, not SDK/fleet), subagents spawn successfully, the sprite appears, but the status badge permanently shows "SPAWNING". The sprite never transitions to "WORKING" while actually running tools, never to "IDLE" when waiting, and jumps straight to dismissal when SubagentStop fires. The inspector can't show what tool the subagent is running ("Reading file X", "Running bash", etc.).

**Root cause:** The relay's PTY hook path only wires `SubagentStart` → `agent.spawn` and `SubagentStop` → `agent.dismissed`. There is no Claude Code hook for "subagent is now running a tool". The SDK adapter path synthesizes `agent.working` / `agent.idle` from `tool-start` / `tool-complete` stream events; the PTY path has no equivalent producer.

**Fix direction:**
- Wire `PreToolUse` hook payloads (which already flow through `/hooks/pre-tool-use`) to also emit `agent.working` when the tool call is attributed to a subagent. The hook payload's `parent_tool_use_id` / `session_id` should let us identify which live subagent owns the call. The task description becomes the tool name (`Read`, `Bash`, `Grep`, etc.) with optional input summary.
- Consider `PostToolUse` → `agent.idle` symmetric transition. Or at least flip back to `.working` with a blank task until the next tool starts. Short-lived "idle" flips during a multi-tool subagent would look jittery — maybe stay `.working` until SubagentStop.
- Relay changes live in `relay/src/hooks/hook-server.ts` (pre-tool-use branch → also emit agent-lifecycle working) and the subagent attribution logic.

**Priority:** P1 — core sprite storytelling broken for every PTY-launched claude session. Also likely the root cause of QA-FIXES #11 (/btw send).

**Files:**
- `relay/src/hooks/hook-server.ts` — emit agent.working alongside approval enqueue.
- `relay/src/events/agent-tracker.ts` — possibly new `working(agentId, tool)` shape.
- iOS `OfficeViewModel.handleAgentWorking` — already consumes correctly; no change expected.

---

### 11. `/btw` send broken for PTY sprites (layered root cause)

**Symptom (L11 QA, 2026-04-20):** user taps a PTY-subagent sprite in the Office, types a `/btw` message, hits send. Text stays in the input. No relay receipt.

**Layer 1 root cause (FIXED):** ws.ts was broadcasting `sprite.link` / `sprite.unlink` via `broadcastToSession(sessionId, ...)`, which only reaches clients who explicitly called `session.attach`. iOS only attaches SDK sessions it starts; PTY-launched claude sessions (registered via `SessionStart` hook) are never attached. Result: iOS received `agent.spawn` (via `broadcastToAll`) but never the paired `sprite.link`, so `AgentState.spriteHandle` stayed nil and `SpriteInspectorView.sendLinkedDraft()` guard failed silently. Every other `agent.*` event in the same switch already used `broadcastToAll` — sprite.link/unlink were the outliers.

Shipped fix: three sites in `relay/src/routes/ws.ts` (sprite.link on spawn, sprite.unlink on complete, sprite.unlink on dismissed) switched from `broadcastToSession` to `broadcastToAll` to match the existing pattern.

**Layer 2 remaining — `/btw` response is always "(Agent completed before delivery)" for PTY sprites (2026-04-20 QA):**

After Layer 1, user confirmed the draft now clears on send and relay receives the message. BUT every response comes back with `status: "dropped"` / `dropReason: "Agent not found or already completed"` (ws.ts:991–992). Prelim analysis:

The relay's `sprite.message` handler at `ws.ts:976-1010` does a synchronous lookup in `spriteMappings` for the `(subagentId, spriteHandle)` pair. For SDK/worker-backed sessions, when the lookup succeeds, the message routes into `fleetManager.enqueueSpriteMessage` which owns a `BtwQueue` per worker — it buffers the message until the next subagent turn boundary and delivers even if the subagent is mid-work.

For PTY-launched sessions there is:
- ✅ A `spriteMappings` entry (created on `SubagentStart`)
- ❌ No worker (`fleetManager.getWorkerForSession()` returns undefined → enqueue returns `false`)
- ❌ No BtwQueue equivalent

What the user actually hits in the Explore-subagent test case is the FIRST dropped branch, not the second: `mapping` is `undefined` because by the time the user taps → types → hits send, the target Explore subagent has already fired `SubagentStop` → the dismissed-case handler at `ws.ts:2210+` has already removed the mapping from `spriteMappings`. Explore subagents live ~5–20 seconds; the UI round-trip can easily exceed that.

**Why SDK didn't hit this:** the worker's BtwQueue accepted the message WHILE the subagent was alive and drained at turn boundary. Relay-side mapping removal happened AFTER delivery. The PTY path has no buffer → message must arrive before dismissal.

**Fix direction (Layer 2 proper):**
- Build a PTY-mode `BtwQueue` that accepts a `/btw` for any still-live *or recently-live* subagent and attempts injection into the owning PTY at the next turn boundary. Since PTY claude is interactive, injection means writing `"/btw <message>\n"` to the PTY input stream when the prompt is visible.
- OR short-term: widen the grace window by keeping the sprite mapping in `spriteMappings` for N seconds AFTER SubagentStop before the dismissed-case splice. Buys user time to type. Still doesn't actually deliver; relay would respond "dropped (too late)" with a clearer message.
- OR deliver via a different channel — write `/btw` as the next prompt into the parent claude session so it gets handled as context next turn. Loses the subagent-specific routing but at least the message arrives somewhere.

**Instrumentation recommendation for next session:** add a `logger.info({ sessionId, subagentId, spriteHandle, mappingFound })` at the top of the `sprite.message` handler so we can confirm the "mapping missing because dismissed" hypothesis vs an alternative (subagentId/spriteHandle drift between iOS and relay).

**Priority:** Layer 1 P1 (shipped). Layer 2 P1 — /btw is the whole reason the sprite metaphor is interactive; PTY users can't meaningfully use it until Layer 2 lands.

**Files (Layer 2 next):**
- `relay/src/routes/ws.ts:976` — `sprite.message` handler; add instrumentation, branch on session kind (worker vs PTY).
- `relay/src/adapters/pty-adapter.ts` — add a `/btw` injection entry point for PTY sessions.
- `relay/src/sprites/btw-queue.ts` (new?) — PTY-mode queue that survives a short post-SubagentStop grace window.
- Possibly keep the spriteMappings splice on `dismissed` but mark the entry as `draining` for N seconds.

---

### 7. Sprites detach from subagents on backgrounding / reconnect / Office recreate (SHIPPED, PR #157)

**Shipped 2026-04-21 (`main` at `37b82bd`).** iOS added `OfficeSceneManager.refreshAllOpenOffices()` wired into two triggers: WS reattach (`MajorTomApp.onChange(relay.connectionState)`) and `tab.list.response` arrival (`RelayService.handleMessage` → `.tabListResponse`). Relay `sprite.state.request` dropped the per-session `session.attach` gate (it had been rejecting every PTY-session query since iOS never attaches PTY sessions) and gained a `sandboxGuard.canAccess` check that mirrors `session.attach`. Persisted-only sessions skip the sandbox check to match `session.attach` semantics.

Device QA still pending — (a) background + return, (b) close Office + reopen, (c) kill-and-relaunch — retain open until confirmed on device.

**Symptoms — two trigger paths for the same root cause:**

1. **WS reconnect (original symptom):** user backgrounds the app while claude is running subagents. On foreground + reconnect, relay-side subagents still produce events but iOS Office has lost its linked sprites for them. Agents keep working; UI doesn't know.
2. **Office close + recreate (L10 QA, 2026-04-19):** user picks "Close Office" from the context menu → SKScene destroyed. Re-tapping the card creates a fresh SKScene, but the already-spawned subagent sprites do NOT reappear — the scene only renders new spawn/working events going forward, so live subagents that spawned before the recreate become invisible.

**Expected (per Wave 6 spec §S4 / S8):** "Relay disconnects mid-subagent → sprite grays out / shows disconnected indicator. Reconnect → restore from relay state." Extends naturally: any fresh SKScene for a tab with live subagents should hydrate from the relay's current mapping state, not just replay future events.

**Fix direction (covers both triggers):**
- iOS emits `sprite.state.request` whenever an Office's SKScene is newly minted — either fresh creation OR recreation after a Close-Office / reconnect. The existing relay-side broadcast already includes all current bindings.
- `OfficeSceneManager` consumes `sprite.state.response` and re-links sprite slots to reported subagent ids before any walk-on animation.
- On primary WS reattach after background, also trigger the refresh for every tab whose Office is currently open.

**Files:**
- `ios/MajorTom/Core/Services/RelayService.swift` — on reconnect, trigger a sprite-state refresh.
- `ios/MajorTom/Features/Office/ViewModels/OfficeSceneManager.swift` — request + consume `sprite.state.response` on scene-create; re-link.
- `relay/src/sprites/sprite-mapper.ts` — already broadcasts on `sprite.state.request`, verify response includes all current bindings with correct character types.

**Priority:** P1 — this breaks a Wave 6 shipped behavior and the visible state diverges from reality for the user.

---

## P2 — Polish / nice-to-have

### 14. Claude's xterm title escape sequences auto-rename the tab (skip this behavior)

**Symptom (L15 QA, 2026-04-21):** when a tab has no user-supplied name, starting a claude session and giving it a task ends up renaming the tab to a long human-readable summary of what claude is doing (e.g., "claude — audit the relay for stale permission handlers"). This overrides the default "Terminal N" label. Once the user manually renames the tab, their name sticks and the auto-rename stops.

**Root cause:** claude (and many TUI tools) emit OSC 0/2 escape sequences (`\x1b]0;TITLE\x07`) to update the terminal title. xterm.js captures these and exposes them as the tab's `title` property, which iOS reads as `tab.title`. Our `displayTitle` chain is `titleStore.title(for: tab.tabId) ?? tab.title`, so whenever no user-set title exists, claude's title wins.

**Fix direction:** suppress or ignore OSC 0/2 title updates from our PTY stream — either filter them in the iOS xterm.html glue before they update `tab.title`, or keep consuming them for display purposes but stop surfacing them to the Office Manager (use tabId or a generic "Terminal N" label instead when `titleStore.title` is nil).

**Files:**
- `ios/MajorTom/Features/Terminal/Resources/terminal.html` — filter title OSC.
- OR `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` — accept xterm title events but don't propagate to `TerminalTab.title`.

**Priority:** P2 polish — harmless but noisy; manual rename is the escape hatch.

---

### 12. PTY reconnect lands at default cwd instead of the tab's prior cwd

**Symptom (L13 QA, 2026-04-20):** user had claude running in a tab with cwd `/Users/seansimpson/Documents/code/dev/major-tom`. Relay was restarted mid-session. On reconnect, terminal shows old buffer (nice!) but the fresh shell prompt lands at `$HOME` / default cwd, not the tab's previous cwd. User has to `cd` back every reconnect.

**Fix direction:** persist cwd per-tab. TabRegistry already has `workingDir` field — on PTY re-spawn, pass the stored cwd as the shell's starting dir. Safest: capture cwd at hook-time (SessionStart payload already has `cwd`), persist into TabMeta, use it on respawn. Fallback to HOME only when the stored dir is missing / unreadable.

**Files:**
- `relay/src/adapters/pty-adapter.ts` — accept an optional cwd override on spawn.
- `relay/src/tabs/tab-registry.ts` — already has `workingDir`; ensure persistence captures it.
- `relay/src/routes/shell.ts` — pass TabRegistry cwd to `ptyAdapter.attach`.

**Priority:** P2 polish — nice-to-have for workflow continuity, not blocking.

### 13. Sprites hang on post-relay-restart orphan (no cleanup for dead sessions)

**Symptom (L13 QA, 2026-04-20):** after relay restart, tab card reappears in Office Manager. Opening the Office shows the old subagent sprites still sitting on their last-seen `Reading X` / `Running Y` state. Their actual claude session is dead (PTY was a child of the old relay), so no more events will ever arrive. User has to manually close + recreate the Office to clear them.

**Fix direction:** on cold relay boot, the tab's session hash-set is empty (sessions don't survive restart per `tab-registry.ts:47-56`). iOS should detect "tab has sprites but no live sessions" on reconnect and sweep orphans. Alternatively — and cleaner — the relay broadcasts a `sprite.state.response` with an empty mapping set when iOS requests sprite state for a tab whose sessions are all dead; iOS reconciles by dismissing locally-held sprites missing from the response.

Related to QA-FIXES #7 (sprite rehydrate gap on reconnect / Office recreate). Fixing #7 properly should subsume this.

**Priority:** P2 — workaround available, but the stale-sprite UX is confusing.

### 11b. "Performance HUD" settings toggle is mostly decorative

**Resolution (2026-04-20):** the translucent HUD the user was seeing turned out to be the iOS device-level Metal Performance HUD (Settings → Developer → Metal Performance HUD on the phone itself) — which is an OS overlay that no app-level code can suppress. Turning that OFF killed the HUD.

Our in-app "Performance HUD" toggle in Settings → Developer only flips `SKView.showsFPS` / `showsNodeCount` / `showsDrawCount` / `showsQuadCount`, which render as simple text numbers in the bottom-right of the Office scene. Commit `734c22f` added `CAMetalLayer.developerHUDProperties = nil/dict` alongside — no functional effect on the device-level HUD, but harmless and at least toggles cleanly on/off if anyone does enable the app-level Metal HUD.

**Follow-up decision needed:**
- **Option A — remove the toggle.** Nobody really needs SKView text stats outside dev profiling. One less knob in Settings.
- **Option B — rename + repurpose.** Rename to "SpriteKit Stats" and make the footer describe what it actually shows (FPS/nodes/draws/quads text), not Metal HUD.
- **Option C — add a deeplink.** Alongside the in-app toggle, add a "Metal HUD (iOS setting)" row with `UIApplication.openURL` to `Settings → Developer`. Would at least let the user jump straight there.

Priority P2 — not functional breakage, just messy UX / misleading label.

---


### 9. Flip sprite character assignment from role-mapping to randomization (FIXED — 2026-04-22)

**Shipped in PR 2 of Wave D (2026-04-22).** Relay `sprite-mapper.ts` now picks from a flat `CHARACTER_POOL` (14 non-dog crew characters) with dup-avoidance against the session's active roster — the 15th+ concurrent spawn duplicates. iOS `SpriteLinkEvent` + `SpriteStateEvent.SpriteMapping` added `characterType: String?`, and the three OfficeViewModel call sites that used to call `RoleMapper.resolveCharacterType` now consume the relay's value directly. `RoleMapper` kept `color(forCanonicalRole:)` (Wave 5 aura palette still keyed on role) but the role→character map, overflow pool, and session-stable bindings are gone.

Closes QA-FIXES **#6** as superseded — the Kendrick/BowenYang-instead-of-botanist divergence was a consequence of iOS's now-dead local role→character lookup.

Spec update: `docs/PHASE-SPRITE-AGENT-WIRING.md` — §Q2 "Character randomization" replaced the locked role-stable paragraph; the "Role → CharacterType mapping (LOCKED)" table was struck in-line and replaced with the `CHARACTER_POOL` spec.

---

### 8. Office teardown UX — don't strand users on "Office not available"

**Symptom (L7 QA, 2026-04-19):** user exits the shell, tab + Office tear down correctly in the background. User then taps the Office bottom-tab → lands on an "Office not available" empty page (because the last-selected tabId is gone) and has to tap Back to reach the Office Manager.

**User expectation:** either the Office teardown animation plays long enough to see the sprites walk off (~5 s), and when it finishes the view auto-pops to the Office Manager — OR if the animation is running offscreen too quickly to notice, skip the "unavailable" intermediate entirely and land directly on the Office Manager.

**Fix direction:**
- Extend the walk-off animation duration for user-visible teardown (kept short when the Office view is NOT currently foregrounded, to avoid wasted work).
- On detecting a tabId-gone transition while the Office view is foregrounded, NavigationStack pop to the Office Manager root once the animation ends.
- On cold-tap of the Office bottom-tab when the last-viewed tabId no longer exists, navigate directly to Office Manager instead of the empty "Office not available" view.

**Files likely involved:**
- `ios/MajorTom/Features/Office/Views/OfficeManagerView.swift` — NavigationStack path management on tab close.
- `ios/MajorTom/Features/Office/Views/OfficeView.swift` — teardown animation timing + completion callback.
- `ios/MajorTom/Features/Office/ViewModels/OfficeSceneManager.swift` — `tab.closed` handler.

**Priority:** P2 — polish, not blocking. Matches L8 (tap close on tab bar) which triggers the same teardown path.

---


### 4b. Approval notification body is raw JSON

**Symptom:** notification body for a pending approval shows the stringified `tool_input` object (e.g. `{"command":"ls -la","description":"..."}`) — works but ugly.

**Fix direction:** humanize per tool in the push payload builder before batching:
- `Bash` → show just the command
- `Read/Edit/Write/MultiEdit` → show path + 1-line summary
- `Agent` → show subagent type + task description
- `WebFetch/WebSearch` → show URL / query
- Fallback → today's behavior

`ios/MajorTom/Features/Office/Models/ToolHumanizer.swift` already exists on the iOS side for sprite bubbles — likely reusable shape for relay-side notification copy too.

**Files:** `relay/src/push/notification-batcher.ts` or wherever the push body is built.

### 5. Wave 5 role aura not rendering

**Symptom:** during L4 QA, subagent sprites spawned linked but user reports only a "green dot below them and their role above them" — no colored aura glow.

**Expected (per `SpriteAura.swift`):** three concentric SKShapeNode circles, role-colored, fade-in on `.working` state. Hidden when a green unread-`/btw`-response glow overtakes it.

**Likely causes:**
- Sprites aren't transitioning to `.working` state after spawn — they go `linked` and stay there, so `showRoleAura()` never runs.
- Aura zPosition is behind the map tiles / other layers.
- Scene hierarchy adds the aura but never adds to parent at the right time.

**Files:** `AgentSprite.swift` (showRoleAura, state setter), `SpriteAura.swift` (fadeIn/fadeOut), `OfficeSceneManager.swift` (agent-lifecycle → state dispatch).

**Not blocking QA.** Follow-up: instrument state transitions server→client to confirm `.working` flips after spawn.

### 6. Sprite role labels / iOS not honoring relay's characterType (SUPERSEDED BY #9 — 2026-04-22)

The secondary concern (iOS ignoring relay's characterType and picking Kendrick / Bowen Yang instead of the role-locked character) is closed as part of QA-FIXES #9: the relay now randomizes per spawn and iOS trusts `sprite.link.characterType` / `sprite.state.mappings[].characterType` verbatim. The client-side `RoleMapper.resolveCharacterType` and its `overflowPool` that were reassigning characters have been deleted.

The original "role labels use agent-type instead of humanized role" issue — relay already emits `canonicalRole` and iOS already surfaces it through `AgentState.role.capitalized`; no separate fix was needed.

---

### 15. /btw response inspector bubble "more/less" expand is a no-op (device QA 2026-04-29)

**Symptom (Wave A device QA, 2026-04-29):** Sean ran A1 — tapped a PTY subagent sprite mid-tool, sent a /btw, response delivered. The inspector pane truncates the response with a `more` (and after toggle attempt, `less`) toggle. Tapping the toggle does nothing — text stays truncated.

**Important:** the in-scene **speech bubble above the sprite** correctly shows the FULL response on one line — so the response payload IS arriving in full client-side. Only the inspector's collapse/expand affordance is dead.

**Expected:** tapping `more` should expand the inspector text to the full payload; `less` should collapse back.

**Files likely involved:**
- `ios/MajorTom/Features/Office/` inspector view (`SpriteInspectorView.swift` or sibling) — the truncation toggle handler
- Whatever `@State` flag drives the truncated-vs-expanded render

**Priority:** P2 polish — full text is reachable via the in-scene speech bubble; this is the inspector-side affordance being broken.

---

### 22. Sprite identity diverges between Office scene and Inspector panel (device QA 2026-05-03)

**Symptom (mid-D8 device QA, 2026-05-03):** Sean tapped a working sprite that the Office scene was rendering as "Frontend dev". The inspector panel that opened on tap showed a DIFFERENT identity — label "Captain" + Captain's sprite image. Two surfaces, same agent, two different characters.

**Why this matters:** PR #161 (D9) was specifically about making the relay the source of truth for `characterType` and having iOS trust it verbatim. This divergence means one of the surfaces is still computing character locally instead of consuming `AgentState.spriteHandle.characterType` (or the freshly-stored relay value).

**Hypothesis:** the inspector view is still resolving sprite from `canonicalRole` via a leftover code path (RoleMapper had `color(forCanonicalRole:)` kept after #161 — maybe character resolution wasn't fully purged from the inspector). "Captain" being the inspector's pick is a tell — that's a default canonical role, suggesting a fallback chain is running.

**Investigation steps when picked up:**
- `ios/MajorTom/Features/Office/Views/SpriteInspectorView.swift` (or similar) — search for `RoleMapper`, `canonicalRole`, anywhere it derives a sprite/character. Compare with how `OfficeSceneManager` resolves the same agent's character.
- Add a log on tap: print `agent.spriteHandle?.characterType`, `agent.role`, `agent.canonicalRole` — confirm what's reaching the inspector vs the scene.
- Likely fix: route inspector through the SAME `characterType(from:)` resolver the scene uses, NOT through role-derivation.

**Priority:** P1 — visibly contradicts the sprite metaphor, exactly the kind of thing D9 was supposed to fix. Should NOT carry into a follow-up wave; pick up next session.

**Files (suspected):**
- `ios/MajorTom/Features/Office/Views/SpriteInspectorView.swift`
- `ios/MajorTom/Features/Office/ViewModels/OfficeViewModel.swift` (`characterType(from:)`)
- `ios/MajorTom/Features/Office/Models/RoleMapper.swift` (suspect leftover usage)

---

### 21. Connect screen shows too many URLs — auto-pick one based on phone network state (device QA 2026-05-03)

**Symptom (device QA, 2026-05-03):** Sean's iPhone Connect screen displays Tailscale URL + LAN URL + PIN + maybe more, plus the Mac's LAN IP drifts (`192.168.1.210` → `192.168.1.254` between sessions), so the cached LAN URL goes stale and reconnect fails silently. User just wants "local OR tunnel" — one path at a time.

**Quick fix (RECOMMENDED, ~2-4 hr work):** detect phone's network state with `NWPathMonitor`, show **only one URL**:
- Tailscale interface up → Tailscale URL
- Otherwise → LAN URL (numeric, will drift if Mac's DHCP lease changes)
- Both up → prefer Tailscale (stable across networks, immune to LAN IP drift)

**Long-term winner:** mDNS/Bonjour discovery. Relay advertises `major-tom._http._tcp.local`, iOS uses `NWBrowser` to discover it on LAN; Tailscale fallback uses MagicDNS hostname (`seans-macbook-pro.tail-scale.ts.net`) so the URL is never a numeric IP. Set-and-forget — but bigger lift (relay-side advertise + iOS discovery flow + naming).

**Files:**
- `ios/MajorTom/Features/Connection/Views/ConnectionView.swift` — drop the multi-URL display, gate on NWPathMonitor
- `ios/MajorTom/Core/Services/NetworkPathMonitor.swift` (likely new)
- For mDNS path (if pursued): `relay/src/server.ts` (advertise via `dns-sd` or `bonjour-service` npm pkg) + `ios/MajorTom/Core/Services/RelayDiscovery.swift` (NWBrowser)

**Priority:** P2 — daily friction. Quick fix is the right move; mDNS only if we end up distributing.

---

### 20. SpriteKit Stats overlay text is tiny / hidden behind bottom tab bar (device QA 2026-05-02)

**Symptom (Wave D #11b device QA, 2026-05-02):** Sean toggled Settings → Developer → "SpriteKit Stats" ON, opened an Office. The expected SKView built-in text overlay (FPS / nodes / draws / quads in bottom-right corner) is either tiny or rendered BEHIND the bottom tab bar (Terminal / Office / Connect / Analytics / … More). Effectively unusable for spot-checking perf.

**Root cause:** SKView's `showsFPS` / `showsNodeCount` / `showsDrawCount` / `showsQuadCount` render their text in the bottom-right corner of the SKView's bounds. The Office's SKView extends behind the bottom safe area / tab bar, so the auto-positioned text gets occluded.

**Fix directions:**
- **A.** Inset the SKView's bottom edge by tab bar height + safe-area-bottom — sacrifices ~80px of Office viewport but shows stats cleanly.
- **B.** Replace SKView's built-in stats with a SwiftUI overlay (manual `Text` views reading `scene.lastUpdateTime` / `nodes.count` etc. via `OfficeSceneManager` exposing them as `@Observable`). Positioned via `.safeAreaInset(edge: .bottom)`. Cleaner, gives us control over font size + color.
- **C.** Move the SKView's stats to top-right via subclassing — SKView's text positioning isn't directly settable but iOS-level workarounds exist.

**B is recommended** — built-in SKView stats are notoriously unreadable on phone screens (white text on whatever the scene background is, no shadow, fixed font size). Going custom future-proofs us.

**Priority:** P3 — dev tooling not user-facing. Only matters when we want to spot-check perf on device.

**Files:**
- `ios/MajorTom/Features/Office/Views/OfficeView.swift` — SKView container, `.safeAreaInset` wiring
- `ios/MajorTom/Features/Office/ViewModels/OfficeSceneManager.swift` — expose stats counters
- `ios/MajorTom/Features/Office/Views/OfficeScene.swift` — likely where the toggle flips `showsFPS` etc.

---

### 18. Bash PS1 missing `\W`/`\w` expansion on first prompt of fresh tab (device QA 2026-05-01)

**Symptom (mid-Wave-D14 device QA, 2026-05-01):** Sean opens a fresh Terminal tab → bash spawns → first prompt renders WITHOUT the cwd basename (the `\W` part of his PS1). `ls` confirms the shell IS in the right cwd (`~/Documents/code/dev`). Once he `cd`'s to ANY directory (even the same one), the prompt renders correctly with the basename. Bug is purely first-prompt only.

**Why this is surprising:** `relay/src/adapters/pty-adapter.ts:386-388` already explicitly sets `env['PWD'] = spawnCwd` before spawn with a comment saying "Without this, bash inherits whatever PWD the relay process has, and the initial PS1 expansion can fall out of sync with the child's actual working directory until the user runs `cd` or equivalent." So someone already tried to fix this. Either (a) the fix doesn't cover this code path, (b) bash startup files are clobbering PWD before PS1 expands, or (c) the spawn cwd doesn't match what bash reports.

**Fix directions:**
- Verify: does `~/.bash_profile` / `~/.bashrc` reset `PWD` somewhere early? Check by running `bash --noprofile --norc -i -c 'echo PS1: $PS1; pwd; echo PWD: $PWD'` in a fresh tab.
- Bash's PS1 expansion uses the kernel cwd (via `getcwd()`) for `\W`/`\w`, NOT the `$PWD` env var. So setting `env['PWD']` in pty-adapter is a no-op for `\W`. The actual fix: ensure `cwd: spawnCwd` is honored by node-pty (look correct in code: line 394). Maybe the issue is shell-init-time race where bash hasn't fully populated its internal cwd yet on the very first prompt.
- Workaround: emit a no-op `cd .` into the PTY immediately after spawn — would force a prompt re-render with the correct basename.
- Or: revisit how `$PROMPT_COMMAND` interacts with the first prompt.

**Priority:** P3 — purely cosmetic, transient, single-prompt. Annoying but not blocking. Roll into terminal polish if we get back to it.

**Files:** `relay/src/adapters/pty-adapter.ts:382-400` (spawn), maybe needs an emitFirstCd flag or a more aggressive PROMPT_COMMAND nudge.

---

### 19. Feature request — Ground Control: user-settable default cwd for fresh shells (device QA 2026-05-01)

**Ask (Sean, 2026-05-01):** "we need to add a user-set default cwd option in Ground Control so if we distribute, users can set their favorite pwd to start in"

**Context:** today, the cwd a fresh terminal tab spawns into is determined by `pty-adapter.ts` `resolveSpawnCwd` → falls back to `this.cwd` (relay process cwd) when no per-tab override exists. For Sean today that's `~/Documents/code/dev` (apparently — needs verification). For a user who installs Major Tom + Ground Control on a fresh machine, the relay cwd would be wherever Ground Control launched it from — probably random.

**Fix direction:**
- Add a "Default working directory" field to Ground Control's relay config UI.
- Persist into the relay's startup config (env var or config.json).
- `pty-adapter.ts` reads this as the bottom-of-the-cascade fallback in `resolveSpawnCwd`.

**Priority:** P3 — relevant for distribution, not for current dev usage. Track in Ground Control roadmap.

**Files (estimated):**
- `ground-control/` — config UI surface
- `relay/src/server.ts` — accept new env / config var
- `relay/src/adapters/pty-adapter.ts` — `this.cwd` honors the configured default

---

### 17. PTY cwd persistence misses plain-shell `cd` updates (device QA 2026-05-01)

**Symptom (Wave D #12 device QA, 2026-05-01):** Sean had a tab with cwd=`/Users/seansimpson/Documents/code/dev/FAKE_DIR/FAKE_SUB_DIR` (cd'd to in a plain shell, never ran claude there). Relay restarted. On reconnect/respawn, iOS landed on a DIFFERENT tab (`tab-272fa801`, auto-named "H4LA") whose persisted `workingDir` was an old `_old_projects/H4LA` path captured weeks ago. New PTY correctly spawned at the persisted dir — but from the user's POV, they were "kicked out" to a stale, unrelated directory.

**Root cause:** `relay/src/tabs/tab-registry.ts` `registerSessionStart` is the ONLY producer of `workingDir`. Plain-shell `cd` events never update the persisted record. Combined with persisted tabs surviving across many sessions, this means the cwd a user sees on reconnect is the cwd at the time of the LAST `claude` SessionStart in that tab — possibly weeks ago, possibly in an unrelated dir.

**Spec:** the original QA-FIXES #12 fix correctly preserves cwd across relay restart for tabs with claude sessions. This is a separate gap — cwd should track the live shell, not just SessionStart payloads.

**Fix directions (pick one):**
- **A.** Add a heartbeat from PTY → registry that calls `registerCwdUpdate(tabId, cwd)`. Could read from `/proc/PID/cwd` (not available on macOS) OR run a background `pwd` periodically (intrusive). OR have iOS observe shell prompts and POST cwd updates (invasive client coupling).
- **B.** Use OSC 7 (`\x1b]7;file://host/path\x07`) — many shells emit this on `cd` and PROMPT_COMMAND can be configured to. Relay's PTY adapter could parse OSC 7 from the output stream and update registry without touching shell config. iTerm2 / VSCode terminal use this. Cleanest.
- **C.** Skip the fix and add a UI affordance: inspector showing "this tab's cwd is X (last set at TIME)" so the user can sanity-check before reconnecting.

**Priority:** P2 — preserves the canonical fix; surfaces a UX foot-gun. Fix only if it bites someone again.

**Related:** also a candidate for cleanup — old persisted tab files (`tab-443f5546.json`, `tab-cc323c29.json`) accumulate forever. Worth a TTL or "remove if not seen in 30d" sweep.

**Files:**
- `relay/src/adapters/pty-adapter.ts` — OSC 7 parse hook in `onData` if going with B
- `relay/src/tabs/tab-registry.ts` — `registerCwdUpdate` method + persistence
- `relay/src/tabs/tab-persistence.ts` — TTL cleanup for stale tabs (separate fix)

---

### 16. /btw subagent responses are nonsensical / unhelpful (device QA 2026-04-29)

**Symptom (Wave A device QA, 2026-04-29):** Sean's /btw messages to mid-tool PTY subagents (`"hey what are you up to?"` etc.) come back with terse / nonsensical / "jibberish" replies from the subagent itself. The /btw IS reaching the subagent and a reply IS being generated and delivered — the user just isn't getting useful information out of it.

**Hypothesis (Sean's, 2026-04-29):** subagent reply behavior may be context-starved or differs from what we'd get if we routed /btw to the **parent** claude session instead of the active subagent. Parent has full context of "what claude is doing right now" and could answer "what are you up to?" meaningfully; subagent only knows its narrow task.

**Possible directions (not yet investigated):**
- A) Investigate prompt framing inside `pty-btw-queue.ts` — what literal text gets injected into the PTY? If we wrap with extra context, does the reply quality improve?
- B) Add a "send to parent claude" toggle in the /btw input UI — let user pick subagent-scope vs session-scope routing.
- C) Document this as expected and adjust user expectations: /btw at subagent level is a "ping" not a "status request".

**Priority:** P3 — not a delivery bug, response-quality concern. Open an investigation when we get back to /btw polish.

---

## Done

_(items move here with PR link + merge date when closed)_
