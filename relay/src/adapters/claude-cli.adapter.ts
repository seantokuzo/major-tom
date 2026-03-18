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
// Spawns `claude -p` per prompt with --output-format stream-json.
// Uses --session-id for first prompt, --resume for subsequent ones.
// Hooks handle structured events (approvals, tool calls, agents).

interface CliSession {
  session: Session;
  activeProcess: ChildProcess | null;
  promptCount: number;
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
    const cliSession: CliSession = {
      session,
      activeProcess: null,
      promptCount: 0,
    };
    this.cliSessions.set(session.id, cliSession);
    logger.info({ sessionId: session.id, workingDir }, 'Claude CLI session created');
    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    if (!this.cliSessions.has(sessionId)) {
      throw new Error(`No CLI session for ${sessionId}`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const cliSession = this.cliSessions.get(sessionId);
    if (!cliSession) {
      throw new Error(`No CLI session for ${sessionId}`);
    }

    // Kill any still-running process from previous prompt
    if (cliSession.activeProcess && !cliSession.activeProcess.killed) {
      cliSession.activeProcess.kill('SIGTERM');
    }

    const isFirstPrompt = cliSession.promptCount === 0;
    cliSession.promptCount++;

    // Build args: --verbose must come before --output-format stream-json
    const args = [
      '--verbose',
      '--output-format', 'stream-json',
      '-p', text,
    ];

    if (isFirstPrompt) {
      args.push('--session-id', cliSession.session.id);
    } else {
      args.push('--resume', cliSession.session.id);
    }

    logger.info(
      { sessionId, promptCount: cliSession.promptCount, isFirstPrompt },
      'Spawning claude -p',
    );

    const child = spawn('claude', args, {
      cwd: cliSession.session.workingDir,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: {
        ...process.env,
        NO_COLOR: '1',
      },
    });

    cliSession.activeProcess = child;

    // Buffer partial lines from stdout
    let stdoutBuffer = '';
    child.stdout?.on('data', (data: Buffer) => {
      stdoutBuffer += data.toString();
      // stream-json sends one JSON object per line
      const lines = stdoutBuffer.split('\n');
      stdoutBuffer = lines.pop() ?? ''; // keep incomplete last line in buffer
      for (const line of lines) {
        if (!line.trim()) continue;
        this.handleStreamLine(sessionId, line.trim());
      }
    });

    child.stderr?.on('data', (data: Buffer) => {
      const text = data.toString().trim();
      if (text) {
        logger.warn({ sessionId, stderr: text }, 'Claude CLI stderr');
        // Forward errors to the client
        if (text.startsWith('Error:')) {
          this.emitter.emit('output', sessionId, `\n[${text}]\n`);
        }
      }
    });

    child.on('exit', (code, signal) => {
      // Flush remaining buffer
      if (stdoutBuffer.trim()) {
        this.handleStreamLine(sessionId, stdoutBuffer.trim());
      }
      logger.info({ sessionId, code, signal }, 'Claude CLI prompt process exited');
      cliSession.activeProcess = null;
    });

    child.on('error', (err) => {
      logger.error({ sessionId, err }, 'Claude CLI process error');
      this.emitter.emit('output', sessionId, `\n[Error: ${err.message}]\n`);
      cliSession.activeProcess = null;
    });
  }

  private handleStreamLine(sessionId: string, line: string): void {
    try {
      const event = JSON.parse(line) as Record<string, unknown>;
      const type = event['type'] as string;

      switch (type) {
        case 'assistant': {
          // Full message with content blocks — extract text
          const message = event['message'] as Record<string, unknown> | undefined;
          const content = message?.['content'] as Array<Record<string, unknown>> | undefined;
          if (content) {
            for (const block of content) {
              if (block['type'] === 'text') {
                this.emitter.emit('output', sessionId, block['text'] as string);
              }
            }
          }
          break;
        }

        case 'content_block_delta': {
          // Incremental text delta (streaming)
          const delta = event['delta'] as Record<string, unknown> | undefined;
          if (delta?.['type'] === 'text_delta') {
            this.emitter.emit('output', sessionId, delta['text'] as string);
          }
          break;
        }

        case 'result': {
          // Final result — don't re-emit text (already sent via assistant event)
          const subtype = event['subtype'] as string | undefined;
          if (subtype === 'error') {
            const errorMsg = event['result'] as string | undefined;
            this.emitter.emit('output', sessionId, `\n[Error: ${errorMsg ?? 'unknown'}]\n`);
          }
          logger.info(
            {
              sessionId,
              subtype,
              durationMs: event['duration_ms'],
              cost: event['total_cost_usd'],
            },
            'Claude prompt completed',
          );
          break;
        }

        case 'system':
          // Init event — log but don't emit
          logger.debug({ sessionId, subtype: event['subtype'] }, 'Claude system event');
          break;

        case 'rate_limit_event':
          // Log rate limit info
          logger.debug({ sessionId }, 'Rate limit event');
          break;

        default:
          logger.debug({ sessionId, type, line: line.slice(0, 200) }, 'Unhandled stream event');
      }
    } catch {
      // Not JSON — emit as raw output
      if (line.length > 0) {
        logger.debug({ sessionId, line: line.slice(0, 200) }, 'Non-JSON stream line');
      }
    }
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const cliSession = this.cliSessions.get(sessionId);
    if (!cliSession?.activeProcess) return;

    cliSession.activeProcess.kill('SIGINT');
    logger.info({ sessionId }, 'Cancel signal sent to CLI');
  }

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
      if (cliSession.activeProcess && !cliSession.activeProcess.killed) {
        cliSession.activeProcess.kill();
      }
      cliSession.session.close();
    }
    this.cliSessions.clear();
    this.emitter.removeAllListeners();
  }
}
