# Ground Control MCP Server — Spec

> Hand this doc to a fresh Claude session on a worktree branch.
> Branch name: `ground-control/mcp-server`

---

## Goal

Let Claude Code agents programmatically read Ground Control status, control
the relay lifecycle, and stream logs — without touching a GUI. Enables
self-healing agent workflows: an agent detects the relay is down, restarts
it via MCP, and resumes work.

---

## Architecture

Ground Control (macOS app) owns the relay lifecycle. The relay itself doesn't
know about its own process management. So the MCP server needs to talk to
Ground Control, not the relay.

```
Claude Code  <-stdio->  mcp-server.js  <-HTTP->  Ground Control (macOS app)
                                                      |
                                                  RelayProcess
                                                  TunnelProcess
                                                  LogStore
                                                  ConfigManager
```

### Step 1: Add a control API to Ground Control

New `ControlServer.swift` — lightweight HTTP server bound to
`127.0.0.1:<controlPort>` (default 9092). Uses NWListener (Foundation,
no external deps).

| Method | Path | Description |
|--------|------|-------------|
| GET | `/control/status` | Relay + tunnel state, restart count, uptime |
| POST | `/control/relay/start` | Start the relay |
| POST | `/control/relay/stop` | Stop the relay |
| POST | `/control/relay/restart` | Restart the relay |
| POST | `/control/tunnel/start` | Start the tunnel (if configured) |
| POST | `/control/tunnel/stop` | Stop the tunnel |
| GET | `/control/logs` | Recent log entries (JSON, last N or since timestamp) |
| GET | `/control/logs/stream` | SSE stream of new log entries |
| GET | `/control/config` | Current config (non-secret fields) |
| PATCH | `/control/config` | Update config fields (restart to apply) |

**Security:** Loopback-only bind, reject non-loopback. Same model as
relay's `/api/admin/status`.

### Step 2: MCP server bridge (Node.js)

New `mcp/ground-control-mcp/` — thin Node MCP server exposing tools:

| Tool | Description |
|------|-------------|
| `get_relay_status` | Relay state, tunnel state, client count, uptime |
| `start_relay` | Start the relay server |
| `stop_relay` | Stop the relay server |
| `restart_relay` | Restart the relay server |
| `start_tunnel` | Start the Cloudflare tunnel |
| `stop_tunnel` | Stop the Cloudflare tunnel |
| `get_logs` | Recent logs, filterable by level/count |
| `get_config` | Current Ground Control config |
| `update_config` | Update config fields |

Registration in `.claude/settings.json`:
```json
{
  "mcpServers": {
    "ground-control": {
      "command": "node",
      "args": ["<repo>/mcp/ground-control-mcp/index.js"]
    }
  }
}
```

### Step 3: Resources (optional)

| URI | Description |
|-----|-------------|
| `ground-control://status` | Live relay + tunnel status |
| `ground-control://logs/recent` | Last 100 log entries |

---

## Key Files to Create

| File | Description |
|------|-------------|
| `macos/GroundControl/Services/ControlServer.swift` | HTTP control API |
| `mcp/ground-control-mcp/package.json` | MCP server package |
| `mcp/ground-control-mcp/src/index.ts` | MCP server entry |
| `mcp/ground-control-mcp/src/tools.ts` | Tool definitions + handlers |

## Key Files to Read First

| File | Why |
|------|-----|
| `macos/GroundControl/Services/RelayProcess.swift` | Lifecycle to expose |
| `macos/GroundControl/Services/TunnelProcess.swift` | Tunnel lifecycle |
| `macos/GroundControl/Services/LogStore.swift` | Log access |
| `macos/GroundControl/Services/ConfigManager.swift` | Config read/write |
| `relay/src/routes/health.ts` | Existing admin API pattern |

## Implementation Order

1. ControlServer.swift — HTTP control API on Ground Control
2. Wire into GroundControlApp (start on launch, add controlPort to config)
3. MCP server scaffold (package.json, tsconfig, index.ts)
4. Tool implementations (one per endpoint)
5. Test: register in Claude Code, call tools
6. Resources (optional follow-up)

## Open Questions

1. **HTTP library:** NWListener (Foundation, no deps) vs Hummingbird (async).
   Rec: NWListener — only ~10 endpoints, no middleware needed.
2. **Auth:** Loopback-only sufficient? Rec: yes, matches relay admin pattern.
3. **Log streaming:** SSE for direct HTTP, polling for MCP tools.
