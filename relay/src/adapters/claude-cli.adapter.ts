import { EventEmitter } from 'node:events';
import {
  unstable_v2_createSession,
  type SDKSession,
  type SDKMessage,
  type PermissionResult,
  type PreToolUseHookInput,
  type SubagentStartHookInput,
  type SubagentStopHookInput,
} from '@anthropic-ai/claude-agent-sdk';
import { Session } from '../sessions/session.js';
import { SessionManager } from '../sessions/session-manager.js';
import { ApprovalQueue } from '../hooks/approval-queue.js';
import { PermissionFilter } from '../permissions/permission-filter.js';
import type { AutoAllowReason } from '../permissions/permission-filter.js';
import type {
  IAdapter,
  ApprovalRequest,
  ToolInfo,
  ToolResult,
  AgentEvent,
  SessionResult,
} from './adapter.interface.js';
import { agentTracker } from '../events/agent-tracker.js';
import { logger } from '../utils/logger.js';
import { BtwQueue, type BtwQueueEventMap } from '../sprites/btw-queue.js';

// ── Claude Code SDK Adapter ─────────────────────────────────
// Uses the official Agent SDK's v2 session API.
// The SDK handles the WebSocket bridge + permission protocol internally.
// We get a simple `canUseTool` callback for approval and an async
// generator for streaming events.

/**
 * Phase 13 Wave 3 — pending `PreToolUse(Task)` → `SubagentStart` correlation.
 *
 * Mirror of the worker-side `PENDING_TASK_TTL_MS` / `PendingTaskEntry`
 * pattern in `relay/src/fleet/worker.ts`. Kept in sync so this adapter
 * (the reference implementation for a future VSCode chat participant
 * phase) stays structurally identical to the live worker path.
 *
 * `SubagentStartHookInput` carries only `agent_id` + `agent_type` —
 * neither the task description nor a correlating tool_use_id. The
 * description lives in the prior `PreToolUse` firing on the `Task`
 * tool. Stash those entries keyed by `tool_use_id` and drain the
 * oldest on each subsequent `SubagentStart`. Lazy GC on every
 * SubagentStart (TTL 30s) so a crashed subagent spawn can't leak
 * entries. 30s is conservative — in practice the gap is milliseconds.
 */
const PENDING_TASK_TTL_MS = 30_000;

interface PendingTaskEntry {
  description: string;
  prompt: string;
  enqueuedAt: number;
}

interface SdkSessionEntry {
  session: Session;
  sdkSession: SDKSession;
  streamAbort: AbortController;
  /** True if we received streaming text deltas — prevents double-emit from assistant message */
  hasStreamedText: boolean;
  /** True while the stream consumer loop is running */
  streamAlive: boolean;
  /** Phase 13 Wave 3 — correlate PreToolUse(Task) → SubagentStart by arrival order. */
  pendingTaskByToolUseId: Map<string, PendingTaskEntry>;
}

/**
 * Drain expired entries from a pending-task map. Called on every
 * `PreToolUse(Task)` insert AND every `SubagentStart` so expired
 * entries can't accumulate when subagent spawns fail/are denied.
 */
function gcPendingTasks(map: Map<string, PendingTaskEntry>): void {
  const now = Date.now();
  for (const [key, value] of map) {
    if (now - value.enqueuedAt > PENDING_TASK_TTL_MS) {
      map.delete(key);
    }
  }
}

/**
 * Consume the oldest pending task entry (FIFO) on SubagentStart.
 *
 * `SubagentStart` carries no `tool_use_id`, so direct lookup is
 * impossible. FIFO ordering is a good-enough approximation: a Task
 * tool call is almost always immediately followed by its own
 * SubagentStart before a subsequent Task fires. Concurrent Task calls
 * still work as long as subagent spawns happen in the same order as
 * the Task calls, which is how the SDK ordinarily drives them. The
 * failure mode is pathological interleaving — see the correlation-miss
 * `warn` below.
 */
function consumeOldestPendingTask(
  map: Map<string, PendingTaskEntry>,
): PendingTaskEntry | undefined {
  const firstKey = map.keys().next();
  if (firstKey.done) return undefined;
  const value = map.get(firstKey.value);
  map.delete(firstKey.value);
  return value;
}

// ── Agent role classification from task description ──────────

const ROLE_KEYWORDS: [RegExp, string][] = [
  [/\b(explore|search|find|grep|look|read|glob|discover)\b/i, 'researcher'],
  [/\b(plan|design|architect|strategy|blueprint)\b/i, 'architect'],
  [/\b(test|validate|verify|assert|spec)\b/i, 'qa'],
  [/\b(build|compile|deploy|docker|ci|infrastructure)\b/i, 'devops'],
  [/\b(style|css|ui|ux|layout|component|svelte|react|frontend)\b/i, 'frontend'],
  [/\b(api|server|database|backend|relay|endpoint|route)\b/i, 'backend'],
  [/\b(review|refactor|fix|lint|cleanup)\b/i, 'lead'],
  [/\b(write|implement|create|add|update|edit)\b/i, 'engineer'],
];

function classifyAgentRole(description: string): string {
  for (const [pattern, role] of ROLE_KEYWORDS) {
    if (pattern.test(description)) return role;
  }
  return 'engineer';
}

/** Auto-allowed tool event — emitted when permission filter auto-approves */
export interface AutoAllowEvent {
  tool: string;
  description: string;
  reason: AutoAllowReason;
  toolUseId: string;
}

/**
 * Sprite-response event type exposed by ClaudeCliAdapter. Keeps ws.ts
 * decoupled from the internal BtwQueue event shape.
 */
export interface SpriteResponseEvent {
  sessionId: string;
  spriteHandle: string;
  subagentId: string;
  messageId: string;
  text: string;
  status: 'delivered' | 'dropped';
  dropReason?: string;
}

export class ClaudeCliAdapter implements IAdapter {
  readonly type = 'cli' as const;
  private emitter = new EventEmitter();
  private sessions = new Map<string, SdkSessionEntry>();
  private sessionManager: SessionManager;
  private approvalQueue: ApprovalQueue;
  readonly permissionFilter: PermissionFilter;
  /** Wave 4 — /btw queue. See `relay/src/sprites/btw-queue.ts`. */
  readonly btwQueue = new BtwQueue();

  constructor(sessionManager: SessionManager, approvalQueue: ApprovalQueue) {
    this.sessionManager = sessionManager;
    this.approvalQueue = approvalQueue;
    this.permissionFilter = new PermissionFilter();

    // Fan queue terminal events out through the adapter's main emitter so
    // ws.ts can subscribe with a single `on('sprite-response', ...)`.
    this.btwQueue.on('responded', (ev: BtwQueueEventMap['responded']) => {
      this.emitter.emit('sprite-response', {
        sessionId: ev.sessionId,
        spriteHandle: ev.spriteHandle,
        subagentId: ev.subagentId,
        messageId: ev.messageId,
        text: ev.text,
        status: 'delivered',
      } satisfies SpriteResponseEvent);
    });
    this.btwQueue.on('dropped', (ev: BtwQueueEventMap['dropped']) => {
      this.emitter.emit('sprite-response', {
        sessionId: ev.sessionId,
        spriteHandle: ev.spriteHandle,
        subagentId: ev.subagentId,
        messageId: ev.messageId,
        text: '',
        status: 'dropped',
        dropReason: ev.reason,
      } satisfies SpriteResponseEvent);
    });
  }

  async start(workingDir: string): Promise<Session> {
    const session = this.sessionManager.create('cli', workingDir);

    // The SDK v2 session API doesn't support cwd — it inherits process.cwd().
    // Warn if the requested workingDir differs from where we're actually running.
    const cwd = process.cwd();
    if (workingDir !== cwd) {
      logger.warn(
        { workingDir, cwd },
        'Requested workingDir differs from process.cwd() — SDK session will use process.cwd()',
      );
    }

    // Phase 13 Wave 3 — per-session state the inline SDK hooks close
    // over. Declared BEFORE unstable_v2_createSession so the hook
    // callbacks capture a stable reference. Stashed on the
    // SdkSessionEntry below.
    const pendingTaskByToolUseId = new Map<string, PendingTaskEntry>();
    // Capture a reference to the emitter for the hook closures below —
    // `this` inside an async callback is lost.
    const emitter = this.emitter;

    const sdkSession = unstable_v2_createSession({
      model: 'claude-sonnet-4-20250514',
      permissionMode: 'default',
      // Phase 13 Wave 2 — thread `options.signal` so cancellation
      // unblocks the queue's pending promise instead of leaking the
      // session until the approval timeout fires.
      canUseTool: (toolName, input, options) =>
        this.handlePermission(session.id, toolName, input, options.toolUseID, options.signal),
      // Phase 13 Wave 3 — real subagent lifecycle events. Replaces
      // the old system-event heuristic that watched for task-shaped
      // SDK messages with first-class hooks. See the comment on
      // `pendingTaskByToolUseId` at module scope for the correlation
      // rationale.
      hooks: {
        PreToolUse: [
          {
            matcher: 'Task',
            hooks: [
              async (input, toolUseID) => {
                if (
                  input.hook_event_name === 'PreToolUse' &&
                  (input as PreToolUseHookInput).tool_name === 'Task' &&
                  typeof toolUseID === 'string'
                ) {
                  const toolInput =
                    ((input as PreToolUseHookInput).tool_input as Record<string, unknown>) ??
                    undefined;
                  const description =
                    typeof toolInput?.['description'] === 'string'
                      ? (toolInput['description'] as string)
                      : '';
                  const prompt =
                    typeof toolInput?.['prompt'] === 'string'
                      ? (toolInput['prompt'] as string)
                      : '';
                  // Drain any TTL-expired entries BEFORE inserting a
                  // new one — otherwise denied/cancelled Tasks (no
                  // corresponding SubagentStart) would leak into the
                  // map for the session lifetime.
                  gcPendingTasks(pendingTaskByToolUseId);
                  pendingTaskByToolUseId.set(toolUseID, {
                    description,
                    prompt,
                    enqueuedAt: Date.now(),
                  });
                }
                // Don't affect permission — canUseTool is the gate.
                return {};
              },
            ],
          },
        ],
        SubagentStart: [
          {
            hooks: [
              async (input) => {
                if (input.hook_event_name !== 'SubagentStart') return {};
                const startInput = input as SubagentStartHookInput;
                const { agent_id: agentId, agent_type: agentType } = startInput;

                const entry = this.sessions.get(session.id);
                if (!entry) return {};

                gcPendingTasks(entry.pendingTaskByToolUseId);
                const pending = consumeOldestPendingTask(entry.pendingTaskByToolUseId);

                const taskDesc = pending?.description ?? '';
                if (!pending) {
                  logger.warn(
                    { agentId, agentType, sessionId: session.id },
                    'sprite-label correlation miss — SubagentStart fired without a pending PreToolUse(Task) entry',
                  );
                }

                const label = taskDesc || agentType;
                const role = taskDesc ? classifyAgentRole(taskDesc) : agentType;

                emitter.emit('agent-lifecycle', {
                  sessionId: session.id,
                  agentId,
                  event: 'spawn',
                  task: label,
                  role,
                } satisfies AgentEvent);
                return {};
              },
            ],
          },
        ],
        SubagentStop: [
          {
            hooks: [
              async (input) => {
                if (input.hook_event_name !== 'SubagentStop') return {};
                const stopInput = input as SubagentStopHookInput;
                const { agent_id: agentId } = stopInput;

                // Wave 4 — drop any /btw messages queued for this subagent.
                // Scenario #4: agent finished before we could deliver. Emits
                // 'dropped' which the adapter forwards as sprite-response.
                this.btwQueue.dropForSubagent(
                  agentId,
                  'Subagent completed before delivery',
                );

                // `last_assistant_message` is available on stopInput
                // but ws.ts's `dismissed` handler (see routes/ws.ts
                // agent-lifecycle switch) ignores `event.result` —
                // only `complete` forwards it. Don't pass dead data.
                emitter.emit('agent-lifecycle', {
                  sessionId: session.id,
                  agentId,
                  event: 'dismissed',
                } satisfies AgentEvent);
                return {};
              },
            ],
          },
        ],
      },
      env: {
        ...process.env,
        NO_COLOR: '1',
      },
    });

    const streamAbort = new AbortController();
    const entry: SdkSessionEntry = {
      session,
      sdkSession,
      streamAbort,
      hasStreamedText: false,
      streamAlive: false,
      pendingTaskByToolUseId,
    };
    this.sessions.set(session.id, entry);

    // Start consuming the stream in the background
    this.consumeStream(session.id, sdkSession, streamAbort.signal);

    logger.info({ sessionId: session.id, workingDir }, 'SDK session created');
    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    const entry = this.sessions.get(sessionId);
    if (!entry) {
      throw new Error(`No SDK session for ${sessionId}`);
    }
    if (!entry.streamAlive) {
      logger.warn({ sessionId }, 'Attach: stream consumer is dead, session unusable');
      throw new Error(`SDK session stream is dead for ${sessionId}`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) {
      throw new Error(`No SDK session for ${sessionId}`);
    }
    if (!entry.streamAlive) {
      throw new Error(`SDK session stream is dead for ${sessionId} — cannot send prompt`);
    }

    // Prepend attached file context if any
    const contextText = entry.session.getContextText();
    const finalText = contextText ? `${contextText}${text}` : text;

    await entry.sdkSession.send(finalText);
    logger.info({ sessionId, textLength: finalText.length, hasContext: !!contextText }, 'Prompt sent via SDK');
  }

  async sendAgentMessage(sessionId: string, agentId: string, text: string): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) {
      throw new Error(`No SDK session for ${sessionId}`);
    }

    // Look up agent context for a more descriptive prefix
    const agent = agentTracker.get(agentId);
    const wrappedText = agent
      ? `[Regarding agent "${agent.role}" (task: "${agent.task}")]: ${text}`
      : `[Regarding agent ${agentId}]: ${text}`;

    await entry.sdkSession.send(wrappedText);
    logger.info({ sessionId, agentId, textLength: text.length }, 'Agent message sent via SDK');
  }

  /**
   * Wave 4 — enqueue a /btw sprite message for turn-boundary injection.
   * Used by ws.ts when a client sends `sprite.message`. The queue emits
   * 'responded' or 'dropped' which fans out as `sprite-response` events
   * to ws.ts.
   */
  enqueueSpriteMessage(input: {
    sessionId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    userText: string;
    role: string;
    task: string;
  }): void {
    if (!this.sessions.has(input.sessionId)) {
      // Session not alive here — this is the single-worker path and the
      // session didn't exist. Emit dropped so caller sees a terminal state.
      this.btwQueue.enqueue(input);
      this.btwQueue.dropForSubagent(input.subagentId, 'Session not alive');
      return;
    }
    this.btwQueue.enqueue(input);
  }

  /** Wave 4 — drop /btw entries for a subagent that's been unlinked. */
  dropSpriteForSubagent(subagentId: string, reason: string): void {
    this.btwQueue.dropForSubagent(subagentId, reason);
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) return;

    // Wave 4 — drop pending /btw entries. They can't be delivered once the
    // SDK session closes.
    this.btwQueue.dropForSession(sessionId, 'Session cancelled');

    // Close the SDK session (kills the underlying Claude process) and
    // abort the stream consumption loop so we stop processing events.
    entry.streamAbort.abort();
    entry.sdkSession.close();
    entry.session.close();
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, 'Session cancelled and closed');
  }

  // ── Permission handling ──────────────────────────────────────

  private async handlePermission(
    sessionId: string,
    toolName: string,
    input: Record<string, unknown>,
    toolUseId: string,
    signal?: AbortSignal,
  ): Promise<PermissionResult> {
    // ── Check permission filter first (smart/god auto-allow) ──
    const filterResult = this.permissionFilter.check(toolName, input);
    if (filterResult.allowed) {
      logger.info(
        { sessionId, toolName, reason: filterResult.reason, toolUseId },
        'Auto-allowed by permission filter',
      );
      this.emitter.emit('auto-allow', {
        tool: toolName,
        description: JSON.stringify(input),
        reason: filterResult.reason,
        toolUseId,
      } satisfies AutoAllowEvent);
      return { behavior: 'allow', toolUseID: toolUseId };
    }

    // ── Not auto-allowed — queue for manual/delay approval ──
    // Phase 13 Wave 2 — use toolUseId as the canonical requestId so the
    // SDK and shell-hook intercept paths share the same dedup key.
    const requestId = toolUseId;
    const description = JSON.stringify(input);
    const details: Record<string, unknown> = {
      tool_name: toolName,
      tool_input: input,
      tool_use_id: toolUseId,
    };

    // Emit approval request to connected clients
    this.emitter.emit('approval-request', {
      requestId,
      tool: toolName,
      description,
      details,
    } satisfies ApprovalRequest);

    logger.info({ sessionId, requestId, toolName, toolUseId }, 'Permission requested');

    const decision = await this.approvalQueue.waitForDecision(requestId, toolName, description, details, signal);

    logger.info({ sessionId, requestId, toolName, decision }, 'Permission decision received');

    if (decision === 'allow_always') {
      // Add to session allowlist for future auto-approval
      this.permissionFilter.addSessionAllow(toolName);
      return { behavior: 'allow', toolUseID: toolUseId };
    }

    if (decision === 'allow') {
      return { behavior: 'allow', toolUseID: toolUseId };
    }

    return {
      behavior: 'deny',
      message: `User denied ${toolName}`,
      toolUseID: toolUseId,
    };
  }

  // ── Stream consumption ───────────────────────────────────────

  private async consumeStream(
    sessionId: string,
    sdkSession: SDKSession,
    signal: AbortSignal,
  ): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (entry) entry.streamAlive = true;

    try {
      // The SDK's stream() generator exits after each turn's `result` message.
      // We must loop and call stream() again to consume subsequent turns.
      while (!signal.aborted) {
        let messagesInTurn = 0;
        for await (const message of sdkSession.stream()) {
          if (signal.aborted) break;
          this.handleSdkMessage(sessionId, message);
          messagesInTurn++;
        }

        if (messagesInTurn === 0) {
          // The SDK's queryIterator is exhausted (Claude process exited).
          // stream() returned immediately with no messages — exit to avoid
          // a tight loop that would starve the Node.js event loop and block
          // all WebSocket message processing (including approval responses).
          logger.warn({ sessionId }, 'Stream returned 0 messages — underlying process likely exited, stopping consumer');
          break;
        }

        // Turn complete (stream yielded `result` and returned).
        // Loop back to call stream() again for the next turn.
        logger.debug({ sessionId, messagesInTurn }, 'Turn stream ended, waiting for next turn');

        // Wave 4 — drain one queued /btw at the turn boundary. See the
        // identical path in fleet/worker.ts for the design rationale.
        if (!signal.aborted) {
          await this.drainOneBtw(sessionId, sdkSession);
        }
      }
    } catch (err) {
      if (!signal.aborted) {
        logger.error({ sessionId, err }, 'Stream error');
        this.emitter.emit('output', sessionId, `\n[Stream error: ${err instanceof Error ? err.message : 'unknown'}]\n`);
      }
    } finally {
      if (entry) entry.streamAlive = false;
      logger.info({ sessionId }, 'Stream consumer exited');
    }
  }

  /**
   * Drain one queued /btw for this session at a turn boundary. One per
   * boundary so the next assistant message can be correlated unambiguously.
   */
  private async drainOneBtw(sessionId: string, sdkSession: SDKSession): Promise<void> {
    // Single-in-flight guard: if a previous /btw for this session is still
    // awaiting a response, do NOT inject another one or response
    // correlation breaks. The next turn boundary (after the response lands
    // or the entry is dropped) will resume draining.
    const inFlight = this.btwQueue.findAwaitingForSession(sessionId);
    if (inFlight) {
      logger.debug(
        {
          sessionId,
          awaitingMessageId: inFlight.messageId,
        },
        'Skipping /btw drain — another /btw still awaiting response for this session',
      );
      return;
    }

    const queued = this.btwQueue.peekQueuedForSession(sessionId);
    if (queued.length === 0) return;
    const oldest = queued[0];
    if (!oldest) return;
    const entry = this.btwQueue.takeNextForSubagent(oldest.subagentId);
    if (!entry) return;
    try {
      await sdkSession.send(entry.constrainedText);
      this.btwQueue.markAwaitingResponse(entry.messageId);
      logger.info(
        {
          sessionId,
          subagentId: entry.subagentId,
          messageId: entry.messageId,
          queuedForMs: Date.now() - entry.queuedAt,
        },
        'Injected /btw at turn boundary, awaiting response',
      );
    } catch (err) {
      logger.error(
        { sessionId, subagentId: entry.subagentId, messageId: entry.messageId, err },
        'Failed to inject /btw — dropping',
      );
      // Drop ONLY this entry so unrelated queued messages for the same
      // subagent survive to try again on the next turn boundary.
      this.btwQueue.dropByMessageId(
        entry.messageId,
        `Injection failed: ${err instanceof Error ? err.message : 'unknown'}`,
      );
    }
  }

  private handleSdkMessage(sessionId: string, message: SDKMessage): void {
    const type = message.type;

    switch (type) {
      case 'system':
        this.handleSystemMessage(sessionId, message);
        break;

      case 'assistant':
        this.handleAssistantMessage(sessionId, message);
        break;

      case 'stream_event':
        this.handleStreamEvent(sessionId, message);
        break;

      case 'result':
        this.handleResultMessage(sessionId, message);
        break;

      default:
        logger.debug({ sessionId, type }, 'Unhandled SDK message type');
    }
  }

  // ── System messages ──────────────────────────────────────────

  private handleSystemMessage(sessionId: string, message: SDKMessage): void {
    if (message.type !== 'system') return;
    const msg = message as Record<string, unknown>;
    const subtype = msg['subtype'] as string;

    switch (subtype) {
      case 'init':
        logger.info(
          { sessionId, model: msg['model'], version: msg['claude_code_version'] },
          'Claude session initialized',
        );
        break;

      // Phase 13 Wave 3 — task-shaped SDK system events are no longer
      // the sprite source of truth. Real `SubagentStart` / `SubagentStop`
      // hooks on the SDK session (see `start()` above) now drive
      // sprite spawn/dismiss, with task-description correlation via
      // `pendingTaskByToolUseId`.

      case 'status': {
        const status = msg['status'] as string | null;
        if (status === 'compacting') {
          this.emitter.emit('output', sessionId, '\n[Compacting context...]\n');
        }
        break;
      }

      case 'api_retry':
        logger.warn({ sessionId, attempt: msg['attempt'], error: msg['error'] }, 'API retry');
        break;

      default:
        logger.debug({ sessionId, subtype }, 'Unhandled system event');
    }
  }

  // ── Assistant messages ───────────────────────────────────────

  private handleAssistantMessage(sessionId: string, message: SDKMessage): void {
    if (message.type !== 'assistant') return;
    const msg = message as Record<string, unknown>;
    const betaMessage = msg['message'] as Record<string, unknown> | undefined;
    if (!betaMessage) return;

    const content = betaMessage['content'] as Array<Record<string, unknown>> | undefined;
    if (!content) return;

    const entry = this.sessions.get(sessionId);

    // Wave 4 — if a /btw is awaiting a response, capture the full text of
    // this assistant message as the response. Emits 'responded' which this
    // adapter forwards as `sprite-response { status: 'delivered' }`.
    const awaiting = this.btwQueue.findAwaitingForSession(sessionId);
    let collectedText = '';

    for (const block of content) {
      if (block['type'] === 'text') {
        // Only emit full text if we didn't already stream it via deltas
        if (!entry?.hasStreamedText) {
          const text = block['text'] as string;
          if (text) {
            this.emitter.emit('output', sessionId, text);
          }
        }
        if (awaiting) {
          const t = block['text'];
          if (typeof t === 'string') collectedText += t;
        }
      }

      if (block['type'] === 'tool_use') {
        this.emitter.emit('tool-start', {
          tool: block['name'] as string,
          input: block['input'] as Record<string, unknown>,
          sessionId,
        } satisfies ToolInfo);
      }
    }

    if (awaiting && collectedText.trim().length > 0) {
      this.btwQueue.markResponded(awaiting.messageId, collectedText);
    }
  }

  // ── Stream events (real-time deltas) ─────────────────────────

  private handleStreamEvent(sessionId: string, message: SDKMessage): void {
    if (message.type !== 'stream_event') return;
    const msg = message as Record<string, unknown>;
    const innerEvent = msg['event'] as Record<string, unknown> | undefined;
    if (!innerEvent) return;

    const eventType = innerEvent['type'] as string;

    switch (eventType) {
      case 'content_block_delta': {
        const delta = innerEvent['delta'] as Record<string, unknown> | undefined;
        if (delta?.['type'] === 'text_delta') {
          const text = delta['text'] as string;
          if (text) {
            // Mark that we're streaming — prevents double-emit from assistant message
            const entry = this.sessions.get(sessionId);
            if (entry) entry.hasStreamedText = true;
            this.emitter.emit('output', sessionId, text);
          }
        }
        break;
      }

      case 'content_block_start': {
        const block = innerEvent['content_block'] as Record<string, unknown> | undefined;
        if (block?.['type'] === 'tool_use') {
          this.emitter.emit('output', sessionId, `\n[Using ${block['name']}...]\n`);
        }
        break;
      }
    }
  }

  // ── Result messages ──────────────────────────────────────────

  private handleResultMessage(sessionId: string, message: SDKMessage): void {
    if (message.type !== 'result') return;

    // Reset streaming flag for next turn
    const entry = this.sessions.get(sessionId);
    if (entry) entry.hasStreamedText = false;

    const msg = message as Record<string, unknown>;
    const subtype = msg['subtype'] as string;
    const isError = msg['is_error'] as boolean;

    if (isError || subtype !== 'success') {
      const errors = msg['errors'] as string[] | undefined;
      const errorText = errors?.join(', ') ?? subtype;
      this.emitter.emit('output', sessionId, `\n[Error: ${errorText}]\n`);
    }

    const rawDuration = Number(msg['durationMs']);
    const rawCost = Number(msg['total_costUsd']);
    const rawTurns = Number(msg['numTurns']);
    const rawInputTokens = Number(msg['input_tokens']);
    const rawOutputTokens = Number(msg['output_tokens']);
    const durationMs = Number.isFinite(rawDuration) ? rawDuration : 0;
    const costUsd = Number.isFinite(rawCost) ? rawCost : 0;
    const numTurns = Number.isFinite(rawTurns) ? rawTurns : 0;
    const inputTokens = Number.isFinite(rawInputTokens) ? rawInputTokens : undefined;
    const outputTokens = Number.isFinite(rawOutputTokens) ? rawOutputTokens : undefined;

    logger.info(
      {
        sessionId,
        subtype,
        durationMs,
        cost: costUsd,
        turns: numTurns,
        inputTokens,
        outputTokens,
      },
      'Prompt result',
    );

    this.emitter.emit('session-result', {
      sessionId,
      costUsd: costUsd,
      numTurns: numTurns,
      durationMs: durationMs,
      inputTokens,
      outputTokens,
    } satisfies SessionResult);
  }

  /** Check if an SDK session exists and its stream is alive */
  isSessionAlive(sessionId: string): boolean {
    const entry = this.sessions.get(sessionId);
    return !!entry?.streamAlive;
  }

  /** Check if an SDK session entry exists (even if stream is dead) */
  hasSession(sessionId: string): boolean {
    return this.sessions.has(sessionId);
  }

  /** Clean up a dead session — abort stream, close SDK session, remove from map */
  destroySession(sessionId: string): void {
    const entry = this.sessions.get(sessionId);
    if (!entry) return;
    // Wave 4 — drop any /btw entries for the session being destroyed.
    this.btwQueue.dropForSession(sessionId, 'Session destroyed');
    entry.streamAbort.abort();
    entry.sdkSession.close();
    entry.session.close();
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, 'Session destroyed (cleanup)');
  }

  // ── Event emitter interface ─────────────────────────────────

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'auto-allow', handler: (event: AutoAllowEvent) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
  on(event: 'session-result', handler: (result: SessionResult) => void): void;
  on(event: 'sprite-response', handler: (ev: SpriteResponseEvent) => void): void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on(event: string, handler: (...args: any[]) => void): void {
    this.emitter.on(event, handler);
  }

  emitApprovalRequest(request: ApprovalRequest): void {
    this.emitter.emit('approval-request', request);
  }

  emitToolStart(info: ToolInfo): void {
    this.emitter.emit('tool-start', info);
  }

  emitToolComplete(result: ToolResult): void {
    this.emitter.emit('tool-complete', result);
  }

  emitAgentLifecycle(event: AgentEvent): void {
    this.emitter.emit('agent-lifecycle', event);
  }

  async dispose(): Promise<void> {
    for (const [sessionId, entry] of this.sessions) {
      logger.info({ sessionId }, 'Disposing SDK session');
      entry.streamAbort.abort();
      entry.sdkSession.close();
      entry.session.close();
    }
    this.sessions.clear();
    this.emitter.removeAllListeners();
  }
}
