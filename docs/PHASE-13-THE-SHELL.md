# Phase 13: "The Shell"

> **Status:** Spec v2 — 2026-04-06 (post-review patch: three independent reviewers audited v1 against context7, SDK source, WebKit bug tracker, and the actual repo state — findings merged below)
> **Branch:** `phase-13/the-shell`
> **Predecessor:** Phase 12 Wave 1 sprite architecture (commit `88a94c0`, local-only WIP)
> **Successor:** Phase 14.alpha "Auto-Clicker" (OAuth refresh via browser automation)

---

## TL;DR

We are throwing away the chat window. Major Tom becomes a **real terminal in your pocket** — a PTY-backed `claude` CLI streamed over WebSocket into xterm.js, with the sprite office and tool-approval UI riding alongside as overlays. Approvals get intercepted via **two parallel paths** (shell hooks for the PTY-spawned `claude`, `canUseTool` for SDK-spawned subagents) and surfaced via **push notifications** that deep-link into a custom approval card. Three modes — `local`, `remote`, `hybrid` — let you pick whether the TUI prompt, the phone card, or both show up for any given request.

This is the pivot. Mission Control as a *chat app* dies in this phase. Mission Control as a *remote shell + ambient office* is born.

---

## Why Pivot

We have spent twelve phases building the world's prettiest fake. The chat window is a lie — `claude` is really a curses TUI with slash commands, file references, status lines, prompts, and a hundred small interactions we have been *guessing at* through a JSON event stream. Every new CLI feature lands and we have to chase it. Every weird state (compaction, login, TUI prompts, multi-line input) is a re-implementation problem.

A real PTY collapses all of that. The CLI is the source of truth. xterm.js renders whatever Anthropic ships, the day they ship it. We build *around* the terminal — approvals, sprites, push, mobile keyboard ergonomics — instead of trying to *replace* it.

Concrete pain we kill:
- "Why doesn't `/login` work from the phone?" — it does in a PTY.
- "Why is the message bubble layout fighting me?" — there are no message bubbles.
- "How do we render the new compaction UI?" — xterm just renders it.
- "Why does mobile feel like a kiosk and not a real machine?" — because it is one. In Phase 13 it isn't.

What we keep: the sprite office, the approval cards, push notifications, the relay's session/auth/persistence layers, the iOS shell. We are not nuking the project — we are nuking the *interaction model* in the middle of it.

---

## North-Star User Flow

> *Daniel sits down at lunch, opens majortom.app on his iPhone. The PWA loads instantly. A black terminal pane fills the screen — bottom of the viewport, ~60% height. Above it: the sprite office, agents milling around. He taps the terminal, the iOS keyboard slides up with a custom keybar above it (Esc, Tab, Ctrl, ↑↓←→). The terminal shows a live `claude` session his desktop left running ten minutes ago. He types: "look at the failing test in cart.spec.ts and fix it." Ten seconds later, his phone buzzes — a push notification: "claude wants to Edit cart.ts (3 changes)". He taps it. The PWA opens to a full-screen approval card with a syntax-highlighted diff. He swipes right to allow. The terminal scrolls in real time as the edit lands. The little code-monkey sprite at desk 3 starts hammering at his keyboard. Daniel locks his phone and goes back to lunch.*

That's the entire phase in one paragraph. Everything below is how we make it real.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  iOS Safari / PWA                                        │
│  ┌────────────────────────────────────────────────────┐  │
│  │  OfficeCanvas (sprite scene — top half)            │  │
│  └────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Shell.svelte                                      │  │
│  │  ┌──────────────────────────────────────────────┐  │  │
│  │  │  xterm.js (canvas/webgl)                     │  │  │
│  │  │  $ claude                                    │  │  │
│  │  │  Welcome to Claude Code...                   │  │  │
│  │  │  > look at the failing test...               │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  │  [ Esc ][ Tab ][ Ctrl ][ ↑ ][ ↓ ][ ← ][ → ][ ⌨ ] │  │
│  └────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────┐  │
│  │  ApprovalCard (overlay, when active)               │  │
│  └────────────────────────────────────────────────────┘  │
└────────────┬─────────────────────────────────────────────┘
             │ WSS (binary frames + JSON control)
             │ Path: /shell/:tabId
             ▼
┌──────────────────────────────────────────────────────────┐
│  Relay (Fastify + ws + fastify-plugin)                   │
│                                                          │
│  ┌────────────────┐    ┌──────────────────────────────┐  │
│  │ pty-adapter.ts │───►│ tmux -L major-tom            │  │
│  │ (node-pty)     │    │   session: major-tom         │  │
│  │                │    │   pane: claude (PTY)         │  │
│  └────────────────┘    └──────────────────────────────┘  │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ Approval pipeline                                   │ │
│  │  ┌──────────────┐   ┌──────────────┐                │ │
│  │  │ Shell hook   │   │ canUseTool   │                │ │
│  │  │ (file-based) │   │ (SDK inline) │                │ │
│  │  └──────┬───────┘   └──────┬───────┘                │ │
│  │         └────────┬─────────┘                        │ │
│  │                  ▼                                  │ │
│  │           ApprovalQueue                             │ │
│  │                  │                                  │ │
│  │       ┌──────────┼──────────┐                       │ │
│  │       ▼          ▼          ▼                       │ │
│  │  Push fire   WS broadcast   tmux send-keys (hybrid) │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Key insight: two intercept paths must coexist

`canUseTool` only fires for sessions that the SDK *itself* spawns. If `claude` is running inside our PTY (which is the entire point of this phase), we cannot intercept *its* tool calls with `canUseTool` — that path is for SDK-managed subagents.

So we run **both**:

| Path | Triggered by | Implementation | Used for |
|------|--------------|----------------|----------|
| **Shell hook** | The `claude` process running inside our PTY | File-based `PreToolUse` hook in a **Major-Tom-owned** `$CLAUDE_CONFIG_DIR/settings.json`, calling the relay's existing loopback hook endpoint | Top-level user-driven CLI sessions |
| **`canUseTool`** | SDK-spawned sessions (e.g., programmatic Task tool flows, SDK-managed subagents in the relay adapter) | Inline JS callback in `claude-cli.adapter.ts` | SDK sessions regardless of mode |

Both paths funnel into the **same** `ApprovalQueue`. Both fire push notifications. Both render the same `ApprovalCard` UI. **Dedup is keyed on `tool_use_id`** (which both paths get from the SDK) — if both ever fire for the same call (e.g., a Task tool subagent on its way up), the second one is coalesced.

> 🧩 **Existing infrastructure:** the relay already has a `PreToolUse` HTTP hook endpoint at `relay/src/hooks/hook-server.ts` that returns the correctly-wrapped `hookSpecificOutput` envelope, AND an `ApprovalQueue` at `relay/src/hooks/approval-queue.ts` with `waitForDecision()` and manual/auto/delay modes. Wave 2 is mostly **wiring** — extending the existing endpoint with mode awareness, threading `tool_use_id` for dedup, and firing push notifications. It is NOT "build a new hook server from scratch."

> ⚠️ **Use `CLAUDE_CONFIG_DIR`, do not patch the user's global `~/.claude/settings.json`.** The env var exists ([docs](https://code.claude.com/docs/en/env-vars)) and lets us point `claude` at a Major-Tom-private config dir (e.g. `$HOME/.major-tom/claude-config`). The PTY adapter sets `CLAUDE_CONFIG_DIR` when spawning `claude`, and we ship our hook entry in *our* settings file, leaving the user's untouched. Idempotent, non-invasive, zero conflict with other tools.

---

## The Three Approval Modes

This is the part the user explicitly asked for. Driven by env var (and mode-toggle UI):

```bash
MAJOR_TOM_APPROVAL=local    # TUI prompts in terminal (default)
MAJOR_TOM_APPROVAL=remote   # Phone-only, terminal blocks
MAJOR_TOM_APPROVAL=hybrid   # Both compete, first decision wins
```

### Mode 1: `local`

The classic CLI experience. The hook returns `{ "permissionDecision": "ask" }` immediately. Claude shows its native TUI prompt inline:

```
╭───────────────────────────────────────────╮
│ Edit cart.ts                              │
│   3 changes                               │
│ [a]llow once  [A]lways  [d]eny  [esc]     │
╰───────────────────────────────────────────╯
```

You answer with the keyboard. The phone gets a **passive notification** ("claude is asking to edit cart.ts on your Mac") with no action buttons — purely informational. Tapping the notification opens the PWA but does *not* try to drive a decision.

**Use case:** You are at your desk, the phone is just an observer.

### Mode 2: `remote`

The hook **blocks** waiting for the phone. The `claude` TUI shows a stub line — `⏳ Waiting for approval (phone)` — and accepts no input until the phone responds. The relay fires a high-priority push notification with the full request payload deep-linked to `/approvals/:id`. The user taps, the PWA opens to a full-screen approval card, swipes right, and the relay HTTP endpoint resolves the hook with the decision. Terminal unblocks and continues.

**Use case:** You are away from the keyboard. You want every decision to come through your phone, full stop.

### Mode 3: `hybrid`

Both. The hook returns `"ask"` (so the TUI prompt appears) **and** fires the push notification. Whichever wins, wins:

- **TUI wins** — you tap `a` on the keyboard, `claude` proceeds. The relay needs no further action; the hook already returned.
- **Phone wins** — you swipe right on the phone. The relay calls `tmux send-keys -t major-tom 'a\r'` to inject the keystroke into the PTY *as if you typed it*. The TUI prompt resolves, `claude` proceeds.

The race is resolved by tmux send-keys, which is the magic glue. We do not need to coordinate state — the TUI is the source of truth, both inputs flow through it.

**Use case:** You want flexibility. Sometimes the laptop is open, sometimes it isn't, you do not want to switch modes constantly.

### Notification semantics across modes

| Mode | Push fires? | Push has action buttons? | Tap behavior |
|------|-------------|--------------------------|--------------|
| `local` | ✅ | ❌ (passive only) | Open PWA, surface in-app approval card as overlay |
| `remote` | ✅ | ✅ on Android PWA; ❌ on iOS PWA (see reality check) | Open PWA, SW posts `show-approval` message, card opens as full-screen overlay |
| `hybrid` | ✅ | same as `remote` | Same as `remote`, with relay injecting `tmux send-keys` to the PTY on decision |

The push pipeline is identical across modes — the relay fires one notification, the client decides what to render. Rendering uses one component (`ApprovalOverlay.svelte`) fed by approval ID from SW postMessage — **not** path-based routing.

> ⚠️ **iOS PWA reality check (verified 2026-04-06):**
>
> 1. **Action buttons are silently ignored on iOS Safari PWA.** Verified Apple Dev Forums #726793 (2024–2025), WebKit explainer, MDN. Only the default "View" action displays; custom `actions` array is dropped.
> 2. **Declarative Web Push (Safari 18.4+) does NOT support action buttons either.** The WebKit blog (Apr 2025) confirms the shipped schema is `{web_push: 8030, notification: {title, body, navigate, lang, dir, silent, app_badge}}`. The explainer lists `actions[]` but **Apple has not shipped that part** as of Safari 18.5. Treat declarative push as a Phase 14+ optimization that we do not depend on.
> 3. **`notificationclick` → URL deep-link is broken on cold-killed iOS PWA.** [WebKit bug 268797](https://bugs.webkit.org/show_bug.cgi?id=268797) (still NEW as of July 2025): tapping a notification on a killed PWA opens the manifest's `start_url`, NOT the requested URL. `client.navigate()` and `clients.openWindow(url)` both fail the requested destination.
> 4. **In EU territories, Apple disabled PWA home-screen install under DMA compliance.** iOS 17.4+ EU users cannot install the PWA at all. This is a known strategic limitation of a PWA-first delivery. Mitigation: fall back to Safari-in-tab for approval handling (no push, WS only) until the native app ships.
>
> **Our workaround (replaces all router-based deep-linking):**
>
> - The PWA has **no router** — `App.svelte` uses `activeTab` state with conditional rendering. We do NOT add one.
> - Every approval notification sets `notification.data = { requestId, navigate: '/approvals/...' }` purely as a hint.
> - `sw.js` (at `/web/public/sw.js`, already exists) handles `notificationclick`: `clients.matchAll({type:'window', includeUncontrolled:true})` → focus existing or `openWindow('/')` → `postMessage({type:'show-approval', requestId})`.
> - App.svelte listens via `navigator.serviceWorker.onmessage` (the pattern already exists in App.svelte:55 for push subscription resend), sets `activeApproval = requestId`, and `ApprovalOverlay.svelte` renders as a full-screen modal over the current tab.
> - **Cold-start fallback:** on every app boot, the PWA calls `GET /api/approvals/pending` and if any exist, shows the freshest as an overlay. This works even if the OS drops the SW postMessage during cold start.
> - Android PWA gets real action buttons via standard Web Push → `event.action` handler in `sw.js` posts the decision directly to `/api/approvals/:id/decision` without opening the PWA.
> - Native iOS app (Phase 14+) gets real APNs action buttons when that phase ships.

---

## PTY / xterm / tmux Foundation

### Why tmux?

Because we want **persistence across WebSocket reconnects**. If you walk into a tunnel and your WS drops, you do not want `claude` to die. Tmux sits between the relay and the PTY:

```
relay (WS handler) ──node-pty──► tmux attach-session ──► detached tmux server ──► claude
```

The tmux server boots once at relay startup, holds the `claude` session forever, and survives WS reconnects, relay restarts (with `tmux -L major-tom` it can even survive that), and lunch breaks. Each WS connection just `attach`es. Multiple devices can attach to the same session simultaneously — desktop browser + phone watching the same terminal.

### Multi-tab

Tmux gives us free multi-tab via windows: `tmux new-window -t major-tom` per tab in the PWA. The "New Tab" button in the shell panel just sends a control message; the relay creates a new tmux window and pipes its output back over a fresh WS subprotocol. We get terminal multiplexing with zero custom code.

### Binary mode

`node-pty` in binary mode (`encoding: null`, `handleFlowControl: true`) plus binary WebSocket frames. Anything else loses bytes on multibyte UTF-8 boundaries (this bites everyone who tries text mode for terminals — verified in node-pty docs, xterm.js issues).

> ⚠️ **TypeScript gotcha:** `node-pty`'s `onData` is typed as `IEvent<string>` regardless of `encoding`. At runtime with `encoding: null` it emits `Buffer`. You need a cast or a local handler type. See [microsoft/node-pty#489](https://github.com/microsoft/node-pty/issues/489).

> ⚠️ **Bootstrap ordering:** the shell route handler MUST await the tmux bootstrap promise before calling `pty.spawn('tmux', [..., 'attach-session', ...])`. If the WS connects before bootstrap finishes, `attach-session` exits 1 and the user gets a dead PTY. Use `attach-session -d` to detach any other attached clients cleanly.

> ⚠️ **Write-after-kill guard:** wrap `ptyProcess.write()` calls in a `disposed` check. On macOS, writing to a killed PTY is a silent no-op that sometimes crashes. Track `disposed` in the adapter closure.

```ts
import * as pty from 'node-pty';
import type { IPty } from 'node-pty';

type PtyDataHandler = (data: string | Buffer) => void;

await tmuxBootstrapPromise;  // wait for detached server to be up

const ptyProcess: IPty = pty.spawn('tmux', ['-L', 'major-tom', 'attach-session', '-d', '-t', 'major-tom'], {
  name: 'xterm-256color',
  cols: 80,
  rows: 24,
  cwd: process.env.HOME,
  env: {
    ...process.env,
    LANG: 'en_US.UTF-8',
    TERM: 'xterm-256color',
    COLORTERM: 'truecolor',
    MAJOR_TOM_TAB_ID: tabId,  // our own correlation key — hook scripts read this
  },
  encoding: null as unknown as undefined,  // binary mode (types lie, see #489)
  handleFlowControl: true,
});

let disposed = false;

// Cast required because types say string, runtime gives Buffer
(ptyProcess.onData as unknown as (cb: PtyDataHandler) => void)((data) => {
  if (disposed) return;
  socket.send(data as Buffer, { binary: true });
});

ptyProcess.onExit(() => {
  disposed = true;
  socket.send(JSON.stringify({ type: 'exit' }));
  socket.close();
});

socket.on('message', (msg: Buffer, isBinary: boolean) => {
  if (disposed) return;
  if (isBinary) {
    ptyProcess.write(msg.toString('binary') as unknown as string);
  } else {
    // JSON control message: { type: 'resize', cols, rows } | { type: 'exit' }
    const ctrl = JSON.parse(msg.toString());
    if (ctrl.type === 'resize') ptyProcess.resize(ctrl.cols, ctrl.rows);
  }
});

socket.on('close', () => {
  disposed = true;
  ptyProcess.kill();
});
```

### xterm.js v6

Pinned package versions (confirmed current 2026-04-06 via `npm view`):

- `@xterm/xterm@^6.0.0`
- `@xterm/addon-fit@^0.11.0`
- `@xterm/addon-webgl@^0.19.0`
- `@xterm/addon-web-links@^0.12.0`

The legacy `xterm-*` packages are **deprecated** — do not install them by accident. `npm view xterm deprecated` explicitly says "Move to @xterm/xterm instead."

> ⚠️ **iOS WebGL context loss:** iOS Safari aggressively drops WebGL contexts when the PWA backgrounds (lock screen, tab switch, low-power mode). Without handling this, the terminal silently goes black after the user locks the phone. Wire `webglAddon.onContextLoss(() => webglAddon.dispose())` and fall back to the canvas renderer. On iPhone form factor, we may want to skip WebGL entirely — measure in Wave 1.

```ts
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebglAddon } from '@xterm/addon-webgl';
import { WebLinksAddon } from '@xterm/addon-web-links';
import '@xterm/xterm/css/xterm.css';

const term = new Terminal({
  fontFamily: 'Berkeley Mono, ui-monospace, Menlo, monospace',
  fontSize: 14,
  cursorBlink: true,
  allowProposedApi: true,  // required by some addons; silences the console.warn
  theme: { background: '#0a0a0a', foreground: '#e8e8e8' },
});

const fit = new FitAddon();
term.loadAddon(fit);
term.loadAddon(new WebLinksAddon());

// Skip WebGL on iOS — context loss bug
const isIOS = /iP(hone|od|ad)/.test(navigator.userAgent);
if (!isIOS) {
  const webgl = new WebglAddon();
  webgl.onContextLoss(() => webgl.dispose());
  term.loadAddon(webgl);
}

term.open(containerEl);
fit.fit();

ws.binaryType = 'arraybuffer';
ws.onmessage = (ev) => {
  if (ev.data instanceof ArrayBuffer) {
    term.write(new Uint8Array(ev.data));
  } else {
    // Text frame = control message (e.g. { type: 'exit' }, resize ACK)
    const ctrl = JSON.parse(ev.data);
    if (ctrl.type === 'exit') term.write('\r\n[session ended]\r\n');
  }
};

// term.onData handles ALL input — keyboard, paste, AND keybar injections via term.input()
term.onData((data) => ws.send(data));
term.onResize(({ cols, rows }) => ws.send(JSON.stringify({ type: 'resize', cols, rows })));
```

### Mobile keybar

iOS soft keyboard does not give us Esc, Ctrl, Tab, or arrow keys. We render a custom strip above the keyboard with sticky modifiers (Ctrl, Alt) and one-shot keys (Esc, Tab, ↑↓←→). The strip is a Svelte component that injects escape sequences via `term.input(data, true)` — this fires `onData` which our existing WS plumbing already handles. **Single code path, no raw-byte bypass.**

> ⚠️ **`visualViewport` gotchas:** the `visualViewport.resize` event fires on keyboard show/hide AND on rotation AND on Safari address-bar collapse AND on focus changes. Listen to both `resize` and `scroll` events, debounce, and derive keyboard visibility from `window.innerHeight - visualViewport.height > 100`.

Layout: left-to-right slim row, ~36px tall, fixed-position above the iOS keyboard (using `visualViewport.height` to detect the keyboard). Buttons:

```
[Esc] [Tab] [Ctrl] [Alt] [↑] [↓] [←] [→] [|] [~] [/] [⌨ hide]
```

Sticky modifiers: tap `Ctrl`, it stays armed until the next key is pressed; that key gets the modifier prefix (e.g., `Ctrl+C` → `\x03`). Visual: armed modifier glows. Long-press a sticky modifier to lock it.

### Fastify plugin glue

`@fastify/websocket` defaults to a 1 MiB `maxPayload` (confirmed in the relay at `relay/src/plugins/websocket.ts:14`: `maxPayload: 1_048_576`). A large PTY buffer flush (tmux full redraw on attach, `cat` on a big file, `vimdiff`) can exceed this. Bump to 8 MiB:

```ts
// relay/src/plugins/websocket.ts — edit the existing registration
await app.register(fastifyWebsocket, {
  options: { maxPayload: 8 * 1024 * 1024 },
});
```

> ⚠️ **Edit the plugin file, NOT `relay/src/server.ts`.** `server.ts` is just the lifecycle wrapper. Routes are registered in `relay/src/app.ts`, and the WebSocket plugin lives at `relay/src/plugins/websocket.ts`.

```ts
// relay/src/app.ts — add the shell route next to existing ones
app.register(async (shellApp) => {
  shellApp.get('/shell/:tabId', { websocket: true }, shellRouteHandler);
});
```

### Host requirements

Document these in the relay README and enforce at runtime in `tmux-bootstrap.ts`:

- **tmux ≥ 3.2** — earlier versions have different `send-keys` semantics for `-X` and the `new-session -A` auto-attach flag behaves differently. Runtime check via `tmux -V`, fail loud if missing or stale.
- **Node.js ≥ 22** — already enforced in `relay/package.json` engines field.
- **Native build toolchain** — `node-pty` is a native Node addon. macOS dev needs Xcode CLI tools; Linux dev needs `python3`, `make`, `g++`. CI/CD images must include these. Document in README.
- **`ws` peer dep** — `@fastify/websocket@11.2.0` peer-depends on `ws@^8.16.0`. The relay currently pins `ws@8.19.0` exact. When adding shell route, verify `npm` doesn't resolve a second copy of `ws` — if it does, bump the explicit pin to a caret range.

---

## Wave Plan

Three waves. Each wave is a single coherent PR. No waves run in parallel.

### Wave 1: PTY Foundation

> **Goal:** Real terminal end-to-end. No approval routing yet. Push notifications and sprites untouched. The success criterion is: open the PWA on phone, tap the terminal, run `ls` and `claude`, see real output, type into a real session, reconnect WS without losing state.

**New files (relay):**

| File | Purpose |
|------|---------|
| `relay/src/adapters/pty-adapter.ts` | New adapter implementing `IAdapter` (or sidecar to it). Spawns tmux attach, pipes binary frames, handles resize/exit. |
| `relay/src/adapters/tmux-bootstrap.ts` | Boot tmux server at relay startup (`tmux -L major-tom new-session -A -d -s major-tom`), verify it is alive, expose `getOrCreateWindow(tabId)` helper. |
| `relay/src/routes/shell.ts` | Fastify WS route handler at `/shell/:tabId`. Auth via existing session cookie. |
| `relay/src/utils/tmux-cli.ts` | Thin shell-out wrapper for `tmux` commands (`new-window`, `kill-window`, `send-keys`, `list-windows`). |

**Modified files (relay):**

| File | Change |
|------|--------|
| `relay/src/app.ts` | Register `shell` route. Call `tmuxBootstrap()` on startup (or during route registration, awaited). |
| `relay/src/plugins/websocket.ts` | Bump `maxPayload` from `1_048_576` to `8 * 1024 * 1024`. Single-line change. |
| `relay/src/sessions/session-manager.ts` | Add `tabs: Map<string, TabHandle>` to session record. A tab = a tmux window. |
| `relay/package.json` | Add `node-pty@^1.1.0`. |

> ⚠️ Do NOT edit `relay/src/server.ts` — it's the lifecycle wrapper that imports and runs `app.ts`. Route and plugin changes live in `app.ts` and `plugins/websocket.ts` respectively.

**New files (web):**

| File | Purpose |
|------|---------|
| `web/src/lib/components/Shell.svelte` | Container for xterm + keybar + tab strip. |
| `web/src/lib/components/XtermPane.svelte` | Pure xterm.js renderer + WS plumbing. |
| `web/src/lib/components/MobileKeybar.svelte` | The custom key strip with sticky modifiers. |
| `web/src/lib/components/ShellTabs.svelte` | New-tab / close-tab / switch-tab UI. |
| `web/src/lib/stores/shell.svelte.ts` | Per-tab WS connections, focus tracking, reconnect logic. |

**Modified files (web):**

| File | Change |
|------|--------|
| `web/src/App.svelte` | Replace `ChatView` with `Shell` in the main pane. ChatView import removed. |
| `web/package.json` | Add `@xterm/xterm@^6.0.0`, `@xterm/addon-fit@^0.11.0`, `@xterm/addon-webgl@^0.19.0`, `@xterm/addon-web-links@^0.12.0`. |
| `web/src/app.css` | Import `@xterm/xterm/css/xterm.css` (may require Vite `optimizeDeps.include` entry — test first). |

**Demolition (web):** *Do not delete yet — Wave 1 ships with both old chat and new shell coexisting behind a feature flag (`localStorage.majorTom.shell = '1'`) so we can A/B test. Demolition happens at the end of Wave 3.*

**Wave 1 success criteria:**

- [ ] `tmux -V` runtime check passes (version ≥ 3.2); fails loud if missing
- [ ] tmux server boots with the relay; `tmux -L major-tom list-sessions` shows it
- [ ] Open PWA in browser, terminal pane appears, can run `ls`, `pwd`, `cat README.md`, `htop`, `less`, `vim`
- [ ] Can run `claude` and have a real session — slash commands work, file refs work, compaction works
- [ ] Resize the browser window → terminal cols/rows update via `onResize`
- [ ] Mobile: tap terminal, custom keybar appears with Esc/Ctrl/arrows; sticky modifiers work; `term.input()` fires `onData`
- [ ] Kill the relay's WS connection (network blip), reconnect → terminal state survives, `claude` session intact
- [ ] Two tabs work, can switch between them, output isolated
- [ ] Two devices attached to the same session see synchronized output; primary/secondary input designation works
- [ ] Relay survives a forced `pkill -9 tmux` in another terminal (bootstrap re-runs idempotently on next WS connect)
- [ ] iOS PWA backgrounded and restored → terminal still renders (WebGL context loss handled or canvas fallback active)
- [ ] Binary frames and JSON control frames coexist cleanly (vim + resize both work)
- [ ] `pty.write` after `ptyProcess.kill()` does not crash or leak

---

### Wave 2: Approval Routing + Three Modes

> **Goal:** Tool approvals work end-to-end through both intercept paths, all three modes function, push notifications fire correctly, the `/approvals/:id` deep-link works on PWA + native.

This wave is the meat. The PTY foundation from Wave 1 just streams bytes — Wave 2 makes the ambient approval pipeline come alive.

#### 2a. Shell hook installer

We ship a small shell script into a **Major-Tom-owned** config directory and set `CLAUDE_CONFIG_DIR=$HOME/.major-tom/claude-config` when the relay spawns `claude` inside the PTY. This leaves the user's real `~/.claude/settings.json` untouched. The installer creates:

```
$HOME/.major-tom/claude-config/
├── settings.json                   (Major-Tom's private settings)
└── hooks/
    ├── pretooluse.sh               (PreToolUse intercept — approval routing)
    └── subagent-start.sh           (SubagentStart intercept — sprite spawn event)
```

The script:

1. Reads the JSON tool-call payload from stdin — includes `tool_name`, `tool_input`, `tool_use_id`, `session_id`, `cwd`, `permission_mode`
2. POSTs it to the relay's existing hook endpoint with mode + tab correlation
3. Emits a **correctly-wrapped `hookSpecificOutput` envelope** on stdout (the wrapping is non-negotiable; see `sdk.d.ts:1378-1384`)

> ⚠️ **The envelope shape is `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}`, NOT `{"permissionDecision":"ask"}`.** The spec's v1 draft got this wrong and would have silently no-op'd. The relay's existing `relay/src/hooks/hook-server.ts:82-87` already emits the correct envelope — reuse that logic.

```bash
#!/usr/bin/env bash
# $HOME/.major-tom/claude-config/hooks/pretooluse.sh
set -euo pipefail

PAYLOAD=$(cat)
MODE=${MAJOR_TOM_APPROVAL:-local}
TAB_ID=${MAJOR_TOM_TAB_ID:-unknown}
RELAY_URL="http://127.0.0.1:${MAJOR_TOM_RELAY_PORT:-8080}/internal/approvals"

# Extract tool_use_id from payload for dedup key (both intercept paths use this)
TOOL_USE_ID=$(printf '%s' "$PAYLOAD" | jq -r '.tool_use_id // empty')

case "$MODE" in
  local)
    # Fire-and-forget notification for phone observer; never block the TUI
    curl -fsS --max-time 1 -X POST "$RELAY_URL" \
      -H "Content-Type: application/json" \
      -H "X-MT-Mode: local" \
      -H "X-MT-Tab: $TAB_ID" \
      -d "$PAYLOAD" >/dev/null 2>&1 &
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}'
    ;;
  remote)
    # Block waiting for phone decision. --max-time matches approval-queue TTL.
    DECISION_JSON=$(curl -fsS --max-time 600 -X POST "$RELAY_URL" \
      -H "Content-Type: application/json" \
      -H "X-MT-Mode: remote" \
      -H "X-MT-Tab: $TAB_ID" \
      -d "$PAYLOAD")
    # The relay returns the full envelope; pass through
    echo "$DECISION_JSON"
    ;;
  hybrid)
    # Fire-and-forget + ask the TUI. tmux send-keys wins if phone decides first.
    curl -fsS --max-time 1 -X POST "$RELAY_URL" \
      -H "Content-Type: application/json" \
      -H "X-MT-Mode: hybrid" \
      -H "X-MT-Tab: $TAB_ID" \
      -d "$PAYLOAD" >/dev/null 2>&1 &
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}'
    ;;
esac
```

The installer (`relay/scripts/install-hooks.ts`) is idempotent:
- Creates `$HOME/.major-tom/claude-config/` if missing
- Writes `settings.json` with a `hooks.PreToolUse[]` entry pointing at `hooks/pretooluse.sh`
- Writes the hook scripts with hash-based versioning (relay re-installs on startup if hash differs)
- Makes scripts executable (`chmod +x`)
- Does **not** touch the user's real `~/.claude/settings.json`

> ⚠️ **Bypass-mode interaction ([Claude Code issue #37420](https://github.com/anthropics/claude-code/issues/37420)):** Returning `permissionDecision: "ask"` from a PreToolUse hook permanently disables Bypass permission mode for the rest of the session. If a user launches `claude --dangerously-skip-permissions` and our hook returns `"ask"` once, they get kicked back to manual approval forever. **Mitigation options:** (a) never return `"ask"` if we detect bypass mode via the `permission_mode` field in the payload — downgrade to `"allow"` with a logged warning; (b) document the interaction and refuse to install our hook if the user is known to run with bypass. TBD in Wave 2 implementation — see Open Question 8.

#### 2b. Extend existing hook-server.ts endpoint

The relay **already has** a loopback hook HTTP endpoint at `relay/src/hooks/hook-server.ts` that emits the correct `hookSpecificOutput` envelope. Wave 2 extends it with mode awareness, `tool_use_id` dedup, and push-notification firing. **Do not create a new `/internal/approvals` route from scratch.**

```ts
// relay/src/hooks/hook-server.ts — extend existing POST handler
app.post('/hooks/pre-tool-use', { config: { loopbackOnly: true } }, async (req, reply) => {
  const payload = req.body as PreToolUseHookInput;
  const mode = (req.headers['x-mt-mode'] as ApprovalMode) ?? 'local';
  const tabId = req.headers['x-mt-tab'] as string ?? 'unknown';
  const dedupKey = payload.tool_use_id;  // canonical dedup key — both paths get this

  // Bypass-mode escape hatch (Claude Code #37420)
  if (payload.permission_mode === 'bypass') {
    logger.warn({ tool: payload.tool_name }, 'bypass mode active — auto-allow to avoid #37420');
    return reply.send({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow' },
    });
  }

  // Coalesce duplicates (both SDK canUseTool and hook path can fire for same tool_use_id)
  if (approvalQueue.isPending(dedupKey)) {
    return reply.send({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'ask' },
    });
  }

  approvalQueue.enqueue({ dedupKey, source: 'hook', mode, tabId, payload });

  // notification-batcher.ts already handles approval batching — use its existing API
  notificationBatcher.addApprovalRequest(payload.tool_name, dedupKey);

  if (mode === 'local' || mode === 'hybrid') {
    return reply.send({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'ask' },
    });
  }

  // remote — block waiting for phone decision (hook's curl --max-time 600 governs the outer ceiling)
  const decision = await approvalQueue.waitForDecision(dedupKey);
  return reply.send({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: decision === 'allow' || decision === 'allow_always' ? 'allow' : 'deny',
    },
  });
});
```

**Hook timeout reality** (this is where my v1 spec was confused):

| Hook type | Default timeout | Where set |
|-----------|-----------------|-----------|
| File-based `command` hook | **600 seconds** (10 min) | `settings.json` `timeout` field, per-matcher override |
| Inline SDK `HookCallbackMatcher.timeout` | **60 seconds** | `options.hooks[...].timeout` in SDK session config |
| `http` hook type | **30 seconds** | hook matcher config |

The spec's `remote` mode user-tap window is governed by the **file-based 600s timeout** — not 60s. The 60s figure only applies to inline SDK hooks, which we only use for `SubagentStart`/`SubagentStop`. **For approval flows, the 600s ceiling is fine.** `canUseTool` has **no timeout at all** — only the abort signal from `options.signal`, which the existing `handlePermission` currently drops on the floor.

#### 2c. tmux send-keys injector

When a phone decision arrives in `hybrid` mode, the relay needs to type it into the right tmux window. The tab → window mapping lives in `session-manager.ts`'s `tabs: Map` from Wave 1. On decision:

```ts
// relay/src/utils/tmux-cli.ts
import { spawnSync } from 'node:child_process';

/**
 * tmux send-keys takes multiple args. Keystrokes and key names go as separate
 * args — 'a' 'Enter' is two args, NOT 'a\r' as one string. Mixing them breaks
 * on some shells and the `Enter` key name is the portable way to do newlines.
 */
export function sendKeys(windowTarget: string, ...keys: string[]): void {
  spawnSync('tmux', ['-L', 'major-tom', 'send-keys', '-t', windowTarget, ...keys], {
    stdio: 'ignore',
  });
}

// relay/src/hooks/approval-queue.ts (additions)
async resolveHybrid(dedupKey: string, decision: 'allow' | 'deny', tabId: string) {
  if (this.isResolved(dedupKey)) return;  // TUI already won the race
  this.markResolved(dedupKey, decision);
  const key = decision === 'allow' ? 'a' : 'd';
  sendKeys(tabId, key, 'Enter');  // two args: the letter and Enter
}
```

Edge cases:
- **TUI already resolved** → `isResolved()` short-circuits, send-keys skipped, no stray keystroke in the shell below the prompt.
- **Stale push on the phone** → after TTL (30s or the claude process's own prompt timeout), the relay emits a WS broadcast `approval.expired` that clears the phone card and calls `registration.getNotifications({tag: dedupKey}).then(ns => ns.forEach(n => n.close()))` via SW postMessage.
- **Input race (user typing when phone taps)** → track `lastPtyInputAt` per tab in the WS handler. If the user typed within the last 500ms, defer the send-keys injection by 1s. If the TUI is already gone (it was in vim, for example), the TTL handles it.
- **Multi-device hybrid (two phones)** → first to tap wins via `markResolved()`; second gets a WS broadcast telling the SW to `notification.close()` its pending notification.

#### 2d. SDK path retrofit (`canUseTool`)

`relay/src/adapters/claude-cli.adapter.ts` already has `canUseTool` wired into `ApprovalQueue` (lines 96–105, 179–239). It needs four changes — none of them mode-gated, because **SDK subagents can fire regardless of approval mode** (a Task tool spawned from the PTY's `claude` still goes through the SDK path for its own nested tools):

1. **`tool_use_id` as the dedup key** — replace `randomUUID()` at line 202 with `toolUseId` so the SDK path and hook path coalesce cleanly on the same logical request.
2. **Push fire on enqueue** — currently only WS broadcasts. Add `notificationBatcher.addApprovalRequest(toolName, toolUseId)` call inside `handlePermission` alongside the existing `approvalQueue.waitForDecision()`.
3. **Abort signal threading** — the SDK's third callback arg (`options`) includes a `signal: AbortSignal` that `handlePermission` currently drops. Thread it through to `approvalQueue.waitForDecision()` so aborts clean up the queue:

   ```ts
   // claude-cli.adapter.ts line ~99
   canUseTool: (toolName, input, options) =>
     this.handlePermission(session.id, toolName, input, options.toolUseID, options.signal),
   
   // line ~179
   private async handlePermission(
     sessionId: string,
     toolName: string,
     input: Record<string, unknown>,
     toolUseId: string,
     signal?: AbortSignal,
   ): Promise<PermissionResult> { ... }
   ```
4. **Return shape** — confirm the existing return shape `{ behavior: 'allow' | 'deny', toolUseID, message? }` matches the SDK's `PermissionResult` type in `sdk.d.ts:126-168`. (Already correct in the existing code — just sanity check.)

> 🧩 **We are NOT removing the SDK adapter in Phase 13.** Even after Wave 3 demolition, the SDK session stays alive as the "control plane" session (fires SubagentStart hooks, provides the agent tracker). The PTY is the user-facing interaction surface; the SDK session is the backend telemetry surface. They coexist.

#### 2e. Push notification routing (mostly wiring, not new code)

`relay/src/push/push-manager.ts` already exists with VAPID, subscription management, and `notifyAll()`. `relay/src/push/notification-batcher.ts` **already batches approval requests** via a 2-second window and exposes `addApprovalRequest(tool, dedupKey)`. Wave 2 is:

1. **Call the existing batcher** from both intercept paths (already shown in 2b and 2d).
2. **Extend the sendable payload** with typed approval fields (tool name, dedupKey as `data.requestId`, mode-specific `actions`).
3. **Add `urgency: 'high'` and `TTL: 30`** headers to `pushManager` calls for approvals so push services don't deliver stale approvals after the desktop resolved them. `web-push@3.6.7` supports this via the `headers` option in `sendNotification()`.
4. **Per-user subscription scoping.** Currently `push-manager.ts:113` uses `notifyAll()` which fans out to every subscription. In a fleet deployment, that's a privacy bug — user A's approvals would buzz user B's phone. Gate the approval notification on `subscription.userId === session.userId`.
5. **Quiet-hours opt-out for approvals.** `notification-config.ts` has `shouldNotify(priority)` that suppresses non-`high` priority during quiet hours. Approval notifications must be tagged `high` OR bypass the filter entirely. **Decide in Wave 2:** the safer default is to tag approvals `high` and let quiet hours still suppress *non-urgent* non-high notifications. Approvals should always ring through.

Final call shape (conceptual — real implementation lives inside the batcher flush):

```ts
// relay/src/push/push-manager.ts — extend existing method
fireApproval(req: {
  dedupKey: string;              // == tool_use_id
  mode: ApprovalMode;
  tool: string;
  summary: string;                // ≤ 100 chars for notification body
  source: 'hook' | 'sdk';
  userId: string;                 // for per-user scoping
}) {
  const actions = req.mode === 'local' ? [] : [
    { action: 'allow', title: 'Allow' },
    { action: 'deny', title: 'Deny' },
  ];
  this.sendToUser(req.userId, {
    title: `claude wants to ${req.tool}`,
    body: req.summary,
    data: { requestId: req.dedupKey, navigate: '/', mode: req.mode },  // navigate:'/' is load-bearing, see reality check
    actions,  // ignored on iOS PWA, used on Android
    tag: req.dedupKey,  // OS-level dedupe — same dedupKey replaces any prior notification
    renotify: true,
  }, {
    urgency: 'high',
    TTL: 30,
  });
}
```

> **The `navigate` field intentionally points at `/`, not `/approvals/:id`.** We are not path-routing. The SW `notificationclick` handler posts `{type: 'show-approval', requestId}` to the PWA, which shows the overlay from whatever tab the user was on. See reality check above.

#### 2f. ApprovalOverlay + existing sw.js extension (no router)

**The PWA has no path-based router.** `web/src/App.svelte` uses `activeTab = $state<ViewTab>('chat' | 'office' | 'characters')` with conditional rendering. We are NOT adding svelte-routing or svelte-spa-router. Instead, we add an **overlay state** that layers the approval card over whatever tab is active:

```svelte
<!-- web/src/App.svelte — add to existing state -->
<script lang="ts">
  let activeApprovalId = $state<string | null>(null);
  
  // Listen for SW postMessage — pattern already exists at App.svelte:55
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data?.type === 'show-approval') {
        activeApprovalId = event.data.requestId;
      } else if (event.data?.type === 'dismiss-approval') {
        if (activeApprovalId === event.data.requestId) activeApprovalId = null;
      }
    });
  }
  
  // Cold-start fallback: check for pending approvals on boot
  $effect(() => {
    if (!relay.isConnected) return;
    relay.fetchPendingApprovals().then((list) => {
      if (list.length > 0) activeApprovalId = list[0].id;
    });
  });
</script>

{#if activeApprovalId}
  <ApprovalOverlay requestId={activeApprovalId} onResolved={() => activeApprovalId = null} />
{/if}
```

**Extend the existing SW** at `web/public/sw.js` (plain JS, NOT TypeScript in `web/src/lib/sw.ts`):

```js
// web/public/sw.js — the notificationclick handler already exists
// and already does clients.matchAll + focus + navigate. Only the
// POSTMESSAGE payload changes to carry the approval ID.

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  // Android/desktop action buttons — direct decision without opening app
  if (event.action === 'allow' || event.action === 'deny') {
    event.waitUntil(
      fetch(`/api/approvals/${event.notification.data.requestId}/decision`, {
        method: 'POST',
        body: JSON.stringify({ decision: event.action }),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    return;
  }
  
  // Default tap: focus/open PWA, then postMessage the approval ID
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      const existing = clients[0];
      if (existing) {
        existing.focus();
        // Small delay for cold-start clients that aren't yet ready to receive
        setTimeout(() => existing.postMessage({
          type: 'show-approval',
          requestId: event.notification.data.requestId,
        }), 100);
      } else {
        self.clients.openWindow('/').then((client) => {
          if (client) setTimeout(() => client.postMessage({
            type: 'show-approval',
            requestId: event.notification.data.requestId,
          }), 500);  // longer delay for fresh-open
        });
      }
    }),
  );
});

// New: WS-driven notification dismissal when another device resolves
self.addEventListener('message', async (event) => {
  if (event.data?.type === 'approval-resolved') {
    const notifications = await self.registration.getNotifications({ tag: event.data.requestId });
    notifications.forEach((n) => n.close());
  }
});
```

When the WS relay broadcasts `approval.resolved` to all connected clients, the client posts the message to its SW, which closes any stale OS-level notifications. This is the "multi-device hybrid broadcast clear" from the open questions.

> ⚠️ **Cold-start iOS gotcha:** On cold-killed iOS PWA, `notificationclick` fires in the SW but `openWindow('/')` opens the manifest `start_url` only — the `postMessage` may fire before the new window's event listener is registered. The `setTimeout(500)` is a compromise; the **real safety net** is the cold-start fallback in `App.svelte` that calls `relay.fetchPendingApprovals()` on every boot and surfaces the freshest one even if postMessage is dropped.

#### 2g. Mode toggle UI

`web/src/lib/components/PermissionModeSwitcher.svelte` **already exists** (545 lines — it currently drives the old manual/auto/delay permission modes from Phase 6 ClaudeGod). Extend it with the three `local`/`remote`/`hybrid` options alongside (or replacing) the existing modes. Persists to relay via the existing settings endpoint. Relay writes the new value into a runtime-readable config file (`$HOME/.major-tom/claude-config/approval-mode.json`) that the hook script sources on next invocation. Live for the next request, no restart needed.

The hook script reads the mode via `MODE=${MAJOR_TOM_APPROVAL:-local}`, which the PTY adapter sets on spawn from the current runtime config. For mid-session toggles, the adapter can export a fresh env var via `pty.resize()` side effects? No — env vars don't propagate. **Solution:** hook script reads the mode from the file on every invocation:

```bash
MODE=$(cat "$MAJOR_TOM_CONFIG_DIR/approval-mode.json" 2>/dev/null | jq -r '.mode // "local"')
```

One file read per tool call. Cheap.

**Wave 2 file list (delta from Wave 1). Bold = new file, plain = extend existing.**

| File | Action | Purpose |
|------|--------|---------|
| `relay/src/hooks/hook-server.ts` | EXTEND | Add mode awareness (`X-MT-Mode`, `X-MT-Tab` headers), `tool_use_id` dedup, bypass-mode auto-allow (#37420), call into `notificationBatcher.addApprovalRequest()` |
| `relay/src/hooks/approval-queue.ts` | EXTEND | Dedup key = `tool_use_id` (not random UUID), hybrid resolution with `isResolved()` guard, TTL (30s), `source: 'hook'|'sdk'` tagging, accept `AbortSignal` on `waitForDecision()` |
| **`relay/src/utils/tmux-cli.ts`** | NEW | `sendKeys(windowTarget, ...keys)` — variadic args, `tmux send-keys -t tgt a Enter` |
| **`relay/scripts/install-hooks.ts`** | NEW | Idempotent installer for `$HOME/.major-tom/claude-config/` — creates dir, writes `settings.json`, drops hook scripts, chmod +x. Hash-based versioning. |
| **`relay/scripts/major-tom-pretooluse.sh`** | NEW | The hook script itself (with correct `hookSpecificOutput` envelope) |
| **`relay/scripts/major-tom-subagent-start.sh`** | NEW | Wave 3 preview — subagent spawn hook (shipped in Wave 2 as a no-op placeholder) |
| `relay/src/push/push-manager.ts` | EXTEND | Typed `fireApproval()` with `urgency: 'high'`, `TTL: 30`, per-user scoping via `sendToUser()` |
| `relay/src/push/notification-batcher.ts` | TOUCH | Already has `addApprovalRequest(tool, dedupKey)` — verify it's called from both intercept paths |
| `relay/src/push/notification-config.ts` | EXTEND | Approval notifications tagged `high` priority to ring through quiet hours |
| `relay/src/adapters/claude-cli.adapter.ts` | EXTEND | Thread `options.signal` through `handlePermission`, use `toolUseID` as dedup key (not `randomUUID`), call `notificationBatcher.addApprovalRequest()` |
| `relay/src/adapters/pty-adapter.ts` | EXTEND (Wave 1 file) | Set `CLAUDE_CONFIG_DIR`, `MAJOR_TOM_APPROVAL`, `MAJOR_TOM_TAB_ID`, `MAJOR_TOM_RELAY_PORT` env vars on PTY spawn |
| `relay/src/routes/api-approvals.ts` | NEW or EXTEND | `GET /api/approvals/pending` (cold-start fallback), `POST /api/approvals/:id/decision` |
| **`web/src/lib/components/ApprovalOverlay.svelte`** | NEW | Full-screen modal over `activeTab` — wraps existing `ApprovalCard.svelte` with route state |
| `web/src/lib/components/PermissionModeSwitcher.svelte` | EXTEND | Add `local`/`remote`/`hybrid` options (or replace existing options) |
| `web/public/sw.js` | EXTEND | `notificationclick` → postMessage `show-approval`; new `message` handler for `approval-resolved` → close tagged notifications |
| `web/src/App.svelte` | EXTEND | Add `activeApprovalId` state, SW message listener, cold-start fetch for pending approvals |
| `web/src/lib/stores/relay.svelte.ts` | EXTEND | Add `fetchPendingApprovals()`, `sendApprovalDecision(id, decision)` |

> **Bigger picture: the "new" file count is ~5, not ~15 as the v1 spec implied.** Most of Wave 2 is extending existing code. The relay already has a loopback hook server, an approval queue, a notification batcher, and a permission mode switcher. Don't rewrite them.

**Wave 2 success criteria:**

- [ ] `npm run install:hooks` is idempotent, creates `$HOME/.major-tom/claude-config/`, does NOT touch user's `~/.claude/`
- [ ] PTY adapter spawns `claude` with `CLAUDE_CONFIG_DIR=$HOME/.major-tom/claude-config` — verify via `env | grep CLAUDE` inside the PTY
- [ ] The hook script emits the correct `hookSpecificOutput` envelope (not the unwrapped `{"permissionDecision": ...}`) — verify with a manual `echo {} | pretooluse.sh` test
- [ ] In `local` mode: run `claude` in PTY, ask it to edit a file, see TUI prompt, answer with keyboard, edit lands. Phone gets passive notification.
- [ ] In `remote` mode: ask `claude` to edit a file, terminal blocks (hook curl --max-time 600 awaits), phone notification arrives, tap → overlay card, swipe → hook returns, terminal unblocks, edit lands.
- [ ] In `hybrid` mode (TUI wins): see TUI prompt, hit `a`, edit lands, phone notification cleared via WS broadcast `approval.resolved` → SW closes tagged notification.
- [ ] In `hybrid` mode (phone wins): see TUI prompt, ignore it, swipe right on phone → `tmux send-keys target a Enter` injects, TUI prompt resolves, edit lands.
- [ ] Mode toggle in PWA changes mode for the next request without restarting `claude` (file-based config read per invocation).
- [ ] Bypass-mode detection: launch `claude --dangerously-skip-permissions`, trigger a tool call, verify hook returns `"allow"` (not `"ask"`), bypass mode remains intact for subsequent calls.
- [ ] `tool_use_id` dedup: simulate both SDK and hook firing for same ID, verify only one push notification fires, verify queue coalesces.
- [ ] Abort signal threading: kill an SDK session mid-approval, verify `approvalQueue.waitForDecision()` returns cleanly without leaking.
- [ ] SDK subagent path: spawn a Task tool from `claude`, see `canUseTool` fire for its inner tool calls, see push notification, see decision flow back through the SDK.
- [ ] Push notification action buttons work on Android PWA (allow/deny without opening app).
- [ ] iOS PWA: tap notification → PWA opens to `/` → SW postMessage delivers → `ApprovalOverlay` appears. Cold-start fallback (phone killed for 15 min) still surfaces approval via `fetchPendingApprovals()`.
- [ ] Multi-device: two phones attached, one resolves → other's OS notification closes via `getNotifications({tag}).close()`.
- [ ] Quiet hours: approvals still ring through (tagged `high` priority); non-approval notifications still suppressed.

---

### Wave 3: Sprite Re-Wiring + Demolition

> **Goal:** Sprites are driven by real `SubagentStart` / `SubagentStop` SDK hooks (one sprite per `agent_id`), the chat layer is fully demolished, the office and the shell live together as the only two surfaces.

#### 3a. Sprite event source switch (with task correlation)

Currently, sprites are driven by a janky heuristic in the SDK event stream — we look for tool calls that *look* like agent spawns and pretend. Phase 13 swaps that for real `SubagentStart` and `SubagentStop` hook events from the SDK. Both events exist in TS SDK 0.2.79+ at `sdk.d.ts:488, 3432-3453`.

> ⚠️ **Schema reality check (from SDK source `sdk.d.ts:3432-3453`):**
>
> - `SubagentStartHookInput` fields: `agent_id`, `agent_type` + `BaseHookInput` fields (`session_id`, `transcript_path`, `cwd`, `permission_mode`). **There is NO `parent_id`, NO `task`, NO `role`.**
> - `SubagentStopHookInput` fields: `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `stop_hook_active`. **There is NO `result` field.** The closest equivalent is `last_assistant_message`.
>
> The task description is NOT in `SubagentStart`. You must correlate with a prior `PreToolUse` hook firing on the `Task` tool (which carries `tool_input.description` and `tool_input.prompt`) by `tool_use_id`, which the SDK correlates with the subsequent `SubagentStart.agent_id` via the parent session's tool-use tracking.

Concrete pattern — correlate PreToolUse(Task) → SubagentStart via a short-lived `pendingTaskByToolUseId` map in the adapter:

```ts
// relay/src/adapters/claude-cli.adapter.ts
const pendingTaskByToolUseId = new Map<string, { description: string; prompt: string }>();
// GC entries older than 30s to avoid leaks

const sdkSession = unstable_v2_createSession({
  // ...
  hooks: {
    PreToolUse: [{
      matcher: { tool_name: 'Task' },
      hooks: [async (input) => {
        const { tool_use_id, tool_input } = input;
        pendingTaskByToolUseId.set(tool_use_id, {
          description: tool_input.description ?? '',
          prompt: tool_input.prompt ?? '',
        });
        return { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow' } };
      }],
    }],
    SubagentStart: [{
      hooks: [async (input) => {
        const { agent_id, agent_type } = input;
        // The Task tool's tool_use_id correlates with the agent's spawn via the SDK's internal tracking —
        // in practice, we approximate by grabbing the most recent pending task entry that matches agent_type
        // (or if only one is pending, use it). See Open Question 11 for the failure modes.
        const taskContext = findPendingTaskByAgentType(pendingTaskByToolUseId, agent_type);
        this.emitter.emit('agent.spawn', {
          agentId: agent_id,
          agentType: agent_type,
          task: taskContext?.description ?? agent_type,
          prompt: taskContext?.prompt ?? '',
        });
        return {};
      }],
    }],
    SubagentStop: [{
      hooks: [async (input) => {
        const { agent_id, last_assistant_message } = input;
        this.emitter.emit('agent.dismissed', {
          agentId: agent_id,
          summary: last_assistant_message ?? '',
        });
        return {};
      }],
    }],
  },
});
```

The PTY-spawned `claude` has its own hook file for the same events. Ship a second shell script alongside the PreToolUse one:

```bash
#!/usr/bin/env bash
# $HOME/.major-tom/claude-config/hooks/subagent-start.sh
PAYLOAD=$(cat)
curl -fsS --max-time 1 -X POST "http://127.0.0.1:${MAJOR_TOM_RELAY_PORT:-8080}/hooks/subagent-start" \
  -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null 2>&1 &
echo '{}'
```

And in `settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "$CLAUDE_CONFIG_DIR/hooks/pretooluse.sh" }] }],
    "SubagentStart": [{ "hooks": [{ "type": "command", "command": "$CLAUDE_CONFIG_DIR/hooks/subagent-start.sh" }] }],
    "SubagentStop": [{ "hooks": [{ "type": "command", "command": "$CLAUDE_CONFIG_DIR/hooks/subagent-stop.sh" }] }]
  }
}
```

Both intercept paths (SDK adapter hooks + PTY shell hooks) funnel into `agentTracker` via the same emitter events. The Phase 12 sprite refactor (commit `88a94c0`) made sprites generic — Phase 13 just plugs in the real event source with the correct schemas and the task-correlation workaround.

#### 3b. Demolition

Now the chat layer dies. Files to delete:

| File | Reason |
|------|--------|
| `web/src/lib/components/ChatView.svelte` | Replaced by `Shell.svelte` |
| `web/src/lib/components/MessageBubble.svelte` | No more chat bubbles |
| `web/src/lib/components/TemplateDrawer.svelte` | No more typed prompts to template — you type into the terminal |
| `web/src/lib/components/TemplateSaveDialog.svelte` | Same reason |
| `web/src/lib/components/PromptHistoryOverlay.svelte` | Terminal has its own history (`↑↓`), do not need ours |
| `web/src/lib/components/StreamingIndicator.svelte` | Terminal renders streaming directly |
| `web/src/lib/components/ContextChips.svelte` | File context goes through CLI's `@file` syntax now |
| `web/src/lib/stores/chat.svelte.ts` (if exists) | Dead state |

Files to **slim** (not delete):

| File | Slim what |
|------|-----------|
| `web/src/lib/db/dexie.ts` | Drop `messages` table — we no longer persist chat history client-side. Keep `sessions`, `approvals`, `settings`. |
| `web/src/lib/stores/relay.svelte.ts` | Drop `sendPrompt`, `messages`, `streamingMessage`. Keep auth, connection, approval. |
| `relay/src/protocol/types.ts` | Drop `prompt`, `output`, `tool.start`, `tool.complete` message types. They are dead now — terminal handles all of that. Keep `approval.*`, `agent.*`, `session.*`. |
| `relay/src/adapters/claude-cli.adapter.ts` | Remove `sendPrompt`, `sendAgentMessage` (we have a real terminal now — agent message goes through `tmux send-keys` to the agent's tab if we wire that up). Keep the `canUseTool` path, the `consumeStream` for SDK subagents, and the new `SubagentStart`/`SubagentStop` hooks. |

Files to **rename / regrade**:

| File | New role |
|------|----------|
| `web/src/lib/components/Terminal.svelte` (the old fake bash terminal) | DELETE — replaced by `Shell.svelte` which wraps `XtermPane.svelte` |
| `web/src/lib/stores/terminal.svelte.ts` | DELETE — fake terminal state, no longer needed |

iOS native side: leave frozen for Phase 13. Phase 14+ is where we add SwiftTerm. The native app stays on the chat-based interaction model until then. (This is consistent with the dual-client strategy — PWA leads, iOS premium follows.)

**Wave 3 success criteria:**

- [ ] Sprites spawn/despawn driven by real `SubagentStart`/`SubagentStop` events from BOTH the SDK adapter and the PTY shell hooks
- [ ] The mapping is 1:1: every `agent_id` gets exactly one sprite, sprite goes away when agent exits (on `SubagentStop.last_assistant_message`)
- [ ] Sprite role labels match the real subagent task description recovered from PreToolUse(Task) correlation; fallback to `agent_type` if correlation fails (log the miss)
- [ ] All chat-layer files deleted, `git grep ChatView` returns nothing
- [ ] `git grep messages` in `web/src/lib/db` returns nothing
- [ ] PWA loads with shell + office, no chat code loaded, no chat code in the bundle
- [ ] Bundle size *decreases* meaningfully (probably 30–40KB minified — chat layer is heavy)
- [ ] Smoke test: full North-Star flow works end-to-end on phone (iPhone PWA + Android PWA)

---

## Open Questions / Risks

These are the things I do not know yet and want to call out so we do not pretend they are solved. **The list grew significantly after the v2 review — items 8–14 are new.**

### 1. tmux send-keys race condition in hybrid mode

If the user is *simultaneously* typing in the terminal at the moment the relay tries to inject `a Enter`, the keystroke could land between user keystrokes and corrupt their input. Mitigation ideas:

- (a) Only inject when the pane has been idle for >500ms (track `lastPtyInputAt` per tab in the WS handler)
- (b) Use `tmux send-keys -X` to target a specific pane state (the prompt, not the editor)
- (c) Accept the race as user error — if you are typing while answering a phone prompt, you deserve the chaos

I lean **(a)**. Worth prototyping in Wave 2.

### 2. Hook `permissionDecision: "ask"` requires interactive terminal

Verified this works in PTYs (PTYs are interactive by definition). But see Q8 below — it trips a known bug when bypass mode is active.

### 3. Hook script latency in `local` mode

`fire-and-forget curl --max-time 1` should be <10ms. If it's not, the user feels it as a stutter every tool call. **Mitigation:** use a Unix domain socket instead of HTTP. Decide in Wave 2 based on measurement.

### 4. Multi-device hybrid mode

Two phones attached to the same session. Both fire push. User taps phone 1, the relay injects via tmux send-keys. Phone 2's push card needs to clear → WS broadcast `approval.resolved`, client posts to SW which calls `registration.getNotifications({tag}).close()`. Pattern documented in 2f.

### 5. iOS native app falls behind

Phase 13 is a PWA-only delivery. The iOS native app keeps the old chat UI until Phase 14+. **Mitigation:** tag iOS native as "legacy chat client" and add a "switch to PWA for shell experience" prompt.

### 6. Push notification budget

Handled: `notification-batcher.ts` already batches approvals via a 2-second window. Wave 2 wires both intercept paths into the existing batcher.

### 7. tmux state on relay restart

If the relay restarts, tmux server keeps running (detached, custom socket). New relay attaches seamlessly. **But:** the in-memory `tabs: Map` is lost. **Mitigation:** on startup, query `tmux list-windows -t major-tom` and rehydrate from actual tmux state. Persist `tabId → windowId` mapping via existing `session-persistence.ts`.

### 8. Bypass-mode interaction bug ([Claude Code #37420](https://github.com/anthropics/claude-code/issues/37420))

**Returning `permissionDecision: "ask"` from a PreToolUse hook permanently disables Bypass permission mode for the rest of the session.** If a user launches `claude --dangerously-skip-permissions` (the most natural "phone manages everything" setup) and our hook returns `"ask"` once, they are kicked back to manual approval forever.

**Mitigation options:**
- (a) Detect `permission_mode === 'bypass'` in the hook payload and auto-allow (downgrade `"ask"` → `"allow"` with a warning log)
- (b) Refuse to install the hook if the user is known to run with bypass
- (c) File an upstream fix and wait

Currently we implement (a) — see the envelope in 2b. Revisit if Anthropic ships a real fix.

### 9. `SubagentStart` has no task context

`SubagentStart` only carries `agent_id` + `agent_type`. The task description the sprite needs for its label must be recovered by correlating with a prior `PreToolUse` on the `Task` tool by tool-use-id → agent-id. The correlation is not 1:1 (see 3a) — failure modes include multiple parallel Task spawns of the same agent_type where we can't tell them apart. **Mitigation:** if correlation fails, fall back to `agent_type` as the sprite label. Log the miss.

### 10. iOS PWA cold-start notification routing ([WebKit bug 268797](https://bugs.webkit.org/show_bug.cgi?id=268797))

Cold-killed iOS PWA does not honor `client.navigate()` or `openWindow(url)` with a non-root URL. Mitigation baked into 2f: (a) notifications always route to `/`, (b) SW posts approval ID to the new window with a 500ms delay, (c) App.svelte cold-start fallback fetches `GET /api/approvals/pending` and surfaces the freshest one independent of the SW postMessage path.

### 11. iOS WebGL context loss when PWA backgrounds

Terminal goes black after lock screen. **Mitigation:** detect iOS via UA sniff, skip WebGL addon entirely, fall back to the canvas renderer. Or wire `webglAddon.onContextLoss(() => webglAddon.dispose())` to re-initialize. Decide in Wave 1 based on measured perf.

### 12. Multi-device same-tmux-session input conflict

Two phones attached to the same tmux window = both phones can type. Tmux mirrors output but does not coordinate input. **Mitigation:** mark one client as "primary" in session-manager; other clients are output-only by default. UI shows "viewing" vs "editing" state.

### 13. tmux external kill recovery

If the user runs `tmux kill-server` in a different shell, our `-L major-tom` server dies with it. **Mitigation:** the bootstrap should be re-runnable on every WS connection, not just startup. Cheap idempotent check: `tmux -L major-tom has-session -t major-tom || tmux -L major-tom new-session -A -d -s major-tom`.

### 14. EU iOS PWA disablement (DMA compliance)

As of iOS 17.4, Apple disabled PWA home-screen install in EU territories under DMA compliance. Web Push does not work for EU iOS users with a PWA delivery. **Impact:** Phase 13's PWA-first strategy fails entirely for an entire market. **Mitigation options:** (a) EU users get Safari-in-tab experience (no push, WS-only with in-app notifications when tab is open); (b) wait for iOS native app (Phase 14+); (c) accept the limitation and document it. Decide before public launch.

### 15. Quiet hours vs approval urgency

`notification-config.ts` has a `shouldNotify(priority)` filter that suppresses non-`high` priority during quiet hours. Approvals must either be tagged `high` or bypass the filter. **Default:** tag approvals `high` and let quiet hours still suppress *other* non-high notifications. Confirm in Wave 2.

### 16. Declarative Web Push is not a dependency

The v1 spec suggested Declarative Web Push (Safari 18.4+) as a fallback path for action buttons. **Reality:** the shipped schema has only `navigate`, no `actions`. `web-push@3.6.7` has no first-class declarative support (different content-type). Treat declarative push as a Phase 14+ optimization — not a Phase 13 dependency. The PWA strategy is: SW postMessage routing + cold-start fallback, no router, no declarative.

---

## What We Are NOT Doing (Phase 14+)

Explicit non-goals so we do not scope-creep:

- ❌ **Native iOS shell** — Phase 14+. SwiftTerm or similar. iOS stays on chat in Phase 13.
- ❌ **`claude /login` automation** — Phase 14.alpha "Auto-Clicker". Browser auto-clicker reads the login URL from the PTY output, clicks "Authorize" via AppleScript / Playwright. Out of scope here.
- ❌ **Voice dictation** — VoiceMicButton stays where it is, but does not get re-wired into the terminal. Phase 14+.
- ❌ **Terminal recording / playback** — cool but not now.
- ❌ **Multiple concurrent `claude` processes** in the same tmux window — out of scope. Use multiple windows (tabs) instead.
- ❌ **Custom theme picker for the terminal** — ship one good dark theme, defer customization.
- ❌ **Tmux pane splitting in the PWA UI** — tabs are enough. Splits are Phase 14+ if anyone asks.

---

## Success Criteria (Phase 13 as a whole)

Phase 13 is done when:

1. **PWA has a real terminal** that runs `claude`, survives reconnects, has working mobile keybar, and is the *only* interaction surface for sending prompts.
2. **All three approval modes work end-to-end** with both intercept paths (PTY shell hook + SDK `canUseTool`).
3. **Push notifications fire correctly** in all three modes with mode-appropriate behavior (passive vs actionable).
4. **Sprites are driven by real `SubagentStart`/`SubagentStop` events**, mapped 1:1 to `agent_id`.
5. **Chat layer is fully demolished** — no `ChatView`, no `MessageBubble`, no chat code in the bundle. `git grep` is the proof.
6. **The North-Star flow** at the top of this doc actually works on a real iPhone, end to end, without me pre-loading any state.
7. **Documentation updated**: PLANNING.md has the Phase 13 entry, README mentions the shell experience, hook installer is documented for users.

---

## Demolition Checklist (running tally — fill in during Wave 3)

```
web/src/lib/components/
  [ ] ChatView.svelte                       DELETE
  [ ] MessageBubble.svelte                  DELETE
  [ ] Terminal.svelte (fake bash one)       DELETE
  [ ] TemplateDrawer.svelte                 DELETE
  [ ] TemplateSaveDialog.svelte             DELETE
  [ ] PromptHistoryOverlay.svelte           DELETE
  [ ] StreamingIndicator.svelte             DELETE
  [ ] ContextChips.svelte                   DELETE

web/src/lib/stores/
  [ ] terminal.svelte.ts                    DELETE
  [ ] (chat-related slices in relay.svelte) SLIM

web/src/lib/db/
  [ ] dexie.ts (messages table)             SLIM

relay/src/protocol/
  [ ] types.ts (chat message types)         SLIM

relay/src/adapters/
  [ ] claude-cli.adapter.ts                 SLIM (kill sendPrompt/sendAgentMessage paths)

ios/MajorTom/Features/
  (nothing — frozen, Phase 14+)
```

---

## Notes for Implementers

**Relay side:**
- **Read the existing `claude-cli.adapter.ts` first** — especially lines 80–240. The `canUseTool` path is already 80% of what Wave 2 needs. Extend it, don't rewrite.
- **Read the existing `hook-server.ts`** — lines 82–87 already emit the correct `hookSpecificOutput` envelope. Copy the pattern, don't reinvent it.
- **Read the existing `notification-batcher.ts`** — `addApprovalRequest(tool, dedupKey)` already exists. Use it.
- **Read the existing `PermissionModeSwitcher.svelte`** (545 lines) — extend it, don't create a new sibling.
- **Edit `relay/src/app.ts` for routes and `relay/src/plugins/websocket.ts` for plugin config** — NOT `server.ts`.
- **Use binary WS frames for PTY data**, JSON text frames for control. Mixing them breaks UTF-8.
- **`encoding: null` on node-pty** + runtime `Buffer` cast (types lie; see microsoft/node-pty#489).
- **`tmux send-keys` takes variadic args**: `sendKeys(target, 'a', 'Enter')` — NOT `'a\r'` as one string.
- **Dedup approval requests by `tool_use_id`**, not freshly-generated UUIDs. Both intercept paths get `tool_use_id` from the SDK.
- **Thread `options.signal` through `handlePermission` → `approvalQueue.waitForDecision()`.** Currently dropped; SDK abort leaks approvals.
- **Use `CLAUDE_CONFIG_DIR` for hook install**, not `~/.claude/settings.json`. Major Tom ships its own config dir and the PTY spawn sets the env var.
- **Bypass-mode escape hatch:** if `payload.permission_mode === 'bypass'`, the hook must return `"allow"` not `"ask"` or you break the user's `--dangerously-skip-permissions` session permanently (#37420).
- **Hook command timeout is 600s (file-based), not 60s.** 60s is only the inline SDK `HookCallbackMatcher.timeout`.

**Web / PWA side:**
- **There is no router.** Do not add one. Overlay pattern + SW postMessage + cold-start fetch fallback is the delivery.
- **Edit `web/public/sw.js`** (plain JS) — NOT `web/src/lib/sw.ts` (doesn't exist).
- **The existing `notificationclick` handler already focuses clients and navigates.** Only the postMessage payload changes.
- **Cold-start fallback is load-bearing** on iOS — every boot should check `GET /api/approvals/pending`.
- **`notification.data.navigate` should point at `/`**, not `/approvals/:id`. Path routing is broken on cold-killed iOS PWA ([WebKit 268797](https://bugs.webkit.org/show_bug.cgi?id=268797)).
- **Skip WebGL on iOS** — set a UA check and don't load the addon. Context loss on background breaks the terminal silently.
- **The mobile keybar is a real Svelte component**, not a div with onclicks. Sticky modifier state, visual feedback, repeat-on-hold for arrows. Use `term.input(data, true)` to inject — single code path.
- **`visualViewport.resize` fires on rotation and address-bar collapse** too, not just keyboard. Debounce and derive keyboard visibility from `window.innerHeight - visualViewport.height > 100`.

**Testing:**
- **Test with `vim`, `htop`, `less`, and `claude`** in the terminal before declaring Wave 1 done. If vim works, your terminal works. If vim is fucked, your escape sequences are wrong.
- **Test the three modes on real devices**: desktop browser + iPhone PWA + Android PWA. The iPhone PWA has to be "Add to Home Screen" installed, not Safari tab.
- **Test cold-start on iPhone**: lock phone for 15 minutes, fire an approval, tap notification — card should appear. If it lands on the wrong tab, the postMessage delay isn't enough.
- **Test `pkill tmux`** while a session is attached — relay should recover via idempotent bootstrap on next connection.
- **Test push notification bodies are ≤ 100 chars.** The full payload lives in the card, not the notification.

---

> **Authors:** Sean + Claude
> **Last updated:** 2026-04-06
