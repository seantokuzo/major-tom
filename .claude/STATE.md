# Major Tom — Project State

> Auto-injected at session start via UserPromptSubmit hook. **Keep it short** —
> this loads on every prompt. Full record and phase archive: `docs/STATE.md`.
> Update both after each milestone.

---

## Where we are — 2026-08-01

**Terminal UX + iOS hardening.** Two iOS fixes shipped today, both surfaced by
adversarial review rather than by QA.

**PR #185 (`bc08c5e`) — terminal paste, dead since April.** `terminal.html`'s
paste handler referenced `encoder`, `var`-declared inside `initTerminal()` while
`window.MajorTom` is assembled in the outer IIFE — every paste threw
`ReferenceError`, silently, because `TerminalViewModel` calls
`evaluateJavaScript(js) { _, _ in }` and drops the error (#190). Broke in
`6db7835` (2026-04-10, "reuse existing TextEncoder in paste()" — itself a
review suggestion), **not** in PR #175; both call sites have been dead since.
The first fix then used the wrong mechanism: raw `ws.send` bypasses **bracketed
paste**, so multi-line clipboard content auto-executes in zsh and gives the
`claude` TUI N prompt turns instead of one. Final fix routes through
`term.paste()` (restores `ESC[200~`/`ESC[201~` gated on DEC 2004, plus
`\r\n → \r`) and sets `identifier: .paste` on the Paste `UIAction` so the
pasteboard read skips the iOS 16 consent modal.

**PR #191 (`2054a50`) — LAN preference actually engages (#183).** Root cause was
Bonjour resolve timing: browser pre-warm at `.onAppear`, discovery grace anchored
at browser start (2s nominal, 250ms floor, 4s ceiling), per-resolver watchdog,
`.failed` cancel + teardown, handler identity guards, `os_log` instrumentation.
Review found worse than a timing bug — on `main` the verified-LAN cache was keyed
on a forgeable address string with no invalidation, and this PR is what promoted
that dead branch to the hot path. Cache is now bound to
`(address, pinnedKey, browserGeneration)` behind one gate, `.background`
invalidation is paired with an `.active` re-resolve, and `resolvePreferringLAN`
is single-flight with fail-closed cancellation. **Behavior change Sean approved:**
the Bonjour branch is gone from `PairingViewModel.currentRelayURL`, so first-time
pairing needs the tunnel or Tailscale — an attacker on the LAN could otherwise
serve their own OAuth client-id, take the Google ID token, and get their relay key
pinned. Post-pairing LAN preference is unaffected. Plain-Wi-Fi pairing against a
`start.sh --local` relay is broken until #198.

**Neither PR has run on a physical device.**

**Signing — Sean is on the paid Apple Developer program.** Team `4B8499Z59P`
converted in place; `project.pbxproj` needs no change. The 7-day expiry was a
provisioning-profile TTL, not a cert limit. `docs/APPLE-SIGNING-SETUP.md`
(`a1570ed`). **Device QA is unblocked.**

**Research banked.** `docs/RESEARCH-XTERM-TOUCH-SELECTION.md` (`7ec2cd9`),
verified against `@xterm/xterm@6.0.0` sources — the mandatory prereq for Terminal
UX Wave 2. Recommends splitting it: **2a** = selection ladder on `term.select()` /
`selectLines()` surfaced in the existing edit menu (~half a day, no gesture
conflict); **2b** = touch-drag selection with DOM handles, edge auto-scroll,
Swift-owned mode arbitration.

---

## Next

**Device QA — top outstanding item, runs in parallel with the code task.**

1. **Paste** — multi-line clipboard content must land **inert awaiting Enter**,
   not auto-execute. Both call sites: keybar and long-press menu.
2. **QA item 8 on #191** — background round-trip on the same Wi-Fi, then open a
   new tab. Direct regression test for the foreground re-resolve.
3. PR #175 Wave-1 touch-input QA, still unconfirmed since May.

**Terminal UX Wave 2a — queued next code task, gated on nothing.** Selection
ladder per the research doc, with **#186** (`setCopyMode` picks the wrong line
when scrollback is non-empty — viewport vs absolute row) and **#187**
(`onSelectionChange` stomps the clipboard and ships the whole selection over the
bridge) folded into the same PR; both are prerequisites. Wave 2b after 2a is
on-device.

### Open issues filed 2026-08-01

- **Terminal** — #186 `setCopyMode` row math · #187 `onSelectionChange` clipboard
  stomping · #188 scrollback unreachable by touch · #189 >64 KiB paste silently
  lost · #190 `evaluateJavaScript` errors discarded · #192 keybar paste consent
- **LAN / discovery** — #193 advertiser slot starvation · #194 split timing
  invariant · #195 misplaced helpers · #196 LAN proof survives a foreground
  network change · #198 no non-mDNS LAN pairing fallback
- **Infra gaps** — **#199 missing App Group
  entitlement (widget/watch/Shortcuts data bridge silently dead)** · #200
  `registerForRemoteNotifications` with no `aps-environment`

---

## Standing constraints

- **Review is local** (commit `0ce0308`). The Claude Code GitHub App is
  uninstalled permanently — no `@claude`, no auto-review, no verdict stickies, no
  bot comments. The orchestrating agent spawns read-only specialist subagents
  against the diff; brief is `CLAUDE.md` "Local Code Review". CI (`ci.yml`,
  `release.yml`) still runs and still gates merge.
- **The main agent is an orchestrator.** Research, planning, specs,
  implementation, review, and shipping all go to subagents.
- **iOS CI exists** (PR #202, closed #197) — `Build (iOS)` builds app + widgets + watch on any PR touching `ios/**`, path-gated, ~2 min. `main` requires the `CI Success` check to merge; admins are exempt, so direct docs pushes to `main` still work (#206).
  Never assert a build you didn't watch complete in the tree under review.
- **Never touch the user's real `~/.claude/`** — Major Tom uses
  `$HOME/.major-tom/claude-config/` via `CLAUDE_CONFIG_DIR`.
- **Secrets indirection** — the tunnel URL and Tailscale address live in a
  gitignored `ios/MajorTom/Secrets.swift`. Fresh clones copy
  `Secrets.swift.example`.
- **Two permission dimensions, both preserved** — `manual`/`auto`/`delay`/`god`
  (inner) and `local`/`remote`/`hybrid` routing (outer).
- **The PWA chat layer stays** as the reference implementation for the future
  VSCode chat participant (`docs/FUTURE-PHASE-VSCODE-CHAT-BRIDGE.md`).

## Strategy

- **PWA** (`web/`) — fast path, served by the relay, no Xcode friction.
- **Native iOS** (`ios/`) — premium track: gamified office, Watch, haptics.
  Sideloaded, not App Store.
- Both talk to the same client-agnostic relay.

## History

Phase archive, wave tables, and PR numbers live in `docs/STATE.md`. Per-phase
specs are `docs/PHASE-*.md`; open handoffs are `docs/HANDOFF-*.md`.
