# Major Tom Terminal Protocol — v2 (post-tmux)

> Wire protocol for the `/shell/:tabId` WebSocket. Replaces the implicit, tmux-coupled v1 protocol that lived in code comments only.
>
> Status: SPEC. Implementation lands with `PHASE-TERMINAL-REBOOT`. Clients (iOS + PWA + Ground Control) are migrated together — no mixed-version exposure ships.

---

## Goal

A plain PTY-per-tab terminal protocol. The relay spawns the user's login shell once per tab, streams bytes over WebSocket, and holds the PTY through a 30-minute disconnect grace so backgrounding the iOS app does not lose state. No multiplexer. No tmux. No grouped view sessions. Multi-device simultaneous attach is explicitly out of scope (deferred to a future multi-user phase — see `// FUTURE: multi-user` markers in the code).

User-started tmux sessions inside the spawned shell (`tmux new -s work`) are unaffected — they daemonize via launchd on macOS and survive the relay process entirely.

---

## Endpoint

```
ws[s]://<relay-host>/shell/:tabId?[cols=<N>&rows=<M>][&token=<jwt>]
```

| Param | Required | Notes |
|-------|----------|-------|
| `:tabId` | yes | Client-owned identifier. Regex `/^[a-zA-Z0-9._-]{1,64}$/`. Invalid → WS close `1008`. |
| `cols` | no | Initial terminal width. Bounds 2–500 (hard reject on out-of-bounds → WS close `1008`). Defaults to 80 when missing. |
| `rows` | no | Initial terminal height. Bounds 2–500 (hard reject on out-of-bounds → WS close `1008`). Defaults to 24 when missing. |
| `token` | optional | Session JWT fallback when no cookie can be attached (WKWebView edge cases) OR the dev-mode legacy `AUTH_TOKEN` value. |

Auth precedence (checked in order):
1. **Dev-mode legacy token** — if `NODE_ENV !== 'production'` AND `AUTH_TOKEN` env is set AND `?token=` matches it, accept.
2. **Session cookie** — `mt-session` cookie verified as a JWT.
3. **Token query fallback** — `?token=<jwt>` verified as a session JWT (used by WKWebView when cookie injection fails).
4. Otherwise: **WS close with code `1008`** ("Authentication required"). REST endpoints under `/shell/*` return HTTP `401` for the same failure.

---

## Frame Encoding

Two frame kinds, distinguished by WebSocket opcode:

- **Binary** — raw PTY bytes. No internal framing.
- **Text** — UTF-8 JSON control message.

Reason: PTY output may contain partial UTF-8 sequences and ANSI escape bytes that text encoding would corrupt. Control plane is JSON for simplicity.

---

## Message Catalog

### Client → Server

| Frame | JSON Fields | Purpose |
|-------|-------------|---------|
| Binary | — | Stdin to PTY. Max **64 KiB** per frame; oversized → WS close `1009`. |
| Text | `{type:"resize", cols:int, rows:int}` | Resize PTY. Bounds 2–500 each. |
| Text | `{type:"input", data:string}` | JSON-wrapped stdin (escape hatch / debug). UTF-8 only. |
| Text | `{type:"kill"}` | Terminate PTY now, no grace, evict from session map. |

### Server → Client

| Frame | JSON Fields | Purpose |
|-------|-------------|---------|
| Text | `{type:"attached", tabId:string, restored:bool}` | Sent once on successful attach. `restored=true` ⇒ reattached to a PTY that was alive in grace. `restored=false` ⇒ fresh PTY (first connect or after grace expiry). |
| Binary | — | PTY stdout/stderr. Sent live. **On reattach, the ring buffer is replayed before live stream resumes.** |
| Text | `{type:"error", message:string}` | Auth failure, spawn failure, or "already attached on another connection". Server closes WS after sending. |
| Text | `{type:"exit", exitCode?:int, signal?:string}` | PTY exited (user typed `exit`, process crashed, etc.). Server closes WS after sending. |

### Removed in v2

| Old | Replacement |
|-----|-------------|
| `{type:"refresh"}` | None — was a tmux redraw hack (`cols-1` then `cols` resize wobble). PTY has no equivalent need. Server silently ignores if received. |

---

## Lifecycle State Machine

```
       ┌──────────────┐
       │   IDLE       │  no PTY, no clients
       └──────┬───────┘
              │ first WS connect with tabId=X
              ▼
       ┌──────────────┐
   ┌──▶│   ACTIVE     │  PTY alive, 1 WS attached
   │   └──┬──────────┬┘
   │      │ WS close │ {type:"kill"} OR PTY natural exit
   │      ▼          ▼
   │  ┌──────────┐  ┌──────────────┐
   │  │ DETACHED │  │  TERMINATED  │  PTY killed, evicted
   │  └──┬───┬───┘  └──────────────┘
   │     │   │                     ▲
   │     │   │ grace timer fires   │
   │     │   └─────────────────────┘
   │     │ same X reconnects (within grace)
   └─────┘
```

### Transitions

| From → To | Trigger | Server actions |
|-----------|---------|----------------|
| `IDLE → ACTIVE` | First WS connect | `pty.spawn($SHELL, ['-l'], {cwd, env})`. Register in `Map<tabId, PtySession>`. Send `{type:"attached", restored:false}`. |
| `ACTIVE → DETACHED` | WS close (network drop / app background / force-quit) | Set `detachedAt`. Start grace timer (default 30 min, env `MAJOR_TOM_PTY_GRACE_MS`). PTY keeps running. |
| `DETACHED → ACTIVE` | New WS connect with same tabId | Cancel grace timer. Send `{type:"attached", restored:true}`. Replay ring buffer (binary frame, may be multiple frames). Resume live streaming. |
| `DETACHED → TERMINATED` | Grace timer fires | `SIGTERM` PTY. After 5 s, `SIGKILL` if still alive. Evict from map. |
| `ACTIVE → TERMINATED` | `{type:"kill"}` from client OR PTY exits naturally | If natural exit: send `{type:"exit", exitCode, signal}`, then close WS. If `kill`: just close. Evict from map. |

### Reconnect to an unknown tabId

Server has no record of `tabId` (never existed, or grace-expired and evicted):

- Treat as `IDLE → ACTIVE` for that tabId. Spawn a fresh PTY.
- `restored:false` in the attached message.
- Server logs via `pino` at WARN level: `{ event: "reconnect_orphaned", tabId, action: "spawn_fresh" }`.
- **Client UI shows fresh terminal silently. No banner. No error.**

### Multi-WS to same tabId (already attached)

Per Q1 — multi-device simultaneous attach is deferred. Implementation:

- Second WS attempt on a tabId in `ACTIVE` state → server sends `{type:"error", message:"tab already attached"}`, closes WS with code `4001` (custom).
- Client should treat `4001` as "another device has this tab" and prompt user (or just retry after backoff). For now, UI just shows the error message in the tab — no special handling required.

---

## REST Surface

### `GET /shell/tabs`

Returns:

```json
[
  { "tabId": "tab-a1b2c3d4", "attached": true,  "lastActivityAt": "2026-04-14T10:22:03.103Z" },
  { "tabId": "tab-9f8e7d6c", "attached": false, "lastActivityAt": "2026-04-14T10:11:45.812Z" }
]
```

Backed by the in-memory session map (no `tmux list-windows` shell-out). Includes both `ACTIVE` (`attached:true`) and `DETACHED` (`attached:false`) tabs. Used by clients on launch to reconcile their stored tab list against the server's reality.

Auth: same as WS (cookie or token).

### `POST /shell/:tabId/kill`

Same effect as sending `{type:"kill"}` over WS. Useful when the WS is in a bad state (CONNECTING, CLOSING). Returns `204` on success, `404` if tabId unknown.

Auth: same as WS.

---

## Configuration (env vars)

| Var | Default | Purpose |
|-----|---------|---------|
| `MAJOR_TOM_PTY_GRACE_MS` | `1800000` (30 min) | DETACHED → TERMINATED timer |
| `MAJOR_TOM_PTY_BUFFER_BYTES` | `262144` (256 KiB) | Per-tab ring buffer size for replay on reattach |
| `MAJOR_TOM_PTY_INPUT_MAX` | `65536` (64 KiB) | Max bytes per binary input frame; oversized → WS close `1009` |
| `SHELL` | `/bin/bash` | Spawned shell. Inherited from user env via Ground Control's launch context. |
| `CLAUDE_WORK_DIR` | `$HOME` | Initial cwd for spawned shell |
| `CLAUDE_CONFIG_DIR` | `<auto>` | Hook script path; injected into PTY env as both `CLAUDE_CONFIG_DIR` and `MAJOR_TOM_CONFIG_DIR` |
| `MAJOR_TOM_APPROVAL` | `local` | Approval mode (`local` / `remote` / `hybrid`). Hybrid uses `pty.write()` injection — no more `tmux send-keys`. |
| `MAJOR_TOM_RELAY_PORT` | `9091` | Hook HTTP server port; injected into PTY env |
| `MAJOR_TOM_TAB_ID` | (per-spawn) | Tab identifier injected into PTY env so hook scripts can route correctly |

---

## Hook Approval Injection (replaces `tmux send-keys`)

Hybrid approval mode injects a decision back into the running PTY when the user approves a tool call from the phone. v2 implementation:

1. Hook script (`pretooluse.sh`) runs inside the PTY's process tree (Claude Code's hook runner).
2. Script `curl`s `/hooks/pre-tool-use` with `tabId` from `$MAJOR_TOM_TAB_ID` env.
3. Relay queues the approval, surfaces it to clients.
4. User taps approve on phone.
5. Relay's hook handler: `sessionMap.get(tabId).write(decision + '\n')` — writes directly to the PTY via the in-memory session map.
6. Hook script reads the decision (or polls the HTTP endpoint for it), returns to Claude Code.

Same observable behavior as v1 (`tmux send-keys`) but cleaner: no shell-out, no socket lookup, no tmux dependency.

---

## Migration / Backwards Compatibility

This is a breaking change to the implicit v1 protocol. All clients (iOS, PWA, Ground Control) ship updated together as part of `PHASE-TERMINAL-REBOOT`.

Required client changes:

- Stop sending `{type:"refresh"}` (silently ignored if sent — but remove the call).
- Handle `{type:"attached", tabId, restored}` (can no-op for now; future UI may surface `restored` for analytics).
- Handle WS close code `4001` ("already attached") — current behavior is fine (just shows error message).
- Reparse `GET /shell/tabs` response — new shape with `attached`/`lastActivityAt` fields.

Unchanged from v1:

- Binary input/output framing.
- `{type:"resize"}`, `{type:"input"}`, `{type:"kill"}` requests.
- `{type:"error"}`, `{type:"exit"}` responses.
- Auth (cookie + token fallback).
- WS endpoint URL pattern.

---

## Rationale Notes (for future readers)

- **Why no SQLite for session state?** PTYs are OS processes, not data. A SQLite row saying "tab X exists" is meaningless if the process is dead. The PTY itself is the source of truth. In-memory `Map` is sufficient and has zero schema/migration cost.
- **Why 30-min grace?** Empirically covers iOS background suspension (≤30 min typical), commute interruptions, lunch breaks. Configurable for users who want longer.
- **Why 256 KiB ring buffer?** Enough to replay a typical scroll-back on reattach without making a huge stream. Configurable. ~10 tabs × 256 KiB = 2.5 MiB resident — negligible on a Mac.
- **Why drop multi-device attach?** Tmux's grouped view sessions were the implementation; without tmux, building it cleanly requires multi-WS broadcast + last-write-wins-input semantics. Worth it only when team-server / multi-user mode lands. Until then, simpler.
- **Why not detach the PTY from the relay process (so it survives relay restart)?** Would require giving up the PTY file descriptors — relay can't read output anymore. Only way to do this cleanly is to use a separate persistent process, which is what tmux already gave us. User accepted the tradeoff: relay-managed PTYs die with the relay; user-started tmux survives independently.
