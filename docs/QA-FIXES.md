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

#### 4e. Scrollbar shows inconsistently

**Symptom:** a right-edge scrollbar sometimes appears that can be tap-hold-dragged — user can't figure out when. Nice to have, but reliability is the ask.

**Fix direction:** define when the scrollbar shows — likely: "when buffer > viewport AND touch has been on the terminal surface for >200 ms without a gesture." Auto-hide after ~1s of no touch. Needs a spec decision before implementation — check with user once we get there.

---

## Done

_(items move here with PR link + merge date when closed)_
