# Phase: Terminal Polish Pass

> Tiny phase — three iOS terminal QoL fixes, one PR. Merges **before** optimization Wave 2 starts so Wave 2 can be pure perf work with clean measurement attribution.

## Scope — three items, nothing else

### 1. `\W` empty on the very first prompt of a new shell/tab

**Symptom**: opening a new terminal tab, the first prompt draws without `\W` (the current-dir basename). The moment the user runs anything (`cd`, `ls`, `pwd`), the next prompt renders correctly and stays correct.

**Already confirmed (2026-04-14 handoff session)**:
- Server-side PS1 is intact — spawning `/bin/bash -l` with the PTY's env variables produces the full PS1 with `\W` visible
- No code on relay or iOS injects into the PTY during attach
- `.bash_profile` line 30 sets PS1, `.bashrc` doesn't touch it

**Remaining hypotheses to investigate** (start here, don't overthink):
- `PtyAdapter.spawnSession()` starts shell with `cwd: opts.cwd ?? HOME`. Maybe the first prompt renders before bash has finished sourcing `.bash_profile`, so PS1 is temporarily the `/etc/bashrc` default (which doesn't contain `\W` in the user's config — `'\h:\W \u\$ '` is only used when `$PS1` is empty).
- iOS client may write a resize-cols byte sequence on attach that triggers bash to redraw the prompt before PS1 fully binds.
- SwiftTerm may be buffering initial output and drawing the first PS1 frame with partial expansion.

**Likely fix shapes** (pick the smallest that works):
- Relay: after `spawnFn(...)`, send a harmless `"\n"` or `"\x0c"` (Ctrl-L = redraw) once the PTY is ready, so bash re-renders the first prompt after PS1 is fully set. Low risk.
- iOS: on attach-success, have `TerminalViewModel` send a single `"\x0c"` to redraw.
- Or: spawn with `['-l', '-i']` explicitly (interactive) — some xterm wrappers need both.

Verify the fix by opening a fresh tab in `~/Documents/code/dev` — `dev` should appear in the first prompt, no user action required.

---

### 2. Auto-retry on terminal connect / reconnect

**Symptom**: backgrounding the iOS app and returning always shows "Terminal Error" with a manual Reconnect button. Manual reconnect succeeds cleanly. Same thing on a brand-new tab sometimes.

**Read**: we're failing too eagerly on the first attempt, or not retrying at all on transient WS failure.

**Requirements**:
- **New tab**: if initial WS connect fails, retry with backoff (e.g., 500ms → 1s → 2s), cap at 3 attempts. Only show "Terminal Error" after all 3 fail.
- **Reconnect after background**: same 3-attempt budget, same backoff.
- **Never retry forever** — cap is non-negotiable. User doesn't want a pinwheel of doom.
- **Keep the manual Reconnect button** — it's the escape hatch when the auto-retry budget is exhausted.

**Touch points**:
- `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` — add retry state to the WS attach flow.

**Protocol note (don't skip)**:
PR #130's `PtyAdapter` has a grace window (`MAJOR_TOM_PTY_GRACE_MS`). A too-fast reattach during that window can collide with the old session's viewer-already-attached guard. Start the first retry at **≥500ms** so we don't race ourselves. The existing `already-attached` rejection returns error code 4001 — treat that as "wait longer and retry," not fatal.

---

### 3. Renameable terminal tabs (native iOS gesture)

**Symptom**: all tabs say "Terminal". User wants to name them per session.

**UX**:
- **Long-press** on a tab → native iOS rename dialog (`.alert` with a `TextField`).
- Confirm saves, Cancel dismisses.
- Default title "Terminal" if unnamed. Don't force a name.
- Haptic `.impact(.medium)` on long-press start, matches existing project pattern.

**Touch points**:
- `ios/MajorTom/Features/Terminal/Views/` — whichever file renders the tab chips
- `ios/MajorTom/Features/Terminal/Models/` (or ViewModel) — add `userTitle: String?` to the tab model
- Persist in UserDefaults alongside existing tab state. Don't send to relay — it's iOS UI metadata only, doesn't belong in the wire protocol.

---

## Branch + workflow

- Branch name: `terminal-polish/three-fixes`
- Three commits (one per item), or one combined commit if they end up small — PR-authoring discretion.
- `xcodebuild` sim build must pass. On-device install for user to spot-check all three.
- Open PR, run the `pr-review-pipeline` skill (Copilot is auto-requested), merge after a clean round (<5 comments).

## Hand off to Optimization Wave 2 after merge

Once this PR is merged to main:

1. `git checkout main && git pull origin main && git branch -d terminal-polish/three-fixes`
2. Start the queued **Optimization Wave 2** per `~/.claude/projects/.../memory/project_optimization_phase.md`:
   - `view.ignoresSiblingOrder = true` + zPosition discipline
   - Cache parallax node refs (kill the `//starsFar`/`//starsNear` recursive `childNode(withName:)` lookups)
   - Verify `.filteringMode = .nearest` on all character textures
   - Frame-budget `applyAgentMoods` / `updateParallax` / `applyTheme` to every 3rd–4th frame
3. Do NOT bundle more polish — Wave 2 is perf only, so we can attribute FPS/energy delta cleanly. If the user reports new bugs, defer to a new polish pass.
4. Wave 1 measurement tooling is already shipped (`docs/PERF-BASELINE.md`, PR #129). Next session will record a proper baseline with FPS + Hitches + Allocations instruments *before* touching Wave 2 code.

## Discipline

- Anything that's not one of the three items above → defer, don't expand scope
- Don't touch SpriteKit / Office / iOS optimization files — that's Wave 2's territory
- Don't touch the relay wire protocol — tab rename is UI-only
