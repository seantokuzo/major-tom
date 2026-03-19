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
} from './adapter.interface.js';
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

    // The SDK v2 session doesn't support cwd directly — it inherits
    // process.cwd(). The relay server should be started from the target
    // working directory (via CLAUDE_WORK_DIR env var).
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
    const entry: SdkSessionEntry = { session, sdkSession, streamAbort };
    this.sessions.set(session.id, entry);

    // Start consuming the stream in the background
    this.consumeStream(session.id, sdkSession, streamAbort.signal);

    logger.info({ sessionId: session.id, workingDir }, 'SDK session created');
    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    if (!this.sessions.has(sessionId)) {
      throw new Error(`No SDK session for ${sessionId}`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) {
      throw new Error(`No SDK session for ${sessionId}`);
    }

    await entry.sdkSession.send(text);
    logger.info({ sessionId, textLength: text.length }, 'Prompt sent via SDK');
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const entry = this.sessions.get(sessionId);
    if (!entry) return;

    // Abort the stream, which should signal the SDK to cancel
    entry.streamAbort.abort();
    logger.info({ sessionId }, 'Cancel signal sent');
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
    const decision = await this.approvalQueue.waitForDecision(requestId, toolName);

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
    try {
      for await (const message of sdkSession.stream()) {
        if (signal.aborted) break;
        this.handleSdkMessage(sessionId, message);
      }
    } catch (err) {
      if (!signal.aborted) {
        logger.error({ sessionId, err }, 'Stream error');
        this.emitter.emit('output', sessionId, `\n[Stream error: ${err instanceof Error ? err.message : 'unknown'}]\n`);
      }
    } finally {
      logger.info({ sessionId }, 'Stream ended');
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
        const description = msg['summary'] as string ?? '';
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'spawn',
          task: description,
          role: 'subagent',
        } satisfies AgentEvent);
        break;
      }

      case 'task_progress': {
        const taskId = msg['task_id'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'working',
          task: (msg['summary'] as string) ?? '',
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

    for (const block of content) {
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
    const msg = message as Record<string, unknown>;
    const subtype = msg['subtype'] as string;
    const isError = msg['is_error'] as boolean;

    if (isError || subtype !== 'success') {
      const errors = msg['errors'] as string[] | undefined;
      const errorText = errors?.join(', ') ?? subtype;
      this.emitter.emit('output', sessionId, `\n[Error: ${errorText}]\n`);
    }

    logger.info(
      {
        sessionId,
        subtype,
        durationMs: msg['duration_ms'],
        cost: msg['total_cost_usd'],
        turns: msg['num_turns'],
      },
      'Prompt result',
    );
  }

  // ── Event emitter interface ─────────────────────────────────

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
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
