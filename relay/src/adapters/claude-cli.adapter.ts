import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import {
  unstable_v2_createSession,
  type SDKSession,
  type SDKMessage,
  type PermissionResult,
} from '@anthropic-ai/claude-agent-sdk';
import { Session } from '../sessions/session.js';
import { SessionManager } from '../sessions/session-manager.js';
import { ApprovalQueue } from '../hooks/approval-queue.js';
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

// ── Claude Code SDK Adapter ─────────────────────────────────
// Uses the official Agent SDK's v2 session API.
// The SDK handles the WebSocket bridge + permission protocol internally.
// We get a simple `canUseTool` callback for approval and an async
// generator for streaming events.

interface SdkSessionEntry {
  session: Session;
  sdkSession: SDKSession;
  streamAbort: AbortController;
  /** True if we received streaming text deltas — prevents double-emit from assistant message */
  hasStreamedText: boolean;
  /** True while the stream consumer loop is running */
  streamAlive: boolean;
}

export class ClaudeCliAdapter implements IAdapter {
  readonly type = 'cli' as const;
  private emitter = new EventEmitter();
  private sessions = new Map<string, SdkSessionEntry>();
  private sessionManager: SessionManager;
  private approvalQueue: ApprovalQueue;

  constructor(sessionManager: SessionManager, approvalQueue: ApprovalQueue) {
    this.sessionManager = sessionManager;
    this.approvalQueue = approvalQueue;
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

    const sdkSession = unstable_v2_createSession({
      model: 'claude-sonnet-4-20250514',
      permissionMode: 'default',
      canUseTool: (toolName, input, options) =>
        this.handlePermission(session.id, toolName, input, options.toolUseID),
      env: {
        ...process.env,
        NO_COLOR: '1',
      },
    });

    const streamAbort = new AbortController();
    const entry: SdkSessionEntry = { session, sdkSession, streamAbort, hasStreamedText: false, streamAlive: false };
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

    entry.sdkSession.send(finalText);
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

  async cancelOperation(sessionId: string): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) return;

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
  ): Promise<PermissionResult> {
    const requestId = randomUUID();

    // Emit approval request to connected clients
    this.emitter.emit('approval-request', {
      requestId,
      tool: toolName,
      description: JSON.stringify(input),
      details: {
        tool_name: toolName,
        tool_input: input,
        tool_use_id: toolUseId,
      },
    } satisfies ApprovalRequest);

    logger.info({ sessionId, requestId, toolName, toolUseId }, 'Permission requested');

    // Block until the client responds
    const description = JSON.stringify(input);
    const details: Record<string, unknown> = {
      tool_name: toolName,
      tool_input: input,
      tool_use_id: toolUseId,
    };
    const decision = await this.approvalQueue.waitForDecision(requestId, toolName, description, details);

    logger.info({ sessionId, requestId, toolName, decision }, 'Permission decision received');

    if (decision === 'allow' || decision === 'allow_always') {
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
        for await (const message of sdkSession.stream()) {
          if (signal.aborted) break;
          this.handleSdkMessage(sessionId, message);
        }
        // Turn complete (stream yielded `result` and returned).
        // Loop back to call stream() again for the next turn.
        logger.debug({ sessionId }, 'Turn stream ended, waiting for next turn');
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

      case 'task_started': {
        const taskId = msg['task_id'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'spawn',
          task: (msg['description'] as string) ?? '',
          role: 'subagent',
        } satisfies AgentEvent);
        break;
      }

      case 'task_progress': {
        const taskId = msg['task_id'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'working',
          task: (msg['description'] as string) ?? (msg['summary'] as string) ?? '',
        } satisfies AgentEvent);
        break;
      }

      case 'task_notification': {
        const taskId = msg['task_id'] as string;
        const status = msg['status'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: status === 'completed' ? 'complete' : 'dismissed',
          result: (msg['summary'] as string) ?? status,
        } satisfies AgentEvent);
        break;
      }

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

    for (const block of content) {
      if (block['type'] === 'text') {
        // Only emit full text if we didn't already stream it via deltas
        if (!entry?.hasStreamedText) {
          const text = block['text'] as string;
          if (text) {
            this.emitter.emit('output', sessionId, text);
          }
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
    entry.streamAbort.abort();
    entry.sdkSession.close();
    entry.session.close();
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, 'Session destroyed (cleanup)');
  }

  // ── Event emitter interface ─────────────────────────────────

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
  on(event: 'session-result', handler: (result: SessionResult) => void): void;
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
