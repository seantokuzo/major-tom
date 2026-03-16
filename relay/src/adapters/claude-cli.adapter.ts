import { EventEmitter } from 'node:events';
import * as pty from 'node-pty';
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
// Spawns Claude Code in a PTY via node-pty.
// Output is streamed to connected iOS clients.
// Input (prompts) is forwarded as PTY stdin.
// Hooks handle structured events (approvals, tool calls, agents).

interface PtySession {
  session: Session;
  process: pty.IPty;
}

export class ClaudeCliAdapter implements IAdapter {
  readonly type = 'cli' as const;
  private emitter = new EventEmitter();
  private ptySessions = new Map<string, PtySession>();
  private sessionManager: SessionManager;

  constructor(sessionManager: SessionManager) {
    this.sessionManager = sessionManager;
  }

  async start(workingDir: string): Promise<Session> {
    const session = this.sessionManager.create('cli', workingDir);

    const ptyProcess = pty.spawn('claude', [], {
      name: 'xterm-color',
      cols: 120,
      rows: 40,
      cwd: workingDir,
      env: {
        ...process.env,
        TERM: 'xterm-color',
      },
    });

    const ptySession: PtySession = { session, process: ptyProcess };
    this.ptySessions.set(session.id, ptySession);

    ptyProcess.onData((data: string) => {
      this.emitter.emit('output', session.id, data);
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      logger.info({ sessionId: session.id, exitCode, signal }, 'Claude CLI process exited');
      session.close();
      this.ptySessions.delete(session.id);
    });

    logger.info({ sessionId: session.id, workingDir, pid: ptyProcess.pid }, 'Claude CLI session started');

    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    if (!this.ptySessions.has(sessionId)) {
      throw new Error(`No PTY process for session ${sessionId}`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const ptySession = this.ptySessions.get(sessionId);
    if (!ptySession) {
      throw new Error(`No PTY process for session ${sessionId}`);
    }

    // Write the prompt text followed by Enter
    ptySession.process.write(text + '\r');
    logger.debug({ sessionId, textLength: text.length }, 'Prompt sent to CLI');
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const ptySession = this.ptySessions.get(sessionId);
    if (!ptySession) return;

    // Send Ctrl+C (ETX) to interrupt
    ptySession.process.write('\x03');
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

  // Called by the hook server when structured events come in
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
    for (const [sessionId, ptySession] of this.ptySessions) {
      logger.info({ sessionId }, 'Disposing CLI session');
      ptySession.process.kill();
      ptySession.session.close();
    }
    this.ptySessions.clear();
    this.emitter.removeAllListeners();
  }
}
