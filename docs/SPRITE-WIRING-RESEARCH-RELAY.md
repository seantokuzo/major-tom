# Sprite-Agent Wiring: Relay + SDK Research Gates

> Research date: 2026-04-16
> Branch: `docs/sprite-agent-wiring-spec`
> Researcher: Claude Opus 4.6

---

## Gate 1: Agent SDK Turn-Boundary Injection

### What We Found

#### Current subagent spawn/lifecycle flow

The relay spawns Claude sessions via the Agent SDK's `unstable_v2_createSession()` API. There are two parallel code paths:

1. **Direct adapter** (`relay/src/adapters/claude-cli.adapter.ts:169-283`) -- used in single-worker mode. Creates an `SDKSession` with hooks for `PreToolUse`, `SubagentStart`, `SubagentStop`.

2. **Fleet worker** (`relay/src/fleet/worker.ts:146-310`) -- used in multi-worker mode (child process). Structurally identical to the adapter, creates its own `SDKSession` with the same hooks.

Both paths use `sdkSession.send(text)` to send user messages and `sdkSession.stream()` to consume responses.

#### How turns work in the SDK

The SDK's `stream()` method is an `AsyncGenerator<SDKMessage, void>` (sdk.d.ts:2695). The existing `consumeStream()` function at `claude-cli.adapter.ts:431-472` and `worker.ts:485-522` reveals the turn model:

```typescript
// The SDK's stream() generator exits after each turn's `result` message.
// We must loop and call stream() again to consume subsequent turns.
while (!signal.aborted) {
  for await (const message of sdkSession.stream()) {
    handleSdkMessage(sessionId, message);
  }
  // Turn complete (stream yielded `result` and returned).
  // Loop back to call stream() again for the next turn.
}
```

The `stream()` generator yields messages until a `result` message (type `SDKResultMessage`), then **returns** (the inner for-await-of loop completes). The outer while-loop then calls `stream()` again for the next turn. This is the definitive "turn boundary" -- the point between one `stream()` completing and the next `send()` call.

#### Turn boundary signals available

| Signal | When | SDK Support | File Reference |
|--------|------|-------------|----------------|
| `result` message | End of each turn (after all tool calls complete and Claude responds) | `SDKResultSuccess \| SDKResultError` (sdk.d.ts:2656) | `handleResultMessage()` at adapter:608, worker:662 |
| `SubagentStop` hook | When a subagent finishes | First-class hook (sdk.d.ts:4463-4465) | adapter:257-278, worker:250-270 |
| `TaskCompleted` hook | When a Task tool completes | First-class hook (sdk.d.ts:4496-4503) | **Not currently wired** |
| `PostToolUse` hook | After any tool execution completes | First-class hook (sdk.d.ts:1621-1627) | **Not currently wired** |
| `message_stop` stream event | When assistant message is complete | Via `stream_event.event.type === 'message_stop'` | **Not currently handled** |

#### Can we inject a user message at turn boundary?

**YES.** The key insight is in the `consumeStream` loop structure:

```
stream() yields messages -> result -> stream() returns
                                         |
                                    [TURN BOUNDARY - this is where we inject]
                                         |
                                    stream() called again for next turn
```

Between `stream()` returning and the next `stream()` call, we can call `sdkSession.send(text)`. The SDK's `send()` method (sdk.d.ts:2693) accepts `string | SDKUserMessage`. This is the natural injection point.

However, there is a critical subtlety: **subagents do NOT have their own `SDKSession` handle.** The relay does not create separate SDK sessions per subagent. A subagent is spawned by Claude's internal `Task` tool within the orchestrator's session. The relay sees:
- `PreToolUse(Task)` hook -> `SubagentStart` hook -> subagent runs -> `SubagentStop` hook -> `PostToolUse(Task)` / `TaskCompleted` hook

The relay has **no direct communication channel to a subagent.** The current `sendAgentMessage()` at `worker.ts:351-361` just wraps the text and sends it to the **main session**:

```typescript
const wrappedText = `[Regarding agent ${agentId}]: ${text}`;
await entry.sdkSession.send(wrappedText);
```

This sends a user-turn to the **orchestrator**, not the subagent. The orchestrator may or may not relay it.

#### The real mechanism for /btw

Since we cannot inject directly into a subagent's conversation, the spec's turn-boundary injection must work differently than initially conceived. Here are the options:

**Option A: Orchestrator relay (current behavior, enhanced)**
- Send `/btw` to the orchestrator session with the constraint framing
- The orchestrator itself decides whether/how to relay to the subagent
- Turn boundary = when the orchestrator's `stream()` returns (main session result)
- Problem: The orchestrator might not relay the message, or might change its behavior

**Option B: `PostToolUse` hook with `additionalContext` (recommended)**
- Register a `PostToolUse` hook with matcher `'Task'` (or any tool)
- When a subagent completes a tool call, the `PostToolUse` hook fires with `tool_use_id`
- The hook can return `{ additionalContext: "User observation: ..." }` which gets appended to the tool result before Claude sees it
- This injects text at the subagent's tool-call boundary without requiring a separate send()
- The SDK already supports this: `PostToolUseHookSpecificOutput.additionalContext` (sdk.d.ts:1629-1633)

**Option C: Queued send() between stream() turns**
- Queue the /btw message on the relay
- In the consumeStream loop, after `stream()` returns (turn boundary), check the queue
- If a message is pending, call `sdkSession.send(constrainedMessage)` before the next `stream()`
- This sends to the main session, but with careful constraint framing

### Feasibility Assessment: YELLOW

The spec's vision of "inject at subagent turn boundary" is not directly possible because the relay has no handle to the subagent's conversation. The SDK does not expose subagent sessions. However, two viable workarounds exist:

1. **PostToolUse hook with additionalContext** -- injects at tool-call boundaries within the current session. This is clean but only works when tool calls happen (not between text turns).

2. **Queued send() at orchestrator turn boundary** -- injects as a new user turn to the main session. The constraint framing tells Claude to relay to the specific subagent.

### Recommended Approach

**Hybrid: PostToolUse `additionalContext` for in-flight subagents + queued `send()` for between-turn injection.**

1. Register a `PostToolUse` hook (any tool, not just Task) that checks the /btw queue for the owning subagent. If a message is queued, return `{ additionalContext: constrainedBtwMessage }`. This piggybacks on tool results the subagent already sees.

2. For between-turn injection (when `stream()` returns), check the queue and call `send()` with the constraint framing directed at the specific subagent.

3. Add `TaskCompleted` hook to detect subagent completion and drop undelivered messages (scenario 4 in the spec).

### Open Questions / Risks

- **PostToolUse fires on ALL tool calls, including subagent tool calls?** Need to verify that hooks fire for tools used within subagents, not just the orchestrator. The `parent_tool_use_id` field on stream events suggests subagent tool events ARE visible, but hook-level visibility needs testing.
- **Can `additionalContext` in PostToolUse actually influence a subagent?** It appends to the tool result the model sees. If the hook fires for a subagent's tool call, the subagent would see it. If it only fires at the orchestrator level, Option B won't work for subagent injection.
- **Race condition**: If `stream()` returns and we inject via `send()`, the orchestrator gets a new user turn. It might not relay to the subagent if the subagent already completed. The `SubagentStop` hook is the guard here.
- **Constraint framing effectiveness**: The spec relies on Claude obeying "do NOT change your task." This is prompt engineering, not a hard guarantee.

---

## Gate 2: Protocol Message Types

### What We Found

#### Existing message conventions

All protocol messages live in `relay/src/protocol/messages.ts` (1233 lines). Key conventions:

1. **Discriminated union on `type` field** -- every message has `type: string` as the routing key
2. **Naming**: dot-separated namespace (`agent.spawn`, `session.start`, `fs.ls`, `git.status`)
3. **Request/response pairs**: client sends `type: 'X'`, server responds with `type: 'X.response'`
4. **Server-initiated events**: no `.response` suffix (`agent.spawn`, `agent.dismissed`)
5. **All messages carry `seq?: number`** via the `ServerMessage` type wrapper (messages.ts:1168)
6. **Client union**: `ClientMessage` (messages.ts:470-519), Server union: `ServerMessageBase` (messages.ts:1096-1160)
7. **IDs**: UUID v4, field names like `sessionId`, `agentId`, `requestId`

#### Existing agent messages for reference

```typescript
// Client -> Server
interface AgentMessageMessage {
  type: 'agent.message';
  sessionId: string;
  agentId: string;
  text: string;
}

// Server -> Client (existing)
interface AgentSpawnMessage {
  type: 'agent.spawn';
  agentId: string;
  parentId?: string;
  task: string;
  role: string;
}
```

### Proposed Schemas

Following existing conventions (dot-separated namespace, `sessionId` on session-scoped messages):

```typescript
// ── Sprite ↔ Agent Wiring Messages ──────────────────────────

// Server → Client: a sprite has been linked to a subagent
interface SpriteLinkMessage {
  type: 'sprite.link';
  sessionId: string;
  spriteHandle: string;         // CharacterType or unique sprite instance ID
  agentId: string;              // subagent's agent_id from SubagentStart
  role: string;                 // classified role (researcher, architect, etc.)
  characterType: string;        // resolved CharacterType for the sprite
  deskIndex?: number;           // assigned desk position (0-5, or undefined for overflow)
}

// Server → Client: sprite unlinked (subagent completed/crashed)
interface SpriteUnlinkMessage {
  type: 'sprite.unlink';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  reason: 'completed' | 'failed' | 'dismissed' | 'session_ended';
}

// Client → Server: user sends /btw message to a sprite's linked subagent
interface SpriteMessageMessage {
  type: 'sprite.message';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  text: string;
  messageId: string;            // client-generated UUID for tracking
}

// Server → Client: /btw response from the subagent
interface SpriteResponseMessage {
  type: 'sprite.response';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  messageId: string;            // correlates to the sprite.message
  text: string;                 // the subagent's constrained response
  status: 'delivered' | 'dropped';  // dropped = subagent completed before delivery
  dropReason?: string;          // only set when status === 'dropped'
}

// Server → Client: full sprite-subagent mapping state (reconnect/sync)
interface SpriteStateMessage {
  type: 'sprite.state';
  sessionId: string;
  mappings: Array<{
    spriteHandle: string;
    agentId: string;
    role: string;
    characterType: string;
    deskIndex?: number;
    pendingBtw?: {              // if a /btw is in-flight
      messageId: string;
      text: string;
      status: 'queued' | 'injected' | 'awaiting_response';
    };
  }>;
  roleBindings: Record<string, string>;  // role -> CharacterType (session-stable)
}
```

### Feasibility Assessment: GREEN

These message types follow existing conventions perfectly. The `sprite.*` namespace is clean, no conflicts. Adding them requires:
1. Interface definitions in `messages.ts`
2. Adding to `ClientMessage` union (for `sprite.message`)
3. Adding to `ServerMessageBase` union (for `sprite.link`, `sprite.unlink`, `sprite.response`, `sprite.state`)
4. Case handler in `ws.ts` message switch
5. IPC messages in `ipc-messages.ts` for fleet worker relay

### Recommended Approach

Add all five message types to `messages.ts`. Wire `sprite.message` handling into the WS route's message switch at `ws.ts` alongside the existing `agent.message` case (line 818). The server-initiated messages (`sprite.link`, `sprite.unlink`, `sprite.state`) are emitted from the fleet manager's agent-lifecycle handler (ws.ts:1689).

### Open Questions

- **`spriteHandle` identity**: Should this be the CharacterType string (e.g., `"frontendDev"`) or a unique per-instance UUID? The clone-not-consume model means multiple sprites of the same CharacterType can exist, so we need per-instance IDs. Recommend: relay generates a UUID `spriteHandle` on link, CharacterType is a separate field.
- **`sprite.state` size**: For reconnect, we send the full mapping. With 6 max agents, this is tiny (~1-2 KB).
- **Event buffering**: Should `sprite.link`/`sprite.unlink` be buffered in the `EventBufferManager` for replay? Yes -- they're session-scoped events and should be replayable on reconnect.

---

## Gate 3: Relay Message Queue Design

### What We Found

#### Current session/adapter architecture

The relay has two modes:

1. **Single-worker** (`ClaudeCliAdapter` at `adapters/claude-cli.adapter.ts`) -- one process, in-memory sessions map.
2. **Fleet mode** (`FleetManager` at `fleet/fleet-manager.ts` + `fleet/worker.ts`) -- parent process forks child workers, communicates via IPC.

In both modes:
- Each SDK session has one `consumeStream` loop running
- `sdkSession.send()` is the only way to inject user input
- The stream loop structure is: `while -> for-await stream() -> handle result -> loop`

The current `sendAgentMessage()` (worker.ts:351-361, adapter:333-347) just wraps text and sends to the main session. There is no queue, no turn boundary detection, no waiting.

#### The approval queue pattern (reusable)

The existing `ApprovalQueue` at `relay/src/hooks/approval-queue.ts` implements a promise-based wait pattern:

```typescript
waitForDecision(requestId, toolName, description, details, signal): Promise<ApprovalDecision>
```

This creates a pending promise that resolves when `resolve(requestId, decision)` is called. This same pattern can be adapted for the /btw queue.

### Proposed Queue Structure

```typescript
interface BtwQueueEntry {
  messageId: string;           // from sprite.message
  spriteHandle: string;
  agentId: string;
  text: string;
  constrainedText: string;     // pre-built injection text with system framing
  queuedAt: number;
  status: 'queued' | 'injected' | 'awaiting_response' | 'responded' | 'dropped';
  responsePromise?: {
    resolve: (response: string) => void;
    reject: (reason: Error) => void;
  };
}

class BtwQueue {
  // One entry per agentId (spec: only 1 message at a time per sprite)
  private pending = new Map<string, BtwQueueEntry>();

  enqueue(entry: Omit<BtwQueueEntry, 'status' | 'queuedAt'>): void;
  
  // Called from consumeStream loop at turn boundary
  getPendingForSession(): BtwQueueEntry[];
  
  // Called when subagent completes before delivery
  dropForAgent(agentId: string, reason: string): BtwQueueEntry | undefined;
  
  // Called when response is extracted from stream
  resolveResponse(agentId: string, response: string): void;
  
  // Called when agent is dismissed
  clearAgent(agentId: string): void;
}
```

### Injection Points in the Stream Loop

The queue integrates into the existing `consumeStream()` at three points:

```typescript
async function consumeStream(sessionId, sdkSession, signal) {
  while (!signal.aborted) {
    for await (const message of sdkSession.stream()) {
      handleSdkMessage(sessionId, message);
      
      // INJECTION POINT 1: PostToolUse hook
      // (registered at session creation, not in this loop)
      // If a /btw is queued for the subagent that owns this tool call,
      // the PostToolUse hook returns additionalContext
    }
    
    // INJECTION POINT 2: Between turns
    // stream() returned -> turn boundary -> check queue
    const pending = btwQueue.getPendingForSession();
    if (pending.length > 0) {
      const entry = pending[0]; // one at a time per spec
      entry.status = 'injected';
      await sdkSession.send(entry.constrainedText);
      entry.status = 'awaiting_response';
      // The next stream() iteration will carry the response
    }
    
    // INJECTION POINT 3: SubagentStop hook
    // (registered at session creation)
    // Drops queued messages for the completed agent
  }
}
```

### Response Extraction

When the subagent responds to a /btw, the response appears in the stream as an `assistant` message or `stream_event` text deltas. The challenge is **correlating the response to the /btw message**.

Approach: After injecting the /btw via `send()`, the next text response from the stream is the /btw response. We track `btwEntry.status === 'awaiting_response'` and capture the next text output as the response, then emit `sprite.response` to the client.

This is imprecise if the orchestrator does something else between injection and response. The constraint framing ("respond in 1-2 sentences about your current progress") should make the response immediate and identifiable.

### Fleet Mode (worker process)

In fleet mode, the queue lives in the worker process (same process as the SDK session). New IPC messages needed:

```typescript
// Parent -> Child: enqueue a /btw
interface IpcSpriteMessage {
  type: 'ipc:sprite.message';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  text: string;
  messageId: string;
}

// Child -> Parent: /btw response
interface IpcSpriteResponse {
  type: 'ipc:sprite.response';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  messageId: string;
  text: string;
  status: 'delivered' | 'dropped';
  dropReason?: string;
}
```

### What Happens if Subagent Completes Before Delivery

Scenario 4 from the spec. The `SubagentStop` hook fires, which:
1. Checks the queue for pending entries with that `agentId`
2. If found, sets status to `dropped`
3. Emits `sprite.response` with `status: 'dropped'` and `dropReason: 'completed before delivery'`

### Feasibility Assessment: YELLOW

The queue design is straightforward. The tricky part is response correlation -- knowing which stream output is the /btw response vs. normal Claude output. This requires either:
- A unique marker in the injection text that the response echoes (fragile)
- Treating the first text response after injection as the /btw response (simple, imprecise)
- Using `parent_tool_use_id` on stream events to identify subagent output (most robust if available)

### Recommended Approach

1. Build `BtwQueue` class alongside existing `ApprovalQueue` in `relay/src/hooks/`
2. One queue per session (scoped to the worker or adapter's session entry)
3. Inject at the `consumeStream` turn boundary (between `stream()` returns)
4. Use `SubagentStop` hook for cleanup of undelivered messages
5. For response detection, use a state machine: after injection, the next complete assistant text response from the stream is captured as the /btw response
6. Add IPC messages for fleet mode relay

### Open Questions / Risks

- **Response extraction accuracy**: If Claude generates multiple messages before the /btw response, we might capture the wrong text. Mitigation: The constraint framing tells Claude to respond immediately in 1-2 sentences.
- **Concurrent subagents**: If two subagents are active, /btw messages to different agents can only be injected one at a time (the spec enforces 1-at-a-time per sprite, but different sprites could be messaged simultaneously). The queue should serialize injection to avoid interleaving.
- **Stream events vs. assistant messages**: The response might come as `stream_event` deltas (real-time) or a complete `assistant` message. We need to handle both paths.

---

## Gate 4: Mapping Persistence Format

### What We Found

#### Existing persistence infrastructure

Session data is already persisted to `~/.major-tom/sessions/` via `SessionPersistence` at `relay/src/sessions/session-persistence.ts`:

- Directory: `~/.major-tom/sessions/`
- Format: JSON files, one per session (`{sessionId}.json`)
- Features: debounced writes (2s), immediate save for shutdown, file listing, delete
- Session ID sanitization (path traversal prevention) at line 44
- The `SessionPersistence` class is injected into `SessionManager` at construction

#### Session lifecycle hooks

| Event | Code Location | Hook |
|-------|--------------|------|
| Session created | `session-manager.ts:38` | `create()` returns new `Session` |
| Session closed | `session-manager.ts:100` | `close()` sets status to `closed` |
| Session destroyed | `session-manager.ts:108` | `destroy()` removes from map |
| Graceful shutdown | `session-persistence.ts:129` | `saveAllImmediate()` flushes pending writes |
| Persistence disposal | `session-persistence.ts:144` | `dispose()` cancels all timers |

The `ws.ts` route handles session lifecycle at the fleet manager level (line 1689+), including agent spawn/dismiss events. It's also where session end cleanup happens.

#### Existing `AgentTracker` state

The `AgentTracker` at `relay/src/events/agent-tracker.ts` holds in-memory `AgentState` objects:

```typescript
interface AgentState {
  agentId: string;
  parentId?: string;
  role: string;
  task: string;
  status: 'spawned' | 'working' | 'idle' | 'complete' | 'dismissed';
  spawnedAt: string;
  updatedAt: string;
}
```

This is a **global singleton** (line 89: `export const agentTracker = new AgentTracker()`). It does not track which session an agent belongs to. Agent dismiss at line 82 deletes the entry from the map.

### Proposed Persistence Format

#### File location

`~/.major-tom/sprite-mappings/{sessionId}.json`

Separate directory from session transcripts to keep concerns isolated and simplify cleanup.

#### File structure

```json
{
  "version": 1,
  "sessionId": "uuid-here",
  "updatedAt": "2026-04-16T12:00:00.000Z",
  "roleBindings": {
    "researcher": "spaceSuit_blue",
    "frontend": "spaceSuit_pink",
    "backend": "spaceSuit_green"
  },
  "mappings": [
    {
      "spriteHandle": "uuid-sprite-1",
      "agentId": "uuid-agent-1",
      "role": "researcher",
      "characterType": "spaceSuit_blue",
      "deskIndex": 0,
      "linkedAt": "2026-04-16T12:00:00.000Z",
      "status": "active"
    },
    {
      "spriteHandle": "uuid-sprite-2",
      "agentId": "uuid-agent-2",
      "role": "frontend",
      "characterType": "spaceSuit_pink",
      "deskIndex": 1,
      "linkedAt": "2026-04-16T12:01:00.000Z",
      "status": "active"
    }
  ],
  "nextDeskIndex": 2
}
```

#### `SpriteMappingPersistence` class

Follows the same pattern as `SessionPersistence`:

```typescript
class SpriteMappingPersistence {
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly dir = join(homedir(), '.major-tom', 'sprite-mappings');

  save(sessionId: string, data: SpriteMappingFile): void;       // debounced 2s
  saveImmediate(sessionId: string, data: SpriteMappingFile): Promise<void>;
  load(sessionId: string): Promise<SpriteMappingFile | null>;
  delete(sessionId: string): Promise<void>;
  deleteAll(): Promise<void>;                                    // graceful shutdown
  listStale(): Promise<string[]>;                                // cold boot cleanup
  dispose(): void;
}
```

### Cleanup Lifecycle Integration

| Spec Event | Implementation |
|-----------|----------------|
| Relay graceful shutdown | `SpriteMappingPersistence.deleteAll()` in the app's `onClose` handler at `app.ts` |
| Terminal session ended | `SpriteMappingPersistence.delete(sessionId)` when `SessionManager.destroy()` is called |
| Background/disconnect | Keep file (30-min grace already exists in PTY adapter) |
| Grace period expires | PTY adapter's grace timer fires -> kills session -> triggers delete |
| Cold boot after crash | On startup: `listStale()` cross-references with live sessions, deletes orphans |

#### Where to hook into existing lifecycle

1. **Session destroy** (`session-manager.ts:108`): Add a call to delete the sprite mapping file. Or better -- listen to the `agent.dismissed` event on the eventBus (event-bus.ts) to remove individual mappings, and session destroy to delete the file.

2. **App shutdown** (`app.ts`): The app already has a shutdown handler. Add `spriteMappingPersistence.deleteAll()` alongside the existing `sessionPersistence` flush.

3. **Cold boot** (`app.ts` startup): After `sessionManager.restoreFromDisk()`, call `spriteMappingPersistence.listStale()` and cross-reference against live session IDs.

4. **Agent lifecycle events** (`ws.ts:1689`): The `fleetManager.on('agent-lifecycle')` handler already processes spawn/dismiss. Add mapping persistence updates here:
   - `spawn` -> create mapping entry, save
   - `dismissed` -> remove mapping entry, save
   
### Feasibility Assessment: GREEN

The persistence infrastructure is well-established. The sprite mapping files are small (< 1KB even with 6 agents). The cleanup lifecycle hooks are clearly identified and already exist in the codebase. This is a straightforward extension of the existing pattern.

### Recommended Approach

1. Create `SpriteMappingPersistence` class mirroring `SessionPersistence`
2. Store files at `~/.major-tom/sprite-mappings/{sessionId}.json`
3. Use debounced writes (2s) like session persistence
4. Hook cleanup into: session destroy, app shutdown, agent dismiss, cold boot
5. The `ws.ts` agent-lifecycle handler is the single point where mapping changes are triggered
6. On iOS reconnect, relay sends `sprite.state` message reconstructed from disk file

### Open Questions

- **In-memory vs. disk**: During normal operation, the mapping is held in memory (either in the fleet worker or the adapter). Disk is only for crash recovery and reconnect. Should we also keep an in-memory mirror in the parent process (for fast `sprite.state` responses), or always delegate to the worker?
  - Recommendation: Keep in-memory in the worker (or adapter), persist to disk on change. Parent process delegates `sprite.state` requests to the worker via IPC.
- **Client-authoritative fallback**: The spec says iOS can re-send its mappings if relay loses state. This requires a `sprite.state` message from client -> server (not currently proposed). Add a `sprite.syncFromClient` message type?
- **Concurrent writes**: Two rapid agent spawns could race on debounced writes. The debounce timer resets, so the second write includes both changes. This is correct behavior.

---

## Summary

| Gate | Assessment | Key Finding | Blocking? |
|------|-----------|-------------|-----------|
| 1. Turn-boundary injection | YELLOW | SDK has no direct subagent session handle. Must inject via orchestrator's `send()` or `PostToolUse` `additionalContext`. Both are viable workarounds. | No -- workarounds exist |
| 2. Protocol messages | GREEN | Clean `sprite.*` namespace, follows existing conventions exactly. 5 new message types. | No |
| 3. Message queue design | YELLOW | Queue is simple but response correlation is imprecise. State machine approach works if constraint framing is effective. | No -- design is solid, needs spike for response extraction |
| 4. Mapping persistence | GREEN | Mirrors existing `SessionPersistence` pattern. All cleanup hooks are identified. | No |

### Recommended Technical Spike

Before Wave 4 implementation, build a minimal spike to validate:

1. **PostToolUse hook fires for subagent tool calls** (not just orchestrator). If it does, `additionalContext` injection is the cleanest path.
2. **Response extraction after `send()` injection** -- send a constrained /btw message via `send()` and verify the response can be reliably captured from the stream.
3. **Constraint framing effectiveness** -- does Claude reliably give a 1-2 sentence status response without changing its task?

These three tests determine whether the /btw mechanism works as designed or needs a different approach.

### Architecture Decision: Where the Queue Lives

The `BtwQueue` should live in the same process as the `SDKSession`:
- **Single-worker mode**: In the `ClaudeCliAdapter`, alongside the `SdkSessionEntry`
- **Fleet mode**: In the worker process, alongside the `WorkerSession`

The parent process (ws.ts) routes `sprite.message` to the correct worker via IPC, just like it routes `agent.message` today.
