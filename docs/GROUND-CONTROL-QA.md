# Ground Control QA Phase — MCP-Driven Verification

> Hand this doc to a fresh Claude session.
> No branch needed — this is a test-only phase, no code changes expected.

---

## Goal

Use the Ground Control MCP server to autonomously verify all Ground Control
features work end-to-end. The MCP server was built specifically so Claude Code
agents can control Ground Control programmatically — this phase validates that
loop.

---

## Prerequisites

### 1. Build the MCP server

```bash
cd mcp/ground-control-mcp
npm install
npm run build
```

### 2. Register in Claude Code

The MCP server should be registered in `.claude/settings.json`:
```json
{
  "mcpServers": {
    "ground-control": {
      "command": "node",
      "args": ["<repo>/mcp/ground-control-mcp/dist/index.js"]
    }
  }
}
```

### 3. Launch Ground Control

Ground Control.app must be running with ControlServer listening on
`127.0.0.1:9092` (default). Verify with:

```bash
curl -s http://127.0.0.1:9092/control/status | jq .
```

If using the bundled app:
```bash
cd macos && bash scripts/build-app.sh && open build/GroundControl.app
```

If using dev mode:
```bash
cd macos && swift run
```

---

## Test Plan

### Test 1: MCP Connection Smoke Test

**Tool:** `get_relay_status`
**Validates:** MCP server connects to ControlServer, returns valid JSON
**Pass criteria:** Returns relay state, tunnel state, uptime fields

### Test 2: Relay Lifecycle

**Steps:**
1. `get_relay_status` — note current state
2. `stop_relay` — should return success
3. `get_relay_status` — state should be `idle` or `stopping`
4. `start_relay` — should return success
5. `get_relay_status` — state should be `running`, uptime near 0

**Validates:** Full relay start/stop cycle via MCP

### Test 3: Relay Restart

**Steps:**
1. `get_relay_status` — note uptime
2. `restart_relay`
3. Wait 3-5 seconds
4. `get_relay_status` — uptime should have reset, state `running`

**Validates:** Restart triggers clean stop + start

### Test 4: Auto-Recovery (Exponential Backoff)

**Steps:**
1. `get_relay_status` — confirm running
2. Kill the relay process externally: `pkill -f "node.*server.js"`
3. Poll `get_relay_status` every 2s for 30s
4. Observe: state should transition through `.restarting(attempt: N)` → `running`
5. Check `restartCount` incremented

**Validates:** Auto-restart with backoff works, state machine is correct
**Note:** This test requires shell access alongside MCP tools

### Test 5: Tunnel Lifecycle

**Prerequisites:** Cloudflare tunnel must be configured in Ground Control
(token + tunnel name in config, `cloudflareEnabled: true`)

**Steps:**
1. `get_relay_status` — check tunnel state (should be `idle` or `running`)
2. `start_tunnel` — should succeed (or return error if not configured)
3. `get_relay_status` — tunnel state should be `running`
4. `stop_tunnel`
5. `get_relay_status` — tunnel state should be `idle`

**Validates:** Tunnel lifecycle independent of relay

### Test 6: Config Read

**Tool:** `get_config`
**Validates:** Returns all non-secret config fields
**Check:** port, hookPort, controlPort, authMode, logLevel, cloudflareEnabled,
autoStart, launchAtLogin all present

### Test 7: Config Update + Validation

**Steps:**
1. `get_config` — save original values
2. `update_config` with valid change (e.g., `logLevel: "debug"`)
3. `get_config` — verify change persisted
4. `update_config` with conflicting ports (e.g., `port: 9092, controlPort: 9092`)
5. Should return 400 with validation error details including which ports conflict
6. `get_config` — verify invalid change was NOT applied
7. `update_config` — restore original values

**Validates:** Config CRUD, copy-on-write validation, port conflict detection

### Test 8: Config controlPort Update

**Steps:**
1. `update_config` with `controlPort: 9093`
2. Response should include `requiresRestart: true`
3. `get_config` — verify controlPort is 9093 in persisted config
4. Restore: `update_config` with `controlPort: 9092`

**Validates:** controlPort is patchable, restart flag returned

### Test 9: Log Access

**Steps:**
1. `get_logs` with default params — should return recent entries
2. `get_logs` with `count: 5` — should return exactly 5 (or fewer if < 5 exist)
3. `get_logs` with `level: "error"` — should filter to errors only
4. `get_logs` with `count: 0` — should return 400 (invalid range)
5. `get_logs` with `count: -1` — should return 400

**Validates:** Log retrieval, filtering, count validation (1...1000 range)

### Test 10: Bundled App Detection

**Prerequisites:** App built with `build-app.sh`

**Steps:**
1. Launch bundled app
2. `get_relay_status` — relay should start using bundled Node + relay
3. `get_config` — verify config loads from expected location
4. Check logs for bundled-mode indicators

**Validates:** NodeBundleManager bundled-mode detection, self-contained launch

### Test 11: Login Items (Manual Verification)

**Steps:**
1. `get_config` — check `launchAtLogin` value
2. `update_config` with `launchAtLogin: true` (if exposed, otherwise manual)
3. Open System Settings → General → Login Items — verify Ground Control listed
4. Toggle off, verify removed

**Validates:** SMAppService integration, config ↔ system sync

---

## Reporting

For each test, report:
- **PASS** / **FAIL** / **SKIP** (with reason)
- Any unexpected behavior or error messages
- Suggestions for fixes if failures found

If issues are found, create a follow-up spec with the fixes needed.

---

## What Success Looks Like

- All MCP tools execute without errors
- Relay and tunnel lifecycle fully controllable via MCP
- Config changes round-trip correctly with validation
- Auto-restart recovers from crashes
- Bundled app works identically to dev mode
- The MCP → ControlServer → Ground Control loop is solid enough for
  autonomous agent workflows
