# Claude Code Stream-JSON Event Reference

> Complete catalog of events available to Major Tom via `--output-format stream-json --verbose`.
> Use this when planning relay event parsing and PWA/iOS rendering.

---

## How We Get Events

| Channel | Flag | What It Gives Us |
|---------|------|-----------------|
| **Stream-JSON stdout** | `--output-format stream-json --verbose` | All events below |
| **Partial streaming** | `--include-partial-messages` | Raw API deltas for real-time text rendering |
| **Permission prompts** | `--permission-prompt-tool stdio` | Tool approval requests via MCP stdin/stdout |
| **Hooks** | Settings-configured scripts | PreToolUse, PostToolUse, SubagentStart/Stop, etc. |

---

## Stream-JSON Output Events

### System Events (`type: "system"`)

#### `system/init` — Session startup
```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "uuid",
  "cwd": "/path",
  "model": "claude-opus-4-6",
  "tools": ["Bash", "Edit", "Read", ...],
  "mcp_servers": [{"name": "github", "status": "connected"}],
  "permissionMode": "default",
  "claude_code_version": "2.1.78",
  "agents": ["general-purpose", "Explore", "Plan", ...],
  "skills": ["update-config", "simplify", ...],
  "plugins": []
}
```
**Use:** Show session info, available tools, connected MCPs.

#### `system/api_retry` — API retry in progress
```json
{
  "type": "system",
  "subtype": "api_retry",
  "attempt": 1,
  "max_retries": 3,
  "retry_delay_ms": 500,
  "error_status": 429,
  "error": "rate_limit|server_error|authentication_failed|billing_error|unknown"
}
```
**Use:** Show retry spinner, warn on auth/billing errors.

#### `system/status` — Status change
```json
{
  "type": "system",
  "subtype": "status",
  "status": "compacting|null",
  "permissionMode": "default"
}
```
**Use:** Show "compacting context..." indicator.

#### `system/compact_boundary` — Context compaction happened
```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "compact_metadata": { "trigger": "manual|auto", "pre_tokens": 12000 }
}
```
**Use:** Note in chat that context was compacted.

#### `system/hook_started` / `system/hook_progress` / `system/hook_response` — Hook lifecycle
```json
{ "type": "system", "subtype": "hook_started", "hook_id": "str", "hook_name": "str", "hook_event": "PreToolUse" }
{ "type": "system", "subtype": "hook_progress", "hook_id": "str", "stdout": "str", "stderr": "str" }
{ "type": "system", "subtype": "hook_response", "hook_id": "str", "exit_code": 0, "outcome": "success|error|cancelled" }
```
**Use:** Track hook execution (our own hooks will show up here!).

#### `system/task_started` / `system/task_progress` / `system/task_notification` — Background tasks (subagents!)
```json
{ "type": "system", "subtype": "task_started", "task_id": "str", "tool_use_id": "str", "description": "str" }
{ "type": "system", "subtype": "task_progress", "task_id": "str", "usage": { "total_tokens": 5000, "tool_uses": 3, "duration_ms": 2000 } }
{ "type": "system", "subtype": "task_notification", "task_id": "str", "status": "completed|failed|stopped", "summary": "str" }
```
**Use:** CRITICAL for gamified office — agent.spawn/working/complete events!

---

### Assistant Messages (`type: "assistant"`)

Complete assistant response with all content blocks:
```json
{
  "type": "assistant",
  "session_id": "uuid",
  "parent_tool_use_id": "str|null",
  "message": {
    "id": "msg_xxx",
    "model": "claude-opus-4-6",
    "content": [
      { "type": "text", "text": "Here's what I found..." },
      { "type": "tool_use", "id": "toolu_xxx", "name": "Read", "input": { "file_path": "/src/main.ts" } }
    ],
    "stop_reason": "end_turn|tool_use|max_tokens",
    "usage": { "input_tokens": 100, "output_tokens": 50 }
  }
}
```
**Use:** Display text responses, detect tool calls. `parent_tool_use_id` tracks subagent hierarchy!

---

### Streaming Deltas (`type: "stream_event"`) — requires `--include-partial-messages`

Raw Claude API streaming events for real-time rendering:

```json
{
  "type": "stream_event",
  "parent_tool_use_id": "str|null",
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": { "type": "text_delta", "text": "incr" }
  }
}
```

**Event subtypes in `event.type`:**
- `message_start` — New message begins
- `content_block_start` — New content block (text or tool_use)
- `content_block_delta` — Incremental text (`text_delta`) or tool input (`input_json_delta`)
- `content_block_stop` — Block done
- `message_delta` — Message-level update (stop_reason, usage)
- `message_stop` — Message complete

**Use:** Real-time text streaming in chat. Tool input preview as it's typed.

---

### User Messages (`type: "user"`)

```json
{
  "type": "user",
  "session_id": "uuid",
  "parent_tool_use_id": "str|null",
  "message": {
    "role": "user",
    "content": "string or [{type: 'tool_result', ...}]"
  },
  "isSynthetic": false
}
```
**Use:** Confirm prompt was received. Tool results show what happened.

---

### Result (`type: "result"`)

Final session/prompt result:
```json
{
  "type": "result",
  "subtype": "success|error_max_turns|error_during_execution|error_max_budget_usd",
  "session_id": "uuid",
  "duration_ms": 45000,
  "duration_api_ms": 30000,
  "num_turns": 5,
  "result": "final text output",
  "total_cost_usd": 0.012,
  "usage": { "input_tokens": 2000, "output_tokens": 500 },
  "permission_denials": [{ "tool_name": "Bash", "tool_input": { "command": "rm -rf /" } }]
}
```
**Use:** Show cost, duration, denied permissions. Detect errors.

---

### Tool Progress (`type: "tool_progress"`)

```json
{
  "type": "tool_progress",
  "tool_use_id": "str",
  "tool_name": "Bash|Read|Edit|WebSearch|...",
  "parent_tool_use_id": "str|null",
  "elapsed_time_seconds": 2.5
}
```
**Use:** Show tool execution timer, which tool is running.

---

### Rate Limit (`type: "rate_limit_event"`)

```json
{
  "type": "rate_limit_event",
  "rate_limit_info": {
    "status": "allowed|allowed_warning|rejected",
    "resetsAt": 1710000000,
    "utilization": 0.85
  }
}
```
**Use:** Show rate limit warning/countdown.

---

### Auth Status (`type: "auth_status"`)

```json
{
  "type": "auth_status",
  "isAuthenticating": true,
  "output": ["log line"],
  "error": "string|null"
}
```

---

### Prompt Suggestion (`type: "prompt_suggestion"`)

```json
{
  "type": "prompt_suggestion",
  "suggestion": "What should I do next?"
}
```
**Use:** Show suggested follow-ups in chat UI.

---

## Hook Events (configured in settings.json)

These fire as scripts/commands, separate from stream-json:

| Hook Event | When | Key Fields |
|------------|------|-----------|
| `PreToolUse` | Before tool execution | `tool_name`, `tool_input` |
| `PostToolUse` | After tool execution | `tool_name`, `tool_input`, `tool_result` |
| `SubagentStart` | Subagent spawned | `agent_id`, `agent_type` |
| `SubagentStop` | Subagent finished | `agent_id`, `agent_type`, `last_assistant_message` |
| `Stop` | Main agent stopping | `reason` |
| `SessionStart` | Session begins | (common fields) |
| `UserPromptSubmit` | User sends prompt | `user_prompt` |
| `PermissionRequest` | Tool needs approval | `tool_name`, `tool_input`, `permission_suggestions` |
| `WorktreeCreate` | Git worktree made | (worktree fields) |
| `WorktreeRemove` | Git worktree removed | (worktree fields) |

All hooks receive common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`.

---

## Permission Flow Options

### Option A: `--permission-prompt-tool stdio` (Recommended)
Claude sends permission requests as MCP tool calls through stdin/stdout. Our relay acts as the MCP tool, receives the request, forwards to PWA, waits for response.

### Option B: Hook scripts
`PreToolUse` hooks POST to our hook HTTP server, which blocks until PWA responds. Already implemented but requires settings.json configuration per-project.

### Option C: `--dangerously-skip-permissions`
Skip all permissions. Fast but no approval UI. Good for trusted automated tasks.

---

## Mapping Events → Gamified Office (Phase 3)

| Stream Event | Office Action |
|-------------|---------------|
| `system/init` | Office opens, lights turn on |
| `system/task_started` | New character spawns, walks to desk |
| `system/task_progress` | Character typing animation, progress bar |
| `system/task_notification (completed)` | Character stands, stretches, walks to break room |
| `system/task_notification (failed)` | Character slumps, error icon |
| `assistant` (with tool_use) | Character picks up tool (wrench for Bash, pencil for Edit, magnifying glass for Read) |
| `tool_progress` | Tool animation plays, timer shows |
| `stream_event/content_block_delta` | Speech bubble with streaming text |
| `rate_limit_event (warning)` | Office lights flicker |
| `rate_limit_event (rejected)` | Power outage animation, everyone stops |
| `system/compact_boundary` | Filing cabinet animation, papers fly |
| `prompt_suggestion` | Character raises hand with thought bubble |

---

## Key Architecture Notes

1. **`parent_tool_use_id`** — Present on every message. This is how we track which subagent owns which output. `null` = main orchestrator. Non-null = subagent spawned by that tool_use.

2. **`--include-partial-messages`** — Required for real-time streaming. Without it, we only get complete messages (bad UX for long responses).

3. **Stream-json captures hook execution** — When our hooks fire, we see `system/hook_started` → `system/hook_progress` → `system/hook_response` in the stream. Useful for debugging but also means we don't strictly need both channels.

4. **Task events ARE subagent events** — `system/task_started` fires when Claude spawns a background agent (subagent). This is our agent.spawn trigger.

---

_Last updated: 2026-03-18_
