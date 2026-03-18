import { EventEmitter } from 'node:events';
import { spawn, type ChildProcess } from 'node:child_process';
import { Session } from '../sessions/session.js';
import { SessionManager } from '../sessions/session-manager.js';
import type {
  IAdapter,
  ApprovalRequest,
  ToolInfo,
  ToolResult,
  AgentEvent,
} from './adapter.interface.js';
import { logger } from '../utils/logger.js';

// ── Claude Code CLI Adapter ─────────────────────────────────
// Persistent process using --input-format stream-json / --output-format stream-json.
// Same approach as VSCode extension: stdin for prompts + permission responses,
// stdout for all events (streaming deltas, tool calls, permissions, results).

interface CliSession {
  session: Session;
  process: ChildProcess;
  stdoutBuffer: string;
}

export class ClaudeCliAdapter implements IAdapter {
  readonly type = 'cli' as const;
  private emitter = new EventEmitter();
  private cliSessions = new Map<string, CliSession>();
  private sessionManager: SessionManager;

  constructor(sessionManager: SessionManager) {
    this.sessionManager = sessionManager;
  }

  async start(workingDir: string): Promise<Session> {
    const session = this.sessionManager.create('cli', workingDir);

    const args = [
      '--verbose',
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--include-partial-messages',
      '--permission-prompt-tool', 'stdio',
      '--no-chrome',
      '--debug-to-stderr',
      '--session-id', session.id,
    ];

    logger.info({ sessionId: session.id, workingDir, args }, 'Spawning persistent Claude process');

    const child = spawn('claude', args, {
      cwd: workingDir,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: {
        ...process.env,
        NO_COLOR: '1',
      },
    });

    const cliSession: CliSession = {
      session,
      process: child,
      stdoutBuffer: '',
    };
    this.cliSessions.set(session.id, cliSession);

    // Parse newline-delimited JSON from stdout
    child.stdout?.on('data', (data: Buffer) => {
      cliSession.stdoutBuffer += data.toString();
      const lines = cliSession.stdoutBuffer.split('\n');
      cliSession.stdoutBuffer = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.trim()) continue;
        this.handleStreamEvent(session.id, line.trim());
      }
    });

    // Debug logs go to stderr (--debug-to-stderr)
    child.stderr?.on('data', (data: Buffer) => {
      const text = data.toString().trim();
      if (text) {
        logger.debug({ sessionId: session.id, stderr: text.slice(0, 300) }, 'Claude stderr');
      }
    });

    child.on('exit', (code, signal) => {
      logger.info({ sessionId: session.id, code, signal }, 'Claude process exited');
      session.close();
      this.cliSessions.delete(session.id);
    });

    child.on('error', (err) => {
      logger.error({ sessionId: session.id, err }, 'Claude process error');
      this.emitter.emit('output', session.id, `\n[Process error: ${err.message}]\n`);
      session.close();
      this.cliSessions.delete(session.id);
    });

    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    if (!this.cliSessions.has(sessionId)) {
      throw new Error(`No CLI session for ${sessionId}`);
    }
    return session;
  }

  // ── Send prompt via stream-json stdin ───────────────────────

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const cliSession = this.cliSessions.get(sessionId);
    if (!cliSession) {
      throw new Error(`No CLI session for ${sessionId}`);
    }

    const message = {
      type: 'user',
      message: {
        role: 'user',
        content: text,
      },
    };

    this.writeStdin(cliSession, message);
    logger.info({ sessionId, textLength: text.length }, 'Prompt sent via stream-json stdin');
  }

  // ── Send permission response via stream-json stdin ──────────

  sendPermissionResponse(sessionId: string, toolUseId: string, decision: string): void {
    const cliSession = this.cliSessions.get(sessionId);
    if (!cliSession) {
      logger.warn({ sessionId }, 'No CLI session for permission response');
      return;
    }

    const message = {
      type: 'user',
      message: {
        role: 'user',
        content: [
          {
            type: 'tool_result',
            tool_use_id: toolUseId,
            content: JSON.stringify({ permissionDecision: decision }),
          },
        ],
      },
    };

    this.writeStdin(cliSession, message);
    logger.info({ sessionId, toolUseId, decision }, 'Permission response sent');
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const cliSession = this.cliSessions.get(sessionId);
    if (!cliSession) return;

    cliSession.process.kill('SIGINT');
    logger.info({ sessionId }, 'Cancel signal sent to CLI');
  }

  // ── Stream event parsing ──────────────────────────────────

  private handleStreamEvent(sessionId: string, line: string): void {
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(line) as Record<string, unknown>;
    } catch {
      logger.debug({ sessionId, line: line.slice(0, 200) }, 'Non-JSON stream line');
      return;
    }

    const type = event['type'] as string;

    switch (type) {
      case 'system':
        this.handleSystemEvent(sessionId, event);
        break;

      case 'assistant':
        this.handleAssistantEvent(sessionId, event);
        break;

      case 'stream_event':
        this.handleStreamDelta(sessionId, event);
        break;

      case 'user':
        // Echo of our input — ignore
        break;

      case 'result':
        this.handleResultEvent(sessionId, event);
        break;

      case 'tool_progress':
        this.handleToolProgress(sessionId, event);
        break;

      case 'rate_limit_event':
        this.handleRateLimit(sessionId, event);
        break;

      case 'auth_status':
        logger.debug({ sessionId }, 'Auth status event');
        break;

      case 'prompt_suggestion': {
        const suggestion = event['suggestion'] as string;
        if (suggestion) {
          this.emitter.emit('prompt-suggestion', sessionId, suggestion);
        }
        break;
      }

      default:
        logger.debug({ sessionId, type, keys: Object.keys(event) }, 'Unhandled stream event type');
    }
  }

  // ── System events ─────────────────────────────────────────

  private handleSystemEvent(sessionId: string, event: Record<string, unknown>): void {
    const subtype = event['subtype'] as string;

    switch (subtype) {
      case 'init':
        logger.info(
          {
            sessionId,
            model: event['model'],
            version: event['claude_code_version'],
            toolCount: (event['tools'] as string[] | undefined)?.length,
          },
          'Claude session initialized',
        );
        break;

      case 'task_started': {
        // Subagent spawned!
        const taskId = event['task_id'] as string;
        const description = event['description'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'spawn',
          task: description,
          role: 'subagent',
        } satisfies AgentEvent);
        logger.info({ sessionId, taskId, description }, 'Subagent started');
        break;
      }

      case 'task_progress': {
        const taskId = event['task_id'] as string;
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: 'working',
          task: (event['description'] as string) ?? '',
        } satisfies AgentEvent);
        break;
      }

      case 'task_notification': {
        const taskId = event['task_id'] as string;
        const status = event['status'] as string;
        const agentEvent = status === 'completed' ? 'complete' : 'dismissed';
        this.emitter.emit('agent-lifecycle', {
          agentId: taskId,
          event: agentEvent,
          result: (event['summary'] as string) ?? status,
        } satisfies AgentEvent);
        logger.info({ sessionId, taskId, status }, 'Subagent finished');
        break;
      }

      case 'api_retry':
        logger.warn(
          {
            sessionId,
            attempt: event['attempt'],
            error: event['error'],
            delay: event['retry_delay_ms'],
          },
          'API retry',
        );
        break;

      case 'status': {
        const status = event['status'] as string | null;
        if (status === 'compacting') {
          this.emitter.emit('output', sessionId, '\n[Compacting context...]\n');
        }
        break;
      }

      case 'hook_started':
      case 'hook_progress':
      case 'hook_response':
        logger.debug({ sessionId, subtype, hookName: event['hook_name'] }, 'Hook event');
        break;

      default:
        logger.debug({ sessionId, subtype }, 'Unhandled system event');
    }
  }

  // ── Assistant messages ────────────────────────────────────

  private handleAssistantEvent(sessionId: string, event: Record<string, unknown>): void {
    const message = event['message'] as Record<string, unknown> | undefined;
    if (!message) return;

    const content = message['content'] as Array<Record<string, unknown>> | undefined;
    if (!content) return;

    // parent_tool_use_id tracks subagent hierarchy — will use in Phase 3
    // const parentToolUseId = (event['parent_tool_use_id'] as string) ?? null;

    for (const block of content) {
      const blockType = block['type'] as string;

      if (blockType === 'text') {
        // Text output — but with --include-partial-messages, we get this via
        // stream_event deltas too. The assistant event is the complete message.
        // We'll use stream_event for real-time and assistant for the final version.
        // Don't double-emit: stream_event handles real-time rendering.
        break;
      }

      if (blockType === 'tool_use') {
        const toolName = block['name'] as string;
        const toolUseId = block['id'] as string;
        const toolInput = block['input'] as Record<string, unknown>;

        // Check if this is a permission prompt
        if (this.isPermissionPrompt(toolName)) {
          this.handlePermissionRequest(sessionId, toolUseId, toolInput);
        } else {
          // Regular tool use — emit tool.start
          this.emitter.emit('tool-start', {
            tool: toolName,
            input: toolInput,
            sessionId,
          } satisfies ToolInfo);
        }
      }
    }
  }

  // ── Permission prompt detection & handling ─────────────────

  private isPermissionPrompt(toolName: string): boolean {
    // Claude Code sends permission requests as tool_use with specific tool names
    // when --permission-prompt-tool stdio is set
    return toolName === 'PermissionPromptTool' ||
           toolName === 'permission_prompt' ||
           toolName.toLowerCase().includes('permission');
  }

  private handlePermissionRequest(
    sessionId: string,
    toolUseId: string,
    input: Record<string, unknown>,
  ): void {
    const requestedTool = (input['tool_name'] as string) ?? 'unknown';
    const requestedInput = input['tool_input'] as Record<string, unknown> | undefined;

    logger.info({ sessionId, toolUseId, requestedTool }, 'Permission request received');

    // Emit as approval request — PWA will show approval UI
    this.emitter.emit('approval-request', {
      requestId: toolUseId,
      tool: requestedTool,
      description: requestedInput ? JSON.stringify(requestedInput) : '',
      details: input,
    } satisfies ApprovalRequest);
  }

  // ── Streaming deltas (real-time text) ─────────────────────

  private handleStreamDelta(sessionId: string, event: Record<string, unknown>): void {
    const innerEvent = event['event'] as Record<string, unknown> | undefined;
    if (!innerEvent) return;

    const eventType = innerEvent['type'] as string;

    switch (eventType) {
      case 'content_block_delta': {
        const delta = innerEvent['delta'] as Record<string, unknown> | undefined;
        if (!delta) break;

        if (delta['type'] === 'text_delta') {
          const text = delta['text'] as string;
          if (text) {
            this.emitter.emit('output', sessionId, text);
          }
        }
        // input_json_delta: tool input streaming — could show in UI
        break;
      }

      case 'content_block_start': {
        const block = innerEvent['content_block'] as Record<string, unknown> | undefined;
        if (block?.['type'] === 'tool_use') {
          const toolName = block['name'] as string;
          if (!this.isPermissionPrompt(toolName)) {
            this.emitter.emit('output', sessionId, `\n[Using ${toolName}...]\n`);
          }
        }
        break;
      }

      // message_start, content_block_stop, message_delta, message_stop
      // — useful for UI state but not critical for now
    }
  }

  // ── Result event ──────────────────────────────────────────

  private handleResultEvent(sessionId: string, event: Record<string, unknown>): void {
    const subtype = event['subtype'] as string;
    const isError = event['is_error'] as boolean;

    if (isError || subtype !== 'success') {
      const errorResult = event['result'] as string | undefined;
      this.emitter.emit('output', sessionId, `\n[Error: ${errorResult ?? subtype}]\n`);
    }

    logger.info(
      {
        sessionId,
        subtype,
        durationMs: event['duration_ms'],
        cost: event['total_cost_usd'],
        turns: event['num_turns'],
      },
      'Prompt result',
    );
  }

  // ── Tool progress ─────────────────────────────────────────

  private handleToolProgress(sessionId: string, event: Record<string, unknown>): void {
    const toolName = event['tool_name'] as string;
    const elapsed = event['elapsed_time_seconds'] as number;
    logger.debug({ sessionId, toolName, elapsed }, 'Tool progress');
  }

  // ── Rate limit ────────────────────────────────────────────

  private handleRateLimit(sessionId: string, event: Record<string, unknown>): void {
    const info = event['rate_limit_info'] as Record<string, unknown> | undefined;
    if (!info) return;

    const status = info['status'] as string;
    if (status === 'rejected') {
      this.emitter.emit('output', sessionId, '\n[Rate limited — waiting for reset...]\n');
      logger.warn({ sessionId, resetsAt: info['resetsAt'] }, 'Rate limited');
    } else if (status === 'allowed_warning') {
      logger.warn({ sessionId, utilization: info['utilization'] }, 'Rate limit warning');
    }
  }

  // ── Helpers ────────────────────────────────────────────────

  private writeStdin(cliSession: CliSession, message: unknown): void {
    const json = JSON.stringify(message);
    cliSession.process.stdin?.write(json + '\n');
  }

  // ── Event emitter interface ───────────────────────────────

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
    for (const [sessionId, cliSession] of this.cliSessions) {
      logger.info({ sessionId }, 'Disposing CLI session');
      cliSession.process.kill();
      cliSession.session.close();
    }
    this.cliSessions.clear();
    this.emitter.removeAllListeners();
  }
}
